import SwiftUI

/// The countdown, the ready time, the confidence, and the "why" — in that order.
/// Everything else on this screen is subordinate to the number in the ring.
struct TodayView: View {
    @EnvironmentObject private var settings: RechargeSettings
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var engine: RecoveryEngine

    @State private var now = Date.now
    @State private var showPaywall = false
    @State private var showEffortSheet = false
    @State private var showFeedbackSheet = false

    /// The ring is a fixed 236pt frame with the largest text in the app inside
    /// it. At an accessibility content size that text no longer fits, so the
    /// ring grows with it rather than clipping the one number the screen exists
    /// to show.
    @Environment(\.dynamicTypeSize) private var typeSize

    private var ringSize: CGFloat { typeSize.isAccessibilitySize ? 300 : 236 }

    /// One-minute tick. The countdown is in hours, so anything faster is wasted
    /// work; a minute keeps the "1h 20m" tail honest.
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var estimate: RecoveryEstimate? { engine.current }

    private var phase: RecoveryPhase {
        RecoveryResolver.phase(in: engine.estimates, now: now)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    if let estimate, estimate.producesCountdown || phase != .noRecentWorkout {
                        whyCard(estimate)
                    }
                    if engine.awaitingEffort != nil {
                        effortCard
                    }
                    contextCard
                    loadCard
                    disclaimer
                }
                .padding(.horizontal, 16)
                // Clears the floating tab bar; without it the disclaimer, which
                // has to stay legible for App Review 1.4.1, sits under the blur.
                .padding(.bottom, 72)
            }
            .background(Theme.background)
            .navigationTitle("Recharge")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await engine.refresh(force: true) }
            .onReceive(ticker) { now = $0 }
            .onAppear { now = .now }
            .task {
                if engine.awaitingFeedback != nil { showFeedbackSheet = true }
            }
            // A countdown usually expires while the app is open on the minute
            // tick, so `.task` alone would miss the moment it actually matters.
            .onChange(of: engine.awaitingFeedback?.sessionID) { _, sessionID in
                if sessionID != nil { showFeedbackSheet = true }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: "today")
                    .environmentObject(store)
            }
            .sheet(isPresented: $showEffortSheet) {
                if let workout = engine.awaitingEffort {
                    EffortPromptSheet(
                        activityLabel: workout.activityLabel,
                        durationMinutes: workout.durationMinutes
                    ) { effort in
                        engine.recordEffort(effort, forSessionID: workout.healthKitUUID)
                    }
                }
            }
            .sheet(isPresented: $showFeedbackSheet) {
                if let pending = engine.awaitingFeedback {
                    ReadinessFeedbackSheet(estimate: pending) { feedback in
                        if let feedback {
                            engine.recordFeedback(feedback, forSessionID: pending.sessionID)
                        } else {
                            engine.dismissFeedback(forSessionID: pending.sessionID)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                CountdownRing(
                    progress: progress,
                    phase: phase,
                    lineWidth: 20
                )
                .frame(width: ringSize, height: ringSize)

                VStack(spacing: 4) {
                    if phase == .noRecentWorkout {
                        Image(systemName: Theme.symbol(for: phase))
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.idle)
                        Text("No workout yet")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    } else if phase == .ready {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(Theme.ready)
                        Text("Ready")
                            .font(Theme.bigNumber(38))
                            .foregroundStyle(Theme.textPrimary)
                    } else {
                        Text(CountdownFormat.remaining(remaining))
                            .font(Theme.bigNumber(50))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .foregroundStyle(Theme.textPrimary)
                        Text("left")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(.top, 12)

            VStack(spacing: 6) {
                Text(readyLine)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                if let estimate, estimate.producesCountdown {
                    // Past tense once it has expired: "Window 18 to 25h" beside a
                    // green Ready ring reads as a live figure it no longer is.
                    Text(phase == .ready
                         ? "Estimate was \(CountdownFormat.window(low: estimate.windowLowHours, high: estimate.windowHighHours))"
                         : "Window \(CountdownFormat.window(low: estimate.windowLowHours, high: estimate.windowHighHours))")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }

                if let estimate {
                    ConfidencePips(confidence: estimate.confidence)
                        .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var progress: Double {
        guard let estimate, estimate.producesCountdown else { return phase == .noRecentWorkout ? 0 : 1 }
        let total = estimate.hours * 3600
        guard total > 0 else { return 1 }
        return min(max(1 - estimate.remainingSeconds(at: now) / total, 0), 1)
    }

    private var remaining: TimeInterval {
        estimate?.remainingSeconds(at: now) ?? 0
    }

    private var readyLine: String {
        switch phase {
        case .noRecentWorkout:
            return "Finish a workout and your estimate appears here."
        case .ready:
            return "Ready for another hard session."
        case .readySoon, .recovering:
            guard let estimate else { return CountdownFormat.phaseDetail(phase) }
            // A low-confidence estimate should not print a minute-precise clock
            // time it cannot support.
            let time = estimate.confidence <= .low
                ? CountdownFormat.readySoftly(estimate.readyAt, now: now)
                : CountdownFormat.readyAt(estimate.readyAt, now: now)
            return "Ready \(time)"
        }
    }

    private var accessibilitySummary: String {
        switch phase {
        case .noRecentWorkout: "No recent workout."
        case .ready: "Ready for another hard session."
        default: "\(CountdownFormat.remaining(remaining)) left. \(readyLine)."
        }
    }

    // MARK: - Why

    private func whyCard(_ estimate: RecoveryEstimate) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Why")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    ProfileChip(
                        profile: estimate.profile,
                        category: estimate.category,
                        activityLabel: estimate.activityLabel
                    )
                }
                ForEach(Array(estimate.reasons.enumerated()), id: \.offset) { _, reason in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Theme.textTertiary)
                            .frame(width: 4, height: 4)
                            .padding(.top, 7)
                        Text(reason)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Text("Set by your \(estimate.activityLabel) \(relativeSessionTime(estimate)).")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 2)
            }
        }
    }

    private func relativeSessionTime(_ estimate: RecoveryEstimate) -> String {
        let elapsed = now.timeIntervalSince(estimate.sessionEnd)
        if elapsed < 3600 { return "just now" }
        return "\(CountdownFormat.remaining(elapsed)) ago"
    }

    // MARK: - Effort prompt

    private var effortCard: some View {
        Button {
            showEffortSheet = true
        } label: {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.recovering)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("How hard was that session?")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Heart rate was unreliable, so your rating decides the estimate.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Context (Pro)

    private var contextCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Body signals")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if !store.isPro { ProBadge() }
                }

                if store.isPro {
                    Text(settings.useContextSignals
                         ? "Sleep, resting heart rate, and HRV are folded into your estimate."
                         : "Body signals are turned off in Settings, so your estimate uses workout load only.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Recharge Pro folds your sleep, resting heart rate, and HRV into the estimate, and adapts the bands to your own history.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    Button {
                        showPaywall = true
                    } label: {
                        Text(store.shortConversionCTALabel)
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.pro, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Load balance (Pro)

    @ViewBuilder
    private var loadCard: some View {
        if store.isPro {
            let balance = engine.loadBalance()
            Card {
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

    // MARK: - Disclaimer

    private var disclaimer: some View {
        Text("Recharge gives a cardiovascular training estimate from your Apple Health data. It is not medical advice and does not diagnose, treat, or prevent any condition.")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }
}

// MARK: - Store CTA helper

private extension StoreService {
    var shortConversionCTALabel: String {
        RechargeConversionCopy.shortCTALabel(eligibleForTrial: canPitchFreeTrial)
    }
}
