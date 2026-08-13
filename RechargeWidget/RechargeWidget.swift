import SwiftUI
import WidgetKit

// MARK: - Entry

struct RechargeWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: RecoverySnapshot
    let style: ComplicationStyle

    var phase: RecoveryPhase { snapshot.phase(at: date) }
    var remaining: TimeInterval { snapshot.remainingSeconds(at: date) }
    var progress: Double { snapshot.progress(at: date) }

    static func placeholder(date: Date = .now) -> RechargeWidgetEntry {
        RechargeWidgetEntry(
            date: date,
            snapshot: RecoverySnapshot(
                readyAt: date.addingTimeInterval(18 * 3600 + 40 * 60),
                sessionEnd: date.addingTimeInterval(-3 * 3600),
                hours: 21.7,
                windowLowHours: 18.4,
                windowHighHours: 24.9,
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

struct RechargeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RechargeWidgetEntry { .placeholder() }

    func getSnapshot(in context: Context, completion: @escaping (RechargeWidgetEntry) -> Void) {
        completion(context.isPreview ? .placeholder() : current(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<RechargeWidgetEntry>) -> Void) {
        let now = Date.now
        let snapshot = RecoverySnapshotStore.load()
        let style = loadWidgetComplicationStyle()
        let entries = CountdownTimeline.entryDates(for: snapshot, now: now).map {
            RechargeWidgetEntry(date: $0, snapshot: snapshot, style: style)
        }
        completion(Timeline(
            entries: entries.isEmpty ? [current(at: now)] : entries,
            policy: .after(CountdownTimeline.refreshDate(for: snapshot, now: now))
        ))
    }

    private func current(at date: Date) -> RechargeWidgetEntry {
        RechargeWidgetEntry(
            date: date,
            snapshot: RecoverySnapshotStore.load(),
            style: loadWidgetComplicationStyle()
        )
    }
}

/// Same App Group key the phone writes; the extension cannot see the
/// `@MainActor` settings object.
func loadWidgetComplicationStyle() -> ComplicationStyle {
    let defaults = UserDefaults(suiteName: rechargeAppGroupID) ?? .standard
    return ComplicationStyle(rawValue: defaults.integer(forKey: SettingsKeys.complicationStyle)) ?? .countdown
}

// MARK: - Views

private struct WidgetCopy {
    static func headline(_ entry: RechargeWidgetEntry) -> String {
        switch entry.phase {
        case .noRecentWorkout: "No workout"
        case .ready: "Ready"
        case .readySoon, .recovering:
            entry.style == .readyClock
                ? (entry.snapshot.readyAt.map(CountdownFormat.clock) ?? "Recovering")
                : CountdownFormat.remaining(entry.remaining)
        }
    }

    static func caption(_ entry: RechargeWidgetEntry) -> String {
        switch entry.phase {
        case .noRecentWorkout: "Finish a workout to start"
        case .ready: "Ready for another hard session"
        case .readySoon, .recovering:
            entry.snapshot.readyAt.map { "Ready \(CountdownFormat.readyAt($0, now: entry.date))" } ?? "Recovering"
        }
    }
}

struct RechargeSmallWidgetView: View {
    let entry: RechargeWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: Theme.symbol(for: entry.phase))
                    .font(.caption)
                    .foregroundStyle(Theme.color(for: entry.phase))
                Spacer()
                if entry.phase == .recovering || entry.phase == .readySoon {
                    CircularProgress(progress: entry.progress, phase: entry.phase)
                        .frame(width: 18, height: 18)
                }
            }
            Spacer()
            Text(WidgetCopy.headline(entry))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Theme.textPrimary)
            Text(WidgetCopy.caption(entry))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
    }
}

struct RechargeMediumWidgetView: View {
    let entry: RechargeWidgetEntry

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                CircularProgress(progress: entry.progress, phase: entry.phase, lineWidth: 8)
                switch entry.phase {
                case .ready:
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.ready)
                case .noRecentWorkout:
                    // `compactRemaining(0)` is the string "Ready", so falling
                    // through to the countdown path would print Ready inside an
                    // empty ring for a user who has never finished a workout.
                    Image(systemName: Theme.symbol(for: .noRecentWorkout))
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.idle)
                case .readySoon, .recovering:
                    Text(CountdownFormat.compactRemaining(entry.remaining))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .frame(width: 74, height: 74)

            VStack(alignment: .leading, spacing: 5) {
                Text(WidgetCopy.headline(entry))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.textPrimary)
                Text(WidgetCopy.caption(entry))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                // Not `hasSession`: past the staleness cutoff the headline reads
                // "No workout", and naming the old session contradicts it.
                if let category = entry.snapshot.category, entry.phase != .noRecentWorkout {
                    Text("\(category.shortLabel) · \(entry.snapshot.activityLabel)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct CircularProgress: View {
    let progress: Double
    let phase: RecoveryPhase
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.ringTrack, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(min(progress, 1), phase == .noRecentWorkout ? 0 : 0.01))
                .stroke(
                    Theme.gradient(for: phase),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

struct RechargeWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RechargeWidgetEntry

    var body: some View {
        content
            .containerBackground(Theme.background, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium: RechargeMediumWidgetView(entry: entry)
        default: RechargeSmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget

struct RechargeWidget: Widget {
    let kind = "RechargeRecoveryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RechargeWidgetProvider()) { entry in
            RechargeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Recovery")
        .description("Time left before another hard session, and a clear Ready mark.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct RechargeWidgetBundle: WidgetBundle {
    var body: some Widget {
        RechargeWidget()
    }
}
