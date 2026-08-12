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
        activityLabel: String = "run"
    ) -> [String] {
        [
            ComplicationCopy.primary(phase: phase, style: style, remaining: remaining, readyAt: readyAt),
            ComplicationCopy.secondary(
                phase: phase, style: style, remaining: remaining, readyAt: readyAt,
                activityLabel: activityLabel
            ),
            ComplicationCopy.inline(phase: phase, style: style, remaining: remaining, readyAt: readyAt),
            ComplicationCopy.rectangularTitle(phase: phase, style: style, remaining: remaining, readyAt: readyAt)
        ]
    }

    /// The whole matrix: four phases, three styles, both activity-label states.
    private func everyString() -> [String] {
        var strings: [String] = []
        for phase in phases {
            for style in ComplicationStyle.allCases {
                for label in ["run", ""] {
                    let remaining: TimeInterval = phase == .readySoon ? 4_500 : 18 * 3600
                    strings += allCopy(
                        phase: phase,
                        style: style,
                        remaining: phase == .ready || phase == .noRecentWorkout ? 0 : remaining,
                        readyAt: phase == .ready || phase == .noRecentWorkout
                            ? nil
                            : now.addingTimeInterval(remaining),
                        activityLabel: label
                    )
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
    func testPrimaryStaysShortEnoughForACircularSlot() {
        for phase in phases {
            for style in ComplicationStyle.allCases {
                let primary = ComplicationCopy.primary(
                    phase: phase,
                    style: style,
                    remaining: 22 * 3600 + 45 * 60,
                    readyAt: now.addingTimeInterval(22 * 3600 + 45 * 60)
                )
                XCTAssertLessThanOrEqual(primary.count, 8, "\(phase)/\(style) primary was \"\(primary)\"")
            }
        }
    }

    func testInlineStaysWithinAOneLineSlot() {
        for phase in phases {
            for style in ComplicationStyle.allCases {
                let inline = ComplicationCopy.inline(
                    phase: phase,
                    style: style,
                    remaining: 18 * 3600,
                    readyAt: now.addingTimeInterval(18 * 3600)
                )
                XCTAssertLessThanOrEqual(inline.count, 20, "\(phase)/\(style) inline was \"\(inline)\"")
            }
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
