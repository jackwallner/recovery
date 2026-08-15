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

    /// When Health last actually answered, as opposed to when the app last
    /// tried. A failed query returns no workouts rather than an empty store, so
    /// without this the screen keeps the previous countdown and a user who just
    /// finished a session cannot tell an import from a silent failure.
    @Published public private(set) var lastSuccessfulImport: Date?
    /// True when the most recent workout read did not happen at all.
    @Published public private(set) var lastImportFailed = false

    /// The Recharge+ thirty-day analysis behind the current estimates.
    ///
    /// Computed even on the free tier, where it changes no number: the
    /// onboarding pitch and the Settings comparison both have to be able to show
    /// what personalisation *would* do, and a pitch built on invented figures is
    /// not a pitch, it is a mock-up.
    @Published public private(set) var personalAnalysis = PersonalRecoveryModel.Analysis.neutral

    /// The standard window beside the personalized one, for the most recent
    /// session that produced a countdown.
    ///
    /// Always populated, and always *computed* rather than derived. Multiplying
    /// the standard hours by `personalAnalysis.factor` was the cheap version and
    /// it understated the difference badly: the personalized window is scored
    /// against the person's own 42-day baseline instead of the population
    /// reference, which moves the relative load, which moves the curve. When the
    /// thirty-day multiplier happened to land near 1 the derived version showed
    /// the same number twice and the conversion card vanished, on exactly the
    /// screens whose whole argument is that the number changes.
    @Published public private(set) var personalizedPreview = PersonalizedPreview.reference(factor: 1)

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
        updateAthleteProfileFromHealth()
        rescore()
        publish()
        lastRefresh = .now
    }

    /// Fills in everything about the person that Health can answer, so
    /// onboarding only ever asks for the rest.
    ///
    /// Safe to call on every refresh: `mergeHealthDerivedProfile` never
    /// overwrites an answer the user typed, and publishes nothing when nothing
    /// changed.
    public func updateAthleteProfileFromHealth() {
        let characteristics = HealthKitService.shared.fetchCharacteristics()
        let derived = derivedTrainingProfile()
        RechargeSettings.shared.mergeHealthDerivedProfile(
            age: characteristics.age,
            sex: characteristics.sex,
            weeklyVolume: derived.volume,
            primaryProfile: derived.primaryProfile
        )
    }

    /// Weekly session count and dominant workout type, from the imported
    /// history.
    ///
    /// Both stay `nil` until there is enough history to mean anything. A single
    /// week of workouts would label a returning runner as a two-a-week trainee
    /// and then quietly lengthen every window they get.
    private func derivedTrainingProfile() -> (volume: WeeklyVolume?, primaryProfile: WorkoutProfile?) {
        let windowDays = 28.0
        let cutoff = DateHelpers.daysAgo(Int(windowDays))
        let recent = ((try? context.fetch(FetchDescriptor<WorkoutRecord>())) ?? [])
            .filter { $0.endDate >= cutoff && $0.effectiveProfile != .easy }
        guard recent.count >= 6 else { return (nil, nil) }

        let perWeek = Double(recent.count) / (windowDays / 7)
        var counts: [WorkoutProfile: Int] = [:]
        for workout in recent { counts[workout.effectiveProfile, default: 0] += 1 }
        let dominant = counts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.rawValue > rhs.key.rawValue : lhs.value < rhs.value
        }?.key
        return (WeeklyVolume.forSessionsPerWeek(perWeek), dominant)
    }

    // MARK: - Import

    private func importWorkouts() async {
        // `nil` is a read that did not happen; `[]` is a store that genuinely
        // has no workouts left. Only the second one may delete anything, or a
        // revoked permission or a flaky query erases the user's history.
        guard let imported = await HealthKitService.shared.fetchWorkouts() else {
            lastImportFailed = true
            return
        }

        let existing = (try? context.fetch(FetchDescriptor<WorkoutRecord>())) ?? []
        let importCutoff = DateHelpers.daysAgo(HealthKitService.importDays)
        let recentExisting = existing.filter { $0.endDate >= importCutoff }
        // HealthKit deliberately makes a denied read look like an empty store.
        // If recent records already exist, treating that empty result as a
        // deletion would erase the user's history after permission is revoked.
        guard !imported.isEmpty || recentExisting.isEmpty else {
            lastImportFailed = true
            engineLogger.error("Health returned no workouts while recent cached records exist; preserving the cache")
            return
        }

        lastImportFailed = false
        lastSuccessfulImport = .now
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
            // No sessions to observe, but the questionnaire still says something,
            // and it is the whole of what a day-one Recharge+ user is shown.
            personalAnalysis = PersonalRecoveryModel.analyse(
                profile: settings.athleteProfile, sessions: [], days: [], now: now
            )
            personalizedPreview = .reference(factor: personalAnalysis.factor)
            return
        }

        let contexts = ((try? context.fetch(FetchDescriptor<DailyContextRecord>())) ?? [])
        let contextByKey = Dictionary(contexts.map { ($0.dateKey, $0) }, uniquingKeysWith: { first, _ in first })
        let restingBaseline = median(contexts.map(\.restingHeartRate).filter { $0 > 0 })
        let hrvBaseline = median(contexts.map(\.heartRateVariability).filter { $0 > 0 })

        let existingStates = ((try? context.fetch(FetchDescriptor<RecoveryStateRecord>())) ?? [])
        var statesByID = Dictionary(existingStates.map { ($0.sessionID, $0) }, uniquingKeysWith: { first, _ in first })

        // Pass one: the standard estimate for every session. It is what the free
        // tier publishes, and the thirty-day analysis needs to know what window
        // each session *would* have had before it can say whether the person
        // training inside it held up.
        let inputs = workouts.map { sessionInput(for: $0, settings: settings) }
        let standardEstimates = inputs.map { session in
            RecoveryCalculator.estimate(
                for: session,
                baseline: .standard(for: session.profile),
                now: now
            )
        }

        let isPro = StoreService.shared.isPro
        let analysis = PersonalRecoveryModel.analyse(
            profile: settings.athleteProfile,
            sessions: zip(inputs, standardEstimates).map { session, standard in
                PersonalRecoveryModel.HistorySession(
                    id: session.id,
                    profile: session.profile,
                    endDate: session.endDate,
                    load: standard.load.value,
                    intensityFraction: SessionLoadCalculator.intensityFraction(for: session),
                    standardHours: standard.hours
                )
            },
            days: contexts.map {
                PersonalRecoveryModel.DayPoint(
                    date: $0.date,
                    restingHeartRate: $0.restingHeartRate > 0 ? $0.restingHeartRate : nil,
                    heartRateVariability: $0.heartRateVariability > 0 ? $0.heartRateVariability : nil
                )
            },
            now: now
        )
        personalAnalysis = analysis

        var history: [(profile: WorkoutProfile, load: Double, date: Date)] = []
        var results: [RecoveryEstimate] = []
        var preview: PersonalizedPreview?

        // Pass two: the estimate the user actually gets. On the free tier that is
        // the standard one already computed — no personal baseline, no overnight
        // context, no calibration, the same table for everyone.
        for (index, workout) in workouts.enumerated() {
            let session = inputs[index]
            // Scored the personalized way regardless of tier. A paying user gets
            // it as their estimate; a free user gets it as the only honest way to
            // show what the upgrade would actually do to *their* numbers.
            let personalized = RecoveryCalculator.estimate(
                for: session,
                baseline: RecoveryBaseline.build(
                    from: history,
                    for: session.profile,
                    now: workout.endDate
                ),
                context: settings.useContextSignals
                    ? contextFor(
                        workout: workout,
                        contextByKey: contextByKey,
                        restingBaseline: restingBaseline,
                        hrvBaseline: hrvBaseline
                    )
                    : .empty,
                calibration: settings.calibrationFactor,
                personalization: .personalized(factor: analysis.factor),
                standardHours: standardEstimates[index].hours,
                now: now
            )
            let estimate = isPro ? personalized : standardEstimates[index]

            // Overwrites as the loop walks forward, so the survivor is the most
            // recent session that produced a countdown either way.
            if standardEstimates[index].producesCountdown || personalized.producesCountdown {
                preview = PersonalizedPreview(
                    label: "Your last \(session.activityLabel)",
                    standardHours: standardEstimates[index].hours,
                    personalizedHours: personalized.hours,
                    isExample: false
                )
            }

            // Cache the load back onto the workout so the baseline for the next
            // session (and the weekly load view) does not have to recompute it.
            // The chain always uses the freshly computed load, even for a frozen
            // record, so a later session is never scored against a stale
            // baseline.
            workout.sessionLoad = estimate.load.value
            workout.loadSource = estimate.load.source

            let published: RecoveryEstimate
            if let record = statesByID[workout.healthKitUUID] {
                // Build 10 records are missing their tier fields. Keep an
                // expired one frozen until RevenueCat answers, then rescore it
                // once under the customer's actual tier.
                let isFrozen = record.readyAt <= now
                    && !unfreezeAll
                    && workout.healthKitUUID != unfrozenSessionID
                    && (
                        record.hasCompleteTierMetadata
                            || !StoreService.shared.entitlementStatusResolved
                    )
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

        // No qualifying session yet is not a reason to show nothing, and neither
        // is a session where the two happen to land on the same rounded hour:
        // fall back to the canonical hard session, which is a real point on the
        // real curve and where the multiplier has room to show.
        if let preview, preview.isVisiblyDifferent {
            personalizedPreview = preview
        } else {
            let reference = PersonalizedPreview.reference(factor: analysis.factor)
            personalizedPreview = reference.isVisiblyDifferent ? reference : (preview ?? reference)
        }

        estimates = results.sorted { $0.sessionEnd > $1.sessionEnd }
        // Every "is this still running / recent enough to ask about" decision
        // below reads the same `now` the estimates were calculated against.
        // Reaching for `Date.now` here instead made a rescore at an injected
        // instant resolve its current estimate and its effort prompt against the
        // wall clock, so the two halves of one pass could disagree.
        current = RecoveryResolver.current(in: results, now: now)
        awaitingFeedback = RecoveryResolver.awaitingFeedback(
            in: results, answered: settings.answeredFeedbackSessions, now: now
        )
        let declined = settings.declinedEffortSessions
        awaitingEffort = workouts
            .filter {
                $0.wantsEffortInput
                    && now.timeIntervalSince($0.endDate) < 2 * 86_400
                    && !declined.contains($0.healthKitUUID)
            }
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

    /// Records that the user declined to rate a session, from either device, and
    /// stops asking about it.
    ///
    /// `publish()` is what actually retires the request on the wrist: it clears
    /// `pendingEffortSessionID` in the App Group and pushes the change to the
    /// Watch, so a decline on one device is honoured on both.
    public func declineEffort(forSessionID sessionID: String) {
        let settings = RechargeSettings.shared
        guard !settings.declinedEffortSessions.contains(sessionID) else { return }
        settings.declinedEffortSessions.insert(sessionID)
        if awaitingEffort?.healthKitUUID == sessionID { awaitingEffort = nil }
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

    /// Advances time-based state without performing another HealthKit import.
    /// The Today timer calls this so an open app asks for feedback and records a
    /// Ready moment when the countdown expires, not on the next launch.
    public func handleClockTick(now: Date = .now) {
        awaitingFeedback = RecoveryResolver.awaitingFeedback(
            in: estimates,
            answered: RechargeSettings.shared.answeredFeedbackSessions,
            now: now
        )
        guard let estimate = RecoveryResolver.current(in: estimates, now: now),
              estimate.producesCountdown,
              estimate.readyAt <= now
        else { return }
        ReviewPromptTracker.recordReadyMoment(sessionID: estimate.sessionID)
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
        personalAnalysis = ScreenshotFixtures.personalAnalysis()
        personalizedPreview = ScreenshotFixtures.personalizedPreview()
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
        // The capture bypasses HealthKit entirely, so the freshness stamp has to
        // be seeded by hand or every screenshot shows an app that has never
        // successfully read anything.
        lastSuccessfulImport = .now
        lastImportFailed = false
    }
    #endif
}
