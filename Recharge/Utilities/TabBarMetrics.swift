import CoreGraphics

/// The tab bar's geometry lives in one place so the bar and the room made for
/// it stay equal.
///
/// Constants rather than a measured height on purpose: every term below is
/// fixed, including `buttonHeight` and the 10pt label inside it, so the bar is
/// the same size at every Dynamic Type setting and there is nothing to measure.
/// If the bar is ever allowed to grow with text, this becomes a measurement and
/// `RootView` has to read it back, not a constant somebody remembers to update.
///
/// In the unit-test target, so `TabBarMetricsTests` can measure every glyph
/// the bar draws against the slot it is given.
enum TabBarMetrics {
    /// Matches `TabButton`'s frame, which is 44 because that is the minimum
    /// comfortable touch target.
    static let buttonHeight: CGFloat = 44
    static let verticalPadding: CGFloat = 6
    static let bottomPadding: CGFloat = 12

    /// The capsule's full height plus the gap under it.
    static var clearance: CGFloat { buttonHeight + verticalPadding * 2 + bottomPadding }

    /// Every tab's icon sits in a slot of this height, whatever the glyph's own
    /// bounds. SF Symbols at one point size are not one height (`sparkles` is
    /// shorter than `hourglass`), and a centred icon-over-label stack moved
    /// each label's baseline by the difference.
    static let iconPointSize: CGFloat = 18
    static let iconSlotHeight: CGFloat = 24
    static let labelSpacing: CGFloat = 4

    /// The glyphs the bar draws, named once so the test measures the same ones.
    enum Symbol {
        static let today = "hourglass"
        static let history = "list.bullet.rectangle"
        static let plus = "sparkles"
        static let upgrade = "lock.fill"
        static let all = [today, history, plus, upgrade]
    }
}
