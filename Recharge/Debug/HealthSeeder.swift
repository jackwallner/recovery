#if DEBUG
import Foundation
@preconcurrency import HealthKit
/// Writes a plausible training history into the **simulator's** Health store so
/// the app can be looked at the way a user sees it.
///
/// Screenshot fixtures bypass HealthKit entirely and hand `RecoveryEngine` a
/// fixed array of finished estimates, which is right for a reproducible capture
/// and useless for the question this exists to answer: what does the app look
/// like when it has actually imported somebody's training. Everything
/// interesting lives in the path fixtures skip — classification, heart-rate
/// coverage, the observed maximum, the quiet threshold, day grouping, stacking,
/// the thirty-day analysis. A fixture that agrees with itself proves nothing.
///
/// Activated with `RECHARGE_SEED_HEALTH=1` in the environment. Never compiled
/// into a Release build, and it asks for **write** authorization, which the real
/// app never does.
///
/// Every sample carries `seedMarker` in its metadata, so a rerun replaces its
/// own data and touches nothing else in the store.
enum HealthSeederConfig {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["RECHARGE_SEED_HEALTH"] == "1"
    }

    /// Days of history to write. Matches the app's own import window, so the
    /// seeded store exercises the same boundary the real one does.
    ///
    /// The default is spelled out rather than read from
    /// `HealthKitService.importDays`, which is main-actor isolated and cannot be
    /// touched from a nonisolated default. `seedCoversTheImportWindow` in
    /// `HealthSeeder` asserts the two still agree.
    static let defaultDays = 120

    static var days: Int {
        if let override = ProcessInfo.processInfo.environment["RECHARGE_SEED_DAYS"],
           let parsed = Int(override) {
            return parsed
        }
        return defaultDays
    }
}

private let seedMarker = "RechargeSeededSample"

/// Where the seeder says what it is doing.
///
/// `Logger.info` lives in the memory buffer and needs `log stream --level info`
/// to be visible at all, which is why an earlier investigation concluded
/// "nothing reaches the device log" and stopped there. A breadcrumb file in the
/// app's own container is retrievable with `simctl get_app_container` after the
/// run, whether or not anybody was streaming at the time, and survives the
/// process being killed by the test harness.
enum SeedTrace {
    private static let url: URL? = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("seed-trace.log")
    }()

    /// Truncates, so a rerun's trace is not read as the previous run's.
    static func begin(_ message: String) {
        if let url { try? Data().write(to: url) }
        mark(message)
    }

    static func mark(_ message: String) {
        let line = String(format: "%.3f %@\n", Date().timeIntervalSince1970, message)
        NSLog("[seed] %@", message)
        guard let url else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}

@MainActor
enum HealthSeeder {
    private static let store = HKHealthStore()

    private static var shareTypes: Set<HKSampleType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.heartRateRecoveryOneMinute),
            HKQuantityType(.vo2Max),
            HKQuantityType(.bodyMass),
            HKCategoryType(.sleepAnalysis)
        ]
    }

    /// The seeder's default window has to cover the app's import window or a
    /// seeded run quietly tests less than it looks like it does.
    static var seedCoversTheImportWindow: Bool {
        HealthSeederConfig.defaultDays >= HealthKitService.importDays
    }

    static func seedIfRequested() async {
        guard HealthSeederConfig.isEnabled, HKHealthStore.isHealthDataAvailable() else { return }
        assert(seedCoversTheImportWindow, "Seed window is shorter than HealthKitService.importDays")
        SeedTrace.begin("seedIfRequested: enter, days=\(HealthSeederConfig.days)")
        do {
            SeedTrace.mark("requestAuthorization: begin")
            try await store.requestAuthorization(toShare: shareTypes, read: HealthKitService.readTypes)
            SeedTrace.mark("requestAuthorization: done")
            try await deleteExistingSeed()
            SeedTrace.mark("deleteExistingSeed: done")
            try await write(days: HealthSeederConfig.days)
            SeedTrace.mark("seeded \(HealthSeederConfig.days) days")
        } catch {
            SeedTrace.mark("FAILED: \(String(describing: error))")
        }
    }

    // MARK: - Cleanup

    /// Clears the previous seed, by **source** as well as by marker.
    ///
    /// The marker alone did not work and the failure was invisible until the
    /// walkthrough finally ran: `HKWorkoutBuilder` never carried `seedMarker`,
    /// so every workout the seeder had ever written survived every later run,
    /// and History showed one 62-minute lift four times over, once per run,
    /// stacking into a 72-hour countdown out of a single session. The samples
    /// *inside* those workouts were marked and were deleted, so what
    /// accumulated was a pile of workouts with no heart rate, which is also the
    /// shape most likely to be read as a model bug rather than a seeding one.
    ///
    /// The workout carries the marker now, and the predicate additionally
    /// matches anything this app wrote. **Recharge never writes to Health**:
    /// the seeder is the only thing in the product that asks for share
    /// authorization at all, so "written by this source" is exactly "seeded",
    /// and it clears whatever an older build left behind rather than only what
    /// this one would recognise.
    private static func deleteExistingSeed() async throws {
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(
                withMetadataKey: seedMarker,
                operatorType: .equalTo,
                value: 1 as NSNumber
            ),
            HKQuery.predicateForObjects(from: [HKSource.default()])
        ])
        for type in shareTypes {
            // A type with nothing seeded throws `noDataAvailable`, which is not
            // an error here — it is the ordinary first run.
            _ = try? await store.deleteObjects(of: type, predicate: predicate)
        }
    }

    // MARK: - The persona

    /// A 34-year-old who trains five or six times a week: two runs, two lifts,
    /// a weekend long ride, and a walk most days.
    ///
    /// Deliberately *not* a tidy athlete. The interesting states in this app are
    /// the messy ones — a lift whose optical heart rate drops out, a walk that
    /// earns no countdown, a Saturday double that stacks — and a persona that
    /// only ever does clean threshold runs would show none of them.
    private struct Session {
        let activity: HKWorkoutActivityType
        let minutes: Double
        /// Fraction of heart-rate reserve held, which is what the samples are
        /// generated from rather than an average bolted on afterwards.
        let reserve: Double
        /// Fraction of the session the heart-rate strap actually covers. Low for
        /// lifting, which is the whole reason the load ladder exists.
        let coverage: Double
    }

    private static let restingHeartRate: Double = 52
    private static let trueMaxHeartRate: Double = 187
    private static let bodyMass: Double = 78

    /// One week of training, indexed by weekday. Seven entries, some empty.
    private static func sessions(forWeekday weekday: Int, week: Int) -> [Session] {
        switch weekday {
        case 1: // Sunday: long ride, and a walk
            return [
                Session(activity: .cycling, minutes: 95 + Double(week % 3) * 12, reserve: 0.66, coverage: 0.95),
                Session(activity: .walking, minutes: 32, reserve: 0.30, coverage: 0.8)
            ]
        case 2: // Monday: easy
            return [Session(activity: .walking, minutes: 45, reserve: 0.28, coverage: 0.85)]
        case 3: // Tuesday: intervals
            return [Session(activity: .running, minutes: 52, reserve: 0.79, coverage: 0.97)]
        case 4: // Wednesday: lift, with the sensor half asleep
            return [Session(activity: .traditionalStrengthTraining, minutes: 62, reserve: 0.44, coverage: 0.31)]
        case 5: // Thursday: steady run
            return [Session(activity: .running, minutes: 46, reserve: 0.68, coverage: 0.96)]
        case 6: // Friday: lift plus an evening walk
            return [
                Session(activity: .functionalStrengthTraining, minutes: 55, reserve: 0.51, coverage: 0.36),
                Session(activity: .walking, minutes: 25, reserve: 0.27, coverage: 0.7)
            ]
        case 7: // Saturday: the double, every third week
            return week % 3 == 0
                ? [
                    Session(activity: .running, minutes: 38, reserve: 0.72, coverage: 0.95),
                    Session(activity: .highIntensityIntervalTraining, minutes: 34, reserve: 0.81, coverage: 0.9)
                  ]
                : [Session(activity: .running, minutes: 70, reserve: 0.62, coverage: 0.94)]
        default:
            return []
        }
    }

    // MARK: - Writing

    private static func write(days: Int) async throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        var dailySamples: [HKSample] = []
        var written = 0

        for dayOffset in stride(from: days, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let week = dayOffset / 7

            // A fortnight off, five weeks back, because a real history has gaps
            // and the baseline's day count has to survive one.
            let isLayoff = (35...48).contains(dayOffset)

            for (index, session) in sessions(forWeekday: weekday, week: week).enumerated() where !isLayoff {
                // The first session lands mid-morning, the second in the
                // evening, which is what makes a same-day double stack.
                let hour = index == 0 ? 8 : 18
                guard let start = calendar.date(bySettingHour: hour, minute: 15, second: 0, of: day),
                      start < .now
                else { continue }
                let end = start.addingTimeInterval(session.minutes * 60)
                guard end < .now else { continue }
                try await writeWorkout(session, start: start, end: end)
                written += 1

                if session.reserve > 0.55 {
                    dailySamples.append(heartRateRecoverySample(after: end, reserve: session.reserve))
                }
            }

            // Overnight context, keyed on the morning the night ended. The
            // day-after bump is what `PersonalRecoveryModel`'s rebound signal
            // is looking for, so it has to actually be here or the analysis has
            // nothing to measure and the Recharge+ pitch reads as neutral.
            let strain = strainFactor(dayOffset: dayOffset, calendar: calendar, today: today)
            guard let morning = calendar.date(bySettingHour: 6, minute: 30, second: 0, of: day),
                  morning < .now
            else { continue }

            dailySamples.append(quantity(
                .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                value: restingHeartRate + strain * 5 + noise(dayOffset, 1.4),
                at: morning
            ))
            dailySamples.append(quantity(
                .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                value: max(58 - strain * 12 + noise(dayOffset, 4), 20),
                at: morning
            ))
            dailySamples.append(quantity(
                .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                value: 14.2 + strain * 1.3 + noise(dayOffset, 0.4),
                at: morning
            ))
            if let sleep = sleepSample(endingAt: morning, dayOffset: dayOffset) {
                dailySamples.append(sleep)
            }
        }

        // One current figure each. Both are read as "the latest sample", so a
        // series would be wasted work.
        if let now = calendar.date(byAdding: .day, value: -1, to: .now) {
            dailySamples.append(quantity(
                .vo2Max,
                unit: HKUnit(from: "ml/kg*min"),
                value: 51.4,
                at: now
            ))
            dailySamples.append(quantity(
                .bodyMass,
                unit: .gramUnit(with: .kilo),
                value: bodyMass,
                at: now
            ))
        }

        try await store.save(dailySamples)
        SeedTrace.mark("wrote \(written) workouts and \(dailySamples.count) daily samples")
    }

    /// How hard the previous two days were, 0...1. Drives the overnight signals
    /// so the rebound measurement has a real disturbance to measure.
    private static func strainFactor(dayOffset: Int, calendar: Calendar, today: Date) -> Double {
        var total = 0.0
        for lookback in 1...2 {
            guard let day = calendar.date(byAdding: .day, value: -(dayOffset + lookback), to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let hardest = sessions(forWeekday: weekday, week: (dayOffset + lookback) / 7)
                .map(\.reserve)
                .max() ?? 0
            // Yesterday counts for twice what the day before does, which is the
            // decay the rebound ratio is trying to estimate.
            total += hardest * (lookback == 1 ? 0.7 : 0.3)
        }
        return min(max(total, 0), 1)
    }

    private static func writeWorkout(_ session: Session, start: Date, end: Date) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = session.activity
        configuration.locationType = .unknown

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: nil)
        try await builder.beginCollection(at: start)

        // One heart-rate sample every thirty seconds. Truncated to `coverage` of
        // the session, so a lifting session genuinely arrives with the sensor
        // having dropped out rather than with a coverage figure asserted on top
        // of full data.
        //
        // Thirty rather than an Apple Watch's five, for two reasons and the
        // second is the interesting one. It is six times fewer samples, and at
        // five seconds a two-month seed did not finish inside six minutes. And
        // it is a cadence no Apple Watch writes, which is exactly what makes it
        // worth seeding: `HealthKitService.heartRateSummary` used to assume five
        // seconds per sample and would have read every one of these sessions as
        // having lost five sixths of its trace.
        let interval: TimeInterval = 30
        let total = end.timeIntervalSince(start)
        let covered = total * session.coverage
        var samples: [HKSample] = []
        var elapsed: TimeInterval = 0
        var index = 0
        while elapsed < covered {
            let progress = elapsed / max(total, 1)
            // A warm-up ramp, then the working reserve, with a hard finish on
            // the interval sessions so there is a real peak for the observed
            // maximum to find.
            let shape = progress < 0.12
                ? progress / 0.12 * 0.85
                : (progress > 0.9 && session.reserve > 0.7 ? 1.14 : 1.0)
            let reserve = min(max(session.reserve * shape + noise(index, 0.03), 0), 1)
            let bpm = restingHeartRate + reserve * (trueMaxHeartRate - restingHeartRate)
            let at = start.addingTimeInterval(elapsed)
            samples.append(quantity(
                .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                value: bpm,
                at: at,
                end: at
            ))
            elapsed += interval
            index += 1
        }

        // Active energy at roughly the reference burn rate for this reserve
        // fraction, scaled by the persona's mass — which is exactly the
        // relationship `SessionLoadCalculator.referenceEnergy(forBodyMass:)`
        // now undoes, so a seeded run is a real test of that correction.
        let massRatio = bodyMass / SessionLoadCalculator.referenceBodyMassKilograms
        let kilocalories = session.minutes
            * session.reserve
            * SessionLoadCalculator.referenceEnergyAtFullReserve
            * massRatio
        samples.append(quantity(
            .activeEnergyBurned,
            unit: .kilocalorie(),
            value: kilocalories,
            at: start,
            end: end
        ))

        try await builder.addSamples(samples)
        // Without this the workout is unmarked and `deleteExistingSeed` cannot
        // find it, so every run leaves its workouts behind for the next one.
        try await builder.addMetadata([seedMarker: 1])
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }

    private static func heartRateRecoverySample(after end: Date, reserve: Double) -> HKSample {
        // A well-trained one-minute recovery, which is what makes the kinetics
        // signal say something rather than sit at neutral.
        quantity(
            .heartRateRecoveryOneMinute,
            unit: HKUnit.count().unitDivided(by: .minute()),
            value: 34 + reserve * 6 + noise(Int(end.timeIntervalSince1970) % 97, 2),
            at: end.addingTimeInterval(60),
            end: end.addingTimeInterval(120)
        )
    }

    private static func sleepSample(endingAt morning: Date, dayOffset: Int) -> HKSample? {
        let hours = 7.1 + noise(dayOffset, 0.9)
        let start = morning.addingTimeInterval(-hours * 3600)
        guard start < morning else { return nil }
        return HKCategorySample(
            type: HKCategoryType(.sleepAnalysis),
            value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: start,
            end: morning,
            metadata: [seedMarker: 1]
        )
    }

    // MARK: - Helpers

    private static func quantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        value: Double,
        at start: Date,
        end: Date? = nil
    ) -> HKQuantitySample {
        HKQuantitySample(
            type: HKQuantityType(identifier),
            quantity: HKQuantity(unit: unit, doubleValue: value),
            start: start,
            end: end ?? start,
            metadata: [seedMarker: 1]
        )
    }

    /// Deterministic pseudo-noise. A seeded run has to be reproducible or two
    /// screenshots of the same build disagree for no reason.
    private static func noise(_ seed: Int, _ amplitude: Double) -> Double {
        let x = sin(Double(seed) * 12.9898) * 43758.5453
        return (x - x.rounded(.down) - 0.5) * 2 * amplitude
    }
}
#endif
