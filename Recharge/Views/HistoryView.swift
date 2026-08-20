import SwiftUI

/// Every session Recharge has scored, newest first, and what each one cost.
///
/// **Every row carries a number.** It did not used to: a session that started no
/// countdown printed the word "None", and for anyone who walks or spins on their
/// easy days that was most of the list. A history whose job is to be the
/// evidence the app is paying attention cannot be a column of the word "None" —
/// it reads as an import that lost the numbers, and it made the app look like it
/// had ignored two thirds of the user's training.
///
/// The fix is in the model rather than in the copy. `recoveryCostHours` is
/// computed for every session, easy ones included, and it is a different
/// question from `hours`: what the session cost, rather than how long a
/// countdown should run. A walk costs something and starts nothing, and both
/// halves of that are now sayable.
///
/// Quiet sessions are still visually subordinate — lighter type, a muted glyph —
/// because the distinction is real and the list would otherwise flatten a
/// three-hour ride and a walk to the shops into the same row.
struct HistoryView: View {
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var engine: RecoveryEngine

    @State private var selected: RecoveryEstimate?

    private struct DayGroup: Identifiable {
        let key: String
        let date: Date
        let estimates: [RecoveryEstimate]
        /// The day's total cost, which is the figure the model itself works in:
        /// `RecoveryBaseline.typicalLoad` is built from daily totals precisely
        /// because adaptation is a property of how much someone trains rather
        /// than of how they slice it up.
        let totalCostHours: Double

        var id: String { key }
    }

    private var grouped: [DayGroup] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: engine.estimates) { estimate in
            DateHelpers.dayKey(for: estimate.sessionEnd, calendar: calendar)
        }
        return groups
            .map { key, estimates in
                let sorted = estimates.sorted { $0.sessionEnd > $1.sessionEnd }
                return DayGroup(
                    key: key,
                    date: sorted.first?.sessionEnd ?? .now,
                    estimates: sorted,
                    totalCostHours: sorted.reduce(0) { $0 + $1.recoveryCostHours }
                )
            }
            .sorted { $0.key > $1.key }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !engine.estimates.isEmpty {
                    list
                } else if isStillImporting {
                    importing
                } else {
                    empty
                }
            }
            .background(Theme.background)
            .navigationTitle("History")
            // Inline, as on Today and across the fleet: a large title draws its
            // own opaque bar over the page background as soon as the list
            // scrolls, and the tinted background is meant to run edge to edge.
            .navigationBarTitleDisplayMode(.inline)
            .tabBarClearance()
            .refreshable { await engine.refresh(force: true) }
            .sheet(item: $selected) { estimate in
                EstimateDetailView(capturedEstimate: estimate)
                    .environmentObject(store)
                    .environmentObject(engine)
            }
        }
    }

    /// The first import walks \(HealthKitService.importDays) days of workouts and
    /// runs a heart-rate query against each one, which takes long enough to see.
    /// Saying "no estimates yet" during it is a false statement about the user's
    /// own history at the one moment they are deciding whether the app works.
    private var isStillImporting: Bool {
        engine.isRefreshing || (engine.lastSuccessfulImport == nil && !engine.lastImportFailed)
    }

    private var importing: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Reading your history")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("Recharge is scoring the last \(HealthKitService.importDays) days of workouts from Apple Health.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(Theme.idle)
            Text("No estimates yet")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(engine.lastImportFailed
                 ? "Recharge couldn't read Apple Health. Grant access under Health › Sharing › Apps, then pull to refresh."
                 : "Nothing in the last \(HealthKitService.importDays) days of Apple Health to score. Finish a workout and it will appear here.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The list's own geometry. The pinned day headers have to mask the rows
    /// passing behind them, so the header background is inflated by exactly
    /// these two numbers and they cannot be typed twice.
    private static let horizontalMargin: CGFloat = 16
    private static let rowSpacing: CGFloat = 10

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Self.rowSpacing, pinnedViews: [.sectionHeaders]) {
                ForEach(grouped) { group in
                    Section {
                        ForEach(group.estimates, id: \.sessionID) { estimate in
                            Button { selected = estimate } label: {
                                HistoryRow(estimate: estimate)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        dayHeader(group)
                    }
                }
            }
            .padding(.horizontal, Self.horizontalMargin)
        }
    }

    private func dayHeader(_ group: DayGroup) -> some View {
        HStack {
            Text(dayHeading(group.date))
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            // The day's total, which is the number a training log is actually
            // about and the one the baseline is built from.
            if group.estimates.count > 1 {
                Text("\(CountdownFormat.hours(group.totalCostHours)) total")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        // A pinned header is drawn over the rows still scrolling behind it, so
        // its background has to cover more than the text: the negative padding
        // inflates it past the stack's 16pt side margins and over the 10pt gap
        // on each side of it. Sized to the text alone, the header let the
        // outgoing card show through in three strips — above it, beside it, and
        // below it — which on a dark screen reads as a second, broken row
        // wedged under the navigation bar.
        .background(
            Theme.background
                .padding(.horizontal, -Self.horizontalMargin)
                .padding(.vertical, -Self.rowSpacing)
        )
    }

    private func dayHeading(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMM")
        return formatter.string(from: date)
    }
}

// MARK: - Row

private struct HistoryRow: View {
    let estimate: RecoveryEstimate

    var body: some View {
        Card(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: Theme.symbol(
                    forActivityLabel: estimate.activityLabel,
                    profile: estimate.profile
                ))
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(estimate.producesCountdown ? Theme.recovering : Theme.idle)

                VStack(alignment: .leading, spacing: 3) {
                    Text(estimate.activityLabel.asSessionTitle)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    // An easy session's category is measured against the easy
                    // population reference, which makes a three-hour round of
                    // golf read "Very hard" on a row that also says it started
                    // no countdown. The category answers a question nobody asked
                    // of an active-recovery session; say what the row means.
                    Text("\(estimate.profile == .easy ? "Active recovery" : estimate.category.shortLabel) · \(timeLabel)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 3) {
                    // What the session cost, on every row without exception.
                    // Which is a different figure from the countdown it set: a
                    // walk costs a couple of hours and starts nothing, and the
                    // subtitle underneath is what keeps those two apart.
                    Text(CountdownFormat.hours(estimate.recoveryCostHours))
                        .font(.system(
                            .title3,
                            design: .rounded,
                            weight: estimate.producesCountdown ? .bold : .semibold
                        ))
                        .monospacedDigit()
                        .foregroundStyle(estimate.producesCountdown ? Theme.textPrimary : Theme.textSecondary)
                    Text(subtitle)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityValue)
            }
        }
    }

    /// What the figure above it means. Three states, and the distinction is the
    /// whole reason a cost and a countdown are separate numbers.
    private var subtitle: String {
        guard estimate.producesCountdown else {
            return estimate.profile == .easy ? "no countdown" : "under the threshold"
        }
        if estimate.isStacked {
            return "\(CountdownFormat.hours(estimate.totalHours)) countdown"
        }
        return "countdown"
    }

    private var accessibilityValue: String {
        let cost = CountdownFormat.hours(estimate.recoveryCostHours)
        guard estimate.producesCountdown else {
            return estimate.profile == .easy
                ? "Cost \(cost). Active recovery, no countdown."
                : "Cost \(cost). Below the threshold, no countdown."
        }
        return estimate.isStacked
            ? "Cost \(cost). Countdown ran \(CountdownFormat.hours(estimate.totalHours)) including carried recovery."
            : "Countdown \(cost)."
    }

    private var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: estimate.sessionEnd)
    }
}
