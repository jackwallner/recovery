import SwiftUI

#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

/// How the app answers a finger.
///
/// Recharge had eighteen `.buttonStyle(.plain)` call sites and no pressed state
/// on any of them, which is what `.plain` means on a custom-drawn button: the
/// label is handed to you and nothing happens on touch down. Every locked card,
/// plan card, effort answer and history row was a rectangle that did not react.
/// A dead control reads as a broken one, and the user blames the app rather than
/// the style.
///
/// One style, applied everywhere, so the reaction is identical on every surface
/// and cannot drift into "this screen animates and that one does not".
public struct PressableButtonStyle: ButtonStyle {
    /// Cards move less than buttons: a large surface scaling as hard as a
    /// 44pt control reads as the whole screen wobbling.
    public enum Weight {
        case control
        case card

        var scale: CGFloat {
            switch self {
            case .control: 0.96
            case .card: 0.985
            }
        }
    }

    var weight: Weight = .control

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(weight: Weight = .control) {
        self.weight = weight
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Reduce Motion keeps the feedback and drops the movement. The
            // control still has to answer; it just answers in opacity.
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? weight.scale : 1))
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

public extension View {
    /// Replaces `.buttonStyle(.plain)` on any button that draws its own label.
    func pressable(_ weight: PressableButtonStyle.Weight = .control) -> some View {
        buttonStyle(PressableButtonStyle(weight: weight))
    }
}

/// Haptics, on meaningful actions only.
///
/// The rule is that a haptic marks a state change the user caused and would
/// otherwise have to read to confirm: an answer recorded, a purchase completed,
/// a countdown reaching Ready. Tapping every button is worse than tapping none,
/// because a signal that fires constantly stops being a signal.
///
/// Deliberately not fired on: scrolling, navigation pushes, or anything the
/// system already taps for (a sheet's own dismiss, a `Toggle`, a picker).
public enum Haptics {
    /// A choice was recorded. Plan card, effort answer, tab change.
    public static func selection() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }

    /// Something completed: a purchase, an import, an effort answer sent to the
    /// phone.
    public static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }

    /// Something could not be done. Never used for a validation message the user
    /// can already see.
    public static func failure() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.failure)
        #endif
    }

    /// The payoff. A countdown reaching Ready is the one moment the app exists
    /// for, and it is the only place a heavier impact is warranted.
    public static func ready() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.notification)
        #endif
    }
}
