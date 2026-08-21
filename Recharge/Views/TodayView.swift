import SwiftUI

/// The number, and almost nothing else.
///
/// This screen used to be a stack of eight cards — the ring, a rest-pattern
/// table, a "why" list, an effort prompt, body signals, training load, a
/// freshness line and a disclaimer — and the countdown it exists to show was the
/// first of them rather than the whole of it. Vitals and VO2 Max are one large
/// figure on an otherwise empty screen, and they are the two in the fleet that
/// read as finished products. Everything that explained the number moved to a
/// detail sheet a tap away, and everything that configured it moved to Settings.
///
/// What is left is deliberate, and it is three things:
///
/// - **The ring**, at whatever size the screen allows.
/// - **One sentence naming the session that set it.** This is the proof, and it
///   is the half that used to be missing: an estimate with no visible cause is
///   an assertion, and a first launch that said "your ride 12h ago didn't start
///   a countdown" was an assertion that the app had ignored the only workout the
///   user came to see.
/// - **The one thing the free tier is missing**, with the real number under a
///   blur.
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
    @State private var showSettings = false
    @State private var showEffortSheet = false
    @State private var showDetail = false

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

    @Environment(\.dynamicTypeSize) private var typeSize

    /// One-minute tick. The countdown is in hours, so anything faster is wasted
    /// work; a minute keeps the "1h 20m" tail honest.
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var phase: RecoveryPhase {
        RecoveryResolver.phase(in: engine.estimates, now: now)
    }

    /// The session this screen narrates. Nil only once the last one is old
    /// enough to have driven the phase to `noRecentWorkout`, so the ring and the
    /// sentence under it can never disagree.
    private var explained: RecoveryEstimate? {
        RecoveryResolver.explanation(in: engine.estimates, now: now)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView(showsIndicators: false) {
                    content(availableHeight: geometry.size.height)
                        .frame(minHeight: geometry.size.height)
                }
                .refreshable { await engine.refresh(force: true) }
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .tabBarClearance()
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
                #if DEBUG
                // Settings is a sheet from this screen's gear button now rather
                // than a tab, so the capture run has to raise it from here.
                if ScreenshotConfig.wantsSettings {
                    showSettings = true
                    return
                }
                #endif
                presentFeedbackIfNeeded()
            }
            // A countdown usually expires while the app is open on the minute
            // tick, so `.task` alone would miss the moment it actually matters.
            .onChange(of: engine.awaitingFeedback?.sessionID) { _, _ in
                presentFeedbackIfNeeded()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(settings)
                    .environmentObject(store)
                    .environmentObject(engine)
            }
            .sheet(isPresented: $showDetail) {
                if let explained {
                    EstimateDetailView(capturedEstimate: explained)
                        .environmentObject(store)
                        .environmentObject(engine)
                }
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
            .onChange(of: showSettings) { _, _ in publishSheetState() }
            .onChange(of: showDetail) { _, _ in publishSheetState() }
            .onChange(of: showEffortSheet) { _, _ in publishSheetState() }
            .onChange(of: feedbackTarget?.sessionID) { _, _ in publishSheetState() }
        }
    }

    // MARK: - Layout

    /// The ring takes whatever the screen has left, the way Vitals sizes its
    /// own. A fixed 236pt frame reads as a small object on a Pro Max and clips
    /// its own number at an accessibility content size; measuring means the one
    /// figure this screen exists to show is always the biggest thing on it.
    private func content(availableHeight: CGFloat) -> some View {
        let ringSize = min(max(availableHeight * 0.34, 200), 300)

        return VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 12)

            if settings.hasDeferredHealthAccess {
                healthAccessCard
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            Spacer(minLength: 20)

            hero(ringSize: ringSize)

            Spacer(minLength: 20)

            VStack(spacing: 12) {
                if engine.awaitingEffort != nil { effortPrompt }
                personalizationCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                freshness
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(10)
                    .background(Theme.cardSurface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Hero

    private func hero(ringSize: CGFloat) -> some View {
        Button { if explained != nil { showDetail = true } } label: {
            VStack(spacing: 16) {
                ZStack {
                    CountdownRing(progress: progress, phase: phase, lineWidth: ringSize * 0.085)
                        .frame(width: ringSize, height: ringSize)
                    ringLabel(ringSize: ringSize)
                }

                VStack(spacing: 6) {
                    Text(headline)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)

                    // **The proof.** One sentence naming the workout that
                    // produced the figure above, present in every state that has
                    // a workout at all — including the two that used to disown
                    // it, an expired countdown and a session too light to start
                    // one. A number with no visible cause is an assertion.
                    if let sourceLine {
                        HStack(spacing: 5) {
                            Text(sourceLine)
                                .multilineTextAlignment(.center)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.horizontal, 28)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(explained == nil)
        .accessibilityIdentifier("today.hero")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(explained == nil ? "" : "Opens the full explanation")
    }

    @ViewBuilder
    private func ringLabel(ringSize: CGFloat) -> some View {
        let numberSize = typeSize.isAccessibilitySize ? ringSize * 0.16 : ringSize * 0.22

        VStack(spacing: 2) {
            switch phase {
            case .noRecentWorkout:
                Image(systemName: Theme.symbol(for: phase))
                    .font(.system(size: ringSize * 0.19))
                    .foregroundStyle(Theme.idle)
                Text("No workout yet")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: ringSize * 0.20))
                    .foregroundStyle(Theme.ready)
                Text("Ready")
                    .font(Theme.bigNumber(numberSize * 0.78))
                    .foregroundStyle(Theme.textPrimary)
            case .readySoon, .recovering:
                Text(CountdownFormat.remaining(remaining))
                    .font(Theme.bigNumber(numberSize))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text("left")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, ringSize * 0.14)
    }

    private var progress: Double {
        guard let explained, explained.producesCountdown else {
            // A session that never started a countdown gets a *full* ring, not
            // an empty one. The ring is how much recovery has been done, and a
            // walk has nothing outstanding — an empty ring beside the word
            // "Ready" is the screen contradicting itself.
            return phase == .noRecentWorkout ? 0 : 1
        }
        let total = explained.totalHours * 3600
        guard total > 0 else { return 1 }
        return min(max(1 - explained.remainingSeconds(at: now) / total, 0), 1)
    }

    private var remaining: TimeInterval {
        explained?.remainingSeconds(at: now) ?? 0
    }

    private var headline: String {
        switch phase {
        case .noRecentWorkout:
            return "Finish a workout and your countdown starts here."
        case .ready:
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

    /// The sentence under the headline: which workout, how long ago, and what it
    /// cost. Every branch names a real session; there is no wording here for
    /// "nothing happened", because that case is the `nil` return.
    private var sourceLine: String? {
        guard let explained else { return nil }
        let session = "\(CountdownFormat.hours(explained.recoveryCostHours)) from your \(explained.activityLabel) \(relativeSessionTime(explained))"

        if explained.producesCountdown {
            return explained.isStacked
                ? "\(session), on top of \(CountdownFormat.hours(explained.carriedHours)) already owed"
                : session
        }
        // The two states that used to read "didn't start a countdown", which
        // told the user what the app declined to do rather than what it found.
        if explained.profile == .easy {
            return "\(session) · active recovery, so nothing to wait out"
        }
        return "\(session) · not enough to start a countdown"
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        switch phase {
        case .noRecentWorkout: parts.append("No recent workout.")
        case .ready: parts.append("Ready.")
        default: parts.append("\(CountdownFormat.remaining(remaining)) left. \(headline).")
        }
        if let sourceLine { parts.append(sourceLine + ".") }
        return parts.joined(separator: " ")
    }

    private func relativeSessionTime(_ estimate: RecoveryEstimate) -> String {
        let elapsed = now.timeIntervalSince(estimate.sessionEnd)
        if elapsed < 3600 { return "just now" }
        return "\(CountdownFormat.remaining(elapsed)) ago"
    }

    // MARK: - The one card

    /// The single conversion surface on this screen, and the only thing left on
    /// it that is not the number itself.
    ///
    /// Free: the standard figure beside the personalized one, the second under a
    /// blur. It is a **real** number under that blur, computed the same way a
    /// subscriber's would be — `RecoveryEngine.personalizedPreview` exists for
    /// exactly this, and a mocked-up figure on a paywall is a figure someone
    /// will hold the app to.
    ///
    /// Pro: the same two numbers with nothing hidden, which is the receipt for
    /// what was bought.
    private var personalizationCard: some View {
        Button {
            // Both taps go to the same place conceptually — "tell me more about
            // this number" — and land on the surface that answers it for the
            // tier the user is on: the Recharge+ tab, which is the paywall
            // before purchase and the feature page after it.
            NotificationCenter.default.post(
                name: store.isPro ? .rechargePlusRequested : .rechargeUpgradeRequested,
                object: nil
            )
        } label: {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(store.isPro ? "Your recharge time" : "Your own recharge time")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 8)
                        if !store.isPro { ProBadge() }
                    }

                    comparison

                    Text(comparisonCaption)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var comparison: some View {
        let preview = engine.personalizedPreview
        return HStack(alignment: .center, spacing: 14) {
            figureColumn(
                label: "Usual",
                text: CountdownFormat.hours(preview.standardHours),
                tint: Theme.textSecondary,
                blurred: false
            )
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
            figureColumn(
                label: "Optimal",
                text: CountdownFormat.hours(preview.personalizedHours),
                tint: Theme.pro,
                blurred: !store.isPro
            )
            Spacer(minLength: 0)
        }
    }

    private func figureColumn(label: String, text: String, tint: Color, blurred: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Group {
                if blurred {
                    // Blurred just enough that the shape of a two-character
                    // figure is still legible as a figure. At a larger radius a
                    // number this size disappears completely and the cell reads
                    // as a rendering fault rather than as a withheld value,
                    // which defeats the reason a real number is computed on this
                    // tier at all.
                    Text(text)
                        .foregroundStyle(tint)
                        .blur(radius: 5)
                        .opacity(0.9)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.pro)
                                .offset(x: 10, y: 2)
                        }
                        .accessibilityLabel("Hidden until you upgrade")
                } else {
                    Text(text).foregroundStyle(tint)
                }
            }
            .font(Theme.bigNumber(28))
            .monospacedDigit()
            .lineLimit(1)

            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var comparisonCaption: String {
        let preview = engine.personalizedPreview
        let subject = preview.isExample ? "A hard 60-minute session" : preview.label
        if store.isPro {
            return "\(subject). Usual is what you have actually done after sessions this size; optimal is what Recharge+ recommends for this one."
        }
        return "\(subject). Usual is read from your own history. Recharge+ adds what the model recommends for this session, from your sleep, heart rate, and thirty-day pattern."
    }

    // MARK: - Transient prompts

    /// Only on screen while there is genuinely a question outstanding, and it
    /// disappears the moment it is answered. Everything else that used to live
    /// down here was permanent furniture, which is why it moved to Settings.
    private var effortPrompt: some View {
        Button { showEffortSheet = true } label: {
            Card(padding: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.recovering)
                    VStack(alignment: .leading, spacing: 2) {
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
                        Text("Heart rate was patchy. Your rating counts whenever it reads harder than the sensors did.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

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

    // MARK: - Freshness

    /// When Health last answered, in the header rather than as a card.
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
            freshnessLine("Checking Apple Health…", tint: Theme.textTertiary)
        } else if engine.lastImportFailed {
            freshnessLine("Couldn't read Apple Health. Pull to retry.", tint: Theme.recovering)
        } else if let imported = engine.lastSuccessfulImport {
            freshnessLine("Updated \(CountdownFormat.elapsed(since: imported, now: now))", tint: Theme.textTertiary)
        }
    }

    private func freshnessLine(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(tint)
    }

    // MARK: - Sheets

    /// Raises the readiness question, once the screen has settled and only for
    /// something the engine is actually waiting on.
    private func presentFeedbackIfNeeded() {
        guard isSettled, feedbackTarget == nil, let pending = engine.awaitingFeedback else { return }
        feedbackTarget = pending
    }

    private func publishSheetState() {
        isPresentingSheet = showSettings || showDetail || showEffortSheet || feedbackTarget != nil
    }
}
