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

    /// Which fields arrived from Health rather than from an answer. Drives both
    /// the "here's what we found" page and the decision about what to ask.
    public var healthDerivedFields: Set<String>

    public static let ageField = "age"
    public static let sexField = "sex"
    public static let weeklyVolumeField = "weeklyVolume"
    public static let primaryProfileField = "primaryProfile"

    public static let empty = AthleteProfile()

    public init(
        age: Int? = nil,
        sex: AthleteSex = .unspecified,
        experience: TrainingExperience? = nil,
        bounceBack: BounceBackHabit? = nil,
        weeklyVolume: WeeklyVolume? = nil,
        primaryProfile: WorkoutProfile? = nil,
        healthDerivedFields: Set<String> = []
    ) {
        self.age = age
        self.sex = sex
        self.experience = experience
        self.bounceBack = bounceBack
        self.weeklyVolume = weeklyVolume
        self.primaryProfile = primaryProfile
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
