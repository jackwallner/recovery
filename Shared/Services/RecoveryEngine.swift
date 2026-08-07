import Foundation
import SwiftData
import WidgetKit
import os

private let engineLogger = Logger(subsystem: "com.jackwallner.recovery", category: "Engine")

/// The phone-side orchestrator: import workouts, score them, persist, and
/// publish the snapshot every other surface reads.
///
/// The dossier's architecture in one type:
///
///     HealthKit -> WorkoutRecord/DailyContextRecord -> RecoveryCalculator
///               -> RecoveryStateRecord -> RecoverySnapshot -> Watch + widgets
///
/// `refresh()` is idempotent and safe to call from a foreground event, an
/// observer fire, or a manual pull.
@MainActor
public final class RecoveryEngine: ObservableObject {
    public static let shared = RecoveryEngine()

    /// The estimate the countdown is showing, or `nil` when nothing is active.
    @Published public private(set) var current: RecoveryEstimate?
    /// Everything scored, newest session first. Drives history.
    @Published public private(set) var estimates: [RecoveryEstimate] = []
    /// The expired estimate whose readiness question has not been answered.
    @Published public private(set) var awaitingFeedback: RecoveryEstimate?
    /// The most recent session the effort question is worth asking about.
    @Published public private(set) var awaitingEffort: WorkoutRecord?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastRefresh: Date?

    private var context: ModelContext { DataService.sharedModelContainer.mainContext }

    private init() {}

    // MARK: - Refresh

    /// Re-imports, rescores, and republishes. Cheap enough to call on every
    /// foreground: HealthKit reads dominate, and they are seconds at worst.
    public func refresh(force: Bool = false) async {
        #if DEBUG
        if ScreenshotConfig.isEnabled {
            loadScreenshotFixtures()
            return
        }
        #endif
        guard !isRefreshing else { return }
        if !force, let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < 30 { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await importWorkouts()
        await importContext()
        rescore()
        publish()
        lastRefresh = .now
    }

    // MARK: - Import

    private func importWorkouts() async {
        // `nil` is a read that did not happen; `[]` is a store that genuinely
        // has no workouts left. Only the second one may delete anything, or a
        // revoked permission or a flaky query erases the user's history.
        guard let imported = await HealthKitService.shared.fetchWorkouts() else { return }

        let existing = (try? context.fetch(FetchDescriptor<WorkoutRecord>())) ?? []
        var byUUID = Dictionary(existing.map { ($0.healthKitUUID, $0) }, uniquingKeysWith: { first, _ in first })
        let ambiguousProfile = RechargeSettings.shared.ambiguousProfile

        for workout in imported {
            let profile = WorkoutClassifier.profile(
                activityCode: workout.activityCode,
                ambiguousProfile: ambiguousProfile
            )
            let label = WorkoutClassifier.label(activityCode: workout.activityCode)

            if let record = byUUID[workout.uuid] {
                // Health can revise a workout after the fact (a third-party app
                // backfilling heart rate, say), so refresh the mutable fields
                // but never touch the user's own override or effort answer.
                record.activeEnergy = workout.activeEnergy ?? record.activeEnergy
                record.averageHeartRate = workout.averageHeartRate ?? record.averageHeartRate
                record.heartRateCoverage = workout.heartRateCoverage
                record.profileRaw = profile.rawValue
                record.activityLabel = label
            } else {
                let record = WorkoutRecord(
                    healthKitUUID: workout.uuid,
                    activityCode: Int(workout.activityCode),
                    startDate: workout.start,
                    endDate: workout.end,
                    durationMinutes: workout.durationMinutes,
                    activeEnergy: workout.activeEnergy ?? 0,
                    averageHeartRate: workout.averageHeartRate ?? 0,
                    heartRateCoverage: workout.heartRateCoverage,
                    profile: profile,
                    sourceName: workout.sourceName,
                    activityLabel: label
                )
                context.insert(record)
                byUUID[workout.uuid] = record
            }
        }

        // Workouts deleted in Health must disappear here too, or a countdown can
        // outlive the session that produced it.
        let liveUUIDs = Set(imported.map(\.uuid))
        let importCutoff = DateHelpers.daysAgo(HealthKitService.importDays)
        for record in existing where record.endDate >= importCutoff && !liveUUIDs.contains(record.healthKitUUID) {
            context.delete(record)
        }

        try? context.save()
    }

    private func importContext() async {
        async let restingSeries = HealthKitService.shared.fetchRestingHeartRate()
        async let hrvSeries = HealthKitService.shared.fetchHeartRateVariability()
        async let sleepByDay = HealthKitService.shared.fetchSleepHours()

        let resting = await restingSeries
        let hrv = await hrvSeries
        let sleep = await sleepByDay
        guard !resting.isEmpty || !hrv.isEmpty || !sleep.isEmpty else { return }

        var byDay: [String: (resting: Double, hrv: Double, sleep: Double)] = [:]
        for point in resting {
            let key = DateHelpers.dayKey(for: point.date)
            byDay[key, default: (0, 0, 0)].resting = point.value
        }
        for point in hrv {
            let key = DateHelpers.dayKey(for: point.date)
            byDay[key, default: (0, 0, 0)].hrv = point.value
        }
        for (key, hours) in sleep {
            byDay[key, default: (0, 0, 0)].sleep = hours
        }

        let existing = (try? context.fetch(FetchDescriptor<DailyContextRecord>())) ?? []
        var byKey = Dictionary(existing.map { ($0.dateKey, $0) }, uniquingKeysWith: { first, _ in first })

        for (key, values) in byDay {
            guard let date = date(fromDayKey: key) else { continue }
            if let record = byKey[key] {
                if values.resting > 0 { record.restingHeartRate = values.resting }
                if values.hrv > 0 { record.heartRateVariability = values.hrv }
                if values.sleep > 0 { record.sleepHours = values.sleep }
                record.lastUpdated = .now
            } else {
                let record = DailyContextRecord(
                    date: date,
                    sleepHours: values.sleep,
                    restingHeartRate: values.resting,
                    heartRateVariability: values.hrv
                )
                context.insert(record)
                byKey[key] = record
            }
        }
        try? context.save()
    }

    // MARK: - Scoring

    /// Rescores every stored workout against the baseline as it stood *at that
    /// point in the history*, so a session is never judged against sessions that
    /// had not happened yet.
    ///
    /// A session whose countdown has already run out is **frozen**: the stored
    /// record keeps the numbers, reasons, and `modelVersion` the app actually
    /// showed the user, and history renders those rather than a fresh
    /// calculation. Without this, today's readiness answer or tonight's sleep
    /// import silently rewrites yesterday's estimate, and the model version on
    /// the detail sheet can never explain an older result because the older
    /// result no longer exists.
    ///
    /// Live countdowns are still recalculated, because a user who corrects their
    /// max heart rate expects the number on screen to move. And an explicit
    /// correction thaws what it corrects: a per-session edit — an effort answer,
    /// a profile override — passes its own ID in `unfreezing`, while a change to
    /// a model-wide assumption the app got wrong for *every* past session (the
    /// HYROX/CrossFit curve, the maximum heart rate) passes `unfreezeAll`.
    /// Calibration is deliberately not in that list: the feedback sheet promises
    /// it tunes future bands, so it must not reach back.
    public func rescore(
        unfreezing unfrozenSessionID: String? = nil,
        unfreezeAll: Bool = false,
        now: Date = .now
    ) {
        let settings = RechargeSettings.shared
        let workouts = ((try? context.fetch(FetchDescriptor<WorkoutRecord>())) ?? [])
            .sorted { $0.endDate < $1.endDate }
        guard !workouts.isEmpty else {
            estimates = []
            current = nil
            awaitingFeedback = nil
            awaitingEffort = nil
            return
        }

        let contexts = ((try? context.fetch(FetchDescriptor<DailyContextRecord>())) ?? [])
        let contextByKey = Dictionary(contexts.map { ($0.dateKey, $0) }, uniquingKeysWith: { first, _ in first })
        let restingBaseline = median(contexts.map(\.restingHeartRate).filter { $0 > 0 })
        let hrvBaseline = median(contexts.map(\.heartRateVariability).filter { $0 > 0 })

        let existingStates = ((try? context.fetch(FetchDescriptor<RecoveryStateRecord>())) ?? [])
        var statesByID = Dictionary(existingStates.map { ($0.sessionID, $0) }, uniquingKeysWith: { first, _ in first })

        var history: [(profile: WorkoutProfile, load: Double, date: Date)] = []
        var results: [RecoveryEstimate] = []

        for workout in workouts {
            let session = sessionInput(for: workout, settings: settings)
            let baseline = RecoveryBaseline.build(
                from: history,
                for: session.profile,
                now: workout.endDate
            )
            let recoveryContext = settings.useContextSignals && StoreService.shared.isPro
                ? contextFor(
                    workout: workout,
                    contextByKey: contextByKey,
                    restingBaseline: restingBaseline,
                    hrvBaseline: hrvBaseline
                )
                : .empty

            let estimate = RecoveryCalculator.estimate(
                for: session,
                baseline: baseline,
                context: recoveryContext,
                calibration: settings.calibrationFactor,
                now: now
            )

            // Cache the load back onto the workout so the baseline for the next
            // session (and the weekly load view) does not have to recompute it.
            // The chain always uses the freshly computed load, even for a frozen
            // record, so a later session is never scored against a stale
            // baseline.
            workout.sessionLoad = estimate.load.value
            workout.loadSource = estimate.load.source

            let published: RecoveryEstimate
            if let record = statesByID[workout.healthKitUUID] {
                let isFrozen = record.readyAt <= now
                    && !unfreezeAll
                    && workout.healthKitUUID != unfrozenSessionID
                if isFrozen {
                    published = record.estimate
                } else {
                    record.update(from: estimate)
                    published = estimate
                }
            } else {
                let record = RecoveryStateRecord(estimate: estimate)
                context.insert(record)
                statesByID[workout.healthKitUUID] = record
                published = estimate
            }

            history.append((profile: session.profile, load: estimate.load.value, date: workout.endDate))
            results.append(published)
        }

        // Drop states whose workout no longer exists.
        let liveIDs = Set(workouts.map(\.healthKitUUID))
        for state in existingStates where !liveIDs.contains(state.sessionID) {
            context.delete(state)
        }
        try? context.save()

        estimates = results.sorted { $0.sessionEnd > $1.sessionEnd }
        current = RecoveryResolver.current(in: results)
        awaitingFeedback = RecoveryResolver.awaitingFeedback(
            in: results, answered: settings.answeredFeedbackSessions
        )
        awaitingEffort = workouts
            .filter { $0.wantsEffortInput && Date.now.timeIntervalSince($0.endDate) < 2 * 86_400 }
            .max { $0.endDate < $1.endDate }
    }

    private func sessionInput(for workout: WorkoutRecord, settings: RechargeSettings) -> SessionInput {
        SessionInput(
            id: workout.healthKitUUID,
            profile: workout.effectiveProfile,
            startDate: workout.startDate,
            endDate: workout.endDate,
            durationMinutes: workout.durationMinutes,
            averageHeartRate: workout.averageHeartRate > 0 ? workout.averageHeartRate : nil,
            restingHeartRate: latestRestingHeartRate(before: workout.endDate),
            maxHeartRate: settings.effectiveMaxHeartRate,
            heartRateCoverage: workout.heartRateCoverage,
            activeEnergyKilocalories: workout.activeEnergy > 0 ? workout.activeEnergy : nil,
            reportedEffort: workout.reportedEffort,
            activityLabel: workout.activityLabel
        )
    }

    private func contextFor(
        workout: WorkoutRecord,
        contextByKey: [String: DailyContextRecord],
        restingBaseline: Double?,
        hrvBaseline: Double?
    ) -> RecoveryContext {
        let record = contextByKey[DateHelpers.dayKey(for: workout.endDate)]
        return RecoveryContext(
            sleepHours: (record?.sleepHours).flatMap { $0 > 0 ? $0 : nil },
            heartRateVariability: (record?.heartRateVariability).flatMap { $0 > 0 ? $0 : nil },
            heartRateVariabilityBaseline: hrvBaseline,
            restingHeartRate: (record?.restingHeartRate).flatMap { $0 > 0 ? $0 : nil },
            restingHeartRateBaseline: restingBaseline
        )
    }

    private func latestRestingHeartRate(before date: Date) -> Double? {
        var descriptor = FetchDescriptor<DailyContextRecord>(
            predicate: #Predicate { $0.date <= date && $0.restingHeartRate > 0 }
        )
        descriptor.sortBy = [SortDescriptor(\DailyContextRecord.date, order: .reverse)]
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.restingHeartRate
    }

    // MARK: - Publish

    /// Writes the snapshot the Watch app and both widget extensions read, then
    /// nudges every timeline.
    public func publish() {
        let snapshot: RecoverySnapshot
        if let estimate = RecoveryResolver.current(in: estimates) {
            snapshot = RecoverySnapshot(estimate: estimate, isPro: StoreService.shared.isPro)
        } else {
            snapshot = .empty
        }
        RecoverySnapshotStore.save(snapshot)

        // The Watch cannot work out on its own which session needs an effort
        // answer — it has no workout history — so the phone names it here.
        let defaults = UserDefaults(suiteName: rechargeAppGroupID)
        if let pending = awaitingEffort {
            defaults?.set(pending.healthKitUUID, forKey: "pendingEffortSessionID")
        } else {
            defaults?.removeObject(forKey: "pendingEffortSessionID")
        }

        WidgetCenter.shared.reloadAllTimelines()

        // The Watch has its own App Group container, so writing the snapshot
        // above reaches the iOS widgets and nothing on the wrist. This is the
        // only path that does. Phone-only: this file is compiled into every
        // target, but only the phone owns the model.
        #if os(iOS)
        PhoneWatchSession.shared.sendSnapshot(
            snapshot,
            pendingEffortSessionID: awaitingEffort?.healthKitUUID,
            complicationStyle: RechargeSettings.shared.complicationStyle.rawValue
        )
        #endif

        if RechargeSettings.shared.notifyOnReady, StoreService.shared.isPro {
            NotificationService.scheduleReadyNotification(for: snapshot)
        } else {
            NotificationService.cancelReadyNotification()
        }

        // The moment the countdown runs out is the app's one genuine win, and
        // the only honest place to open the review funnel from.
        if let estimate = current, estimate.producesCountdown, estimate.readyAt <= .now {
            ReviewPromptTracker.recordReadyMoment(sessionID: estimate.sessionID)
        }
        if !estimates.isEmpty { ReviewPromptTracker.recordEstimateAvailable() }
    }

    // MARK: - User input

    /// Applies a session RPE the user supplied, from either device, and
    /// recalculates immediately.
    public func recordEffort(_ effort: Double, forSessionID sessionID: String) {
        var descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.healthKitUUID == sessionID }
        )
        descriptor.fetchLimit = 1
        guard let workout = (try? context.fetch(descriptor))?.first else {
            engineLogger.error("Effort arrived for an unknown session \(sessionID, privacy: .public)")
            return
        }
        workout.reportedEffort = min(max(effort, 1), 10)
        try? context.save()
        rescore(unfreezing: sessionID)
        publish()
    }

    /// Records the answer to the expired-countdown question and folds it into
    /// the personal calibration factor.
    public func recordFeedback(_ feedback: ReadinessFeedback, forSessionID sessionID: String) {
        var descriptor = FetchDescriptor<RecoveryStateRecord>(
            predicate: #Predicate { $0.sessionID == sessionID }
        )
        descriptor.fetchLimit = 1
        (try? context.fetch(descriptor))?.first?.userFeedback = feedback
        try? context.save()

        RechargeSettings.shared.applyFeedback(feedback)
        RechargeSettings.shared.recordFeedbackAnswered(sessionID)
        awaitingFeedback = nil
        rescore()
        publish()
    }

    public func dismissFeedback(forSessionID sessionID: String) {
        RechargeSettings.shared.recordFeedbackAnswered(sessionID)
        awaitingFeedback = nil
    }

    /// Per-session profile override — the HYROX/CrossFit escape hatch.
    public func overrideProfile(_ profile: WorkoutProfile, forSessionID sessionID: String) {
        var descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.healthKitUUID == sessionID }
        )
        descriptor.fetchLimit = 1
        guard let workout = (try? context.fetch(descriptor))?.first else { return }
        workout.profileOverride = profile
        try? context.save()
        rescore(unfreezing: sessionID)
        publish()
    }

    /// A model-wide assumption changed (the HYROX/CrossFit curve, the maximum
    /// heart rate), so every stored session was scored on a premise the user has
    /// now corrected. Thaw the lot and republish.
    public func rescoreAfterModelSettingChange() {
        rescore(unfreezeAll: true)
        publish()
    }

    /// The Pro entitlement arrived (or went away) after the last refresh, so the
    /// estimate and the App Group snapshot were calculated under the wrong tier.
    /// Recalculate the live countdown and republish so the Watch, the widgets,
    /// and the Ready notification agree with what the user just paid for.
    public func entitlementDidChange() {
        guard !ScreenshotConfig.isEnabled else { return }
        rescore()
        publish()
    }

    // MARK: - Weekly load (Pro)

    /// Acute (7-day) and chronic (28-day) load totals, the standard training
    /// stress pair. Shown, never used to make a claim.
    public func loadBalance(now: Date = .now) -> (acute: Double, chronic: Double) {
        #if DEBUG
        // Screenshot mode seeds estimates, not `WorkoutRecord`s, so the SwiftData
        // fetch below returns nothing and the Pro capture would show 0 and 0
        // beside a history of eight scored sessions. Derive it from the same
        // fixtures the rest of the frame is built from.
        if ScreenshotConfig.isEnabled {
            let acute = ScreenshotFixtures.history(now: now)
                .filter { $0.sessionEnd >= now.addingTimeInterval(-7 * 86_400) }
                .reduce(0) { $0 + $1.load.value }
            let chronic = ScreenshotFixtures.history(now: now)
                .filter { $0.sessionEnd >= now.addingTimeInterval(-28 * 86_400) }
                .reduce(0) { $0 + $1.load.value }
            return (acute, chronic / 4)
        }
        #endif
        let workouts = ((try? context.fetch(FetchDescriptor<WorkoutRecord>())) ?? [])
        let acuteCutoff = now.addingTimeInterval(-7 * 86_400)
        let chronicCutoff = now.addingTimeInterval(-28 * 86_400)
        let acute = workouts.filter { $0.endDate >= acuteCutoff }.reduce(0) { $0 + $1.sessionLoad }
        let chronicTotal = workouts.filter { $0.endDate >= chronicCutoff }.reduce(0) { $0 + $1.sessionLoad }
        // Chronic is expressed as a weekly average so the two are comparable.
        return (acute, chronicTotal / 4)
    }

    /// Daily load totals for the last `days` days, oldest first.
    public func dailyLoads(days: Int = 14, now: Date = .now) -> [(date: Date, load: Double)] {
        let workouts = ((try? context.fetch(FetchDescriptor<WorkoutRecord>())) ?? [])
        var totals: [String: Double] = [:]
        for workout in workouts {
            totals[DateHelpers.dayKey(for: workout.endDate), default: 0] += workout.sessionLoad
        }
        return (0..<days).reversed().compactMap { offset in
            let date = DateHelpers.daysAgo(offset, from: now)
            return (date: date, load: totals[DateHelpers.dayKey(for: date)] ?? 0)
        }
    }

    // MARK: - Helpers

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return Calendar.current.date(from: components)
    }

    #if DEBUG
    private func loadScreenshotFixtures() {
        estimates = ScreenshotFixtures.history()
        current = RecoveryResolver.current(in: estimates)
        awaitingFeedback = nil
        awaitingEffort = nil
        let snapshot = ScreenshotFixtures.snapshot()
        RecoverySnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        // Deliberately not `publish()`: that would derive the snapshot from the
        // resolver and lose the curated fixture reasons the capture depends on.
        // But the Watch still has to receive it, or a paired screenshot run
        // shows a live countdown on the phone and an empty ring on the wrist —
        // which is exactly how the missing transport went unnoticed.
        #if os(iOS)
        PhoneWatchSession.shared.sendSnapshot(
            snapshot,
            pendingEffortSessionID: ScreenshotConfig.wantsEffortPrompt ? "screenshot-0" : nil,
            complicationStyle: RechargeSettings.shared.complicationStyle.rawValue
        )
        #endif
        lastRefresh = .now
    }
    #endif
}
