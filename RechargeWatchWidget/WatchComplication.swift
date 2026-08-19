import SwiftUI
import WidgetKit

// MARK: - Entry

struct RecoveryEntry: TimelineEntry {
    let date: Date
    let snapshot: RecoverySnapshot
    let style: ComplicationStyle
    /// The read state is carried on the entry rather than re-read per string,
    /// because a timeline is built once and rendered many times.
    var dataState: ComplicationCopy.DataState = .synced

    var phase: RecoveryPhase { snapshot.phase(at: date) }
    var remaining: TimeInterval { snapshot.remainingSeconds(at: date) }
    var progress: Double { snapshot.progress(at: date) }

    static func placeholder(date: Date = .now) -> RecoveryEntry {
        RecoveryEntry(
            date: date,
            snapshot: RecoverySnapshot(
                readyAt: date.addingTimeInterval(18 * 3600),
                sessionEnd: date.addingTimeInterval(-3 * 3600),
                hours: 21,
                windowLowHours: 18,
                windowHighHours: 24,
                profile: .endurance,
                activityLabel: "run",
                category: .hard,
                confidence: .high,
                reasons: [],
                calculatedAt: date
            ),
            style: .countdown,
            dataState: .synced
        )
    }
}

// MARK: - Provider

/// Reads the cached snapshot the phone wrote and lays out the whole descent.
/// See `CountdownTimeline` for why a countdown needs more than one entry.
struct RecoveryTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecoveryEntry {
        .placeholder()
    }

    func getSnapshot(in context: Context, completion: @escaping (RecoveryEntry) -> Void) {
        // The gallery preview should look like a live countdown, not an empty
        // state, or nobody adds the complication.
        completion(context.isPreview ? .placeholder() : currentEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<RecoveryEntry>) -> Void) {
        let now = Date.now
        let state = snapshotForTimeline(at: now)
        let style = loadComplicationStyle()

        let entries = CountdownTimeline.entryDates(for: state.snapshot, now: now).map {
            RecoveryEntry(
                date: $0,
                snapshot: state.snapshot,
                style: style,
                dataState: state.dataState
            )
        }
        completion(Timeline(
            entries: entries.isEmpty ? [currentEntry(at: now)] : entries,
            policy: .after(CountdownTimeline.refreshDate(for: state.snapshot, now: now))
        ))
    }

    private func currentEntry(at date: Date) -> RecoveryEntry {
        let state = snapshotForTimeline(at: date)
        return RecoveryEntry(
            date: date,
            snapshot: state.snapshot,
            style: loadComplicationStyle(),
            dataState: state.dataState
        )
    }

    /// The snapshot plus whether one has ever been written here. The second half
    /// cannot be recovered from the first: an empty snapshot and a missing one
    /// decode to the same value, and only the presence of the key separates
    /// "the phone has never reached this wrist" from "the phone says you have
    /// not trained recently".
    private func snapshotForTimeline(at date: Date) -> (snapshot: RecoverySnapshot, dataState: ComplicationCopy.DataState) {
        let stored = RecoverySnapshotStore.loadIfPresent()
#if DEBUG
        // The capture app seeds the fixture in the App Group. The watch
        // simulator may keep a cached empty timeline until the next reload,
        // so the debug-only fallback keeps the production complication view
        // honest while making the screenshot deterministic.
        if stored?.hasSession != true,
           UserDefaults(suiteName: rechargeAppGroupID)?.bool(forKey: "rechargeScreenshotMode") == true {
            return (ScreenshotFixtures.snapshot(now: date), .synced)
        }
#endif
        if let stored { return (stored, .synced) }
        return (
            .empty,
            RecoverySnapshotStore.hasEverSynced() ? .unreadable : .neverSynced
        )
    }
}

/// Extensions cannot see the `@MainActor` settings object, so the style is read
/// straight out of the App Group with the same key it was written with.
func loadComplicationStyle() -> ComplicationStyle {
    let defaults = UserDefaults(suiteName: rechargeAppGroupID) ?? .standard
    return ComplicationStyle(rawValue: defaults.integer(forKey: SettingsKeys.complicationStyle)) ?? .countdown
}

// MARK: - Shared copy

/// The strings themselves live in `Shared/Utilities/ComplicationCopy.swift`, so
/// the test target can compile them. These are the entry-shaped call sites.
extension RecoveryEntry {
    /// "No snapshot has ever arrived" is a different state from "no workout in
    /// four days", and on the wrist it is by far the more likely one: the Watch
    /// has its own App Group container, only the Watch *app* can write into it,
    /// and a widget extension cannot hold a `WCSession`. Someone who installs
    /// Recharge and adds the complication before opening the Watch app is in
    /// this state, and used to be shown a bare `--`.
    /// Derived from whether anything has ever *arrived*, not from whether the
    /// snapshot has a session in it. Those are different questions, and asking
    /// the second one meant a user who synced fine but had not trained in four
    /// days was told to open Recharge and set it up — with nothing to set up,
    /// and no way to make the message go away short of doing a workout. The
    /// "no workout" answer is `noRecentWorkout`, and it already exists.
    var primaryText: String {
        ComplicationCopy.primary(
            phase: phase, style: style, remaining: remaining, readyAt: snapshot.readyAt,
            dataState: dataState
        )
    }

    var secondaryText: String {
        ComplicationCopy.secondary(
            phase: phase, style: style, remaining: remaining, readyAt: snapshot.readyAt,
            activityLabel: snapshot.activityLabel, dataState: dataState
        )
    }

    var inlineText: String {
        ComplicationCopy.inline(
            phase: phase, style: style, remaining: remaining, readyAt: snapshot.readyAt,
            dataState: dataState
        )
    }

    var rectangularTitleText: String {
        ComplicationCopy.rectangularTitle(
            phase: phase, style: style, remaining: remaining, readyAt: snapshot.readyAt,
            dataState: dataState
        )
    }
}

// MARK: - Families

struct RecoveryCircularView: View {
    let entry: RecoveryEntry

    var body: some View {
        // A gauge only makes sense while something is actually running down.
        if entry.phase == .ready || entry.phase == .noRecentWorkout {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: entry.symbolName)
                        .font(.system(size: 15, weight: .semibold))
                    Text(entry.primaryText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .widgetAccentable()
        } else {
            Gauge(value: min(max(entry.progress, 0), 1)) {
                Image(systemName: "hourglass")
            } currentValueLabel: {
                Text(entry.primaryText)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Theme.color(for: entry.phase))
        }
    }
}

struct RecoveryRectangularView: View {
    let entry: RecoveryEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.symbolName)
                .font(.title3)
                .foregroundStyle(Theme.color(for: entry.phase))
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.rectangularTitleText)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .monospacedDigit()
                Text(entry.secondaryText)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
    }
}

struct RecoveryInlineView: View {
    let entry: RecoveryEntry

    var body: some View {
        // Inline renders as one text run beside the system's own glyph slot.
        Label(entry.inlineText, systemImage: entry.symbolName)
    }
}

struct RecoveryCornerView: View {
    let entry: RecoveryEntry

    var body: some View {
        if entry.phase == .ready || entry.phase == .noRecentWorkout {
            Image(systemName: entry.symbolName)
                .font(.title2)
                .widgetLabel { Text(entry.primaryText) }
        } else {
            // The corner is the narrowest text region on a face and it carries
            // the longest strings we produce: `readyClock` puts a whole clock
            // here ("10:29 PM"), `countdown` puts "1h 20m". Without these it
            // truncates, so it scales down the way every sibling family does.
            Text(entry.primaryText)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .widgetLabel {
                    // The curved label around a corner slot is a gauge, which is
                    // exactly the right shape for a countdown.
                    Gauge(value: min(max(entry.progress, 0), 1)) {
                        Text("Recovery")
                    }
                    .tint(Theme.color(for: entry.phase))
                }
        }
    }
}

// MARK: - Entry view

struct RecoveryComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecoveryEntry

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(URL(string: "recharge://today"))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular: RecoveryCircularView(entry: entry)
        case .accessoryRectangular: RecoveryRectangularView(entry: entry)
        case .accessoryInline: RecoveryInlineView(entry: entry)
        case .accessoryCorner: RecoveryCornerView(entry: entry)
        default: RecoveryCircularView(entry: entry)
        }
    }
}

private extension RecoveryEntry {
    var symbolName: String {
        dataState == .synced ? Theme.symbol(for: phase) : "arrow.triangle.2.circlepath"
    }
}

// MARK: - Widget

struct RecoveryComplication: Widget {
    let kind = "RechargeRecovery"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecoveryTimelineProvider()) { entry in
            RecoveryComplicationView(entry: entry)
        }
        .configurationDisplayName("Recovery")
        .description("Time left before another hard session, and a clear Ready mark.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

@main
struct RechargeWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecoveryComplication()
    }
}
