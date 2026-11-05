import Foundation

/// A free trial measured in days or months. Never rendered to a finished label
/// and passed around as text: every sentence that names it is its own key.
public enum IntroTrialLength: Equatable, Sendable {
    case days(Int)
    case months(Int)

    /// "7-day free · Nothing charged today"
    public var badge: String {
        switch self {
        case .days(let n): String(localized: "\(n)-day free · Nothing charged today", bundle: .recharge)
        case .months(let n): String(localized: "\(n)-month free · Nothing charged today", bundle: .recharge)
        }
    }
}
