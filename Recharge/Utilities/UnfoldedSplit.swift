import CoreGraphics
import SwiftUI

/// Pane frames for the unfolded iPhone Duo: Today (or Recharge+, with the tab
/// bar) on the leading side of the fold, History on the trailing side, so no
/// card straddles the crease. `nil` keeps the single-column layout: every
/// ordinary iPhone, the folded Duo, and the unfolded Duo held in portrait, where
/// each half would be too narrow.
struct UnfoldedSplit: Equatable, Sendable {
    var primaryWidth: CGFloat
    var secondaryX: CGFloat
    var secondaryWidth: CGFloat

    /// Narrowest pane that still fits the compact Today and History layouts.
    static let minimumPaneWidth: CGFloat = 360

    /// - Parameters:
    ///   - width: the container's width.
    ///   - fold: the vertical fold's leading and trailing edge in the same
    ///     coordinate space, or `nil` when the system reports none.
    static func make(width: CGFloat, isRegularWidth: Bool, fold: ClosedRange<CGFloat>?) -> UnfoldedSplit? {
        guard isRegularWidth, width >= minimumPaneWidth * 2 else { return nil }
        if let fold,
           fold.lowerBound >= minimumPaneWidth,
           width - fold.upperBound >= minimumPaneWidth {
            return UnfoldedSplit(
                primaryWidth: fold.lowerBound,
                secondaryX: fold.upperBound,
                secondaryWidth: width - fold.upperBound
            )
        }
        let half = (width / 2).rounded(.down)
        return UnfoldedSplit(primaryWidth: half, secondaryX: half, secondaryWidth: width - half)
    }
}

/// Which side of the unfolded iPhone Duo's fold a screen fills. `nil` in the
/// environment everywhere else, including the folded Duo.
enum UnfoldedPane: Sendable {
    case leading, trailing
}

extension UnfoldedSplit {
    /// The band a scrollable screen keeps above its bottom safe area for
    /// the floating tab bar, which sits `barClearance` above the screen's edge.
    ///
    /// Folded, the band is clear and as tall as the bar, so the last row rests
    /// above the capsule and passing rows still scroll behind it. The trailing
    /// pane has no bar under it. The leading pane's band runs from the bar's
    /// top edge to the bottom of the screen, so nothing is ever drawn under the
    /// capsule beside a History pane that runs to the bottom edge.
    static func tabBarBand(pane: UnfoldedPane?, barClearance: CGFloat, bottomSafeArea: CGFloat) -> CGFloat {
        switch pane {
        case nil: barClearance
        case .trailing: 0
        case .leading: max(0, barClearance - bottomSafeArea)
        }
    }
}

extension GeometryProxy {
    /// The vertical fold's horizontal extent in this proxy's space. Inactive
    /// folds count too, so the panes don't jump while the device opens.
    func verticalFold() -> ClosedRange<CGFloat>? {
        guard #available(iOS 27.1, *) else { return nil }
        let fold = reservedRegions(kind: .division, options: .includeInactive)
            .map(\.frame)
            .first { $0.height > $0.width && $0.minX > 0 && $0.maxX < size.width }
        guard let fold else { return nil }
        return fold.minX...fold.maxX
    }
}
