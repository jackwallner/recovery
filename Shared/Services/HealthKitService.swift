import Foundation
@preconcurrency import HealthKit
import os
#if os(watchOS)
import WatchKit
#endif

private let healthLogger = Logger(subsystem: "com.jackwallner.recovery", category: "HealthKit")

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
    ///
    /// Every type here has to be read by something the user can see, or the
    /// permission sheet asks for more than the app does. VO2 max was in this set
    /// and nothing consumed it, which put an unexplained Cardio Fitness row in
    /// front of exactly the audience that reads the sheet carefully. Add it back
    /// only alongside a feature that uses it and copy that names it.
    /// Date of birth and biological sex earn their place the same way: age sets
    /// the age-predicted maximum heart rate every session's intensity is
    /// measured against, and sex selects the formula (Gulati for women, Tanaka
    /// otherwise). Both are consumed on **both** tiers, and reading them is what
    /// lets onboarding stop asking for what the phone already knows.
    public static var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.activeEnergyBurned),
            HKCategoryType(.sleepAnalysis),
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex)
        ]
    }

    /// How far back the workout import reaches. Wide enough to build the 42-day
    /// baseline on first launch with room for a gap in training.
    public static let importDays = 120

    private var installedObserverTypes: Set<String> = []
    private var pendingRefreshTask: Task<Void, Never>?
    private var pendingObserverCompletions: [ObserverCompletion] = []

    /// HealthKit's completion closure is supplied by a nonisolated callback.
    /// This box keeps that callback on its originating path while allowing the
    /// coalesced refresh task to carry an explicit, audited boundary to the
    /// main actor.
    private final class ObserverCompletion: @unchecked Sendable {
        private let handler: () -> Void

        init(_ handler: @escaping () -> Void) {
            self.handler = handler
        }

        func call() { handler() }
    }

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

    // MARK: - Characteristics

    /// What Health can tell us about the person rather than about a session.
    public struct AthleteCharacteristics: Sendable {
        public var age: Int?
        public var sex: AthleteSex?
    }

    /// Reads date of birth and biological sex.
    ///
    /// Characteristics are a synchronous, throwing API rather than a query, and
    /// a `nil` here is ambiguous in the usual HealthKit way: it means the user
    /// never filled the field in *or* declined the read. Either way the answer
    /// is the same — ask for it in onboarding — so the ambiguity never has to be
    /// resolved.
    public func fetchCharacteristics() -> AthleteCharacteristics {
        #if DEBUG
        if ScreenshotConfig.isEnabled { return AthleteCharacteristics(age: 34, sex: .male) }
        #endif
        guard HKHealthStore.isHealthDataAvailable() else { return AthleteCharacteristics() }

        var characteristics = AthleteCharacteristics()
        if let components = try? store.dateOfBirthComponents(),
           let birthDate = Calendar.current.date(from: components) {
            let years = Calendar.current.dateComponents([.year], from: birthDate, to: .now).year
            if let years, (10...100).contains(years) { characteristics.age = years }
        }
        if let biologicalSex = try? store.biologicalSex().biologicalSex {
            switch biologicalSex {
            case .female: characteristics.sex = .female
            case .male: characteristics.sex = .male
            default: characteristics.sex = nil
            }
        }
        return characteristics
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

    /// Returns `nil` when the read did not happen — Health unavailable, query
    /// failed, screenshot mode — as opposed to `[]`, which means the store
    /// genuinely holds no qualifying workouts.
    ///
    /// The distinction is load-bearing. `RecoveryEngine.importWorkouts` deletes
    /// stored records that no longer appear in Health, and a failed query that
    /// looked like an empty one would wipe the user's entire history.
    public func fetchWorkouts(days: Int = HealthKitService.importDays) async -> [ImportedWorkout]? {
        #if DEBUG
        if ScreenshotConfig.isEnabled { return nil }
        #endif
        guard HKHealthStore.isHealthDataAvailable() else { return nil }

        let start = DateHelpers.daysAgo(days)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let workouts: [HKWorkout]? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    healthLogger.error("Workout query failed: \(String(describing: error), privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }

        guard let workouts else { return nil }

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

    /// Coalesces observer callbacks while keeping every HealthKit completion
    /// handler open until the import and publish have finished. HealthKit may
    /// terminate a background launch as soon as its handler returns, so calling
    /// it before `RecoveryEngine.refresh()` loses the very workout that woke us.
    private func enqueueObserverRefresh(completion: ObserverCompletion) {
        pendingObserverCompletions.append(completion)
        guard pendingRefreshTask == nil else { return }

        pendingRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self else { return }

            await RecoveryEngine.shared.refresh()
            let completions = self.pendingObserverCompletions
            self.pendingObserverCompletions.removeAll()
            self.pendingRefreshTask = nil
            completions.forEach { $0.call() }
        }
    }

    /// Wakes the app when a workout lands, so the countdown appears without the
    /// user opening anything.
    public func enableBackgroundDelivery() {
        if ScreenshotConfig.isEnabled { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let deliveries: [(type: HKSampleType, frequency: HKUpdateFrequency)] = [
            (HKObjectType.workoutType(), .immediate),
            (HKQuantityType(.restingHeartRate), .daily),
            (HKQuantityType(.heartRateVariabilitySDNN), .daily),
            (HKCategoryType(.sleepAnalysis), .daily)
        ]

        for delivery in deliveries {
            store.enableBackgroundDelivery(for: delivery.type, frequency: delivery.frequency) { _, error in
                if let error {
                    healthLogger.error("Background delivery failed: \(String(describing: error), privacy: .public)")
                }
            }
        }

        for delivery in deliveries {
            let identifier = delivery.type.identifier
            guard !installedObserverTypes.contains(identifier) else { continue }
            installedObserverTypes.insert(identifier)

            let query = HKObserverQuery(sampleType: delivery.type, predicate: nil) { [weak self] _, completionHandler, error in
                if let error {
                    healthLogger.error("Observer error: \(String(describing: error), privacy: .public)")
                    completionHandler()
                    return
                }
                #if os(watchOS)
                // The CAROUSEL watchdog has a tight CPU budget, so the observer
                // callback only schedules; the protected handler does the work.
                let completion = ObserverCompletion(completionHandler)
                Task { @MainActor in
                    WKApplication.shared().scheduleBackgroundRefresh(
                        withPreferredDate: Date(timeIntervalSinceNow: 5), userInfo: nil
                    ) { _ in }
                    completion.call()
                }
                #else
                let completion = ObserverCompletion(completionHandler)
                Task { @MainActor in
                    // Health often delivers several notifications for one
                    // workout. Coalesce them, but keep every observer task
                    // alive until the shared refresh has published.
                    self?.enqueueObserverRefresh(completion: completion) ?? completion.call()
                }
                #endif
            }
            store.execute(query)
        }
    }
}
