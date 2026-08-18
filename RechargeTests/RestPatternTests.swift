import XCTest

/// The three-column comparison: what the person does, what the table says for
/// people like them, and what Recharge+ would say.
///
/// Properties rather than values wherever possible, for the same reason
/// `RecoveryMatrixTests` is: the numbers here are tunable and the guarantees are
/// not.
final class RestPatternTests: XCTestCase {

    private let now = RecoveryFixtures.now

    // MARK: - Builders

    private func session(
        hoursAgo: Double,
        band: LoadCategory,
        profile: WorkoutProfile = .endurance,
        standard: Double = 20,
        personalized: Double = 16
    ) -> RestPattern.Session {
        RestPattern.Session(
            id: "s-\(hoursAgo)-\(band.rawValue)",
            endDate: now.addingTimeInterval(-hoursAgo * 3600),
            profile: profile,
            band: band,
            standardHours: standard,
            personalizedHours: personalized
        )
    }

    /// `count` sessions of one band, evenly `everyHours` apart, most recent last.
    private func evenlySpaced(
        _ count: Int,
        band: LoadCategory,
        everyHours: Double,
        standard: Double = 20,
        personalized: Double = 16
    ) -> [RestPattern.Session] {
        (0..<count).map { index in
            session(
                hoursAgo: Double(count - index) * everyHours,
                band: band,
                standard: standard,
                personalized: personalized
            )
        }
    }

    private func row(_ rows: [RestPattern.Row], _ band: LoadCategory) -> RestPattern.Row {
        guard let match = rows.first(where: { $0.band == band }) else {
            XCTFail("no row for \(band)")
            return RestPattern.Row(
                band: band, observedRestHours: nil, gapSamples: 0,
                similarProfilesHours: 0, personalizedHours: 0, isExample: true
            )
        }
        return match
    }

    // MARK: - Shape

    func testThereIsExactlyOneRowPerBandAndEasyIsNotOneOfThem() {
        let rows = RestPattern.rows(sessions: [], profile: .empty, now: now)
        XCTAssertEqual(rows.map(\.band), [.typical, .hard, .unusuallyHard])
        XCTAssertFalse(rows.contains { $0.band == .easy }, "an easy session never starts a countdown")
    }

    /// The card has to say something on the very first launch, or the comparison
    /// that frames the whole app only appears after the first workout.
    func testAUserWithNoHistoryStillGetsAFullTable() {
        let rows = RestPattern.rows(sessions: [], profile: .empty, now: now)
        XCTAssertEqual(rows.count, 3)
        for row in rows {
            XCTAssertTrue(row.isExample, "\(row.band) claimed to be measured with no sessions")
            XCTAssertNil(row.observedRestHours)
            XCTAssertEqual(row.gapSamples, 0)
            XCTAssertGreaterThan(row.similarProfilesHours, 0)
            XCTAssertGreaterThan(row.personalizedHours, 0)
        }
    }

    func testHarderBandsNeverGetAShorterModelledWindow() {
        let profile = AthleteProfile(age: 34, experience: .threeToTenYears, weeklyVolume: .fiveOrSix)
        let rows = RestPattern.rows(sessions: [], profile: profile, now: now)
        for (lower, upper) in zip(rows, rows.dropFirst()) {
            XCTAssertLessThanOrEqual(
                lower.similarProfilesHours, upper.similarProfilesHours,
                "\(upper.band) is not longer than \(lower.band)"
            )
        }
    }

    func testEveryFigureStaysInsideTheBoundsTheAppPromisesEverywhereElse() {
        // Every profile, every band, and a prior at each extreme.
        let profiles: [AthleteProfile] = [
            .empty,
            AthleteProfile(age: 66, experience: .underOneYear, bounceBack: .threeOrMoreDays, weeklyVolume: .oneOrTwo),
            AthleteProfile(age: 21, experience: .tenYearsPlus, bounceBack: .nextDay, weeklyVolume: .sevenPlus)
        ]
        for profile in profiles {
            for primary in [WorkoutProfile.endurance, .strength, .mixed] {
                var withPrimary = profile
                withPrimary.primaryProfile = primary
                for row in RestPattern.rows(sessions: [], profile: withPrimary, now: now) {
                    XCTAssertTrue(row.similarProfilesHours.isFinite)
                    XCTAssertTrue(row.personalizedHours.isFinite)
                    XCTAssertGreaterThanOrEqual(row.similarProfilesHours, RecoveryCalculator.minimumCountdownHours)
                    XCTAssertLessThanOrEqual(row.similarProfilesHours, RecoveryCalculator.maximumHours)
                    XCTAssertGreaterThanOrEqual(row.personalizedHours, RecoveryCalculator.minimumCountdownHours)
                    XCTAssertLessThanOrEqual(row.personalizedHours, RecoveryCalculator.maximumHours)
                }
            }
        }
    }

    // MARK: - The measurement

    func testTheObservedGapIsTheMedianIntervalAfterASessionOfThatBand() {
        // Four hard sessions, 30 hours apart. Three gaps, all 30.
        let rows = RestPattern.rows(
            sessions: evenlySpaced(4, band: .hard, everyHours: 30),
            profile: .empty,
            now: now
        )
        let hard = row(rows, .hard)
        XCTAssertEqual(hard.gapSamples, 3)
        XCTAssertEqual(hard.observedRestHours ?? 0, 30, accuracy: 0.001)
        XCTAssertFalse(hard.isExample)
    }

    /// The interval belongs to the session the rest was taken *from*, not the one
    /// it was taken before. Keying it the other way answers a different question
    /// — how fresh you went in — which is `PersonalRecoveryModel`'s tolerance
    /// signal, not this.
    func testAGapIsAttributedToTheSessionThatStartedIt() {
        let sessions = [
            session(hoursAgo: 100, band: .unusuallyHard),
            session(hoursAgo: 40, band: .typical),
            session(hoursAgo: 10, band: .typical)
        ]
        let rows = RestPattern.rows(sessions: sessions, profile: .empty, now: now)
        // Two gaps: 60h after the very hard one, 30h after the first moderate one.
        XCTAssertEqual(row(rows, .unusuallyHard).gapSamples, 1)
        XCTAssertEqual(row(rows, .typical).gapSamples, 1)
        XCTAssertEqual(row(rows, .hard).gapSamples, 0)
    }

    func testASingleGapIsNotEnoughToClaimAHabit() {
        let rows = RestPattern.rows(
            sessions: evenlySpaced(2, band: .hard, everyHours: 30),
            profile: .empty,
            now: now
        )
        let hard = row(rows, .hard)
        XCTAssertEqual(hard.gapSamples, 1)
        XCTAssertNil(hard.observedRestHours, "one interval is not \"you usually\"")
    }

    /// A fortnight off is a break from training, not a rest interval, and one of
    /// them drags a median into fiction.
    func testALayoffIsNotCountedAsRest() {
        let sessions = [
            session(hoursAgo: 2000, band: .hard),
            session(hoursAgo: 100, band: .hard),
            session(hoursAgo: 70, band: .hard),
            session(hoursAgo: 40, band: .hard)
        ]
        let rows = RestPattern.rows(sessions: sessions, profile: .empty, now: now)
        let hard = row(rows, .hard)
        XCTAssertEqual(hard.gapSamples, 2, "the 1900-hour layoff was counted as rest")
        XCTAssertEqual(hard.observedRestHours ?? 0, 30, accuracy: 0.001)
    }

    func testSessionsOlderThanTheWindowContributeNothing() {
        // One hour clear of the cutoff, which is inclusive: a session landing
        // exactly on it is inside the window, and the first draft of this test
        // put one there and then asserted it was not.
        let firstOutside = Double(RestPattern.windowDays * 24) + 1
        let old = (0..<6).map { session(hoursAgo: firstOutside + Double($0) * 30, band: .hard) }
        let rows = RestPattern.rows(sessions: old, profile: .empty, now: now)
        XCTAssertEqual(row(rows, .hard).gapSamples, 0)
        XCTAssertTrue(row(rows, .hard).isExample)
    }

    /// The cutoff is inclusive, and something has to say so or the next person to
    /// write a boundary test guesses wrong the way the last one did.
    func testASessionExactlyOnTheCutoffIsInsideTheWindow() {
        let onTheEdge = [session(hoursAgo: Double(RestPattern.windowDays * 24), band: .hard)]
        XCTAssertFalse(
            row(RestPattern.rows(sessions: onTheEdge, profile: .empty, now: now), .hard).isExample
        )
    }

    func testEasySessionsAreExcludedEntirely() {
        let sessions = [
            session(hoursAgo: 100, band: .hard),
            session(hoursAgo: 70, band: .easy, profile: .easy),
            session(hoursAgo: 40, band: .hard)
        ]
        let rows = RestPattern.rows(sessions: sessions, profile: .empty, now: now)
        // The walk in the middle must not split the 60-hour gap into two.
        XCTAssertEqual(row(rows, .hard).gapSamples, 1)
    }

    func testUnorderedInputIsHandled() {
        let ordered = evenlySpaced(5, band: .hard, everyHours: 26)
        let shuffled = ordered.shuffled()
        XCTAssertEqual(
            RestPattern.rows(sessions: shuffled, profile: .empty, now: now),
            RestPattern.rows(sessions: ordered, profile: .empty, now: now)
        )
    }

    // MARK: - The two modelled columns

    /// The headline claim of the whole card, and the one the model already made
    /// but nothing on screen could show: the personalized column is not the
    /// standard one times a multiplier.
    func testThePersonalizedColumnIsComputedRatherThanDerived() {
        let sessions = evenlySpaced(4, band: .hard, everyHours: 30, standard: 24, personalized: 15)
        let rows = RestPattern.rows(sessions: sessions, profile: .empty, now: now)
        let hard = row(rows, .hard)
        XCTAssertEqual(hard.personalizedHours, 15, accuracy: 0.001)
        XCTAssertEqual(hard.similarProfilesHours, 24, accuracy: 0.001)
        XCTAssertTrue(hard.isVisiblyPersonalized)
    }

    /// The middle column is a **pass-through** of the standard estimate, not a
    /// second adjustment applied on top of it.
    ///
    /// It used to be `standardHours * AthleteProfile.prior`, which was the only
    /// place in the app where the free tier acknowledged the questionnaire. Now
    /// that the standard estimate is itself scaled by `fitnessScale`, keeping
    /// the multiplication would count weekly volume and experience twice and put
    /// this card into open disagreement with the countdown on the same screen.
    func testTheSimilarColumnIsExactlyTheStandardEstimate() {
        let sessions = evenlySpaced(4, band: .hard, everyHours: 30, standard: 24, personalized: 15)
        for volume in WeeklyVolume.allCases {
            for experience in TrainingExperience.allCases {
                let profile = AthleteProfile(age: 34, experience: experience, weeklyVolume: volume)
                let rows = RestPattern.rows(sessions: sessions, profile: profile, now: now)
                XCTAssertEqual(
                    row(rows, .hard).similarProfilesHours, 24, accuracy: 0.001,
                    "\(volume.label) / \(experience.label) moved a figure the standard tier had already set"
                )
            }
        }
    }

    /// Someone who trains more often must not be told to rest longer. The claim
    /// still holds end to end; it is just made one stage earlier now, in the
    /// standard estimate that feeds this card (`GarminAnchorTests`
    /// `testMoreTrainingNeverLengthensTheStandardWindow`). Asserted here on the
    /// figures a real engine would hand in, so the two halves cannot drift.
    func testAHigherTrainingVolumeNeverLengthensTheSimilarProfilesColumn() {
        var previous: [Double]?
        for volume in WeeklyVolume.allCases {
            let profile = AthleteProfile(age: 34, experience: .threeToTenYears, weeklyVolume: volume)
            let standard = RecoveryCalculator.estimate(
                for: RecoveryFixtures.thresholdRun60,
                baseline: .standard(for: .endurance, fitnessScale: profile.fitnessScale),
                now: now
            )
            let sessions = evenlySpaced(
                4, band: .hard, everyHours: 30,
                standard: standard.hours, personalized: standard.hours * 0.9
            )
            let hours = RestPattern.rows(sessions: sessions, profile: profile, now: now)
                .map(\.similarProfilesHours)
            if let previous {
                for (earlier, later) in zip(previous, hours) {
                    XCTAssertLessThanOrEqual(
                        later, earlier + 0.0001,
                        "training \(volume.label) a week was given a longer window than the tier below it"
                    )
                }
            }
            previous = hours
        }
    }

    /// The row a brand-new user sees, and the one the onboarding upgrade pitch
    /// is made of. Both columns used to print `reference * prior`, so on a fresh
    /// install the pitch was two identical numbers with a blur over one of them.
    ///
    /// The blurred figure is the multiplier `PersonalRecoveryModel` actually
    /// returns for this person with no history, so it stays a number the app
    /// will honour rather than a number invented to make the card sell.
    func testTheExampleRowShowsWhatPersonalisationWouldActuallyDo() {
        let profile = AthleteProfile(
            age: 28, experience: .tenYearsPlus, bounceBack: .nextDay, weeklyVolume: .sevenPlus
        )
        let rows = RestPattern.rows(sessions: [], profile: profile, now: now)
        let expected = PersonalRecoveryModel.analyse(
            profile: profile, sessions: [], days: [], now: now
        ).factor

        for row in rows {
            XCTAssertTrue(row.isExample)
            XCTAssertLessThan(
                row.personalizedHours, row.similarProfilesHours,
                "this person's answers say they recover fast and the pitch showed them nothing"
            )
            XCTAssertEqual(
                row.personalizedHours, row.similarProfilesHours * expected, accuracy: 0.05,
                "the blurred figure is not the one a subscriber would get on day one"
            )
        }
    }

    /// And when the answers are neutral it shows no difference, because there is
    /// none to show yet. A pitch is not allowed to manufacture one.
    func testTheExampleRowClaimsNothingWhenTheAnswersSayNothing() {
        let neutral = AthleteProfile(
            age: 30, experience: .oneToThreeYears, bounceBack: .aboutTwoDays, weeklyVolume: .threeOrFour
        )
        for row in RestPattern.rows(sessions: [], profile: neutral, now: now) {
            XCTAssertEqual(row.personalizedHours, row.similarProfilesHours, accuracy: 0.2)
        }
    }

    /// A profile with no answers makes no claim about fitness, so the middle
    /// column is the plain standard curve.
    func testAnUnansweredProfileGetsThePlainStandardCurve() {
        let rows = RestPattern.rows(sessions: [], profile: .empty, now: now)
        for row in rows {
            XCTAssertEqual(
                row.similarProfilesHours,
                RestPattern.referenceHours(for: row.band, profile: .endurance),
                accuracy: 0.001
            )
        }
    }

    // MARK: - Copy

    func testTheCopyNeverMakesAMedicalClaim() {
        let banned = ["recovered", "safe to train", "injury", "your body", "cure", "diagnos", "muscle"]
        var strings: [String] = []
        for band in RestPattern.bands {
            for observed in [nil, 18.0, 44.0] as [Double?] {
                let row = RestPattern.Row(
                    band: band,
                    observedRestHours: observed,
                    gapSamples: observed == nil ? 0 : 4,
                    similarProfilesHours: 22,
                    personalizedHours: observed == nil ? 22 : 16,
                    isExample: observed == nil
                )
                strings.append(RestPattern.personalizedSentence(row))
                if let sentence = RestPattern.observedSentence(row) { strings.append(sentence) }
            }
        }
        XCTAssertFalse(strings.isEmpty)
        for text in strings {
            for phrase in banned {
                XCTAssertFalse(text.lowercased().contains(phrase), "\"\(phrase)\" appeared in \"\(text)\"")
            }
        }
    }

    /// The card is a comparison, not a prescription. Nothing in it may tell the
    /// user what they *should* do.
    func testTheCopyNeverIssuesAnInstruction() {
        let row = RestPattern.Row(
            band: .hard, observedRestHours: 44, gapSamples: 5,
            similarProfilesHours: 22, personalizedHours: 16, isExample: false
        )
        let strings = [RestPattern.observedSentence(row), RestPattern.personalizedSentence(row)].compactMap { $0 }
        for text in strings {
            for phrase in ["you should", "you need to", "wait until", "do not train"] {
                XCTAssertFalse(text.lowercased().contains(phrase), "\"\(phrase)\" appeared in \"\(text)\"")
            }
        }
    }

    func testTheObservedSentenceIsAbsentUntilThereIsSomethingToSay() {
        let empty = RestPattern.Row(
            band: .hard, observedRestHours: nil, gapSamples: 1,
            similarProfilesHours: 22, personalizedHours: 16, isExample: false
        )
        XCTAssertNil(RestPattern.observedSentence(empty))
    }

    func testTheObservedSentenceNamesTheSampleItIsBuiltFrom() {
        let row = RestPattern.Row(
            band: .hard, observedRestHours: 31, gapSamples: 4,
            similarProfilesHours: 22, personalizedHours: 16, isExample: false
        )
        let sentence = RestPattern.observedSentence(row) ?? ""
        XCTAssertTrue(sentence.contains("31h"), sentence)
        XCTAssertTrue(sentence.contains("4 gaps"), sentence)
        XCTAssertTrue(sentence.lowercased().contains("hard"), sentence)
    }

    func testThePersonalizedSentenceNamesTheDirectionOfTheChange() {
        let shorter = RestPattern.Row(
            band: .hard, observedRestHours: nil, gapSamples: 0,
            similarProfilesHours: 24, personalizedHours: 16, isExample: false
        )
        let longer = RestPattern.Row(
            band: .hard, observedRestHours: nil, gapSamples: 0,
            similarProfilesHours: 16, personalizedHours: 24, isExample: false
        )
        XCTAssertTrue(RestPattern.personalizedSentence(shorter).contains("shorter"))
        XCTAssertTrue(RestPattern.personalizedSentence(longer).contains("longer"))
        XCTAssertNotEqual(
            RestPattern.personalizedSentence(shorter),
            RestPattern.personalizedSentence(longer)
        )
    }
}
