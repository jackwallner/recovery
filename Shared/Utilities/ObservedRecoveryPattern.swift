import Foundation

/// What the person actually does: how long they leave between sessions of a
/// given size, read straight off their own workout history.
///
/// This is the free tier. It is a **description**, not a prediction, and that is
/// the whole point of it: a number derived from the user's own calendar can
/// never be a number they do not recognise. The model's estimate — what the
/// window arguably *should* be, given the session, the overnight signals and
/// their thirty-day analysis — is what Recharge+ sells on top of it.
///
/// The two tiers used to be two versions of the same calculation, one scored
/// against a population reference and one against the person's own load
/// distribution, and the gap between them was unbounded: a user training
/// frequently in short sessions was shown 6 hours on the free tier and 36 on the
/// paid one for the same workout. Both figures were internally consistent and
/// together they were nonsense. Describing the habit and prescribing the window
/// are two different questions, and asking two different questions is what makes
/// two different answers legible.
///
/// Pure and `Sendable`: no HealthKit, no SwiftData, no clock of its own.
public struct ObservedRecoveryPattern: Sendable, Equatable {

    // MARK: - Bands

    /// How big this session was *for this person*, on the only scale they can
    /// check: their own recent sessions. Three rungs rather than four, because
    /// the statistic underneath each one is a median of a handful of gaps and a
    /// fourth rung would split a thin sample twice.
    public enum EffortBand: String, Codable, Sendable, CaseIterable {
        case light
        case moderate
        case hard

        public var label: String {
            switch self {
            case .light: "Light"
            case .moderate: "Moderate"
            case .hard: "Hard"
            }
        }

        /// Phrased as the session, for a sentence like "after a hard session
        /// you usually go again after about 44h".
        public var sessionPhrase: String {
            switch self {
            case .light: "a light session"
            case .moderate: "a moderate session"
            case .hard: "a hard session"
            }
        }
    }

    /// One finished workout, reduced to the four things the pattern reads.
    public struct Session: Sendable, Equatable {
        public let profile: WorkoutProfile
        public let startDate: Date
        public let endDate: Date
        public let load: Double

        public init(profile: WorkoutProfile, startDate: Date, endDate: Date, load: Double) {
            self.profile = profile
            self.startDate = startDate
            self.endDate = endDate
            self.load = load
        }
    }

    /// The observed gap for one band, and how much evidence is behind it.
    public struct BandPattern: Sendable, Equatable {
        public let band: EffortBand
        public let medianGapHours: Double
        public let sampleCount: Int

        public init(band: EffortBand, medianGapHours: Double, sampleCount: Int) {
            self.band = band
            self.medianGapHours = medianGapHours
            self.sampleCount = sampleCount
        }
    }

    // MARK: - Constants

    /// History the pattern is read from. The same window the importer fetches,
    /// so the pattern can always see everything the app knows about.
    public static let windowDays = 120

    /// Gaps needed before a band speaks for itself. Below this the band falls
    /// back to the pooled figure, and below *that* there is no pattern and the
    /// model's estimate is what the free tier shows.
    public static let minimumGaps = 3

    /// A gap longer than this is a holiday, an injury, or a phone that was left
    /// at home. Recovery is not what happened in it, so it is not counted.
    public static let maximumGapHours: Double = 168

    /// Below this the "next session" is part of the same training block — a
    /// warm-up logged separately, a two-part brick — rather than a return after
    /// recovery.
    public static let minimumGapHours: Double = 1

    /// What the next session has to be before it counts as having "gone again".
    ///
    /// This is the question the whole statistic turns on, and the first cut got
    /// it half right. Somebody who walks the day after a hard ride has a
    /// 24-hour gap because of a walk, not because of recovery, so a light
    /// session cannot end a gap. But requiring the *same size again* has the
    /// opposite failure and it is worse: a weekly long run is the biggest thing
    /// in that person's week, nothing matches it until the next one, and the
    /// habit came back as "you go again after 7 days" for somebody training five
    /// times a week.
    ///
    /// The bar is therefore the lower of two things: a fraction of the session
    /// just finished, and a fraction of what this person's sessions usually
    /// weigh. Going again means going back to real training, not repeating your
    /// hardest day.
    public static let comparableFraction = 0.85
    /// The second half of that bar, against the person's median session. Lower
    /// than `comparableFraction` because it is a floor on "real training"
    /// rather than a match: a moderate run genuinely is going again after a long
    /// one.
    public static let typicalFraction = 0.70

    /// The longest observed gap the countdown will show. Garmin's own documented
    /// ceiling, and above four days a countdown has stopped being a countdown.
    public static let maximumUsualHours: Double = 96

    // MARK: - Stored

    public let bands: [EffortBand: BandPattern]
    /// Every counted gap regardless of band. What a band falls back to while its
    /// own sample is thin.
    public let pooled: BandPattern?
    /// Tercile boundaries of the person's own session loads. Below the first is
    /// light, above the second is hard.
    public let lightCeiling: Double
    public let moderateCeiling: Double
    /// Non-easy sessions the bands were cut from.
    public let sessionCount: Int

    public init(
        bands: [EffortBand: BandPattern],
        pooled: BandPattern?,
        lightCeiling: Double,
        moderateCeiling: Double,
        sessionCount: Int
    ) {
        self.bands = bands
        self.pooled = pooled
        self.lightCeiling = lightCeiling
        self.moderateCeiling = moderateCeiling
        self.sessionCount = sessionCount
    }

    /// The pattern of somebody the app has not watched train yet.
    public static let empty = ObservedRecoveryPattern(
        bands: [:], pooled: nil, lightCeiling: 0, moderateCeiling: 0, sessionCount: 0
    )

    // MARK: - Reading it

    /// True when at least one figure in here came from the user's own training
    /// rather than from nothing. The free tier falls back to the model estimate
    /// while this is false, and says so.
    public var hasEvidence: Bool { pooled != nil }

    /// Which band a session of this size falls into.
    ///
    /// Terciles of the person's own loads, which is deliberately a *ranking*
    /// rather than a threshold: "hard" means hard for them, and the sentence the
    /// app prints ("after a hard session you usually...") is only checkable
    /// against their own training. `referenceLoad` is the fallback split for a
    /// history too thin to have terciles.
    public func band(forLoad load: Double, referenceLoad: Double) -> EffortBand {
        let low: Double
        let high: Double
        if lightCeiling > 0 && moderateCeiling > lightCeiling {
            low = lightCeiling
            high = moderateCeiling
        } else {
            low = referenceLoad * 0.70
            high = referenceLoad * 1.30
        }
        if load <= low { return .light }
        if load <= high { return .moderate }
        return .hard
    }

    /// How long this person usually leaves after a session of this size, or nil
    /// when their history has not shown it yet.
    ///
    /// The ladder is band, then pooled, then nothing. A band with two gaps in it
    /// is not a pattern, and the pooled figure — every counted gap they have —
    /// is a much better answer than a median of two.
    public func usualGapHours(for band: EffortBand) -> Double? {
        if let own = bands[band], own.sampleCount >= Self.minimumGaps {
            return clampGap(own.medianGapHours)
        }
        guard let pooled, pooled.sampleCount >= Self.minimumGaps else { return nil }
        return clampGap(pooled.medianGapHours)
    }

    /// The band statistic actually used for `band`, so a surface can say how
    /// many sessions are behind the number it is printing.
    public func evidence(for band: EffortBand) -> BandPattern? {
        if let own = bands[band], own.sampleCount >= Self.minimumGaps { return own }
        guard let pooled, pooled.sampleCount >= Self.minimumGaps else { return nil }
        return pooled
    }

    /// Whether the figure for `band` is that band's own or the pooled fallback.
    /// The copy differs: one is "after a hard session", the other is "between
    /// sessions".
    public func isBandSpecific(_ band: EffortBand) -> Bool {
        (bands[band]?.sampleCount ?? 0) >= Self.minimumGaps
    }

    private func clampGap(_ hours: Double) -> Double {
        guard hours.isFinite else { return RecoveryCalculator.minimumCountdownHours }
        return min(max(hours, RecoveryCalculator.minimumCountdownHours), Self.maximumUsualHours)
    }

    /// The free tier's answer for one session: how long this person usually
    /// leaves, plus enough about where it came from for a screen to say so.
    public struct Window: Sendable, Equatable {
        public let hours: Double
        public let band: EffortBand
        public let sampleCount: Int
        /// False when the figure is the pooled one because this band's own
        /// sample was too thin. The copy differs, so the caller has to know.
        public let isBandSpecific: Bool

        public init(hours: Double, band: EffortBand, sampleCount: Int, isBandSpecific: Bool) {
            self.hours = hours
            self.band = band
            self.sampleCount = sampleCount
            self.isBandSpecific = isBandSpecific
        }
    }

    /// Everything a caller needs for one session in one call, or nil when this
    /// person's history has not shown a pattern yet.
    public func window(forLoad load: Double, referenceLoad: Double) -> Window? {
        let band = band(forLoad: load, referenceLoad: referenceLoad)
        guard let hours = usualGapHours(for: band), let evidence = evidence(for: band) else { return nil }
        return Window(
            hours: hours,
            band: band,
            sampleCount: evidence.sampleCount,
            isBandSpecific: isBandSpecific(band)
        )
    }

    // MARK: - Building it

    /// Reads the pattern off a history.
    ///
    /// - Parameters:
    ///   - sessions: every workout in the window, in any order.
    ///   - now: the calculation instant.
    ///   - windowDays: how far back to look.
    ///
    /// `easy` sessions are excluded on both sides of every gap: an
    /// active-recovery walk is neither a session somebody recovers *from* nor
    /// evidence that they were ready to train again. It is the same rule
    /// `RecoveryBaseline` applies, for the same reason.
    public static func analyse(
        sessions: [Session],
        now: Date = .now,
        windowDays: Int = ObservedRecoveryPattern.windowDays
    ) -> ObservedRecoveryPattern {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let ordered = sessions
            .filter { $0.profile != .easy && $0.load > 0 && $0.endDate >= cutoff && $0.endDate <= now }
            .sorted { $0.endDate < $1.endDate }
        guard ordered.count >= 2 else { return .empty }

        let loads = ordered.map(\.load).sorted()
        let lightCeiling = RecoveryBaseline.percentile(1.0 / 3.0, in: loads)
        let moderateCeiling = RecoveryBaseline.percentile(2.0 / 3.0, in: loads)

        // The "real training" half of the bar. Median rather than mean, so one
        // three-hour ultra cannot raise the threshold on a whole history.
        let medianLoad = RecoveryBaseline.percentile(0.5, in: loads)

        var gapsByBand: [EffortBand: [Double]] = [:]
        var allGaps: [Double] = []

        for (index, session) in ordered.enumerated() {
            guard let gap = gapAfter(index, in: ordered, medianLoad: medianLoad) else { continue }
            let band = bandFor(
                load: session.load, lightCeiling: lightCeiling, moderateCeiling: moderateCeiling
            )
            gapsByBand[band, default: []].append(gap)
            allGaps.append(gap)
        }

        var bands: [EffortBand: BandPattern] = [:]
        for (band, gaps) in gapsByBand {
            bands[band] = BandPattern(
                band: band,
                medianGapHours: RecoveryBaseline.percentile(0.5, in: gaps.sorted()),
                sampleCount: gaps.count
            )
        }
        let pooled = allGaps.isEmpty ? nil : BandPattern(
            band: .moderate,
            medianGapHours: RecoveryBaseline.percentile(0.5, in: allGaps.sorted()),
            sampleCount: allGaps.count
        )

        return ObservedRecoveryPattern(
            bands: bands,
            pooled: pooled,
            lightCeiling: lightCeiling,
            moderateCeiling: moderateCeiling,
            sessionCount: ordered.count
        )
    }

    /// Hours from the end of session `index` to the start of the next session
    /// that counts as **going again**, or nil when there wasn't one inside the
    /// cap.
    ///
    /// Lighter sessions in between are skipped rather than ending the search: a
    /// hard Monday, an easy Tuesday and a hard Wednesday is a 48-hour gap
    /// between the two efforts that matter, and counting the walk would report
    /// that this person recovers in a day.
    private static func gapAfter(_ index: Int, in ordered: [Session], medianLoad: Double) -> Double? {
        let session = ordered[index]
        let bar = min(session.load * comparableFraction, medianLoad * typicalFraction)
        for next in ordered.dropFirst(index + 1) {
            let hours = next.startDate.timeIntervalSince(session.endDate) / 3600
            guard hours.isFinite else { return nil }
            if hours > maximumGapHours { return nil }
            guard next.load >= bar else { continue }
            guard hours >= minimumGapHours else { continue }
            return hours
        }
        return nil
    }

    private static func bandFor(
        load: Double, lightCeiling: Double, moderateCeiling: Double
    ) -> EffortBand {
        if load <= lightCeiling { return .light }
        if load <= moderateCeiling { return .moderate }
        return .hard
    }
}
