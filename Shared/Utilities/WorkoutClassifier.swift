import Foundation

/// Maps a HealthKit activity type onto one of the four recovery profiles.
///
/// Kept free of `HealthKit` so it stays in the pure test target: callers pass
/// the raw `HKWorkoutActivityType` rawValue. The mapping table is the one place
/// the HYROX/CrossFit ambiguity is resolved.
public enum WorkoutClassifier {

    /// HealthKit activity type raw values. HealthKit's enum is stable across
    /// releases, so pinning the numbers here is safe and keeps this file
    /// importable by the pure test target.
    ///
    /// Pinning is safe; transcribing was not. The original table omitted
    /// `australianFootball` (3), which shifted every value from `badminton` (4)
    /// through `crossTraining` (11) up by one. Boxing arrived as an unmapped
    /// code and was scored as endurance; basketball was read as the name one
    /// slot below it and fell through to the default; a climb was read as
    /// boxing. `WorkoutClassifierTests.testTheRawValuesMatchHealthKit` pins the
    /// whole table against the SDK's own numbering so a future edit cannot
    /// reintroduce a shift.
    /// `CaseIterable` so an audit can sweep the whole table rather than the
    /// handful of codes someone thought to list. `RecoveryMatrixTests` scores
    /// every case against every persona, which is the only way a mapping bug in
    /// a sport nobody on the team plays gets caught.
    public enum ActivityCode: UInt, Sendable, CaseIterable {
        case americanFootball = 1
        case archery = 2
        case australianFootball = 3
        case badminton = 4
        case baseball = 5
        case basketball = 6
        case bowling = 7
        case boxing = 8
        case climbing = 9
        case cricket = 10
        case crossTraining = 11
        case curling = 12
        case cycling = 13
        case dance = 14
        case danceInspiredTraining = 15
        case elliptical = 16
        case equestrianSports = 17
        case fencing = 18
        case fishing = 19
        case functionalStrengthTraining = 20
        case golf = 21
        case gymnastics = 22
        case handball = 23
        case hiking = 24
        case hockey = 25
        case hunting = 26
        case lacrosse = 27
        case martialArts = 28
        case mindAndBody = 29
        // Deprecated in iOS 11, but old records still carry it.
        case mixedMetabolicCardioTraining = 30
        case paddleSports = 31
        case play = 32
        case preparationAndRecovery = 33
        case racquetball = 34
        case rowing = 35
        case rugby = 36
        case running = 37
        case sailing = 38
        case skatingSports = 39
        case snowSports = 40
        case soccer = 41
        case softball = 42
        case squash = 43
        case stairClimbing = 44
        case surfingSports = 45
        case swimming = 46
        case tableTennis = 47
        case tennis = 48
        case trackAndField = 49
        case traditionalStrengthTraining = 50
        case volleyball = 51
        case walking = 52
        case waterFitness = 53
        case waterPolo = 54
        case waterSports = 55
        case wrestling = 56
        case yoga = 57
        case barre = 58
        case coreTraining = 59
        case crossCountrySkiing = 60
        case downhillSkiing = 61
        case flexibility = 62
        case highIntensityIntervalTraining = 63
        case jumpRope = 64
        case kickboxing = 65
        case pilates = 66
        case snowboarding = 67
        case stairs = 68
        case stepTraining = 69
        case wheelchairWalkPace = 70
        case wheelchairRunPace = 71
        case taiChi = 72
        case mixedCardio = 73
        case handCycling = 74
        case discSports = 75
        case fitnessGaming = 76
        case cardioDance = 77
        case socialDance = 78
        case pickleball = 79
        case cooldown = 80
        case swimBikeRun = 82
        case transition = 83
        case underwaterDiving = 84
        case other = 3000
    }

    /// The two activity types HYROX and CrossFit arrive as. Both are genuinely
    /// ambiguous — the same code covers a circuit workout and a barbell
    /// session — so they follow a user-set default rather than a fixed answer.
    public static let ambiguousCodes: Set<UInt> = [
        ActivityCode.functionalStrengthTraining.rawValue,
        ActivityCode.highIntensityIntervalTraining.rawValue
    ]

    /// Default profile for the ambiguous codes. `mixed`, per the build plan:
    /// HYROX and CrossFit are the common case for this audience, and the mixed
    /// curve is the conservative answer for a session that might be either.
    public static let ambiguousDefault: WorkoutProfile = .mixed

    /// - Parameters:
    ///   - activityCode: `HKWorkoutActivityType.rawValue`.
    ///   - ambiguousProfile: the user's "these are usually my…" setting, applied
    ///     only to `ambiguousCodes`.
    ///   - override: a per-session choice, which beats everything.
    public static func profile(
        activityCode: UInt,
        ambiguousProfile: WorkoutProfile = ambiguousDefault,
        override: WorkoutProfile? = nil
    ) -> WorkoutProfile {
        if let override { return override }
        if ambiguousCodes.contains(activityCode) { return ambiguousProfile }
        guard let code = ActivityCode(rawValue: activityCode) else { return .endurance }

        switch code {
        // Endurance: sustained cardiovascular work with reliable heart rate.
        case .cycling, .running, .rowing, .swimming, .elliptical, .stairClimbing,
             .stairs, .stepTraining, .crossCountrySkiing, .handCycling,
             .wheelchairRunPace, .swimBikeRun, .mixedCardio, .jumpRope,
             .trackAndField, .paddleSports, .waterFitness, .hiking, .downhillSkiing,
             .snowboarding, .snowSports, .surfingSports, .skatingSports:
            return .endurance

        // Strength: optical heart rate is unreliable, effort input matters most.
        case .traditionalStrengthTraining, .coreTraining, .climbing, .gymnastics:
            return .strength

        // Mixed: both systems taxed within one session.
        case .crossTraining, .boxing, .kickboxing, .martialArts, .wrestling,
             .fencing, .basketball, .soccer, .rugby, .hockey, .lacrosse,
             .handball, .waterPolo, .squash, .racquetball, .tennis, .badminton,
             .volleyball, .americanFootball, .australianFootball, .cardioDance,
             .dance, .danceInspiredTraining, .fitnessGaming, .discSports,
             .pickleball, .tableTennis, .baseball, .softball, .cricket,
             .equestrianSports, .mixedMetabolicCardioTraining:
            return .mixed

        // Easy / active recovery: never starts a countdown.
        case .walking, .wheelchairWalkPace, .yoga, .pilates, .barre, .flexibility,
             .mindAndBody, .taiChi, .preparationAndRecovery, .cooldown, .transition,
             .golf, .archery, .fishing, .hunting, .play, .socialDance,
             .bowling, .curling:
            return .easy

        // Everything else defaults to endurance: it is the middle curve and the
        // one with the most reliable load source.
        default:
            return .endurance
        }
    }

    /// Human-readable session name for the "why" line. Falls back to a generic
    /// word rather than exposing a HealthKit enum name to the user.
    public static func label(activityCode: UInt) -> String {
        guard let code = ActivityCode(rawValue: activityCode) else { return "workout" }
        switch code {
        case .running: return "run"
        case .cycling: return "ride"
        case .walking: return "walk"
        case .swimming: return "swim"
        case .rowing: return "row"
        case .hiking: return "hike"
        case .elliptical: return "elliptical session"
        case .stairClimbing, .stairs, .stepTraining: return "stair session"
        case .traditionalStrengthTraining: return "lifting session"
        case .functionalStrengthTraining: return "functional session"
        case .highIntensityIntervalTraining: return "HIIT session"
        case .coreTraining: return "core session"
        case .crossTraining: return "cross-training session"
        case .yoga: return "yoga session"
        case .pilates: return "pilates session"
        case .barre: return "barre session"
        case .flexibility, .preparationAndRecovery, .cooldown: return "mobility session"
        case .boxing, .kickboxing: return "boxing session"
        case .martialArts: return "martial arts session"
        case .tennis: return "tennis match"
        case .basketball: return "basketball game"
        case .soccer: return "soccer game"
        case .swimBikeRun: return "triathlon session"
        case .mixedCardio: return "cardio session"
        case .jumpRope: return "jump rope session"
        case .climbing: return "climb"
        case .crossCountrySkiing: return "ski"
        case .downhillSkiing: return "ski run"
        case .snowboarding: return "snowboard session"
        default: return "workout"
        }
    }

    /// The same label as a heading.
    ///
    /// `label(activityCode:)` is deliberately lowercase, because most of its
    /// uses are mid-sentence ("9h from your run 3h ago"). The two places that
    /// need it as a title (History's rows and `EstimateDetailView`'s
    /// navigation title) used `String.capitalized`, which uppercases the first
    /// letter of every word **and lowercases the rest**, so "HIIT session"
    /// rendered as "Hiit Session". It is the only label with an acronym in it,
    /// which is why nothing caught it until a seeded store put a real HIIT
    /// session in History.
    ///
    /// This raises the first character of each word and leaves every other
    /// character alone.
    public static func title(activityCode: UInt) -> String {
        label(activityCode: activityCode).asSessionTitle
    }
}

extension String {
    /// Uppercases the first character of each whitespace-separated word and
    /// touches nothing else, so acronyms survive.
    public var asSessionTitle: String {
        split(separator: " ", omittingEmptySubsequences: false)
            .map { word in
                guard let first = word.first else { return String(word) }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}
