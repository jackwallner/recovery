import UIKit
import XCTest

/// The tab labels drifted: `Recharge+` sat 5-7 px below `Today` on the
/// unfolded iPhone Duo, because each button centred its own glyph's height
/// over its label. Every glyph now gets one slot, so these pin that the slot
/// holds every glyph and that the slot plus label still fit the button.
@MainActor
final class TabBarMetricsTests: XCTestCase {
    private var iconConfiguration: UIImage.SymbolConfiguration {
        let base = UIFont.systemFont(ofSize: TabBarMetrics.iconPointSize, weight: .medium)
        let rounded = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 0) } ?? base
        return UIImage.SymbolConfiguration(font: rounded)
    }

    func testEveryTabGlyphFitsTheSharedIconSlot() throws {
        for name in TabBarMetrics.Symbol.all {
            let image = try XCTUnwrap(
                UIImage(systemName: name, withConfiguration: iconConfiguration),
                "\(name) is not an SF Symbol"
            )
            XCTAssertLessThanOrEqual(
                image.size.height, TabBarMetrics.iconSlotHeight,
                "\(name) is taller than the slot, so it would push its label down"
            )
        }
    }

    func testTheSlotAndLabelFitTheButton() {
        let label = UIFont.preferredFont(
            forTextStyle: .caption2,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        )
        let stack = TabBarMetrics.iconSlotHeight + TabBarMetrics.labelSpacing + label.lineHeight
        XCTAssertLessThanOrEqual(stack, TabBarMetrics.buttonHeight)
    }
}
