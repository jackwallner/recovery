import SwiftUI
import UIKit

/// iPad layout helpers. Phones keep their layouts; everything here only takes
/// effect on a regular-width, regular-height window or on the iPad idiom.
@MainActor
enum Device {
    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
}

extension View {
    /// Caps a column at a readable width and centres it. A no-op on any
    /// container narrower than `limit`, so phones and compact windows are
    /// untouched.
    func readableWidth(_ limit: CGFloat = 560) -> some View {
        frame(maxWidth: limit).frame(maxWidth: .infinity)
    }

    /// A tall, form-width sheet on iPad (iOS 18+), the plain sheet elsewhere.
    /// The default iPad form sheet is a short card that clips a paywall, and
    /// `.page` stretches it across the whole window.
    @ViewBuilder
    func iPadSheet() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(TallFormSizing())
        } else {
            self
        }
    }
}

@available(iOS 18.0, *)
private struct TallFormSizing: PresentationSizing {
    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        // The context carries nothing to measure; the system clamps the
        // proposal to the window.
        ProposedViewSize(width: 600, height: 880)
    }
}
