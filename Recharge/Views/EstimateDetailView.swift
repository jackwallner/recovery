import SwiftUI

/// Everything about one session, on a sheet a tap away from both places a
/// session appears: the ring on Today, and a row in History.
///
/// This is where all of Today's explanatory furniture went. The screen showing
/// the number is now only the number, which means the explanation had to have
/// somewhere to be — and one sheet reached from either surface is better than
/// the cards it replaces, because it can be as long as it needs to be and
/// nobody has to scroll past it to see the countdown.
struct EstimateDetailView: View {
    /// What the row (or the ring) was showing when it was tapped. Only ever a
    /// fallback: the sheet renders the engine's live copy so an override
    /// recalculates the header, the window, the reasons, and the numbers in
    /// place. Without that, changing Endurance to Strength moved the segmented
    /// control and left every figure on the sheet describing the estimate the
    /// app had already replaced.
    let capturedEstimate: RecoveryEstimate

    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var engine: RecoveryEngine
    @Environment(\.dismiss) private var dismiss

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
                    if store.isPro {
                        profileOverride
                        loadCard
                    } else {
                        proTeaser
                    }
                    disclaimer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle(estimate.activityLabel.asSessionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                // The cost, always. A session that started no countdown still
                // cost something, and the word "None" here was the app refusing
                // to answer the question the sheet was opened to answer.
                Text(CountdownFormat.hours(estimate.recoveryCostHours))
                    .font(Theme.bigNumber(38))
                    .foregroundStyle(Theme.textPrimary)
                Text(costCaption)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

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

    private var costCaption: String {
        guard estimate.producesCountdown else {
            return estimate.profile == .easy
                ? "Active recovery. Counted toward your training load, and it never starts or extends a countdown."
                : "Counted toward your training load. Not enough on its own to start a countdown."
        }
        let window = CountdownFormat.window(low: estimate.windowLowHours, high: estimate.windowHighHours)
        return "Countdown ran \(window), ready \(CountdownFormat.readyAt(estimate.readyAt, now: estimate.sessionEnd))."
    }

    // MARK: - Why

    private var reasons: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Why")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                ForEach(Array(estimate.reasons.enumerated()), id: \.offset) { _, reason in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Theme.textTertiary)
                            .frame(width: 4, height: 4)
                            .padding(.top, 7)
                        Text(reason)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: - Numbers

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

    // MARK: - Training load (Pro)

    private var loadCard: some View {
        let balance = engine.loadBalance()
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Training load")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 20) {
                    loadFigure("This week", balance.acute)
                    loadFigure("4-week average", balance.chronic)
                }
                Text("Load is a proxy built from your own sessions, not a measurement.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func loadFigure(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Int(value.rounded()))")
                .font(Theme.bigNumber(26))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Session type (Pro)

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
        Button {
            dismiss()
            NotificationCenter.default.post(name: .rechargeUpgradeRequested, object: nil)
        } label: {
            Card {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Correct this session")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Recharge+ lets you re-classify a session, see your weekly load, and tell Recharge when an estimate was off.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    ProBadge()
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var disclaimer: some View {
        Text("Recharge gives a cardiovascular training estimate from your Apple Health data. It is not medical advice and does not diagnose, treat, or prevent any condition. Talk with a qualified health professional before making medical decisions.")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }
}
