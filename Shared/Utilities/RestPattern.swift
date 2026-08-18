import Foundation

/// What the person actually does, what the table says people like them do, and
/// what Recharge would tell them to do — three numbers per intensity band, on
/// one screen.
///
/// This exists because the app was answering a question nobody asked. A single
/// countdown says "18h" and gives the user no way to tell whether that is a lot,
/// a little, or roughly what they were going to do anyway. The three columns are
/// the comparison that makes the number mean something:
///
/// | Column | What it is | Where it comes from |
/// |---|---|---|
/// | Your history | The gap you actually leave between sessions in this band | Measured. Median of the real intervals in `windowDays` of history. |
/// | Similar profiles | What the standard model gives someone at your training level | Exactly the free-tier estimate. The standard tier is already scaled to the person by `AthleteProfile.fitnessScale`, so this column *is* that number rather than a separate adjustment applied on top of it. |
/// | Yours | What Recharge+ makes of it | The personalized estimate, computed against the person's own baseline. Never the standard figure times a multiplier. |
///
/// **Training more means shorter windows, and this is where that becomes
/// visible.** Both of the personal paths already run that way — relative load is
/// divided by the person's own median session, so a bigger median makes the same
/// workout a smaller multiple, and `PersonalRecoveryModel.densityFactor` reduces
/// the multiplier as chronic weekly load rises. Neither was legible anywhere in
/// the app, because a lone countdown has nothing to be shorter *than*.
///
/// Pure and `Sendable`: no HealthKit, no SwiftData, no clock of its own.
///
/// Compliance: everything here is a cardiovascular training estimate and a
/// description of past training. Nothing in it measures tissue repair, illness,
/// or injury risk, and no column may be described as a target the user should
/// hit.
public enum RestPattern {

    // MARK: - Bounds

    /// How far back the observed gaps are measured.
    ///
    /// Longer than `RecoveryBaseline.historyDays` (42) and much longer than
    /// `PersonalRecoveryModel.windowDays` (30) on purpose: those two feed *the
    /// estimate* and have to track the person as they are now, while this is a
    /// description of a habit and wants enough intervals in the rarer bands to
    /// have a median at all. Somebody who does one very hard session a month has
    /// two gaps in ninety days and none in thirty.
    public static let windowDays = 90

    /// Intervals needed before a band will state an observed figure.
    ///
    /// Two, not one: a single gap is the interval between two particular
    /// sessions, and calling that "you usually rest" is a claim the sample
    /// cannot support.
    public static let minimumGapSamples = 2

    /// Gaps longer than this are not rest between sessions, they are a break
    /// from training, and including them drags the median into fiction.
    public static let maximumGapHours: Double = 14 * 24

    /// The bands, hardest last. `easy` is absent because an easy session never
    /// starts a countdown, so it has no window to compare a gap against.
    public static let bands: [LoadCategory] = [.typical, .hard, .unusuallyHard]

    /// Relative load at the middle of each band, used when the person has no
    /// session in it yet. Straight off `RecoveryCalculator.curve`'s own
    /// breakpoints, so a fallback row is a real point on the real curve rather
    /// than an invented number.
    ///
    /// `unusuallyHard` is open-ended above 2.0, so it is anchored at 2.5 rather
    /// than at a midpoint that does not exist.
    static func referenceRelativeLoad(for band: LoadCategory) -> Double {
        switch band {
        case .easy: return RecoveryCalculator.easyCeiling / 2
        case .typical: return (RecoveryCalculator.easyCeiling + RecoveryCalculator.typicalCeiling) / 2
        case .hard: return (RecoveryCalculator.typicalCeiling + RecoveryCalculator.hardCeiling) / 2
        case .unusuallyHard: return 2.5
        }
    }

    // MARK: - Inputs

    /// One scored session, as the pattern needs to see it.
    ///
    /// Both figures are carried because the engine already computes both for
    /// every session on both tiers, and because deriving one from the other is
    /// the mistake `RecoveryEngine.personalizedPreview` was fixed for:
    /// personalisation changes the baseline a session is measured against as
    /// well as applying a multiplier, so `standardHours * factor` understates it.
    public struct Session: Sendable, Equatable {
        public let id: String
        public let endDate: Date
        public let profile: WorkoutProfile
        /// The band, taken from the standard scoring so the row a session lands
        /// in does not move when the user subscribes.
        public let band: LoadCategory
        public let standardHours: Double
        public let personalizedHours: Double

        public init(
            id: String,
            endDate: Date,
            profile: WorkoutProfile,
            band: LoadCategory,
            standardHours: Double,
            personalizedHours: Double
        ) {
            self.id = id
            self.endDate = endDate
            self.profile = profile
            self.band = band
            self.standardHours = standardHours
            self.personalizedHours = personalizedHours
        }
    }

    // MARK: - Output

    /// One intensity band, three figures.
    public struct Row: Sendable, Equatable, Identifiable {
        public let band: LoadCategory

        /// Median hours the person actually left between a session in this band
        /// and their next qualifying session. `nil` until `minimumGapSamples`
        /// intervals exist — the row still renders, it just does not claim.
        public let observedRestHours: Double?
        public let gapSamples: Int

        /// What the standard table gives someone with this person's answers.
        public let similarProfilesHours: Double

        /// What Recharge+ gives *them*. Gated behind the entitlement on screen,
        /// computed either way, because a pitch built on an invented figure is
        /// not a pitch.
        public let personalizedHours: Double

        /// True when no session of this band exists yet and the two model
        /// figures come from the canonical mid-band session instead. Surfaces
        /// have to say so.
        public let isExample: Bool

        public var id: String { band.rawValue }

        public init(
            band: LoadCategory,
            observedRestHours: Double?,
            gapSamples: Int,
            similarProfilesHours: Double,
            personalizedHours: Double,
            isExample: Bool
        ) {
            self.band = band
            self.observedRestHours = observedRestHours
            self.gapSamples = gapSamples
            self.similarProfilesHours = similarProfilesHours
            self.personalizedHours = personalizedHours
            self.isExample = isExample
        }

        /// Whether the two model figures would render as different strings. The
        /// conversion surface leads with the difference, so it has to be able to
        /// ask before it promises one.
        public var isVisiblyPersonalized: Bool {
            abs(personalizedHours - similarProfilesHours) >= 0.5
        }

        /// How the person's habit compares with what Recharge would say. Signed:
        /// negative means they already train back sooner than the estimate.
        public var observedMinusPersonalized: Double? {
            observedRestHours.map { $0 - personalizedHours }
        }
    }

    // MARK: - Entry point

    /// Builds one row per band.
    ///
    /// - Parameters:
    ///   - sessions: scored sessions, any order. Only qualifying ones inside the
    ///     window take part; `easy` sessions are excluded entirely, as they are
    ///     everywhere else in the model.
    ///   - profile: the onboarding answers, for the "similar profiles" column.
    ///   - now: the calculation instant. Injected so tests are deterministic.
    public static func rows(
        sessions: [Session],
        profile: AthleteProfile,
        now: Date = .now
    ) -> [Row] {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let window = sessions
            .filter { $0.endDate >= cutoff && $0.endDate <= now && $0.profile != .easy && $0.band != .easy }
            .sorted { $0.endDate < $1.endDate }

        let gaps = observedGaps(in: window)
        // The personal multiplier available before any session has been
        // observed: the questionnaire prior, clamped to the same bounds the
        // thirty-day analysis is clamped to.
        let dayOneFactor = min(
            max(profile.prior ?? 1, PersonalRecoveryModel.minimumFactor),
            PersonalRecoveryModel.maximumFactor
        )
        let dominant = profile.primaryProfile.flatMap { $0 == .easy ? nil : $0 } ?? .endurance

        return bands.map { band in
            let inBand = window.filter { $0.band == band }
            let banded = gaps[band] ?? []

            let similar: Double
            let personalized: Double
            let isExample: Bool
            if let standard = median(inBand.map(\.standardHours)),
               let personal = median(inBand.map(\.personalizedHours)) {
                similar = clampToWindow(standard)
                personalized = clampToWindow(personal)
                isExample = false
            } else {
                // No session in this band yet. The canonical mid-band session on
                // the person's dominant profile is a real point on the real
                // curve, which is the same fallback `PersonalizedPreview` uses
                // and for the same reason.
                // Defined in *relative* terms, so it is the same number of
                // hours whatever the person's fitness level scales their
                // denominator to: a mid-band session is a bigger absolute
                // session for a fitter person, and still a mid-band one.
                let reference = referenceHours(for: band, profile: dominant)
                similar = clampToWindow(reference)
                // The two columns must not print the same number here. This is
                // the row a brand-new user sees, it is what the onboarding
                // upgrade pitch is made of, and a blurred figure identical to
                // the one beside it sells nothing and looks like a bug. Both
                // columns used to be `reference * prior`, so on a fresh install
                // the pitch was two identical numbers with a blur over one.
                //
                // `dayOneFactor` is not a device for making them differ: it is
                // exactly what `PersonalRecoveryModel` returns for this person
                // with no history, which is the multiplier a subscriber would
                // actually get on their first day. The number under the blur
                // stays a number the app will honour.
                personalized = clampToWindow(reference * dayOneFactor)
                isExample = true
            }

            return Row(
                band: band,
                observedRestHours: banded.count >= minimumGapSamples ? median(banded) : nil,
                gapSamples: banded.count,
                similarProfilesHours: similar,
                personalizedHours: personalized,
                isExample: isExample
            )
        }
    }

    /// The standard window for the canonical mid-band session of a profile.
    static func referenceHours(for band: LoadCategory, profile: WorkoutProfile) -> Double {
        let base = RecoveryCalculator.baseHours(forRelativeLoad: referenceRelativeLoad(for: band))
        return clampToWindow(base * profile.windowMultiplier)
    }

    /// Every displayed figure is a recovery window, so it obeys the same bounds
    /// every recovery window obeys. Without this the "similar profiles" column
    /// could print 84 hours for a very hard session on the mixed curve, above a
    /// maximum the app promises everywhere else it can never exceed.
    static func clampToWindow(_ hours: Double) -> Double {
        guard hours > 0, hours.isFinite else { return 0 }
        return min(max(hours, RecoveryCalculator.minimumCountdownHours), RecoveryCalculator.maximumHours)
    }

    // MARK: - The measurement

    /// Hours between each session and the next qualifying one, keyed by the band
    /// of the session that *started* the gap.
    ///
    /// The earlier session is what the rest is being taken from, so it is what
    /// the interval belongs to. Keying on the later one would answer a different
    /// question — "how fresh were you going in" — which is `PersonalRecoveryModel`'s
    /// tolerance signal, not this.
    static func observedGaps(in ordered: [Session]) -> [LoadCategory: [Double]] {
        var gaps: [LoadCategory: [Double]] = [:]
        for (earlier, later) in zip(ordered, ordered.dropFirst()) {
            let hours = later.endDate.timeIntervalSince(earlier.endDate) / 3600
            // A layoff is not a rest interval. Zero and negative cannot happen on
            // sorted input, but the guard is cheap and the alternative is a
            // median dragged to nonsense by one holiday.
            guard hours > 0, hours <= maximumGapHours else { continue }
            gaps[earlier.band, default: []].append(hours)
        }
        return gaps
    }

    // MARK: - Copy

    /// The sentence for a row's observed column. Empty when the band has not
    /// earned one.
    ///
    /// Compliance: a description of what the person did, never a statement about
    /// what their body did or an instruction about what to do next.
    public static func observedSentence(_ row: Row) -> String? {
        guard let hours = row.observedRestHours else { return nil }
        return "You usually leave \(CountdownFormat.hours(hours)) after a "
            + "\(row.band.shortLabel.lowercased()) session (\(row.gapSamples) "
            + "\(row.gapSamples == 1 ? "gap" : "gaps") measured)."
    }

    /// The line that names what the personalized column would change, for a
    /// surface pitching the upgrade.
    public static func personalizedSentence(_ row: Row) -> String {
        let difference = row.personalizedHours - row.similarProfilesHours
        guard abs(difference) >= 0.5 else {
            return "Your own history lands close to the standard estimate for a "
                + "\(row.band.shortLabel.lowercased()) session."
        }
        let hours = CountdownFormat.hours(abs(difference))
        return difference < 0
            ? "Your own history brings a \(row.band.shortLabel.lowercased()) session in \(hours) shorter."
            : "Your own history pushes a \(row.band.shortLabel.lowercased()) session out \(hours) longer."
    }

    // MARK: - Helpers

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 0 { return (sorted[middle - 1] + sorted[middle]) / 2 }
        return sorted[middle]
    }
}
