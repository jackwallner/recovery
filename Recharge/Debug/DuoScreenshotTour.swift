#if DEBUG
import Foundation

/// Unattended iPhone Duo capture (`gh-sim launch --device 'iPhone Duo'`).
/// DEBUG only, so none of it ships.
///
/// `-DuoTour` walks the main screens on a timer, because `simctl openurl`
/// raises a confirmation alert and the capture job cannot tap. `-DuoRoutes a,b`
/// is the walk while folded and `-DuoRoutesRegular a,b` while split (the inner
/// display). `-DuoTourFirst <s>` is the delay before the first route and
/// `-DuoTourStep <s>` the dwell on each. The walk repeats, and restarts when
/// the panes split or join, so each display gets all of it. Every step is
/// logged as a `DUOTOUR` line, which maps the captures to routes.
///
/// A route is `tab/panel`, either half optional. Tabs: `today`, `history`,
/// `plus`. Panels: `settings`, and `detail:<n>`, the nth newest session.
enum DuoScreenshotTour {
    private static let arguments = ProcessInfo.processInfo.arguments

    static var isEnabled: Bool { arguments.contains("-DuoTour") }

    static func routes(split: Bool) -> [String] {
        let list = value(split ? "-DuoRoutesRegular" : "-DuoRoutes")
            ?? (split
                ? "today,today/detail:0,plus,plus/detail:4,today/settings"
                : "today,history,plus,today/detail:0")
        return list.split(separator: ",").map(String.init)
    }

    static var firstDelay: Double { value("-DuoTourFirst").flatMap(Double.init) ?? 2 }
    static var step: Double { value("-DuoTourStep").flatMap(Double.init) ?? 10 }

    private static func value(_ key: String) -> String? {
        guard let i = arguments.firstIndex(of: key), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }
}
#endif
