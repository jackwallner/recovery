import CoreGraphics
import XCTest

final class UnfoldedSplitTests: XCTestCase {
    /// The unfolded iPhone Duo's inner display, held landscape.
    private let innerWidth: CGFloat = 951

    func testCompactWidthNeverSplits() {
        XCTAssertNil(UnfoldedSplit.make(width: 466, isRegularWidth: false, fold: nil))
        XCTAssertNil(UnfoldedSplit.make(width: innerWidth, isRegularWidth: false, fold: 455.5...495.5))
    }

    func testPortraitUnfoldStaysSingleColumn() {
        // 669 pt wide: two 360 pt panes do not fit.
        XCTAssertNil(UnfoldedSplit.make(width: 669, isRegularWidth: true, fold: nil))
    }

    func testPanesMeetTheFoldEdges() throws {
        // The fold the iPhone Duo simulator reports on iOS 27.1.
        let split = try XCTUnwrap(UnfoldedSplit.make(width: innerWidth, isRegularWidth: true, fold: 455.5...495.5))
        XCTAssertEqual(split.primaryWidth, 455.5)
        XCTAssertEqual(split.secondaryX, 495.5)
        XCTAssertEqual(split.secondaryWidth, innerWidth - 495.5)
    }

    func testZeroWidthFoldStillMeetsIt() throws {
        let split = try XCTUnwrap(UnfoldedSplit.make(width: innerWidth, isRegularWidth: true, fold: 475...475))
        XCTAssertEqual(split.primaryWidth, 475)
        XCTAssertEqual(split.secondaryX, 475)
        XCTAssertEqual(split.primaryWidth + split.secondaryWidth, innerWidth)
    }

    func testNoFoldSplitsEvenly() throws {
        let split = try XCTUnwrap(UnfoldedSplit.make(width: innerWidth, isRegularWidth: true, fold: nil))
        XCTAssertEqual(split.primaryWidth, 475)
        XCTAssertEqual(split.secondaryX, 475)
        XCTAssertEqual(split.secondaryWidth, 476)
    }

    func testOffCentreFoldFallsBackToAnEvenSplit() throws {
        // A fold that would leave the trailing pane under 360 pt is ignored.
        let split = try XCTUnwrap(UnfoldedSplit.make(width: 800, isRegularWidth: true, fold: 500...510))
        XCTAssertEqual(split.primaryWidth, 400)
        XCTAssertEqual(split.secondaryX, 400)
    }

    func testEverySplitKeepsBothPanesUsableAndCoversTheWidth() {
        for width in stride(from: CGFloat(600), through: 1400, by: 7) {
            guard let split = UnfoldedSplit.make(width: width, isRegularWidth: true, fold: nil) else {
                XCTAssertLessThan(width, UnfoldedSplit.minimumPaneWidth * 2)
                continue
            }
            XCTAssertGreaterThanOrEqual(split.primaryWidth, UnfoldedSplit.minimumPaneWidth)
            XCTAssertGreaterThanOrEqual(split.secondaryWidth, UnfoldedSplit.minimumPaneWidth)
            XCTAssertEqual(split.secondaryX + split.secondaryWidth, width)
        }
    }

    // MARK: - The tab bar's band

    /// `TabBarMetrics.clearance`: the capsule's 56 pt plus the 12 pt under it.
    private let barClearance: CGFloat = 68

    func testLeadingPaneBandMeetsTheBarsTopEdge() {
        // 34 pt is the home indicator's strip on the unfolded Duo. The band and
        // that strip together cover exactly the bar's height, so the band's top
        // edge is the capsule's top edge and nothing scrolls in under it.
        for safeArea: CGFloat in [0, 20, 34] {
            let band = UnfoldedSplit.tabBarBand(pane: .leading, barClearance: barClearance, bottomSafeArea: safeArea)
            XCTAssertEqual(band + safeArea, barClearance)
        }
    }

    func testLeadingPaneBandIsNeverNegative() {
        XCTAssertEqual(UnfoldedSplit.tabBarBand(pane: .leading, barClearance: barClearance, bottomSafeArea: 90), 0)
    }

    func testTrailingPaneReservesNothing() {
        XCTAssertEqual(UnfoldedSplit.tabBarBand(pane: .trailing, barClearance: barClearance, bottomSafeArea: 34), 0)
    }

    func testFoldedKeepsThePhoneClearance() {
        // Folded is the ordinary phone layout: the last row rests a full bar
        // above the home indicator, as it always has.
        XCTAssertEqual(UnfoldedSplit.tabBarBand(pane: nil, barClearance: barClearance, bottomSafeArea: 34), barClearance)
    }
}
