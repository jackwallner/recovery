import SwiftUI

/// The countdown, the ready time, the confidence, and the "why" — in that order.
/// Everything else on this screen is subordinate to the number in the ring.
struct TodayView: View {
    /// Reported upwards so `RootView` never raises a review ask or a trial pitch
    /// over a question this screen is already asking. SwiftUI drops the second
    /// present, and a review prompt that never appeared has still spent its one
    /// chance.
    @Binding var isPresentingSheet: Bool

    @EnvironmentObject private var settings: RechargeSettings
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var engine: RecoveryEngine

    @State private var now = Date.now
    @State private var showPaywall = false
    @State private var showEffortSheet = false

    /// The estimate the readiness question is about, **captured** rather than
    /// read live from the engine.
    ///
    /// It used to be `.sheet(isPresented:)` with the body reading
    /// `engine.awaitingFeedback` inside. Answering calls
    /// `engine.recordFeedback`, which sets `awaitingFeedback` to nil, which
    /// re-evaluated the sheet's body to an empty `if let` *before* the dismiss
    /// landed — so tapping any of the three answers left a blank sheet sitting
    /// there. That is the "blocked off and doesn't do anything" report: the
    /// answer was recorded every time, and then the UI ate it.
    @State private var feedbackTarget: RecoveryEstimate?

    /// Set once Today has been on screen long enough for the onboarding
    /// transition to finish. `RootView` cross-fades onboarding out over a
    /// quarter of a second, and a sheet raised inside that window fights the
    /// transition and lands half-drawn, which is the glitch on first launch.
    @State private var isSettled = false

    /// The ring is a fixed 236pt frame with the largest text in the app inside
    /// it. At an accessibility content size that text no longer fits, so the
    /// ring grows with it rather than clipping the one number the screen exists
    /// to show.
    @Environment(\.dynamicTypeSize) private var typeSize

    private var ringSize: CGFloat { typeSize.isAccessibilitySize ? 300 : 236 }

    /// One-minute tick. The countdown is in hours, so anything faster is wasted
    /// work; a minute keeps the "1h 20m" tail honest.
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var phase: RecoveryPhase {
        RecoveryResolver.phase(in: engine.estimates, now: now)
    }

    /// The estimate this screen may narrate. Nil once the last session is old
    /// enough to have driven the phase to `noRecentWorkout`, so the window,
    /// confidence, and Why card cannot contradict the hero.
    private var explained: RecoveryEstimate? {
        RecoveryResolver.explanation(in: engine.estimates, now: now)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    if settings.hasDeferredHealthAccess {
                        healthAccessCard
                    }
                    // Above the Why card on purpose. "Why 18h" is only worth
                    // reading once you know whether 18h is a lot; the comparison
                    // is the frame and the explanation is the detail.
                    if !engine.restPattern.isEmpty {
                        RestPatternCard(
                            rows: engine.restPattern,
                            isPro: store.isPro,
                            onUpgrade: { showPaywall = true }
                        )
                    }
                    if let explained {
                        whyCard(explained)
                    }
                    if engine.awaitingEffort != nil {
                        effortCard
                    }
                    contextCard
                    loadCard
                    freshness
                    disclaimer
                }
                .padding(.horizontal, 16)
            }
            .tabBarClearance()
            .background(Theme.background)
            .navigationTitle("Recharge")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await engine.refresh(force: true) }
            .onReceive(ticker) { date in
                now = date
                engine.handleClockTick(now: date)
            }
            .onAppear { now = .now }
            .task {
                // Let the onboarding cross-fade finish before anything is
                // presented over it.
                try? await Task.sleep(for: .milliseconds(400))
                isSettled = true
                presentFeedbackIfNeeded()
            }
            // A countdown usually expires while the app is open on the minute
            // tick, so `.task` alone would miss the moment it actually matters.
            .onChange(of: engine.awaitingFeedback?.sessionID) { _, _ in
                presentFeedbackIfNeeded()
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
                        if let effort {
                            engine.recordEffort(effort, forSessionID: workout.healthKitUUID)
                        } else {
                            engine.declineEffort(forSessionID: workout.healthKitUUID)
                        }
                    }
                }
            }
            // `item:` rather than `isPresented:`, so the sheet renders the
            // estimate it was opened with instead of whatever the engine is
            // currently holding. Answering clears `engine.awaitingFeedback`, and
            // under the old wiring that emptied the sheet's body mid-tap.
            .sheet(item: $feedbackTarget) { pending in
                ReadinessFeedbackSheet(estimate: pending) { feedback in
                    if let feedback {
                        engine.recordFeedback(feedback, forSessionID: pending.sessionID)
                    } else {
                        engine.dismissFeedback(forSessionID: pending.sessionID)
                    }
                    feedbackTarget = nil
                }
            }
            .onChange(of: showPaywall) { _, _ in publishSheetState() }
            .onChange(of: showEffortSheet) { _, _ in publishSheetState() }
            .onChange(of: feedbackTarget?.sessionID) { _, _ in publishSheetState() }
        }
    }

    /// Raises the readiness question, once the screen has settled and only for
    /// something the engine is actually waiting on.
    private func presentFeedbackIfNeeded() {
        guard isSettled, feedbackTarget == nil, let pending = engine.awaitingFeedback else { return }
        feedbackTarget = pending
    }

    private func publishSheetState() {
        isPresentingSheet = showPaywall || showEffortSheet || feedbackTarget != nil
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

                if let explained, explained.producesCountdown {
                    // Past tense once it has expired: "Window 18 to 25h" beside a
                    // green Ring reads as a live figure it no longer is.
                    Text(phase == .ready
                         ? "Estimate was \(CountdownFormat.window(low: explained.windowLowHours, high: explained.windowHighHours))"
                         : "Window \(CountdownFormat.window(low: explained.windowLowHours, high: explained.windowHighHours))")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)

                    // A stacked countdown is longer than the session on screen
                    // appears to justify, and without saying why that reads as
                    // the app having got it wrong.
                    if explained.isStacked {
                        Text(CountdownFormat.stackedNote(
                            sessionHours: explained.hours,
                            carriedHours: explained.carriedHours
                        ))
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let explained {
                    ConfidencePips(confidence: explained.confidence)
                        .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var progress: Double {
        // A stale estimate is not explained, so it must not paint a full ring
        // beside the "no workout yet" hero either.
        guard let explained, explained.producesCountdown else { return phase == .noRecentWorkout ? 0 : 1 }
        let total = explained.totalHours * 3600
        guard total > 0 else { return 1 }
        return min(max(1 - explained.remainingSeconds(at: now) / total, 0), 1)
    }

    private var remaining: TimeInterval {
        explained?.remainingSeconds(at: now) ?? 0
    }

    private var readyLine: String {
        switch phase {
        case .noRecentWorkout:
            return "Finish a workout and your estimate appears here."
        case .ready:
            // A session that never started a countdown lands here too, because
            // "no countdown running" and "the countdown finished" are the same
            // phase. They are not the same sentence: "Ready for another hard
            // session" an hour after a walk reads as the end of a window that
            // never began, which is the single most confusing thing this screen
            // can say. Name what actually happened instead.
            if let explained, !explained.producesCountdown {
                return "Your \(explained.activityLabel) \(relativeSessionTime(explained)) didn't start a countdown."
            }
            return "Ready for another hard session."
        case .readySoon, .recovering:
            guard let explained else { return CountdownFormat.phaseDetail(phase) }
            // A low-confidence estimate should not print a minute-precise clock
            // time it cannot support.
            let time = explained.confidence <= .low
                ? CountdownFormat.readySoftly(explained.readyAt, now: now)
                : CountdownFormat.readyAt(explained.readyAt, now: now)
            return "Ready \(time)"
        }
    }

    private var accessibilitySummary: String {
        switch phase {
        case .noRecentWorkout: "No recent workout."
        case .ready: readyLine
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
                        // Not "your rating decides the estimate", which is what
                        // this said and is not what the model does: strength and
                        // mixed sessions take the *highest* of heart rate,
                        // effort, energy and the type-typical guess, so an
                        // honest low rating can lose to a signal that read
                        // harder. Promising the answer is decisive and then
                        // moving the number by nothing is a worse outcome than
                        // never asking.
                        Text("Heart rate was patchy here. Your rating counts whenever it reads harder than the sensors did.")
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

    private var healthAccessCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Connect Apple Health", systemImage: "heart.text.square.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Recharge needs workout access before it can start a countdown. You can connect now, or manage access later in the Health app under Sharing, then Apps.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Button("Request access") {
                    Task { await requestHealthAccess() }
                }
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.recovering, in: Capsule())
                .foregroundStyle(.white)
                .buttonStyle(.plain)
            }
        }
    }

    private func requestHealthAccess() async {
        do {
            try await HealthKitService.shared.requestAuthorization()
            settings.hasDeferredHealthAccess = false
            await engine.refresh(force: true)
        } catch {
            settings.hasDeferredHealthAccess = true
        }
    }

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
                    Text("Recharge+ folds your sleep, resting heart rate, and HRV into the estimate within a bounded range.")
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

    // MARK: - Freshness

    /// When Health last answered.
    ///
    /// A failed workout query returns nothing rather than an empty store, which
    /// is what stops a flaky read from erasing history — but it also means the
    /// screen keeps the previous countdown and looks exactly as it does after a
    /// successful import. A user who has just finished a session needs to be
    /// able to tell those apart before deciding whether to wait or go and check
    /// their permissions.
    @ViewBuilder
    private var freshness: some View {
        if engine.isRefreshing {
            freshnessLine("Checking Apple Health…", symbol: "arrow.triangle.2.circlepath", tint: Theme.textTertiary)
        } else if engine.lastImportFailed {
            freshnessLine(
                "Couldn't read Apple Health. Pull down to try again.",
                symbol: "exclamationmark.triangle.fill",
                tint: Theme.recovering
            )
        } else if let imported = engine.lastSuccessfulImport {
            freshnessLine(
                "Updated \(CountdownFormat.elapsed(since: imported, now: now))",
                symbol: "checkmark.circle",
                tint: Theme.textTertiary
            )
        }
    }

    private func freshnessLine(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    // MARK: - Disclaimer

    private var disclaimer: some View {
        Text("Recharge gives a cardiovascular training estimate from your Apple Health data. It is not medical advice and does not diagnose, treat, or prevent any condition. Talk with a qualified health professional before making medical decisions.")
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
