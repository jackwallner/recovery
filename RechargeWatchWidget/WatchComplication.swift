import SwiftUI
import WidgetKit

// MARK: - Entry

struct RecoveryEntry: TimelineEntry {
    let date: Date
    let snapshot: RecoverySnapshot
    let style: ComplicationStyle

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
            style: .countdown
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
        let snapshot = RecoverySnapshotStore.load()
        let style = loadComplicationStyle()

        let entries = CountdownTimeline.entryDates(for: snapshot, now: now).map {
            RecoveryEntry(date: $0, snapshot: snapshot, style: style)
        }
        completion(Timeline(
            entries: entries.isEmpty ? [currentEntry(at: now)] : entries,
            policy: .after(CountdownTimeline.refreshDate(for: snapshot, now: now))
        ))
    }

    private func currentEntry(at date: Date) -> RecoveryEntry {
        RecoveryEntry(
            date: date,
            snapshot: RecoverySnapshotStore.load(),
            style: loadComplicationStyle()
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

/// One place decides what each style says, so all four families stay in step.
enum ComplicationCopy {
    /// The big value in the middle of a circular or corner slot.
    static func primary(_ entry: RecoveryEntry) -> String {
        switch entry.phase {
        case .noRecentWorkout:
            return "--"
        case .ready:
            return entry.style == .state ? "READY" : "Ready"
        case .readySoon, .recovering:
            switch entry.style {
            case .countdown:
                return CountdownFormat.compactRemaining(entry.remaining)
            case .readyClock:
                return entry.snapshot.readyAt.map(CountdownFormat.clock) ?? "--"
            case .state:
                return entry.phase == .readySoon ? "SOON" : "REC"
            }
        }
    }

    /// The line under it on rectangular, and the widget label on corner/inline.
    static func secondary(_ entry: RecoveryEntry) -> String {
        switch entry.phase {
        case .noRecentWorkout:
            return "No workout"
        case .ready:
            // Not "Ready to train": on a glance surface with no room for the
            // qualifier, that reads as clearance to train rather than as an
            // estimate about training load, which is the only thing the model
            // knows. Every other surface says "hard session"; so does this one.
            return entry.snapshot.activityLabel.isEmpty
                ? "Ready for a hard session"
                : "After your \(entry.snapshot.activityLabel)"
        case .readySoon, .recovering:
            switch entry.style {
            case .countdown:
                return entry.snapshot.readyAt.map { "Ready \(CountdownFormat.clock($0))" } ?? "Recovering"
            case .readyClock:
                return CountdownFormat.compactRemaining(entry.remaining) + " left"
            case .state:
                return CountdownFormat.compactRemaining(entry.remaining) + " left"
            }
        }
    }

    /// Inline slots are a handful of characters wide and get no ring, so they
    /// carry the shortest complete sentence available.
    static func inline(_ entry: RecoveryEntry) -> String {
        switch entry.phase {
        case .noRecentWorkout: "No workout"
        // The inline slot has room for one word, and "Ready" is the token every
        // other surface already uses for an expired estimate.
        case .ready: "Ready"
        case .readySoon, .recovering:
            switch entry.style {
            case .countdown: "\(CountdownFormat.compactRemaining(entry.remaining)) to ready"
            case .readyClock: entry.snapshot.readyAt.map { "Ready \(CountdownFormat.clock($0))" } ?? "Recovering"
            case .state: entry.phase == .readySoon ? "Ready soon" : "Recovering"
            }
        }
    }

    static func rectangularTitle(_ entry: RecoveryEntry) -> String {
        switch entry.phase {
        case .noRecentWorkout: "Recharge"
        case .ready: "Ready"
        case .readySoon, .recovering:
            switch entry.style {
            case .countdown: "Recover \(CountdownFormat.compactRemaining(entry.remaining))"
            case .readyClock: entry.snapshot.readyAt.map { "Ready \(CountdownFormat.clock($0))" } ?? "Recovering"
            case .state: entry.phase == .readySoon ? "READY SOON" : "RECOVERING"
            }
        }
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
                    Image(systemName: Theme.symbol(for: entry.phase))
                        .font(.system(size: 15, weight: .semibold))
                    Text(ComplicationCopy.primary(entry))
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
                Text(ComplicationCopy.primary(entry))
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
            Image(systemName: Theme.symbol(for: entry.phase))
                .font(.title3)
                .foregroundStyle(Theme.color(for: entry.phase))
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 1) {
                Text(ComplicationCopy.rectangularTitle(entry))
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .monospacedDigit()
                Text(ComplicationCopy.secondary(entry))
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
        Label(ComplicationCopy.inline(entry), systemImage: Theme.symbol(for: entry.phase))
    }
}

struct RecoveryCornerView: View {
    let entry: RecoveryEntry

    var body: some View {
        if entry.phase == .ready || entry.phase == .noRecentWorkout {
            Image(systemName: Theme.symbol(for: entry.phase))
                .font(.title2)
                .widgetLabel { Text(ComplicationCopy.primary(entry)) }
        } else {
            Text(ComplicationCopy.primary(entry))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
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
