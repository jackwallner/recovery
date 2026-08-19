import SwiftUI

/// Every estimate the app has produced, newest first, plus what it said and why.
///
/// The list itself is free — a user who cannot see what the app told them
/// yesterday has no reason to trust it today. The per-session detail (accuracy
/// feedback, profile override, the load figure) is Pro.
struct HistoryView: View {
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var engine: RecoveryEngine

    @State private var showPaywall = false
    @State private var selected: RecoveryEstimate?

    /// Whether the sessions that produced no countdown are expanded.
    ///
    /// Collapsed by default, and that is the whole point. Somebody who walks
    /// three times a day and rides easy in between had a History tab that was
    /// twenty identical rows of "Walk · Active recovery · None" with the two
    /// estimates that actually matter buried somewhere inside it. The list is
    /// supposed to be the evidence that the app is paying attention; a wall of
    /// "None" is the opposite.
    @State private var showsQuietSessions = false

    private struct DayGroup: Identifiable {
        let key: String
        let date: Date
        /// Sessions that started a countdown. These are the list.
        let scored: [RecoveryEstimate]
        /// Everything else — walks, easy spins, anything under the threshold.
        let quiet: [RecoveryEstimate]

        var id: String { key }
        var isEmpty: Bool { scored.isEmpty && quiet.isEmpty }
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
                    scored: sorted.filter(\.producesCountdown),
                    quiet: sorted.filter { !$0.producesCountdown }
                )
            }
            // A day with nothing but walks still gets a header and a one-line
            // summary, because "you walked four times and none of it counted" is
            // information. A day with nothing at all does not exist.
            .filter { !$0.isEmpty }
            .sorted { $0.key > $1.key }
    }

    private var quietSessionCount: Int {
        engine.estimates.count { !$0.producesCountdown }
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
            .refreshable { await engine.refresh(force: true) }
            .sheet(item: $selected) { estimate in
                EstimateDetailView(capturedEstimate: estimate)
                    .environmentObject(store)
                    .environmentObject(engine)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: "history")
                    .environmentObject(store)
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
                if !store.isPro { weeklyLoadTeaser }
                ForEach(grouped) { group in
                    Section {
                        ForEach(group.scored, id: \.sessionID) { estimate in
                            Button { selected = estimate } label: {
                                HistoryRow(estimate: estimate)
                            }
                            .buttonStyle(.plain)
                        }
                        if !group.quiet.isEmpty {
                            if showsQuietSessions {
                                ForEach(group.quiet, id: \.sessionID) { estimate in
                                    Button { selected = estimate } label: {
                                        HistoryRow(estimate: estimate)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                quietSummary(group)
                            }
                        }
                    } header: {
                        HStack {
                            Text(dayHeading(group.date))
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                        // A pinned header is drawn over the rows still
                        // scrolling behind it, so its background has to cover
                        // more than the text: the negative padding inflates it
                        // past the stack's 16pt side margins and over the 10pt
                        // gap on each side of it. Sized to the text alone, the
                        // header let the outgoing card show through in three
                        // strips — above it, beside it, and below it — which on
                        // a dark screen reads as a second, broken row wedged
                        // under the navigation bar.
                        .background(
                            Theme.background
                                .padding(.horizontal, -Self.horizontalMargin)
                                .padding(.vertical, -Self.rowSpacing)
                        )
                    }
                }
                if quietSessionCount > 0 { quietToggle }
            }
            .padding(.horizontal, Self.horizontalMargin)
        }
    }

    /// One line in place of a day's worth of walks.
    private func quietSummary(_ group: DayGroup) -> some View {
        Button { showsQuietSessions = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                Text(quietSummaryText(group))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func quietSummaryText(_ group: DayGroup) -> String {
        let count = group.quiet.count
        let noun = count == 1 ? "session" : "sessions"
        return group.scored.isEmpty
            ? "\(count) light \(noun), no countdown"
            : "and \(count) light \(noun)"
    }

    private var quietToggle: some View {
        Button { showsQuietSessions.toggle() } label: {
            Text(showsQuietSessions
                 ? "Hide light sessions"
                 : "Show \(quietSessionCount) light \(quietSessionCount == 1 ? "session" : "sessions")")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var weeklyLoadTeaser: some View {
        Button { showPaywall = true } label: {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: "chart.bar.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.pro)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Weekly load and accuracy")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("See how your week compares to your own four-week average, and tell Recharge when it got an estimate wrong.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    ProBadge()
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
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
                    Text(estimate.activityLabel.capitalized)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    // An easy session's category is measured against the easy
                    // population reference, which makes a three-hour round of
                    // golf read "Very hard" on the row that also says its
                    // countdown is "None". The category answers a question
                    // nobody asked of an active-recovery session; say what the
                    // row actually means instead.
                    Text("\(estimate.profile == .easy ? "Active recovery" : estimate.category.shortLabel) · \(timeLabel)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    // A bare dash was a deliberate classification that nobody
                    // read as one. A history full of them looks like an import
                    // that lost the numbers, and an easy session has no number
                    // to lose: `easy` produces no window on either tier, so
                    // there is no day-one figure being withheld here. Say so in
                    // a word instead of punctuating it.
                    // The countdown this session actually set, which is the
                    // stacked total. Showing its own cost instead would put a
                    // different number in the list from the one the hero showed
                    // on the day.
                    Text(estimate.producesCountdown ? CountdownFormat.hours(estimate.totalHours) : "None")
                        .font(.system(
                            .title3,
                            design: .rounded,
                            weight: estimate.producesCountdown ? .bold : .semibold
                        ))
                        .monospacedDigit()
                        .foregroundStyle(estimate.producesCountdown ? Theme.textPrimary : Theme.textSecondary)
                        .accessibilityLabel(estimate.producesCountdown
                                            ? CountdownFormat.hours(estimate.totalHours)
                                            : "No countdown")
                    // And where that total came from, so a 30h row under a
                    // 40-minute session is legible rather than suspicious.
                    if estimate.isStacked {
                        Text("incl. \(CountdownFormat.hours(estimate.carriedHours)) carried")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    ConfidencePips(confidence: estimate.confidence, showsLabel: false)
                }
            }
        }
    }

    private var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: estimate.sessionEnd)
    }
}

// MARK: - Detail

private struct EstimateDetailView: View {
    /// What the row was showing when it was tapped. Only ever a fallback: the
    /// sheet renders the engine's live copy so an override recalculates the
    /// header, the window, the reasons, and the numbers in place. Without that,
    /// changing Endurance to Strength moved the segmented control and left every
    /// figure on the sheet describing the estimate the app had already replaced.
    let capturedEstimate: RecoveryEstimate

    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var engine: RecoveryEngine
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    private var estimate: RecoveryEstimate {
        engine.estimates.first { $0.sessionID == capturedEstimate.sessionID } ?? capturedEstimate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    reasons
                    numbers
                    if store.isPro { profileOverride } else { proTeaser }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle(estimate.activityLabel.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: "history_detail")
                    .environmentObject(store)
            }
        }
    }

    private var header: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(estimate.producesCountdown
                     ? CountdownFormat.window(low: estimate.windowLowHours, high: estimate.windowHighHours)
                     : "No countdown")
                    .font(Theme.bigNumber(34))
                    .foregroundStyle(Theme.textPrimary)
                if estimate.producesCountdown {
                    Text("Ready \(CountdownFormat.readyAt(estimate.readyAt, now: estimate.sessionEnd))")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                // The arithmetic behind a stacked window, stated where there is
                // room for it. Recovery time is cumulative, so this session
                // landed on a countdown that was still running.
                if estimate.isStacked {
                    Text(CountdownFormat.stackedNote(
                        sessionHours: estimate.hours,
                        carriedHours: estimate.carriedHours
                    ))
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    ProfileChip(
                        profile: estimate.profile,
                        category: estimate.category,
                        activityLabel: estimate.activityLabel
                    )
                    ConfidencePips(confidence: estimate.confidence)
                }
            }
        }
    }

    private var reasons: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Why")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                ForEach(Array(estimate.reasons.enumerated()), id: \.offset) { _, reason in
                    Text("• \(reason)")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var numbers: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Numbers")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                detailRow("Session load", String(format: "%.0f", estimate.load.value))
                // The comparison a standard estimate makes is against a fixed
                // population reference, not against the person, and labelling it
                // "your usual" would be the one claim the free tier is not
                // entitled to make.
                detailRow(
                    estimate.tier == .standard ? "Compared to a typical session" : "Compared to your usual",
                    String(format: "%.2f×", estimate.relativeLoad)
                )
                detailRow("Load from", estimate.load.source.label)
                if estimate.load.source == .heartRate {
                    detailRow("Heart-rate coverage", "\(Int((estimate.load.heartRateCoverage * 100).rounded()))%")
                }
                detailRow("Estimate", estimate.tier.label)
                if estimate.tier == .personalized, estimate.personalFactor != 1 {
                    detailRow(
                        "Your adjustment",
                        String(format: "%+.0f%%", (estimate.personalFactor - 1) * 100)
                    )
                }
                detailRow("Model version", "v\(estimate.modelVersion)")
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var profileOverride: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Session type")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Recharge scored this as \(estimate.profile.label.lowercased()). Change it if that is wrong for this session.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Picker("Session type", selection: Binding(
                    get: { estimate.profile },
                    set: { engine.overrideProfile($0, forSessionID: capturedEstimate.sessionID) }
                )) {
                    ForEach(WorkoutProfile.allCases, id: \.self) { profile in
                        Text(profile.label).tag(profile)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var proTeaser: some View {
        Button { showPaywall = true } label: {
            Card {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Correct this session")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Recharge+ lets you re-classify a session and tell Recharge when an estimate was off.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    ProBadge()
                }
            }
        }
        .buttonStyle(.plain)
    }
}
