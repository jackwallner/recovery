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

    /// Closes the detail when it fills the trailing pane of the unfolded iPhone
    /// Duo rather than a sheet, where `dismiss` has nothing to dismiss.
    var onDone: (() -> Void)?

    private var estimate: RecoveryEstimate {
        engine.estimates.first { $0.sessionID == capturedEstimate.sessionID } ?? capturedEstimate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    header
                    reasons
                    numbers
                    if store.isPro {
                        intensityOverride
                        loadCard
                    } else {
                        proTeaser
                    }
                    disclaimer
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.xl)
            }
            .background(Theme.background)
            .navigationTitle(WorkoutClassifier.displayTitle(estimate.activityLabel))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { close() }
                }
            }
        }
    }

    private func close() {
        if let onDone { onDone() } else { dismiss() }
    }

    // MARK: - Header

    /// True when this session's countdown has already run out.
    ///
    /// The sheet has to lead with that, because the tap that opens it usually
    /// came from the word **Ready** on Today, and the question behind that tap
    /// is "ready from what, and why". Leading with the session's cost answered a
    /// question the user had not asked and left the one they had unanswered.
    private var hasExpired: Bool {
        estimate.producesCountdown && estimate.readyAt <= .now
    }

    private var header: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                if hasExpired { readyBanner }

                // The cost, always. A session that started no countdown still
                // cost something, and the word "None" here was the app refusing
                // to answer the question the sheet was opened to answer.
                Text(CountdownFormat.hours(estimate.recoveryCostHours))
                    .countdownNumber(38)
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
                HStack(spacing: Theme.Space.xs) {
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

    /// What "Ready" actually means, in the two sentences it takes to say it: the
    /// countdown this session set, and the fact that it has since run out.
    private var readyBanner: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.ready)
                Text("Ready")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(readyExplanation)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, Theme.Space.xs)
        .accessibilityElement(children: .combine)
    }

    private var readyExplanation: String {
        let ran = CountdownFormat.hours(estimate.totalHours)
        let ago = CountdownFormat.elapsed(since: estimate.readyAt, now: .now)
        let activity = WorkoutClassifier.displayLabel(estimate.activityLabel)
        guard estimate.isStacked else {
            return String(localized: "Your \(activity) set a \(ran) countdown. It ran out \(ago), so nothing is outstanding.", bundle: .recharge)
        }
        let carried = CountdownFormat.hours(estimate.carriedHours)
        return String(localized: "Your \(activity) set a \(ran) countdown, including \(carried) still owed from before it. It ran out \(ago), so nothing is outstanding.", bundle: .recharge)
    }

    private var costCaption: String {
        guard estimate.producesCountdown else {
            return estimate.profile == .easy
                ? String(localized: "Active recovery. Counted toward your training load, and it never starts or extends a countdown.", bundle: .recharge)
                : String(localized: "Counted toward your training load. Not enough on its own to start a countdown.", bundle: .recharge)
        }
        let window = CountdownFormat.window(low: estimate.windowLowHours, high: estimate.windowHighHours)
        // "Tomorrow" is read against today, not against the day of the session,
        // or an old session in History claims to be ready tomorrow.
        guard !hasExpired else { return String(localized: "Countdown ran \(window).", bundle: .recharge) }
        let ready = CountdownFormat.readyAt(estimate.readyAt, now: .now)
        return String(localized: "Countdown runs \(window), ready \(ready).", bundle: .recharge)
    }

    // MARK: - Why

    private var reasons: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Why")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                ForEach(Array(estimate.reasons.enumerated()), id: \.offset) { _, reason in
                    HStack(alignment: .top, spacing: Theme.Space.xs) {
                        Circle()
                            .fill(Theme.textTertiary)
                            .frame(width: 4, height: 4)
                            .padding(.top, Theme.Space.xs)
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
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Numbers")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                detailRow(String(localized: "Session load", bundle: .recharge), estimate.load.value.formatted(.number.precision(.fractionLength(0))))
                // Relative load is measured against the population reference on
                // the free tier and against the person's own baseline on the
                // paid one, both of which are about the *session's size*. It is
                // not what the free countdown is built from any more — that is
                // the observed gap — so the row says which comparison it is.
                let relativeLoad = estimate.relativeLoad.formatted(.number.precision(.fractionLength(2)))
                detailRow(
                    estimate.tier == .standard ? String(localized: "Compared to a typical session", bundle: .recharge) : String(localized: "Compared to your usual", bundle: .recharge),
                    String(localized: "\(relativeLoad)×", bundle: .recharge),
                    spoken: String(localized: "\(relativeLoad) times", bundle: .recharge)
                )
                detailRow(String(localized: "Load from", bundle: .recharge), estimate.load.source.label)
                if estimate.load.source == .heartRate {
                    detailRow(String(localized: "Heart-rate coverage", bundle: .recharge), String(localized: "\(Int((estimate.load.heartRateCoverage * 100).rounded()))%", bundle: .recharge))
                }
                detailRow(String(localized: "Estimate", bundle: .recharge), estimate.tier.label)
                if estimate.tier == .personalized, estimate.personalFactor != 1 {
                    detailRow(
                        String(localized: "\(PersonalRecoveryModel.windowDays)-day recovery rate", bundle: .recharge),
                        (estimate.personalFactor - 1).formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))
                    )
                }
                detailRow(String(localized: "Model version", bundle: .recharge), String(localized: "v\(estimate.modelVersion)", bundle: .recharge))

                if let reconciliation { comparisonNote(reconciliation) }
            }
        }
    }

    /// **The row above is one term, and it used to look like the whole sum.**
    ///
    /// It was labelled "Your adjustment" and printed `personalFactor`, the
    /// thirty-day recovery-rate multiplier. That is the *smallest* of the three
    /// things separating the two figures, and printing it alone beside a
    /// standard 23h and a Recharge+ 8h told the user the difference was 6% when
    /// what they could see was 65%. Two numbers that disagree by an order of
    /// magnitude with a "-6%" underneath is not an explanation, it is the app
    /// contradicting itself in one card.
    ///
    /// The three terms, stated: the two tiers answer different *questions*
    /// (a habit read off the calendar, against a window recommended for this
    /// session), the recommendation is scored against the person's own baseline
    /// rather than the population reference, and only then is the multiplier
    /// applied.
    private struct Reconciliation {
        let standardHours: Double
        let personalizedHours: Double
        let percent: Int
    }

    private var reconciliation: Reconciliation? {
        guard estimate.tier == .personalized else { return nil }
        let standard = estimate.standardHours
        guard standard > 0, estimate.hours > 0 else { return nil }
        guard abs(estimate.hours - standard) >= 0.5 else { return nil }
        return Reconciliation(
            standardHours: standard,
            personalizedHours: estimate.hours,
            percent: Int((((estimate.hours / standard) - 1) * 100).rounded())
        )
    }

    private func comparisonNote(_ note: Reconciliation) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Divider().overlay(Theme.textTertiary.opacity(0.3))
            detailRow(
                String(localized: "\(RechargeConversionCopy.standardColumn) → \(RechargeConversionCopy.proColumn)", bundle: .recharge),
                String(localized: "\(CountdownFormat.hours(note.standardHours)) → \(CountdownFormat.hours(note.personalizedHours))", bundle: .recharge)
            )
            Text(reconciliationDetail(note))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, Theme.Space.xxs)
    }

    private func reconciliationDetail(_ note: Reconciliation) -> String {
        let percent = abs(note.percent)
        let days = PersonalRecoveryModel.windowDays
        let rate = Int(((estimate.personalFactor - 1) * 100).rounded())
        let shorter = note.percent < 0
        switch (shorter, rate == 0) {
        case (true, true):
            return String(localized: "\(percent)% shorter overall, and the \(days)-day recovery rate above left it where it was. The rest is your own baseline standing in for the population reference, and your sleep and heart rate around the session.", bundle: .recharge)
        case (true, false):
            return String(localized: "\(percent)% shorter overall, and the \(days)-day recovery rate above is \(abs(rate))% of it. The rest is your own baseline standing in for the population reference, and your sleep and heart rate around the session.", bundle: .recharge)
        case (false, true):
            return String(localized: "\(percent)% longer overall, and the \(days)-day recovery rate above left it where it was. The rest is your own baseline standing in for the population reference, and your sleep and heart rate around the session.", bundle: .recharge)
        case (false, false):
            return String(localized: "\(percent)% longer overall, and the \(days)-day recovery rate above is \(abs(rate))% of it. The rest is your own baseline standing in for the population reference, and your sleep and heart rate around the session.", bundle: .recharge)
        }
    }

    private func detailRow(_ label: String, _ value: String, spoken: String? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .accessibilityLabel(spoken ?? value)
        }
    }

    // MARK: - Training load (Pro)

    private var loadCard: some View {
        let balance = engine.loadBalance()
        return Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Training load")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: Theme.Space.lg) {
                    loadFigure(String(localized: "This week", bundle: .recharge), balance.acute)
                    loadFigure(String(localized: "4-week average", bundle: .recharge), balance.chronic)
                }
                Text("Load is a proxy built from your own sessions, not a measurement.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func loadFigure(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.hair) {
            Text("\(Int(value.rounded()))")
                .countdownNumber(26)
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - How hard it was (Pro)

    /// **The correction is about intensity, not about kind.**
    ///
    /// This used to offer Endurance / Strength / Mixed / Easy, which asked the
    /// user to fix the half the app was already right about: HealthKit says what
    /// activity a session was, and `WorkoutClassifier` maps that with every raw
    /// value pinned by a test. What the app genuinely gets wrong is *how hard*
    /// it was — a walk that was a hill march, a lift the optical sensor slept
    /// through — and Light / Moderate / Hard is the only scale anybody can
    /// answer after the fact.
    ///
    /// It also has to move the countdown, which the profile picker frequently
    /// did not: changing a walk from Easy to Endurance left the load exactly
    /// where the sensors had put it. An intensity override replaces the load
    /// outright and lifts the session off the `easy` profile, so the ring
    /// changes in the direction the label promises. `nil` is the way back to
    /// whatever Recharge worked out on its own.
    private var intensityOverride: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    Text("How hard was it?")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: Theme.Space.xs)
                    if engine.intensityOverride(forSessionID: capturedEstimate.sessionID) != nil {
                        Button("Use Recharge's") {
                            Haptics.selection()
                            engine.overrideIntensity(nil, forSessionID: capturedEstimate.sessionID)
                        }
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.pro)
                    }
                }
                Text(intensityCaption)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("How hard was it?", selection: Binding(
                    get: {
                        engine.intensityOverride(forSessionID: capturedEstimate.sessionID)
                            ?? estimate.category.intensity
                    },
                    set: {
                        Haptics.selection()
                        engine.overrideIntensity($0, forSessionID: capturedEstimate.sessionID)
                    }
                )) {
                    ForEach(SessionIntensity.allCases) { intensity in
                        Text(intensity.label).tag(intensity)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var intensityCaption: String {
        guard let override = engine.intensityOverride(forSessionID: capturedEstimate.sessionID) else {
            return String(localized: "Recharge read this as \(estimate.category.sentenceLabel) from \(estimate.load.source.label). Change it and the countdown is recalculated from your answer.", bundle: .recharge)
        }
        switch override {
        case .light: return String(localized: "You marked this light, so that is what the countdown was built from.", bundle: .recharge)
        case .moderate: return String(localized: "You marked this moderate, so that is what the countdown was built from.", bundle: .recharge)
        case .hard: return String(localized: "You marked this hard, so that is what the countdown was built from.", bundle: .recharge)
        }
    }

    private var proTeaser: some View {
        Button {
            close()
            NotificationCenter.default.post(name: .rechargeUpgradeRequested, object: nil)
        } label: {
            Card {
                HStack(spacing: Theme.Space.sm) {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text("Correct this session")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Recharge+ lets you mark a session light, moderate or hard and have the countdown recalculated, pin your own hours to each intensity, and see your weekly load.")
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
        .pressable(.card)
    }

    private var disclaimer: some View {
        Text("Recharge gives a cardiovascular training estimate from your Apple Health data. It is not medical advice and does not diagnose, treat, or prevent any condition. Talk with a qualified health professional before making medical decisions.")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Space.xs)
            .padding(.top, Theme.Space.xxs)
    }
}
