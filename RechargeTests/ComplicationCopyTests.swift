import XCTest

/// The complication is the glanciest surface in the app and the one with the
/// least room for a qualifier, which makes it both the most likely place for a
/// compliance slip and, until `ComplicationCopy` moved into `Shared`, the only
/// user-facing copy the suite could not see at all.
final class ComplicationCopyTests: XCTestCase {

    private let now = RecoveryFixtures.now
    private let phases: [RecoveryPhase] = [.noRecentWorkout, .ready, .readySoon, .recovering]

    /// Every string the four families can render, for one phase and style.
    private func allCopy(
        phase: RecoveryPhase,
        style: ComplicationStyle,
        remaining: TimeInterval,
        readyAt: Date?,
        activityLabel: String = "run",
        dataState: ComplicationCopy.DataState = .synced
    ) -> [String] {
        [
            ComplicationCopy.primary(
                phase: phase, style: style, remaining: remaining, readyAt: readyAt,
                dataState: dataState
            ),
            ComplicationCopy.secondary(
                phase: phase, style: style, remaining: remaining, readyAt: readyAt,
                activityLabel: activityLabel, dataState: dataState
            ),
            ComplicationCopy.inline(
                phase: phase, style: style, remaining: remaining, readyAt: readyAt,
                dataState: dataState
            ),
            ComplicationCopy.rectangularTitle(
                phase: phase, style: style, remaining: remaining, readyAt: readyAt,
                dataState: dataState
            )
        ]
    }

    /// The whole matrix: four phases, three styles, both activity-label states,
    /// both data states.
    ///
    /// `dataState` is in here rather than tested on its own because every
    /// property the other tests assert — no medical claim, never empty, fits the
    /// slot — has to hold for the never-synced strings too, and a state that only
    /// its own test can see is a state the compliance checks do not cover.
    private func everyString() -> [String] {
        var strings: [String] = []
        for phase in phases {
            for style in ComplicationStyle.allCases {
                for label in ["run", ""] {
                    for dataState in ComplicationCopy.DataState.allCases {
                        let remaining: TimeInterval = phase == .readySoon ? 4_500 : 18 * 3600
                        strings += allCopy(
                            phase: phase,
                            style: style,
                            remaining: phase == .ready || phase == .noRecentWorkout ? 0 : remaining,
                            readyAt: phase == .ready || phase == .noRecentWorkout
                                ? nil
                                : now.addingTimeInterval(remaining),
                            activityLabel: label,
                            dataState: dataState
                        )
                    }
                }
            }
        }
        return strings
    }

    // MARK: - Compliance

    /// The same list `testNoPhaseCopyMakesAMedicalClaim` holds the phone copy
    /// to. A complication has no room to frame the number as an estimate, so it
    /// has even less licence to imply a clearance to train.
    func testNoComplicationCopyMakesAMedicalClaim() {
        let banned = ["recovered", "safe to train", "injury", "your body", "cure", "diagnos", "muscle"]
        for text in everyString() {
            for phrase in banned {
                XCTAssertFalse(
                    text.lowercased().contains(phrase),
                    "\"\(phrase)\" appeared in complication copy: \"\(text)\""
                )
            }
        }
    }

    func testReadyNeverPromisesClearanceToTrain() {
        // "Ready to train" was the original ready-state string and reads as
        // permission rather than as a statement about training load.
        for text in everyString() {
            XCTAssertFalse(text.lowercased().contains("ready to train"), "\"\(text)\"")
        }
    }

    // MARK: - Shape

    func testNoStringIsEverEmpty() {
        for text in everyString() {
            XCTAssertFalse(text.isEmpty, "a complication slot would render nothing")
        }
    }

    /// Circular and corner slots are a handful of characters wide. This is the
    /// guard against a style quietly growing a string those families cannot fit.
    /// Widened from a single sample to the whole range, because the sample was
    /// the reason the previous width claim held: `compactRemaining` was checked
    /// at 22h45m, which is below the 24-hour boundary where the string used to
    /// collapse to `"2d"` and now reads `"2d 23h"`.
    func testPrimaryStaysShortEnoughForACircularSlot() {
        for phase in phases {
            for style in ComplicationStyle.allCases {
                for dataState in ComplicationCopy.DataState.allCases {
                    for minutes in stride(from: 1, through: 72 * 60, by: 7) {
                        let remaining = TimeInterval(minutes * 60)
                        let primary = ComplicationCopy.primary(
                            phase: phase,
                            style: style,
                            remaining: remaining,
                            readyAt: now.addingTimeInterval(remaining),
                            dataState: dataState
                        )
                        XCTAssertLessThanOrEqual(
                            primary.count, 8,
                            "\(phase)/\(style)/\(dataState) primary was \"\(primary)\" at \(minutes)m left"
                        )
                    }
                }
            }
        }
    }

    func testInlineStaysWithinAOneLineSlot() {
        for phase in phases {
            for style in ComplicationStyle.allCases {
                for dataState in ComplicationCopy.DataState.allCases {
                    for minutes in stride(from: 1, through: 72 * 60, by: 7) {
                        let remaining = TimeInterval(minutes * 60)
                        let inline = ComplicationCopy.inline(
                            phase: phase,
                            style: style,
                            remaining: remaining,
                            readyAt: now.addingTimeInterval(remaining),
                            dataState: dataState
                        )
                        XCTAssertLessThanOrEqual(
                            inline.count, 20,
                            "\(phase)/\(style)/\(dataState) inline was \"\(inline)\" at \(minutes)m left"
                        )
                    }
                }
            }
        }
    }

    // MARK: - The state that looked like a broken complication

    /// A complication that has never been handed a snapshot must say so, not
    /// render a dash.
    ///
    /// The Watch has its own App Group container and only the Watch *app* writes
    /// into it, so between installing Recharge and opening it on the wrist the
    /// extension has genuinely never been told anything. That went through the
    /// `noRecentWorkout` branch, whose primary string is `"--"`, and a face
    /// showing `--` with no explanation is indistinguishable from a complication
    /// that does not work.
    func testAComplicationThatHasNeverSyncedSaysSoRatherThanShowingADash() {
        for style in ComplicationStyle.allCases {
            let strings = allCopy(
                phase: .noRecentWorkout,
                style: style,
                remaining: 0,
                readyAt: nil,
                activityLabel: "",
                dataState: .neverSynced
            )
            for text in strings {
                XCTAssertFalse(
                    text.trimmingCharacters(in: CharacterSet(charactersIn: "- ")).isEmpty,
                    "\(style) rendered \"\(text)\", which reads as a broken complication"
                )
            }
            XCTAssertTrue(
                strings.contains { $0.lowercased().contains("open") },
                "\(style) never tells the user what to do about it: \(strings)"
            )
        }
    }

    /// And the two states have to be distinguishable, or the fix is cosmetic:
    /// "you have not set this up" and "you have not trained in four days" are
    /// different problems with different answers.
    func testNeverSyncedAndNoRecentWorkoutDoNotReadTheSame() {
        for style in ComplicationStyle.allCases {
            let synced = allCopy(
                phase: .noRecentWorkout, style: style, remaining: 0, readyAt: nil,
                activityLabel: "", dataState: .synced
            )
            let never = allCopy(
                phase: .noRecentWorkout, style: style, remaining: 0, readyAt: nil,
                activityLabel: "", dataState: .neverSynced
            )
            XCTAssertNotEqual(synced, never, "\(style) says the same thing in both states")
        }
    }

    // MARK: - The countdown actually counts down

    func testTheCountdownStyleRendersTheRemainingTime() {
        for hours in [0.5, 1.5, 18.0, 30.0] {
            let remaining = hours * 3600
            let primary = ComplicationCopy.primary(
                phase: .recovering, style: .countdown,
                remaining: remaining, readyAt: now.addingTimeInterval(remaining)
            )
            XCTAssertEqual(primary, CountdownFormat.compactRemaining(remaining))
        }
    }

    func testTheReadyClockStyleRendersTheReadyTimeNotTheRemaining() {
        let readyAt = now.addingTimeInterval(18 * 3600)
        XCTAssertEqual(
            ComplicationCopy.primary(
                phase: .recovering, style: .readyClock, remaining: 18 * 3600, readyAt: readyAt
            ),
            CountdownFormat.clock(readyAt)
        )
    }

    /// The clock styles read `readyAt`, which a malformed snapshot can be
    /// missing while still reporting a running phase. It must not render "nil".
    func testAMissingReadyTimeFallsBackRatherThanRenderingNil() {
        for style in ComplicationStyle.allCases {
            for text in allCopy(phase: .recovering, style: style, remaining: 3600, readyAt: nil) {
                XCTAssertFalse(text.lowercased().contains("nil"), "\"\(text)\"")
            }
        }
    }

    // MARK: - Phase distinctions the user has to be able to see

    func testEachPhaseReadsDifferentlyWithinAStyle() {
        for style in ComplicationStyle.allCases {
            let rendered = phases.map { phase in
                ComplicationCopy.inline(
                    phase: phase, style: style,
                    remaining: phase == .readySoon ? 3_600 : 18 * 3600,
                    readyAt: now.addingTimeInterval(phase == .readySoon ? 3_600 : 18 * 3600)
                )
            }
            XCTAssertEqual(
                Set(rendered).count, rendered.count,
                "two phases render identically in \(style): \(rendered)"
            )
        }
    }

    func testTheNoWorkoutStateNeverBorrowsTheReadyWord() {
        // "Ready" in an empty state would tell a user who has never finished a
        // workout that they are cleared for one.
        for style in ComplicationStyle.allCases {
            for text in allCopy(phase: .noRecentWorkout, style: style, remaining: 0, readyAt: nil) {
                XCTAssertFalse(text.lowercased().contains("ready"), "\"\(text)\"")
            }
        }
    }

    func testTheReadyStateNamesTheSessionWhenThereIsOneAndDoesNotWhenThereIsNot() {
        XCTAssertEqual(
            ComplicationCopy.secondary(
                phase: .ready, style: .countdown, remaining: 0, readyAt: nil, activityLabel: "run"
            ),
            "After your run"
        )
        XCTAssertEqual(
            ComplicationCopy.secondary(
                phase: .ready, style: .countdown, remaining: 0, readyAt: nil, activityLabel: ""
            ),
            "Ready for a hard session"
        )
    }
}
