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

    private var grouped: [(key: String, estimates: [RecoveryEstimate])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: engine.estimates) { estimate in
            DateHelpers.dayKey(for: estimate.sessionEnd, calendar: calendar)
        }
        return groups
            .map { (key: $0.key, estimates: $0.value.sorted { $0.sessionEnd > $1.sessionEnd }) }
            .sorted { $0.key > $1.key }
    }

    var body: some View {
        NavigationStack {
            Group {
                if engine.estimates.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .background(Theme.background)
            .navigationTitle("History")
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

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(Theme.idle)
            Text("No estimates yet")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("Finish a workout and Recharge will score it here.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10, pinnedViews: [.sectionHeaders]) {
                if !store.isPro { weeklyLoadTeaser }
                ForEach(grouped, id: \.key) { group in
                    Section {
                        ForEach(group.estimates, id: \.sessionID) { estimate in
                            Button { selected = estimate } label: {
                                HistoryRow(estimate: estimate)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text(dayHeading(group.estimates.first?.sessionEnd ?? .now))
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                        .background(Theme.background)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 72)
        }
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
                    Text("\(estimate.category.shortLabel) · \(timeLabel)")
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
                    Text(estimate.producesCountdown ? CountdownFormat.hours(estimate.hours) : "None")
                        .font(.system(
                            .title3,
                            design: .rounded,
                            weight: estimate.producesCountdown ? .bold : .semibold
                        ))
                        .monospacedDigit()
                        .foregroundStyle(estimate.producesCountdown ? Theme.textPrimary : Theme.textSecondary)
                        .accessibilityLabel(estimate.producesCountdown
                                            ? CountdownFormat.hours(estimate.hours)
                                            : "No countdown")
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
                        Text("Pro lets you re-classify a session and tell Recharge when an estimate was off.")
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
