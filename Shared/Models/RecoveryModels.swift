import Foundation

// MARK: - Model version

/// Bumped whenever the calculator's numbers change. Stored on every estimate so
/// history can explain why an old window disagrees with what the same session
/// would produce today, and so the determinism test has something to pin to.
///
/// 2: the standard/personalized split. Version 1 scored every user against their
/// own median session; the free tier now scores against a fixed population
/// reference, and Recharge+ adds `PersonalRecoveryModel` on top.
///
/// 3: the load ladder and the floor. Strength now takes the highest available
/// signal instead of the first one it trusts, so a lift no longer scores three
/// different windows depending on which sensor worked; the energy inference is
/// floored for strength, where kilocalories per minute under-read for reasons
/// unrelated to how hard the session was; and every qualifying session clears
/// six hours, the minimum Garmin documents for the same feature. Windows for
/// strength sessions roughly doubled; endurance is unchanged except below the
/// floor.
///
/// 5: what "typical" means, on both sides of the comparison. The personal
/// baseline is totalled **per day** rather than per session, because a user who
/// trains three times a day was being described by the median of one of those
/// sessions — so their ordinary Tuesday read as five times normal, pinned the
/// 72-hour ceiling, and every extra session they did made it worse. And the
/// population reference came down to a lightly active adult's training day
/// (85/105/115 to 52/64/70, ratios unchanged), because it is the answer given to
/// someone with no history and that person is not a trained athlete. Together
/// they put the two tiers the right way round: training more now shortens the
/// window instead of lengthening it. Free-tier windows get longer; windows for
/// anyone training more than a couple of times a week get shorter.
///
/// 8: recovery time is cumulative. A session done inside a running countdown now
/// starts its own from where that countdown would have finished rather than from
/// now, so a same-day double costs more than a single session. Recharge used to
/// take the *maximum* of overlapping windows, which made two hard sessions four
/// hours apart read exactly like one, at the one moment somebody coming from a
/// Garmin expects the number to jump. Only windows that overlap change, so a
/// user who trains once a day sees nothing move.
///
/// 9: uncertainty ranges obey the same 72-hour ceiling as the point estimate,
/// and non-finite sensor, calibration, and residual inputs fall back to safe
/// finite values instead of reaching a view or a persisted record.
///
/// 10: the app measures more of what it was guessing. The heart-rate ceiling is
/// now the person's own *observed* maximum where the workout history has one,
/// and the age formula is the fallback rather than the answer — which moves
/// every intensity reading for anyone whose real ceiling is not what Tanaka
/// predicts. VO2 max joins the two training-level questions in
/// `AthleteProfile.fitnessScale`, on both tiers, because it is a measurement of
/// training level rather than a personalisation of the window. Body mass closes
/// the energy path's known residual, so an 95 kg lifter's calorie-derived load
/// stops reading as a harder session than it was. Overnight respiratory rate
/// joins sleep, resting heart rate and HRV in the context adjustment, and
/// heart-rate recovery joins the thirty-day analysis as a fourth signal. And
/// **every** session now carries a `recoveryCostHours`, easy ones included, so
/// history has a figure for a walk without a walk ever starting a countdown.
/// 11: the two tiers stopped being two versions of the same calculation. The
/// free tier now **describes** what the person actually does — the median gap
/// between sessions of comparable size, read off their own history by
/// `ObservedRecoveryPattern` — and Recharge+ **recommends** a window against
/// that habit. The old split scored the same session against two different
/// denominators, one population and one personal, with nothing bounding the
/// distance between them: a user training seven days a week in short sessions
/// was shown 6 hours free and 36 hours paid for one workout. Both were correct
/// arithmetic and the pair was nonsense. The personal denominator is also now
/// bounded to 0.75-1.40x the population reference for the same reason, so the
/// paid figure can be tuned but never relocated.
public let recoveryModelVersion = 11

// MARK: - Tier

/// Which of the two models produced an estimate.
///
/// Stored on every estimate, because the two answer subtly different questions
/// and a history list that mixes them without saying so is lying by omission.
public enum RecoveryTier: String, Codable, Sendable {
    /// What the person actually does: the median gap between sessions of
    /// comparable size, read off their own history by `ObservedRecoveryPattern`.
    /// A description, not a prediction — which is what makes it a number they
    /// can always recognise. Falls back to the modelled estimate at the training
    /// level they stated, while their history is too thin to show a pattern.
    ///
    /// The raw value stays `standard` because it is persisted on every record
    /// ever written.
    case standard
    /// What the model recommends for this session: their own baseline, their
    /// thirty-day analysis, overnight context, and their calibration feedback.
    case personalized

    public var label: String {
        switch self {
        case .standard: "Your usual"
        case .personalized: "Optimal"
        }
    }
}

/// The Recharge+ multiplier, carried into the calculator as one value so the
/// calculator itself stays free of any notion of entitlement.
public struct RecoveryPersonalization: Sendable, Equatable {
    public let tier: RecoveryTier
    /// Multiplier on the standard window. Exactly 1 for `.standard`.
    public let factor: Double

    public static let standard = RecoveryPersonalization(tier: .standard, factor: 1)

    public static func personalized(factor: Double) -> RecoveryPersonalization {
        RecoveryPersonalization(tier: .personalized, factor: PersonalRecoveryModel.clamp(factor))
    }

    private init(tier: RecoveryTier, factor: Double) {
        self.tier = tier
        self.factor = factor
    }
}

// MARK: - Profiles

/// The four recovery curves. A session is classified into exactly one; the load
/// source and the shape of the decay both depend on which.
public enum WorkoutProfile: String, Codable, CaseIterable, Sendable {
    /// Run, ride, row, swim. Heart-rate reserve TRIMP is reliable here.
    case endurance
    /// Lifting. Optical HR is unreliable under grip and bar contact, so this
    /// leans on perceived effort; longer tail than endurance at equal effort.
    case strength
    /// HYROX, CrossFit, circuits. Both systems taxed, so the longest window.
    case mixed
    /// Walk, yoga, mobility. Contributes nothing and never starts or extends a
    /// countdown.
    case easy

    public var label: String {
        switch self {
        case .endurance: "Endurance"
        case .strength: "Strength"
        case .mixed: "Mixed"
        case .easy: "Easy"
        }
    }

    /// Recovery-window multiplier relative to the endurance baseline curve.
    /// `easy` is zero because an active-recovery session must never produce a
    /// countdown at all.
    public var windowMultiplier: Double {
        switch self {
        case .endurance: 1.0
        case .strength: 1.15
        case .mixed: 1.30
        case .easy: 0.0
        }
    }

    /// Recovery **cost** multiplier, which is `windowMultiplier` everywhere it
    /// matters and a small positive number for `easy`.
    ///
    /// The two are separate because they answer different questions, and
    /// collapsing them is what put the word "None" beside every walk in
    /// history. `windowMultiplier` decides how long a *countdown* runs, and easy
    /// has to be exactly zero there or an active-recovery walk could start or
    /// lengthen one — the guarantee the whole `easy` profile exists to make.
    /// `costMultiplier` decides what the session *cost*, which is a description
    /// of the session rather than an instruction to the countdown, and a
    /// forty-minute walk did not cost nothing.
    ///
    /// Nothing downstream of the countdown reads this: `producesCountdown`,
    /// `readyAt`, `totalHours`, the snapshot, the complication and the stacking
    /// chain are all still driven by `hours`, which is still zero for easy.
    public var costMultiplier: Double {
        switch self {
        case .easy: 0.30
        default: windowMultiplier
        }
    }

    /// Perceived effort assumed when a session has neither usable heart rate nor
    /// energy data. Deliberately mid-range: enough to register, not enough to
    /// dominate a countdown on a guess.
    public var assumedEffort: Double {
        switch self {
        case .endurance: 5
        // Was 6, which made the blind guess the *largest* signal for a lifting
        // session: 60 minutes of it produced more load than the same session's
        // energy reading. A fallback has to sit at or below what the informed
        // sources say for a typical session of the type, or having no data pays
        // better than having some.
        case .strength: 5
        // Was 7, for the same reason strength's was 6: it put the blind guess
        // above every informed source for a typical session of the type. A
        // 60-minute mixed session reads 78 from a good heart-rate trace and 108
        // from an RPE of 6, and the type-typical fallback was scoring it 126 —
        // so a manually entered game outscored a recorded one, and the longest
        // window in the app belonged to the session it knew least about.
        case .mixed: 6
        case .easy: 2
        }
    }

    /// The population reference a session is measured against when there is no
    /// personal history to use: the whole of the standard tier, and the
    /// bootstrap for a Recharge+ user in their first few weeks.
    ///
    /// **The anchor is Firstbeat's activity class 3 to 5, "already engaged in
    /// training" — not a sedentary adult and not a trained one.** That is where
    /// Garmin's own default sits, and Recharge's standard tier is trying to be
    /// the same thing: the estimate you get before anything has been measured
    /// about you. Firstbeat's scale runs 0 to 2 for beginners, 3 to 5 for people
    /// already training, 6 to 7 for the highly fit, and 7.5 to 10 for athletes,
    /// and Training Effect (which recovery time is derived from) is EPOC scaled
    /// by that class. Picking the bottom of the scale is not a neutral default,
    /// it is a different claim about the user.
    ///
    /// | Profile | Reference training day | Load |
    /// |---|---|---|
    /// | endurance | ~45 min at 65% heart-rate reserve | 70 |
    /// | strength | ~50 min at RPE 5.5 | 86 |
    /// | mixed | ~45 min at RPE 6.5 | 94 |
    ///
    /// The endurance figure is **fitted**, not chosen: `GarminAnchorTests` scores
    /// thirteen canonical sessions against the recovery-time bands Garmin is
    /// observed to produce (easy 0-12h, moderate 12-24h, hard 24-48h, very hard
    /// 48-72h) and 70 is the value that lands all thirteen inside their band. The
    /// two previous values both miss, in opposite directions: 85 ran short from a
    /// steady 45 minutes upward, and 52 ran long enough that an ordinary tempo
    /// hour returned 50 hours and a hard interval session pinned the 72-hour
    /// ceiling. 52 came from wanting personalisation to be able to shorten a fit
    /// user's window, which was the right goal aimed at the wrong constant: the
    /// personal denominator is *measured* from their own history and is free to
    /// be two or three times this, so lowering the population reference never
    /// created that headroom. It only made the free tier longer for everybody,
    /// including the beginner it was lowered for.
    ///
    /// The ratios between the three profiles are unchanged across all three
    /// revisions (85/105/115, then 52/64/70, now 70/86/94), so nothing about the
    /// relative cost of a lift against a ride has ever been retuned here. Only
    /// the level has moved.
    ///
    /// Compare `RecoveryBaseline.typicalLoad`, which is the same quantity
    /// measured from the person's own history and totalled per day. The two have
    /// to describe the same kind of thing or the comparison the app is built on
    /// is a change of units.
    public var standardTypicalLoad: Double {
        switch self {
        case .endurance: 70
        case .strength: 86
        case .mixed: 94
        case .easy: 16
        }
    }

    /// True when perceived effort is worth asking the user for. Strength and
    /// mixed sessions are exactly the ones heart rate gets wrong.
    public var wantsEffortInput: Bool {
        self == .strength || self == .mixed
    }
}

// MARK: - Load

/// Which of the three fallbacks actually produced the session load. Drives both
/// the confidence rating and the "why" copy.
public enum LoadSource: String, Codable, Sendable {
    /// Heart-rate-reserve TRIMP from in-workout heart-rate samples.
    case heartRate
    /// User-reported effort (session RPE).
    case reportedEffort
    /// Duration + active energy, with an intensity inferred from the burn rate.
    case energy
    /// Duration and profile only. Weakest signal we will act on.
    case duration

    public var label: String {
        switch self {
        case .heartRate: "heart rate"
        case .reportedEffort: "your effort rating"
        case .energy: "duration and energy"
        case .duration: "duration"
        }
    }
}

/// One session scored both ways: the standard window beside the personalized
/// one. What every Recharge+ conversion surface argues from.
///
/// The two figures are always computed, never derived by multiplying the
/// standard hours by the thirty-day factor. Personalisation changes the
/// *baseline* a session is measured against as well as applying the multiplier,
/// and the derived version dropped the larger of the two effects.
public struct PersonalizedPreview: Sendable, Equatable {
    public let label: String
    /// What the free tier shows: the person's own usual gap after a session
    /// like this one, or the standard estimate while their history is too thin
    /// to have shown one.
    public let standardHours: Double
    /// What Recharge+ recommends for the same session.
    public let personalizedHours: Double
    /// True when there was no qualifying session to use and the figures come
    /// from the canonical hard endurance session instead. Surfaces have to say
    /// so: "for example" is the difference between a projection and a claim
    /// about the user's own training.
    public let isExample: Bool

    public init(label: String, standardHours: Double, personalizedHours: Double, isExample: Bool) {
        self.label = label
        self.standardHours = standardHours
        self.personalizedHours = personalizedHours
        self.isExample = isExample
    }

    /// The fallback for a user with no qualifying session yet: a real point on
    /// the real curve, so even day one shows arithmetic rather than a mock-up.
    public static func reference(factor: Double) -> PersonalizedPreview {
        let hours = RecoveryCalculator.referenceHardSessionHours
        return PersonalizedPreview(
            label: "A hard 60-minute session",
            standardHours: hours,
            personalizedHours: hours * factor,
            isExample: true
        )
    }

    /// Whether the two figures would render as the same string. The conversion
    /// card leads with the difference, so a surface has to be able to ask.
    public var isVisiblyDifferent: Bool {
        abs(personalizedHours - standardHours) >= 0.5
    }
}

/// Where a session sits against the person's own recent history.
public enum LoadCategory: String, Codable, Sendable {
    case easy
    case typical
    case hard
    case unusuallyHard

    /// One intensity ladder, four rungs.
    ///
    /// "Easy" and "Typical" were the original words and they were reading as two
    /// different kinds of statement: one about how hard the session felt, one
    /// about how it compared to something the label never named. Light /
    /// Moderate / Hard / Very hard is a single scale, and the "for you" suffix
    /// is what names the comparison.
    public var label: String {
        switch self {
        case .easy: "Light for you"
        case .typical: "Moderate for you"
        case .hard: "Hard for you"
        case .unusuallyHard: "Very hard for you"
        }
    }

    /// "For you" is only true when the comparison was against the person's own
    /// sessions. On the standard tier the session is measured against a fixed
    /// population reference, so the label has to drop the claim and name the
    /// comparison it did make instead.
    public func label(for tier: RecoveryTier) -> String {
        guard tier == .standard else { return label }
        switch self {
        case .easy: return "Light session"
        case .typical: return "Moderate session"
        case .hard: return "Hard session"
        case .unusuallyHard: return "Very hard session"
        }
    }

    public var shortLabel: String {
        switch self {
        case .easy: "Light"
        case .typical: "Moderate"
        case .hard: "Hard"
        case .unusuallyHard: "Very hard"
        }
    }
}

/// The output of stage 1: one number on a common scale, plus how we got it.
public struct SessionLoad: Codable, Sendable, Equatable {
    public let value: Double
    public let source: LoadSource
    /// Fraction of the workout covered by usable heart-rate samples, 0...1.
    public let heartRateCoverage: Double

    public init(value: Double, source: LoadSource, heartRateCoverage: Double = 0) {
        self.value = value.isFinite ? max(0, value) : 0
        self.source = source
        self.heartRateCoverage = heartRateCoverage.isFinite ? min(max(heartRateCoverage, 0), 1) : 0
    }
}

// MARK: - Inputs

/// Everything the calculator needs to know about one finished workout. No
/// HealthKit types: the calculator stays pure and unit-testable.
public struct SessionInput: Sendable, Equatable {
    public let id: String
    public let profile: WorkoutProfile
    public let startDate: Date
    public let endDate: Date
    /// Wall-clock minutes of the session.
    public let durationMinutes: Double
    public let averageHeartRate: Double?
    public let restingHeartRate: Double?
    public let maxHeartRate: Double?
    public let heartRateCoverage: Double
    public let activeEnergyKilocalories: Double?
    /// Session RPE on the 1-10 Borg CR10 scale, if the user supplied one.
    public let reportedEffort: Double?
    /// The person's body mass in kilograms, when Health knows it.
    ///
    /// Only the energy path reads it, and only to undo the thing that path was
    /// always known to get wrong: HealthKit's active energy already accounts for
    /// weight, so at the same fraction of heart-rate reserve a 95 kg athlete
    /// burns more per minute than a 60 kg one and the inference reads them as
    /// having worked harder. It is a correction to a measurement, not a fact
    /// about how fast someone recovers, which is why it applies on both tiers.
    public let bodyMassKilograms: Double?
    public let activityLabel: String

    public init(
        id: String,
        profile: WorkoutProfile,
        startDate: Date,
        endDate: Date,
        durationMinutes: Double? = nil,
        averageHeartRate: Double? = nil,
        restingHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        heartRateCoverage: Double = 0,
        activeEnergyKilocalories: Double? = nil,
        reportedEffort: Double? = nil,
        bodyMassKilograms: Double? = nil,
        activityLabel: String = "workout"
    ) {
        self.id = id
        self.profile = profile
        self.startDate = startDate
        self.endDate = endDate
        let duration = durationMinutes ?? max(endDate.timeIntervalSince(startDate) / 60, 0)
        self.durationMinutes = duration.isFinite ? max(duration, 0) : 0
        self.averageHeartRate = averageHeartRate.flatMap { $0.isFinite ? $0 : nil }
        self.restingHeartRate = restingHeartRate.flatMap { $0.isFinite ? $0 : nil }
        self.maxHeartRate = maxHeartRate.flatMap { $0.isFinite ? $0 : nil }
        self.heartRateCoverage = heartRateCoverage.isFinite ? min(max(heartRateCoverage, 0), 1) : 0
        self.activeEnergyKilocalories = activeEnergyKilocalories.flatMap { $0.isFinite ? $0 : nil }
        self.reportedEffort = reportedEffort.flatMap { $0.isFinite ? min(max($0, 1), 10) : nil }
        // Bounded to a plausible adult range. A stray 0.2 kg sample from a
        // kitchen scale would otherwise divide the reference burn rate by
        // nothing and turn a gentle walk into a 72-hour window.
        self.bodyMassKilograms = bodyMassKilograms.flatMap {
            $0.isFinite && (30...250).contains($0) ? $0 : nil
        }
        self.activityLabel = activityLabel
    }
}

/// Sleep / HRV / resting-heart-rate context for the day the session landed in.
/// Every field is optional: absent context lowers confidence, it never blocks an
/// estimate.
public struct RecoveryContext: Sendable, Equatable {
    public let sleepHours: Double?
    public let heartRateVariability: Double?
    public let heartRateVariabilityBaseline: Double?
    public let restingHeartRate: Double?
    public let restingHeartRateBaseline: Double?
    /// Overnight breaths per minute, and the person's own usual figure.
    ///
    /// The fourth overnight signal, and the smallest: it moves the estimate
    /// half as far as resting heart rate does, because it is noisier and
    /// because four signals that each move the number as much as one would
    /// between them swamp the session that the estimate is supposed to be
    /// about. Like the other three it is bounded by `contextAdjustment`'s
    /// overall clamp, so adding it cannot widen the total range.
    public let respiratoryRate: Double?
    public let respiratoryRateBaseline: Double?

    public static let empty = RecoveryContext()

    public init(
        sleepHours: Double? = nil,
        heartRateVariability: Double? = nil,
        heartRateVariabilityBaseline: Double? = nil,
        restingHeartRate: Double? = nil,
        restingHeartRateBaseline: Double? = nil,
        respiratoryRate: Double? = nil,
        respiratoryRateBaseline: Double? = nil
    ) {
        self.sleepHours = sleepHours
        self.heartRateVariability = heartRateVariability
        self.heartRateVariabilityBaseline = heartRateVariabilityBaseline
        self.restingHeartRate = restingHeartRate
        self.restingHeartRateBaseline = restingHeartRateBaseline
        self.respiratoryRate = respiratoryRate
        self.respiratoryRateBaseline = respiratoryRateBaseline
    }

    /// True when nothing at all is known. Used to distinguish "no context" from
    /// "context that happens to be neutral".
    public var isEmpty: Bool {
        sleepHours == nil
            && heartRateVariability == nil
            && restingHeartRate == nil
            && respiratoryRate == nil
    }
}

// MARK: - Outputs

/// The five surfaces from the dossier collapse to four here: "low confidence" is
/// orthogonal to where the countdown is, so it rides on `Confidence` and is
/// rendered as a badge rather than replacing the phase.
public enum RecoveryPhase: String, Codable, Sendable {
    case noRecentWorkout
    case ready
    case readySoon
    case recovering

    public var label: String {
        switch self {
        case .noRecentWorkout: "No recent workout"
        case .ready: "Ready"
        case .readySoon: "Ready soon"
        case .recovering: "Recovering"
        }
    }
}

public enum RecoveryConfidence: String, Codable, Sendable, Comparable {
    case buildingBaseline
    case low
    case medium
    case high

    private var order: Int {
        switch self {
        case .buildingBaseline: 0
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }

    public static func < (lhs: RecoveryConfidence, rhs: RecoveryConfidence) -> Bool {
        lhs.order < rhs.order
    }

    public var label: String {
        switch self {
        case .buildingBaseline: "Building baseline"
        case .low: "Low confidence"
        case .medium: "Medium confidence"
        case .high: "High confidence"
        }
    }

    public var shortLabel: String {
        switch self {
        case .buildingBaseline: "Building"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

/// One finished calculation. Everything the UI, the complication, and the
/// history explanation need, with no back-reference to HealthKit.
public struct RecoveryEstimate: Codable, Sendable, Equatable, Identifiable {
    /// One estimate per session, so the session is the identity.
    public var id: String { sessionID }

    public let sessionID: String
    public let profile: WorkoutProfile
    public let activityLabel: String
    public let calculatedAt: Date
    public let sessionEnd: Date
    public let readyAt: Date
    /// Point estimate in hours. Zero means the session produced no countdown.
    public let hours: Double
    /// Bounded window we actually show, e.g. "18 to 28h".
    public let windowLowHours: Double
    public let windowHighHours: Double
    public let load: SessionLoad
    public let relativeLoad: Double
    public let category: LoadCategory
    public let confidence: RecoveryConfidence
    public let reasons: [String]
    public let modelVersion: Int
    /// Which model produced this. Defaults to `.standard` so an estimate decoded
    /// from a version-1 record still reads back.
    public let tier: RecoveryTier
    /// The Recharge+ multiplier that was applied. Exactly 1 on the standard tier.
    public let personalFactor: Double
    /// The same session scored through the Standard path. Stored explicitly
    /// because removing only `personalFactor` does not undo a personal baseline,
    /// overnight context, or calibration.
    public let standardHours: Double

    /// Recovery still outstanding from earlier sessions at the moment this one
    /// ended, in hours. Zero for a session that started from Ready.
    ///
    /// **Recovery time is cumulative, and this is what makes it so.** Garmin
    /// documents the behaviour plainly: if eighteen hours were left from
    /// yesterday's run and another session is done today, the new time stacks on
    /// top. Recharge used to take the *maximum* of overlapping windows instead,
    /// which meant two hard sessions four hours apart read exactly the same as
    /// one, and the number failed to move at the one moment a Garmin user would
    /// expect it to spike.
    ///
    /// Kept separate from `hours` rather than folded into it, because the two
    /// answer different questions and both are needed. `hours` is what *this
    /// session* cost, which is what the tier comparison, the rest-pattern bands
    /// and the history rows are about. `totalHours` is how long the countdown
    /// actually runs.
    ///
    /// Decodes to 0 for any record written before stacking existed, which is the
    /// truthful legacy value: those estimates were not stacked.
    public let carriedHours: Double

    /// What this session cost, in hours, whether or not it started a countdown.
    ///
    /// **`hours` is an instruction to the countdown; this is a description of
    /// the session.** They are the same number for a qualifying session and
    /// they diverge in exactly two places, both of which used to render as the
    /// word "None":
    ///
    /// - an `easy` session, where `hours` must be zero so a walk can never start
    ///   or lengthen a countdown, but the walk still cost something;
    /// - a session under the person's quiet threshold, which does not earn a
    ///   countdown of its own but is not nothing either.
    ///
    /// It also skips the six-hour countdown floor, because that floor exists to
    /// stop a *countdown* being over before bedtime and has nothing to say about
    /// what forty minutes of walking cost.
    ///
    /// Nothing that drives a countdown reads this. `producesCountdown`,
    /// `readyAt`, `totalHours`, the snapshot, the complication and the stacking
    /// chain are all still `hours`.
    ///
    /// Decodes to `hours` for records written before it existed, which is the
    /// truthful legacy value for every estimate that had one and an honest zero
    /// for every estimate that did not.
    public let recoveryCostHours: Double

    /// How long the countdown actually runs: this session's own cost plus
    /// whatever was still outstanding, bounded by the same ceiling every other
    /// window obeys. Zero when the session started no countdown, so an
    /// active-recovery walk can neither start one nor inherit one.
    public var totalHours: Double {
        guard producesCountdown else { return 0 }
        return min(hours + max(carriedHours, 0), RecoveryCalculator.maximumHours)
    }

    /// True when this session landed on top of recovery that was still running.
    /// The surfaces that show a countdown have to be able to say so, or a number
    /// larger than the session appears to justify looks like a bug.
    public var isStacked: Bool { producesCountdown && carriedHours > 0.05 }

    public var producesCountdown: Bool { hours > 0 }

    public init(
        sessionID: String,
        profile: WorkoutProfile,
        activityLabel: String,
        calculatedAt: Date,
        sessionEnd: Date,
        readyAt: Date,
        hours: Double,
        windowLowHours: Double,
        windowHighHours: Double,
        load: SessionLoad,
        relativeLoad: Double,
        category: LoadCategory,
        confidence: RecoveryConfidence,
        reasons: [String],
        modelVersion: Int = recoveryModelVersion,
        tier: RecoveryTier = .standard,
        personalFactor: Double = 1,
        standardHours: Double? = nil,
        carriedHours: Double = 0,
        recoveryCostHours: Double? = nil
    ) {
        let safeHours = hours.isFinite ? max(hours, 0) : 0
        let safeLow = windowLowHours.isFinite ? max(windowLowHours, 0) : 0
        let safeHigh = windowHighHours.isFinite ? max(windowHighHours, 0) : 0
        let safeRelative = relativeLoad.isFinite ? max(relativeLoad, 0) : 0
        let safePersonalFactor = personalFactor.isFinite && personalFactor > 0 ? personalFactor : 1
        let safeCarried = carriedHours.isFinite ? max(carriedHours, 0) : 0

        self.sessionID = sessionID
        self.profile = profile
        self.activityLabel = activityLabel
        self.calculatedAt = calculatedAt
        self.sessionEnd = sessionEnd
        self.readyAt = readyAt
        self.hours = safeHours
        self.windowLowHours = safeLow
        self.windowHighHours = safeHigh
        self.load = load
        self.relativeLoad = safeRelative
        self.category = category
        self.confidence = confidence
        self.reasons = reasons
        self.modelVersion = modelVersion
        self.tier = tier
        self.personalFactor = safePersonalFactor
        self.standardHours = standardHours.flatMap { $0.isFinite ? max($0, 0) : nil }
            ?? (safeHours / safePersonalFactor)
        self.carriedHours = safeCarried
        self.recoveryCostHours = recoveryCostHours.flatMap {
            $0.isFinite ? min(max($0, 0), RecoveryCalculator.maximumHours) : nil
        } ?? safeHours
    }

    /// Tier metadata arrived in model version 2, and `standardHours` was added
    /// later. Missing fields decode to the closest truthful legacy value.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        profile = try container.decode(WorkoutProfile.self, forKey: .profile)
        activityLabel = try container.decode(String.self, forKey: .activityLabel)
        calculatedAt = try container.decode(Date.self, forKey: .calculatedAt)
        sessionEnd = try container.decode(Date.self, forKey: .sessionEnd)
        readyAt = try container.decode(Date.self, forKey: .readyAt)
        let decodedHours = try container.decode(Double.self, forKey: .hours)
        let decodedLow = try container.decode(Double.self, forKey: .windowLowHours)
        let decodedHigh = try container.decode(Double.self, forKey: .windowHighHours)
        hours = decodedHours.isFinite ? max(decodedHours, 0) : 0
        windowLowHours = decodedLow.isFinite ? max(decodedLow, 0) : 0
        windowHighHours = decodedHigh.isFinite ? max(decodedHigh, 0) : 0
        load = try container.decode(SessionLoad.self, forKey: .load)
        let decodedRelative = try container.decode(Double.self, forKey: .relativeLoad)
        relativeLoad = decodedRelative.isFinite ? max(decodedRelative, 0) : 0
        category = try container.decode(LoadCategory.self, forKey: .category)
        confidence = try container.decode(RecoveryConfidence.self, forKey: .confidence)
        reasons = try container.decode([String].self, forKey: .reasons)
        modelVersion = try container.decode(Int.self, forKey: .modelVersion)
        tier = try container.decodeIfPresent(RecoveryTier.self, forKey: .tier) ?? .standard
        let decodedFactor = try container.decodeIfPresent(Double.self, forKey: .personalFactor) ?? 1
        personalFactor = decodedFactor.isFinite && decodedFactor > 0 ? decodedFactor : 1
        let decodedStandard = try container.decodeIfPresent(Double.self, forKey: .standardHours)
        standardHours = decodedStandard.flatMap { $0.isFinite ? max($0, 0) : nil }
            ?? (hours / personalFactor)
        let decodedCarried = try container.decodeIfPresent(Double.self, forKey: .carriedHours) ?? 0
        carriedHours = decodedCarried.isFinite ? max(decodedCarried, 0) : 0
        let decodedCost = try container.decodeIfPresent(Double.self, forKey: .recoveryCostHours)
        recoveryCostHours = decodedCost.flatMap {
            $0.isFinite ? min(max($0, 0), RecoveryCalculator.maximumHours) : nil
        } ?? hours
    }

    /// Phase at a given instant. Derived rather than stored so a cached estimate
    /// can't go stale about whether it has expired.
    public func phase(at now: Date) -> RecoveryPhase {
        guard producesCountdown else { return .ready }
        let remaining = readyAt.timeIntervalSince(now)
        if remaining <= 0 { return .ready }
        if remaining <= 2 * 3600 { return .readySoon }
        return .recovering
    }

    public func remainingSeconds(at now: Date) -> TimeInterval {
        max(readyAt.timeIntervalSince(now), 0)
    }
}

// MARK: - Calibration

/// The one-tap question asked once a countdown expires.
public enum ReadinessFeedback: String, Codable, Sendable, CaseIterable {
    case feltReady
    case okayNotFresh
    case notReady

    public var label: String {
        switch self {
        case .feltReady: "Felt ready"
        case .okayNotFresh: "Okay but not fresh"
        case .notReady: "Not ready"
        }
    }

    /// Multiplicative nudge applied to the stored calibration factor. Small on
    /// purpose: one answer should never swing the model.
    public var calibrationNudge: Double {
        switch self {
        case .feltReady: 0.95
        case .okayNotFresh: 1.0
        case .notReady: 1.05
        }
    }
}

public enum RecoveryCalibration {
    public static let minimum = 0.80
    public static let maximum = 1.25
    public static let neutral = 1.0

    /// Folds one answer into the running factor, bounded so a run of "not ready"
    /// taps can stretch windows by at most a quarter.
    public static func apply(_ feedback: ReadinessFeedback, to factor: Double) -> Double {
        let safeFactor = factor.isFinite ? factor : neutral
        return min(max(safeFactor * feedback.calibrationNudge, minimum), maximum)
    }
}

// MARK: - Complication style

/// Drives every complication family from one cached estimate. The audience for
/// this app left Garmin, so how the countdown reads is a setting rather than a
/// hardcode.
public enum ComplicationStyle: Int, Codable, Sendable, CaseIterable {
    /// Garmin-like: hours remaining plus a ring. The default.
    case countdown = 0
    /// The clock time the estimate expires at.
    case readyClock = 1
    /// The state word, with the hours demoted to a subtitle.
    case state = 2

    public var label: String {
        switch self {
        case .countdown: "Countdown"
        case .readyClock: "Ready at"
        case .state: "State"
        }
    }

    public var detail: String {
        switch self {
        case .countdown: "Hours left, with a ring. Closest to Garmin."
        case .readyClock: "The clock time you are estimated to be ready."
        case .state: "Recovering / Ready soon / Ready."
        }
    }
}
