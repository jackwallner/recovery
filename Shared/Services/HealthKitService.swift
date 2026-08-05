import Foundation
import HealthKit
import os
#if os(watchOS)
import WatchKit
#endif

private let healthLogger = Logger(subsystem: "com.jackwallner.recharge", category: "HealthKit")

/// Every HealthKit read the app makes, and the observer that wakes it when a
/// workout lands.
///
/// Deliberately knows nothing about the recovery model — it returns plain value
/// types, and `RecoveryEngine` decides what they mean. That split is what keeps
/// the calculator unit-testable without a Health store.
@MainActor
public final class HealthKitService: ObservableObject {
    public static let shared = HealthKitService()

    private let store = HKHealthStore()
    @Published public private(set) var isAuthorized: Bool = false

    /// Requested in a single sheet. Splitting them across prompts is what makes
    /// HealthKit silently suppress the second one.
    public static var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.vo2Max),
            HKCategoryType(.sleepAnalysis)
        ]
    }

    /// How far back the workout import reaches. Wide enough to build the 42-day
    /// baseline on first launch with room for a gap in training.
    public static let importDays = 120

    private var installedObserverTypes: Set<String> = []
    private var pendingRefreshTask: Task<Void, Never>?

    private init() {
        if ScreenshotConfig.isEnabled {
            isAuthorized = true
        } else {
            // `authorizationStatus(for:)` only reports write access, which is
            // useless for a read-only app. The async request-status API at least
            // tells us whether the sheet still needs showing.
            Task {
                if await self.authorizationRequestStatus() == .unnecessary {
                    self.isAuthorized = true
                }
            }
        }
    }

    // MARK: - Authorization

    public func requestAuthorization() async throws {
        if ScreenshotConfig.isEnabled {
            isAuthorized = true
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
            isAuthorized = true
            enableBackgroundDelivery()
        } catch {
            healthLogger.error("Authorization failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    public func authorizationRequestStatus() async -> HKAuthorizationRequestStatus? {
        if ScreenshotConfig.isEnabled { return .unnecessary }
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        return await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: Self.readTypes) { status, error in
                if let error {
                    healthLogger.error("Request status failed: \(String(describing: error), privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: status)
            }
        }
    }

    /// Apple never exposes whether the user allowed *reads*; an empty result and
    /// a denial look identical. So we resolve the sheet if it is still pending
    /// and otherwise just query.
    public func synchronizeAuthorization() async {
        if ScreenshotConfig.isEnabled {
            isAuthorized = true
            return
        }
        guard HKHealthStore.isHealthDataAvailable(), let status = await authorizationRequestStatus() else { return }
        switch status {
        case .shouldRequest:
            try? await requestAuthorization()
        case .unnecessary:
            isAuthorized = true
            enableBackgroundDelivery()
        case .unknown:
            break
        @unknown default:
            isAuthorized = true
        }
    }

    // MARK: - Workouts

    /// One imported workout, before the model has looked at it.
    public struct ImportedWorkout: Sendable {
        public let uuid: String
        public let activityCode: UInt
        public let start: Date
        public let end: Date
        public let durationMinutes: Double
        public let activeEnergy: Double?
        public let averageHeartRate: Double?
        public let heartRateCoverage: Double
        public let sourceName: String
    }

    public func fetchWorkouts(days: Int = HealthKitService.importDays) async -> [ImportedWorkout] {
        #if DEBUG
        if ScreenshotConfig.isEnabled { return [] }
        #endif
        guard HKHealthStore.isHealthDataAvailable() else { return [] }

        let start = DateHelpers.daysAgo(days)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    healthLogger.error("Workout query failed: \(String(describing: error), privacy: .public)")
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }

        var results: [ImportedWorkout] = []
        results.reserveCapacity(workouts.count)
        for workout in workouts {
            // Zero-length and absurdly long entries are almost always a bad
            // import from a third-party app; scoring them produces nonsense.
            let minutes = workout.duration / 60
            guard minutes >= 1, minutes <= 24 * 60 else { continue }

            let heartRate = await heartRateSummary(for: workout)
            results.append(ImportedWorkout(
                uuid: workout.uuid.uuidString,
                activityCode: workout.workoutActivityType.rawValue,
                start: workout.startDate,
                end: workout.endDate,
                durationMinutes: minutes,
                activeEnergy: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                    .sumQuantity()?.doubleValue(for: .kilocalorie()),
                averageHeartRate: heartRate.average,
                heartRateCoverage: heartRate.coverage,
                sourceName: workout.sourceRevision.source.name
            ))
        }
        return results
    }

    /// Average in-workout heart rate, plus how much of the session the samples
    /// actually cover.
    ///
    /// Coverage is the load model's honesty check: a lifting session where the
    /// optical sensor dropped out returns a plausible-looking average over three
    /// minutes of a sixty-minute session, and TRIMP built on that is a lie.
    /// Apple Watch samples roughly every five seconds during a workout, so we
    /// treat each sample as covering that much of the clock.
    private func heartRateSummary(for workout: HKWorkout) async -> (average: Double?, coverage: Double) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate, end: workout.endDate, options: .strictStartDate
        )

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.heartRate),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    healthLogger.error("Heart-rate query failed: \(String(describing: error), privacy: .public)")
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }

        guard !samples.isEmpty, workout.duration > 0 else { return (nil, 0) }

        let values = samples.map { $0.quantity.doubleValue(for: bpm) }
        let average = values.reduce(0, +) / Double(values.count)

        let assumedSampleInterval: TimeInterval = 5
        let covered = Double(samples.count) * assumedSampleInterval
        let coverage = min(covered / workout.duration, 1)

        return (average, coverage)
    }

    // MARK: - Context signals

    public func fetchRestingHeartRate(days: Int = 30) async -> [(date: Date, value: Double)] {
        await quantitySeries(
            type: HKQuantityType(.restingHeartRate),
            unit: HKUnit.count().unitDivided(by: .minute()),
            days: days
        )
    }

    public func fetchHeartRateVariability(days: Int = 30) async -> [(date: Date, value: Double)] {
        await quantitySeries(type: HKQuantityType(.heartRateVariabilitySDNN), unit: .secondUnit(with: .milli), days: days)
    }

    public func fetchVO2Max(days: Int = 180) async -> Double? {
        let unit = HKUnit.literUnit(with: .milli)
            .unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        return await quantitySeries(type: HKQuantityType(.vo2Max), unit: unit, days: days).last?.value
    }

    private func quantitySeries(
        type: HKQuantityType,
        unit: HKUnit,
        days: Int
    ) async -> [(date: Date, value: Double)] {
        #if DEBUG
        if ScreenshotConfig.isEnabled { return [] }
        #endif
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let start = DateHelpers.daysAgo(days)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                // A denied read type is indistinguishable from no data and comes
                // back empty, which every consumer already renders as an empty
                // state. So failures are logged, never surfaced as a banner.
                if let error {
                    healthLogger.error("Quantity query failed: \(String(describing: error), privacy: .public)")
                    continuation.resume(returning: [])
                    return
                }
                let points = (samples as? [HKQuantitySample] ?? []).map {
                    (date: $0.endDate, value: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }

    /// Asleep hours per night, keyed on the day the night *ended*. Only the
    /// asleep stages count; time in bed is not sleep.
    public func fetchSleepHours(days: Int = 30) async -> [String: Double] {
        #if DEBUG
        if ScreenshotConfig.isEnabled { return [:] }
        #endif
        guard HKHealthStore.isHealthDataAvailable() else { return [:] }
        let start = DateHelpers.daysAgo(days)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictEndDate)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    healthLogger.error("Sleep query failed: \(String(describing: error), privacy: .public)")
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: samples as? [HKCategorySample] ?? [])
            }
            store.execute(query)
        }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]

        var totals: [String: Double] = [:]
        for sample in samples where asleepValues.contains(sample.value) {
            let key = DateHelpers.dayKey(for: sample.endDate)
            totals[key, default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 3600
        }
        return totals
    }

    // MARK: - Background delivery

    /// Wakes the app when a workout lands, so the countdown appears without the
    /// user opening anything.
    public func enableBackgroundDelivery() {
        if ScreenshotConfig.isEnabled { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let types: [HKSampleType] = [HKObjectType.workoutType()]

        for type in types {
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, error in
                if let error {
                    healthLogger.error("Background delivery failed: \(String(describing: error), privacy: .public)")
                }
            }
        }

        for type in types {
            let identifier = type.identifier
            guard !installedObserverTypes.contains(identifier) else { continue }
            installedObserverTypes.insert(identifier)

            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
                // Call this immediately — watchOS kills the app if it does not
                // arrive within fifteen seconds.
                completionHandler()
                if let error {
                    healthLogger.error("Observer error: \(String(describing: error), privacy: .public)")
                    return
                }
                #if os(watchOS)
                // The CAROUSEL watchdog has a tight CPU budget, so the observer
                // callback only schedules; the protected handler does the work.
                Task { @MainActor in
                    WKApplication.shared().scheduleBackgroundRefresh(
                        withPreferredDate: Date(timeIntervalSinceNow: 5), userInfo: nil
                    ) { _ in }
                }
                #else
                Task { @MainActor in
                    // Health often delivers several notifications for one
                    // workout. Coalesce them into a single recalculation.
                    self?.pendingRefreshTask?.cancel()
                    self?.pendingRefreshTask = Task {
                        try? await Task.sleep(for: .milliseconds(800))
                        guard !Task.isCancelled else { return }
                        await RecoveryEngine.shared.refresh()
                    }
                }
                #endif
            }
            store.execute(query)
        }
    }
}
