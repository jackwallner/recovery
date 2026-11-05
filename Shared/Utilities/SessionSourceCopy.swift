import Foundation

/// The sentence under Today's countdown: which workout, how long ago, and what
/// it cost. One whole key per shape, because the pieces (a cost, a session name,
/// a time ago, a reason there is no countdown) reorder between languages.
///
/// `punctuated` is the VoiceOver variant, which ends the sentence; the on-screen
/// line does not.
enum SessionSourceCopy {
    enum Kind {
        /// A countdown set by this session alone.
        case plain
        /// A countdown that also carries time still owed from an earlier one.
        case stacked
        /// Active recovery: costs something, starts nothing.
        case easy
        /// Under the person's threshold for a countdown.
        case notEnough
    }

    static func line(
        kind: Kind,
        costHours: Double,
        carriedHours: Double,
        activityLabel: String,
        secondsSinceEnd: TimeInterval,
        punctuated: Bool
    ) -> String {
        let cost = CountdownFormat.hours(costHours)
        let carried = CountdownFormat.hours(carriedHours)
        let activity = WorkoutClassifier.displayLabel(activityLabel)
        let ago = CountdownFormat.remaining(secondsSinceEnd)
        // "Just now" only for the first minute. It used to cover the first
        // hour, so a session that ended 59 minutes ago read "just now" beside a
        // History row stamped an hour earlier.
        let justNow = secondsSinceEnd < 60
        return switch (kind, justNow, punctuated) {
        case (.plain, true, false): String(localized: "\(cost) from your \(activity) just now", bundle: .recharge)
        case (.plain, true, true): String(localized: "\(cost) from your \(activity) just now.", bundle: .recharge)
        case (.plain, false, false): String(localized: "\(cost) from your \(activity) \(ago) ago", bundle: .recharge)
        case (.plain, false, true): String(localized: "\(cost) from your \(activity) \(ago) ago.", bundle: .recharge)
        case (.stacked, true, false): String(localized: "\(cost) from your \(activity) just now, on top of \(carried) already owed", bundle: .recharge)
        case (.stacked, true, true): String(localized: "\(cost) from your \(activity) just now, on top of \(carried) already owed.", bundle: .recharge)
        case (.stacked, false, false): String(localized: "\(cost) from your \(activity) \(ago) ago, on top of \(carried) already owed", bundle: .recharge)
        case (.stacked, false, true): String(localized: "\(cost) from your \(activity) \(ago) ago, on top of \(carried) already owed.", bundle: .recharge)
        case (.easy, true, false): String(localized: "\(cost) from your \(activity) just now · active recovery, so nothing to wait out", bundle: .recharge)
        case (.easy, true, true): String(localized: "\(cost) from your \(activity) just now · active recovery, so nothing to wait out.", bundle: .recharge)
        case (.easy, false, false): String(localized: "\(cost) from your \(activity) \(ago) ago · active recovery, so nothing to wait out", bundle: .recharge)
        case (.easy, false, true): String(localized: "\(cost) from your \(activity) \(ago) ago · active recovery, so nothing to wait out.", bundle: .recharge)
        case (.notEnough, true, false): String(localized: "\(cost) from your \(activity) just now · not enough to start a countdown", bundle: .recharge)
        case (.notEnough, true, true): String(localized: "\(cost) from your \(activity) just now · not enough to start a countdown.", bundle: .recharge)
        case (.notEnough, false, false): String(localized: "\(cost) from your \(activity) \(ago) ago · not enough to start a countdown", bundle: .recharge)
        case (.notEnough, false, true): String(localized: "\(cost) from your \(activity) \(ago) ago · not enough to start a countdown.", bundle: .recharge)
        }
    }
}
