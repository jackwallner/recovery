import Foundation

/// What Recharge knows about the person, as opposed to what it knows about one
/// session.
///
/// Two rules govern everything in this file:
///
/// 1. **Health answers first.** Age, sex, and training volume are all derivable
///    from data the user has already given Apple, and an onboarding question
///    that asks for something the phone already knows reads as a form to fill
///    in rather than a setup that is paying attention. `HealthDerived` records
///    what was found; `AthleteProfile.gaps` is what is left to ask.
/// 2. **Every stored field moves a number.** Nothing is collected because it
///    would be nice to have. The multipliers are right here, so a field with no
///    multiplier is a field that should not be asked for.
///
/// Pure and `Sendable`: no HealthKit, no SwiftData, so the whole thing is
/// testable without a Health store.

// MARK: - Answers

/// How long the person has been training consistently.
///
/// Trained populations show an attenuated damage-and-inflammation response to
/// the same relative load, which is the "repeated bout effect". The multipliers
/// are deliberately small: experience shifts recovery, it does not halve it.
public enum TrainingExperience: Int, Codable, Sendable, CaseIterable {
    case underOneYear = 0
    case oneToThreeYears = 1
    case threeToTenYears = 2
    case tenYearsPlus = 3

    public var label: String {
        switch self {
        case .underOneYear: "Less than a year"
        case .oneToThreeYears: "1 to 3 years"
        case .threeToTenYears: "3 to 10 years"
        case .tenYearsPlus: "10 years or more"
        }
    }

    var recoveryFactor: Double {
        switch self {
        case .underOneYear: 1.08
        case .oneToThreeYears: 1.00
        case .threeToTenYears: 0.96
        case .tenYearsPlus: 0.94
        }
    }

    /// Contribution to `AthleteProfile.fitnessScale`, which moves the *standard*
    /// tier's population denominator. Separate from `recoveryFactor` above
    /// because it answers a different question: that one is how fast this person
    /// clears a given load, this one is how much load their ordinary training
    /// day carries. Firstbeat's activity class asks about both years of training
    /// and weekly hours, so both are here.
    var fitnessFactor: Double {
        switch self {
        case .underOneYear: 0.85
        case .oneToThreeYears: 1.00
        case .threeToTenYears: 1.10
        case .tenYearsPlus: 1.18
        }
    }
}

/// The person's own read on how quickly they come back. Self-report is a weak
/// signal on its own, which is exactly why it is a *prior*: it carries the first
/// few weeks and then gives way to what the data shows.
public enum BounceBackHabit: Int, Codable, Sendable, CaseIterable {
    case nextDay = 0
    case aboutTwoDays = 1
    case threeOrMoreDays = 2
    case notSure = 3

    public var label: String {
        switch self {
        case .nextDay: "Usually the next day"
        case .aboutTwoDays: "About two days"
        case .threeOrMoreDays: "Three days or more"
        case .notSure: "I honestly don't know"
        }
    }

    var recoveryFactor: Double {
        switch self {
        case .nextDay: 0.86
        case .aboutTwoDays: 1.00
        case .threeOrMoreDays: 1.16
        case .notSure: 1.00
        }
    }
}

/// Sessions per week. Derived from imported workouts whenever there is enough
/// history, and only asked for when there is not.
///
/// Higher chronic volume means the person is adapted to more frequent work, so
/// the same relative load costs them a shorter turnaround.
public enum WeeklyVolume: Int, Codable, Sendable, CaseIterable {
    case oneOrTwo = 0
    case threeOrFour = 1
    case fiveOrSix = 2
    case sevenPlus = 3

    public var label: String {
        switch self {
        case .oneOrTwo: "1 to 2"
        case .threeOrFour: "3 to 4"
        case .fiveOrSix: "5 to 6"
        case .sevenPlus: "7 or more"
        }
    }

    var recoveryFactor: Double {
        switch self {
        case .oneOrTwo: 1.07
        case .threeOrFour: 1.00
        case .fiveOrSix: 0.96
        case .sevenPlus: 0.92
        }
    }

    /// Contribution to `AthleteProfile.fitnessScale`. The closest thing Recharge
    /// asks to Firstbeat's activity class, and the larger of the two terms:
    /// how often someone trains says more about the size of their ordinary
    /// training day than how long they have been doing it.
    var fitnessFactor: Double {
        switch self {
        case .oneOrTwo: 0.78
        case .threeOrFour: 1.00
        case .fiveOrSix: 1.20
        case .sevenPlus: 1.40
        }
    }

    public static func forSessionsPerWeek(_ sessions: Double) -> WeeklyVolume {
        switch sessions {
        case ..<2.5: .oneOrTwo
        case ..<4.5: .threeOrFour
        case ..<6.5: .fiveOrSix
        default: .sevenPlus
        }
    }
}

/// Biological sex, used only for the age-predicted maximum heart rate. Gulati is
/// the better-validated formula for women; Tanaka for everyone else.
public enum AthleteSex: Int, Codable, Sendable {
    case unspecified = 0
    case female = 1
    case male = 2
}

// MARK: - Profile

public struct AthleteProfile: Codable, Sendable, Equatable {
    /// Years. From Health's date of birth where available, otherwise asked.
    public var age: Int?
    public var sex: AthleteSex
    public var experience: TrainingExperience?
    public var bounceBack: BounceBackHabit?
    public var weeklyVolume: WeeklyVolume?
    /// The profile the person trains in most often. Presentation only — the
    /// per-profile curves already handle the model side.
    public var primaryProfile: WorkoutProfile?

    /// Health's most recent VO2 max estimate, in ml/kg/min.
    ///
    /// Never asked for — it is read or it is absent. It feeds `fitnessScale`,
    /// which means it reaches the **standard** tier, and that is deliberate for
    /// the same reason the age-predicted heart-rate ceiling does: it is a
    /// *measurement of training level*, not a personalisation of the recovery
    /// window. The tier line is measurement versus personalisation, and what
    /// Recharge+ sells is scoring a session against the person's own
    /// distribution of loads. Knowing that somebody's cardiorespiratory fitness
    /// is 58 rather than 34 does not do that; it picks which population
    /// denominator was the right one to start from, which is what Firstbeat's
    /// activity class does at setup on a Garmin.
    public var vo2Max: Double?

    /// The highest heart rate actually observed across the imported workout
    /// history, in bpm. Written by `RecoveryEngine`, never asked for.
    public var observedMaxHeartRate: Double?

    /// Health's most recent body mass, in kilograms.
    ///
    /// Consumed by exactly one thing — `SessionLoadCalculator`'s energy path,
    /// where it corrects a burn rate that already includes the person's weight.
    /// It is not a recovery input and it must never become one: how much
    /// somebody weighs says nothing about how fast they clear a training load,
    /// and a health app that quietly made heavier users wait longer would be
    /// making a claim it cannot support.
    public var bodyMassKilograms: Double?

    /// Which fields arrived from Health rather than from an answer. Drives both
    /// the "here's what we found" page and the decision about what to ask.
    public var healthDerivedFields: Set<String>

    public static let ageField = "age"
    public static let sexField = "sex"
    public static let weeklyVolumeField = "weeklyVolume"
    public static let primaryProfileField = "primaryProfile"
    public static let vo2MaxField = "vo2Max"
    public static let observedMaxHeartRateField = "observedMaxHeartRate"
    public static let bodyMassField = "bodyMass"

    public static let empty = AthleteProfile()

    public init(
        age: Int? = nil,
        sex: AthleteSex = .unspecified,
        experience: TrainingExperience? = nil,
        bounceBack: BounceBackHabit? = nil,
        weeklyVolume: WeeklyVolume? = nil,
        primaryProfile: WorkoutProfile? = nil,
        vo2Max: Double? = nil,
        observedMaxHeartRate: Double? = nil,
        bodyMassKilograms: Double? = nil,
        healthDerivedFields: Set<String> = []
    ) {
        self.age = age
        self.sex = sex
        self.experience = experience
        self.bounceBack = bounceBack
        self.weeklyVolume = weeklyVolume
        self.primaryProfile = primaryProfile
        self.vo2Max = vo2Max.flatMap { $0.isFinite && (10...90).contains($0) ? $0 : nil }
        self.observedMaxHeartRate = observedMaxHeartRate.flatMap {
            $0.isFinite && (120...230).contains($0) ? $0 : nil
        }
        self.bodyMassKilograms = bodyMassKilograms.flatMap {
            $0.isFinite && (30...250).contains($0) ? $0 : nil
        }
        self.healthDerivedFields = healthDerivedFields
    }

    // MARK: Maximum heart rate

    /// Age-predicted maximum heart rate.
    ///
    /// Used by **both** tiers, and deliberately so: an age-predicted max is part
    /// of measuring the session, not part of personalising the recovery window.
    /// Scoring a 58-year-old against a flat 185 bpm ceiling does not make the
    /// free estimate "standard", it makes it wrong.
    ///
    /// Tanaka (208 − 0.7 × age) rather than 220 − age, which overestimates the
    /// young and underestimates the old. Gulati (206 − 0.88 × age) for women,
    /// where it is the better-validated fit.
    public var predictedMaxHeartRate: Double? {
        guard let age, (10...100).contains(age) else { return nil }
        let value = sex == .female
            ? 206 - 0.88 * Double(age)
            : 208 - 0.7 * Double(age)
        return value.rounded()
    }

    /// The ceiling every session's intensity is actually measured against:
    /// what was **observed**, and only failing that what age predicts.
    ///
    /// An age formula is a population average with a standard deviation around
    /// 10 to 12 bpm, which is enormous at the scale it is used here — the whole
    /// heart-rate path is `(average − resting) / (max − resting)`, so a ceiling
    /// that is 12 bpm wrong misprices every session that person will ever
    /// record, in the same direction, forever. Tanaka was the right answer when
    /// the app had nothing to compare against; it is the wrong one when a
    /// hundred and twenty days of workout heart rate are sitting in Health.
    ///
    /// The observed figure is not the single highest sample ever recorded
    /// (`HealthKitService` takes a high percentile within each session, and
    /// `RecoveryEngine` a high percentile across sessions), because one optical
    /// artefact should not become somebody's permanent ceiling. It is only
    /// believed when it is at least as high as what age predicts: a real max
    /// heart rate is elicited by a genuinely maximal effort, so a user who has
    /// never gone that hard will show an observed peak well below their true
    /// ceiling, and taking it literally would inflate every intensity reading
    /// they have.
    public var effectiveMaxHeartRate: Double? {
        switch (observedMaxHeartRate, predictedMaxHeartRate) {
        case let (.some(observed), .some(predicted)): return max(observed, predicted)
        case let (.some(observed), .none): return observed
        case let (.none, .some(predicted)): return predicted
        case (.none, .none): return nil
        }
    }

    /// True when the ceiling above came from the person's own workouts rather
    /// than from a formula. The onboarding readout and Settings both say which.
    public var usesObservedMaxHeartRate: Bool {
        guard let observed = observedMaxHeartRate else { return false }
        guard let predicted = predictedMaxHeartRate else { return true }
        return observed >= predicted
    }

    // MARK: Fitness level

    /// How this person's ordinary training day compares to the population
    /// reference, as a multiplier on `WorkoutProfile.standardTypicalLoad`.
    ///
    /// **This is the one thing about the person that reaches the standard
    /// tier**, and it is what makes the free estimate an answer rather than an
    /// average. Firstbeat scales EPOC by an activity class the user enters at
    /// setup — 0-2 beginner, 3-5 already training, 6-7 highly fit — so Garmin's
    /// pre-measurement number is already tuned to a stated fitness level, and
    /// `standardTypicalLoad` (70, the middle of that scale) is only the answer
    /// for someone sitting exactly in the middle of it. One denominator cannot
    /// serve both a beginner and a six-times-a-week runner.
    ///
    /// Only the two questions that are genuinely about *fitness* feed it:
    /// weekly volume and training experience. Age and bounce-back are claims
    /// about recovery *kinetics* rather than about training level, and those
    /// stay in `prior`, on the personalized tier, which is what Recharge+ sells.
    /// Age still reaches the standard tier through `predictedMaxHeartRate`,
    /// because that is measuring the session rather than personalising the
    /// answer.
    ///
    /// Geometric mean rather than a product, for a stronger reason than the one
    /// in `prior`: the two terms are **correlated**. Someone who has trained for
    /// ten years usually also trains often, and multiplying the two would count
    /// one fact twice. The span is deliberately modest — 0.81 for a beginner
    /// doing one or two sessions a week, 1.28 for a ten-year athlete training
    /// seven times, so a denominator between about 57 and 90 against the
    /// reference 70. `GarminAnchorTests` pins what that does to a hard hour at
    /// both ends.
    ///
    /// Returns 1 when neither question has been answered, which is the honest
    /// reading: no claim about fitness, so the population reference stands.
    ///
    /// `weeklyVolume` may have been **derived** from the imported history rather
    /// than typed (`RecoveryEngine.derivedTrainingProfile`), so a free user's
    /// training level can move without them answering anything. That is
    /// deliberate and it is what Garmin does too — activity class updates itself
    /// as the watch sees more training — and it stays inside the tier line
    /// because what reaches the estimate is a four-level bucket, not the
    /// person's baseline. The paid tier is the one that scores each session
    /// against their own distribution of loads.
    public var fitnessScale: Double {
        var factors: [Double] = []
        if let weeklyVolume { factors.append(weeklyVolume.fitnessFactor) }
        if let experience { factors.append(experience.fitnessFactor) }
        if let vo2Factor { factors.append(vo2Factor) }
        guard !factors.isEmpty else { return 1 }
        return exp(factors.reduce(0) { $0 + log($1) } / Double(factors.count))
    }

    /// VO2 max as a training-level multiplier, on the same scale as the two
    /// questionnaire terms and folded in by the same geometric mean.
    ///
    /// Anchored at 45 ml/kg/min, which is not a coincidence: it is the same
    /// reference adult `SessionLoadCalculator.referenceEnergyAtFullReserve` is
    /// derived from, so the one number that describes the population elsewhere
    /// in the model describes it here too.
    ///
    /// The square root is what keeps it honest. VO2 max is a *capacity*, and the
    /// quantity `fitnessScale` needs is the size of an ordinary training day,
    /// which grows more slowly than capacity does — somebody at 60 does not
    /// train a third harder every day than somebody at 45. The bounds are the
    /// same 0.78 to 1.40 the weekly-volume term already spans, so adding a third
    /// measured term cannot widen the range the standard tier was fitted at.
    var vo2Factor: Double? {
        guard let vo2Max, vo2Max.isFinite, (10...90).contains(vo2Max) else { return nil }
        return min(max((vo2Max / 45).squareRoot(), 0.78), 1.40)
    }

    // MARK: Prior

    /// Recovery beyond about thirty slows gradually; below it there is little
    /// left to gain. A gentle linear ramp off a reference age of 30, bounded so
    /// age alone can never dominate the estimate.
    var ageFactor: Double {
        guard let age, (10...100).contains(age) else { return 1 }
        return min(max(1 + Double(age - 30) * 0.005, 0.95), 1.18)
    }

    /// The questionnaire's contribution to the personal recovery factor, before
    /// any evidence from history is folded in.
    ///
    /// `nil` when nothing has been answered or derived, so the caller can tell
    /// "neutral prior" apart from "no prior at all".
    public var prior: Double? {
        var factors: [Double] = []
        if age != nil { factors.append(ageFactor) }
        if let experience { factors.append(experience.recoveryFactor) }
        if let bounceBack { factors.append(bounceBack.recoveryFactor) }
        if let weeklyVolume { factors.append(weeklyVolume.recoveryFactor) }
        guard !factors.isEmpty else { return nil }
        // Geometric mean rather than a product: four mild multipliers should
        // combine into one mild multiplier, not compound into a large one.
        let logSum = factors.reduce(0) { $0 + log($1) }
        return exp(logSum / Double(factors.count))
    }

    /// True once there is enough to personalise with at all.
    public var isUsable: Bool { prior != nil }

    // MARK: Gaps

    /// The questions still worth asking, in the order they should be asked.
    ///
    /// Experience and bounce-back are always here: Health has no idea how long
    /// someone has been lifting or how they feel two days later. Everything else
    /// only appears when Health could not answer it.
    public var gaps: [ProfileQuestion] {
        var questions: [ProfileQuestion] = []
        if age == nil { questions.append(.age) }
        if experience == nil { questions.append(.experience) }
        if weeklyVolume == nil { questions.append(.weeklyVolume) }
        if bounceBack == nil { questions.append(.bounceBack) }
        return questions
    }
}

/// One gap-filling question. The cases are the only things Recharge ever asks
/// for, and each one maps to a field with a multiplier in this file.
public enum ProfileQuestion: String, Codable, Sendable, CaseIterable, Identifiable {
    case age
    case experience
    case weeklyVolume
    case bounceBack

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .age: "How old are you?"
        case .experience: "How long have you been training?"
        case .weeklyVolume: "How many sessions in a typical week?"
        case .bounceBack: "After a hard session, when do you feel ready again?"
        }
    }

    public var detail: String {
        switch self {
        case .age:
            "Sets the heart-rate ceiling every session is measured against, and how quickly the window closes."
        case .experience:
            "Years of consistent training change how the same relative load lands."
        case .weeklyVolume:
            "Someone training six days a week is adapted to a shorter turnaround than someone training two."
        case .bounceBack:
            "Your own read on it. Recharge starts here and replaces it with what your data shows."
        }
    }
}
