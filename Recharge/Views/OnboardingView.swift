import SwiftUI

/// Setup, in six kinds of page: what it is, what it needs, what Health already
/// told us, the handful of questions Health could not answer, what the number
/// means, and one decision.
///
/// Two structural rules hold across all of them, and both were bugs before they
/// were rules:
///
/// - **The buttons never move.** Every page — the trial offer included — ends in
///   the same `OnboardingActions` block, and that block reserves *both* variable
///   rows: the secondary action whether or not the page has one, and the
///   Restore/Terms/Privacy slot whether or not the page is a purchase point.
///   Nothing that varies between pages is allowed below the primary button, so
///   its distance from the bottom of the screen is a constant. Both halves were
///   bugs first: a "Not now" that appears on page two used to shove the primary
///   up by its own height, and the trial page's subscription disclosure used to
///   shove it up again by two lines of eleven-point legal text — on the one
///   screen in the flow that takes money.
/// - **The step list is frozen once, not derived continuously.** The questions
///   depend on what Health supplied, and answering one removes it from
///   `AthleteProfile.gaps`. Recomputing the array from the profile would delete
///   the page the user is standing on.
struct OnboardingView: View {
    @EnvironmentObject private var settings: RechargeSettings
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var engine: RecoveryEngine

    @State private var index = 0
    @State private var isRequestingHealth = false
    @State private var healthError: String?
    /// Set when the user leaves the Health page, in either direction. Until then
    /// the flow past it is unknown, because Health is what decides which
    /// questions are left to ask.
    @State private var hasResolvedHealth = false
    @State private var questions: [ProfileQuestion] = []
    @State private var healthSummary: HealthReadout?

    private enum Step: Hashable {
        case welcome
        case health
        case readout
        case question(ProfileQuestion)
        case honesty
        case offer
    }

    private var steps: [Step] {
        var steps: [Step] = [.welcome, .health]
        guard hasResolvedHealth else { return steps }
        // A readout page with nothing on it is worse than no readout page.
        if healthSummary?.isEmpty == false { steps.append(.readout) }
        steps += questions.map(Step.question)
        steps += [.honesty, .offer]
        return steps
    }

    private var step: Step { steps[min(index, steps.count - 1)] }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $index) {
                ForEach(Array(steps.enumerated()), id: \.offset) { position, step in
                    page(for: step).tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            progress
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
        }
        .background(Theme.background)
        .animation(.easeInOut(duration: 0.25), value: index)
        .animation(.easeInOut(duration: 0.25), value: steps.count)
    }

    /// A bar rather than dots, because the number of steps is not known until
    /// Health has answered and a row of dots that grows by three mid-flow reads
    /// as a mistake.
    private var progress: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ringTrack)
                Capsule()
                    .fill(Theme.recovering)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1) of \(plannedStepCount)")
    }

    /// Until Health answers, the flow is measured against its longest possible
    /// shape: welcome, Health, the readout, every question, the explanation, and
    /// the offer.
    ///
    /// Resolving Health can only ever *remove* questions, so the bar can only
    /// jump forward. Using the two known steps as the denominator instead would
    /// show a half-finished setup on the first screen of seven.
    private var plannedStepCount: Int {
        hasResolvedHealth ? steps.count : 5 + ProfileQuestion.allCases.count
    }

    private var fraction: Double {
        Double(index + 1) / Double(max(plannedStepCount, 1))
    }

    @ViewBuilder
    private func page(for step: Step) -> some View {
        switch step {
        case .welcome: welcome
        case .health: healthAccess
        case .readout: readout
        case .question(let question): questionPage(question)
        case .honesty: honesty
        case .offer: offer
        }
    }

    private func advance() {
        guard index + 1 < steps.count else { return }
        index += 1
    }

    // MARK: - Welcome

    private var welcome: some View {
        OnboardingPage(
            symbol: "hourglass",
            tint: Theme.recovering,
            title: "Recovery time,\non the watch you own",
            message: "Finish a hard session and Recharge starts a countdown. When it runs out, you get a clear Ready — the answer a Garmin gives you, from Apple Health.",
            primaryTitle: "Continue",
            primaryAction: advance
        )
    }

    // MARK: - Health access

    private var healthAccess: some View {
        OnboardingPage(
            symbol: "heart.text.square.fill",
            tint: Theme.recoveringSecondary,
            title: "Recharge reads\nApple Health",
            message: "Your workouts and heart rate build the estimate. Your date of birth sets the heart-rate range it is measured against. Sleep, resting heart rate, and HRV sharpen it. Nothing is written back, and your Health data never leaves your devices.",
            primaryTitle: isRequestingHealth ? "Requesting…" : "Connect Apple Health",
            primaryAction: requestHealthAccess,
            primaryDisabled: isRequestingHealth,
            secondaryTitle: "Not now",
            // Disabled while the sheet is in flight. Otherwise the user taps
            // Not now, the app advances, and the delayed system sheet lands on
            // top of a page that never asked for it.
            secondaryAction: isRequestingHealth ? nil : { deferHealthAccess() },
            footnote: healthError,
            isBusy: isRequestingHealth
        )
    }

    private func requestHealthAccess() {
        guard !isRequestingHealth else { return }
        isRequestingHealth = true
        healthError = nil
        Task {
            do {
                try await HealthKitService.shared.requestAuthorization()
                settings.hasDeferredHealthAccess = false
                await engine.refresh(force: true)
                isRequestingHealth = false
                resolveHealth()
            } catch {
                // A refusal is a legitimate choice, not an error state to shout
                // about — but the explanation has to be readable, so stay on the
                // page that shows it rather than advancing out from under it.
                healthError = "Recharge couldn't read Health. You can grant access in the Health app under Sharing › Apps, then pull to refresh."
                isRequestingHealth = false
            }
        }
    }

    private func deferHealthAccess() {
        settings.hasDeferredHealthAccess = true
        resolveHealth()
    }

    /// Freezes the rest of the flow: what Health managed to answer, and what is
    /// therefore still worth asking.
    private func resolveHealth() {
        let profile = settings.athleteProfile
        healthSummary = HealthReadout(profile: profile, analysis: engine.personalAnalysis)
        questions = profile.gaps
        hasResolvedHealth = true
        advance()
    }

    // MARK: - Readout

    private var readout: some View {
        OnboardingReadoutPage(
            summary: healthSummary ?? HealthReadout(profile: settings.athleteProfile, analysis: engine.personalAnalysis),
            remainingQuestions: questions.count,
            primaryAction: advance
        )
    }

    // MARK: - Questions

    private func questionPage(_ question: ProfileQuestion) -> some View {
        ProfileQuestionPage(
            question: question,
            profile: $settings.athleteProfile,
            onAnswer: advance
        )
    }

    // MARK: - Honesty

    private var honesty: some View {
        OnboardingPage(
            symbol: "info.circle.fill",
            tint: Theme.idle,
            title: "What the number\nactually means",
            message: "Recharge estimates when another hard session is likely to be reasonable, based on your recent workout load. It is a cardiovascular training estimate, not a measure of muscle repair, illness, or injury risk, and not medical advice. Talk with a qualified health professional before making medical decisions.",
            primaryTitle: "I understand",
            primaryAction: advance
        )
    }

    // MARK: - Offer

    private var offer: some View {
        TrialOfferPage(
            onDecline: finish,
            onPurchased: finish,
            declineTitle: "Get Started",
            showsPersonalization: true
        )
        .environmentObject(store)
        .environmentObject(engine)
        .environmentObject(settings)
    }

    private func finish() {
        settings.hasAnsweredProfileQuestions = true
        settings.hasCompletedSetup = true
        settings.lastTrialOfferShownDate = .now
        // The answers only reach a number through a rescore, and a user who
        // upgrades on this very page would otherwise see their old windows until
        // the next refresh.
        engine.rescoreAfterModelSettingChange()
    }
}

// MARK: - Reusable explanatory page

/// Explanation on top, one decision pinned to the thumb zone underneath.
///
/// The explanation scrolls and the buttons do not. At an accessibility content
/// size the icon, title, and message are several times taller than the screen,
/// and the previous fixed `VStack` with `Spacer()`s simply clipped them — the
/// user reached the Health prompt having been shown a title ending in "on the
/// wat…". Scrolling the top half is what makes the copy reachable; keeping the
/// buttons out of the scroll view is what keeps the decision reachable too.
private struct OnboardingPage: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    let primaryTitle: String
    let primaryAction: () -> Void
    var primaryDisabled = false
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
    var footnote: String?
    var isBusy = false

    /// Below the accessibility sizes the fixed 64pt symbol is the right anchor;
    /// above them it is just a large object competing with the copy for a screen
    /// that has already run out of room.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if !typeSize.isAccessibilitySize {
                        Image(systemName: symbol)
                            .font(.system(size: 64))
                            .foregroundStyle(tint)
                            .padding(.bottom, 28)
                            .accessibilityHidden(true)
                    }

                    Text(title)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        // A largeTitle at the top accessibility sizes runs to
                        // four full-width lines and pushes the explanation off
                        // the screen entirely. Capping the *headline* keeps it
                        // large without letting it crowd out the copy that
                        // actually has to be read before the Health prompt; the
                        // body below scales all the way.
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 14)

                    Text(message)
                        .font(.system(.body, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)

                    // Inside the scroll view, not between it and the buttons.
                    // This was the last thing in the flow that could still move
                    // the CTA: three lines of explanation about a denied Health
                    // permission used to shove the button up by about fifty
                    // points at the exact moment the user was reaching for it.
                    if let footnote {
                        Text(footnote)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 16)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 0)
                .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            OnboardingActions(
                primaryTitle: primaryTitle,
                primaryAction: primaryAction,
                tint: tint,
                primaryDisabled: primaryDisabled,
                isBusy: isBusy,
                secondaryTitle: secondaryTitle,
                secondaryAction: secondaryAction
            )
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }
}

// MARK: - Health readout

/// What Health answered, in the user's words rather than the model's.
struct HealthReadout: Equatable {
    var rows: [Row] = []

    struct Row: Equatable, Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
    }

    init(profile: AthleteProfile, analysis: PersonalRecoveryModel.Analysis) {
        if analysis.qualifyingSessions > 0 {
            let perWeek = String(format: "%.1f", analysis.sessionsPerWeek)
            rows.append(Row(
                id: "sessions",
                symbol: "figure.run",
                title: "\(analysis.qualifyingSessions) sessions in the last \(PersonalRecoveryModel.windowDays) days",
                detail: "About \(perWeek) a week."
            ))
        }
        if let primary = profile.primaryProfile {
            rows.append(Row(
                id: "profile",
                symbol: "chart.bar.fill",
                title: "Mostly \(primary.label.lowercased()) work",
                detail: "Each type gets its own recovery curve."
            ))
        }
        if profile.healthDerivedFields.contains(AthleteProfile.ageField),
           let age = profile.age, let max = profile.predictedMaxHeartRate {
            rows.append(Row(
                id: "age",
                symbol: "heart.fill",
                title: "Age \(age), from your Health profile",
                detail: "Sets an estimated \(Int(max)) bpm ceiling for intensity."
            ))
        }
    }

    var isEmpty: Bool { rows.isEmpty }
}

private struct OnboardingReadoutPage: View {
    let summary: HealthReadout
    let remainingQuestions: Int
    let primaryAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text("Here's what\nHealth already knew")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 22)

                    VStack(spacing: 12) {
                        ForEach(summary.rows) { row in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: row.symbol)
                                    .font(.system(size: 17))
                                    .foregroundStyle(Theme.recovering)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title)
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(row.detail)
                                        .font(.system(.footnote, design: .rounded))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    Text(footer)
                        .font(.system(.footnote, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 20)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 0)
                .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            OnboardingActions(primaryTitle: "Continue", primaryAction: primaryAction)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }

    private var footer: String {
        switch remainingQuestions {
        case 0: "That's everything Recharge needs."
        case 1: "One question left — Health can't answer this one."
        default: "\(remainingQuestions) short questions left, for the things Health can't answer."
        }
    }
}

// MARK: - Question page

/// One question, one screen, and the same action block underneath as every other
/// page. Answering advances; the primary button is the way to skip.
private struct ProfileQuestionPage: View {
    let question: ProfileQuestion
    @Binding var profile: AthleteProfile
    let onAnswer: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(question.title)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 8)

                    Text(question.detail)
                        .font(.system(.footnote, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 22)

                    switch question {
                    case .age: ageOptions
                    case .experience: options(TrainingExperience.allCases, label: \.label, isSelected: { profile.experience == $0 }, select: { profile.experience = $0 })
                    case .weeklyVolume: options(WeeklyVolume.allCases, label: \.label, isSelected: { profile.weeklyVolume == $0 }, select: { profile.weeklyVolume = $0 })
                    case .bounceBack: options(BounceBackHabit.allCases, label: \.label, isSelected: { profile.bounceBack == $0 }, select: { profile.bounceBack = $0 })
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 0)
                .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            OnboardingActions(
                primaryTitle: hasAnswer ? "Continue" : "Skip this one",
                primaryAction: onAnswer,
                tint: hasAnswer ? Theme.recovering : Theme.idle
            )
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }

    private var hasAnswer: Bool {
        switch question {
        case .age: profile.age != nil
        case .experience: profile.experience != nil
        case .weeklyVolume: profile.weeklyVolume != nil
        case .bounceBack: profile.bounceBack != nil
        }
    }

    /// Ten-year bands rather than a wheel. The only thing age feeds is a
    /// heart-rate ceiling and a gentle ramp, and neither can tell 34 from 36.
    private var ageOptions: some View {
        VStack(spacing: 10) {
            ForEach(Self.ageBands, id: \.midpoint) { band in
                optionRow(
                    title: band.label,
                    isSelected: profile.age == band.midpoint,
                    action: { profile.age = band.midpoint }
                )
            }
        }
    }

    private static let ageBands: [(label: String, midpoint: Int)] = [
        ("Under 25", 21),
        ("25 to 34", 30),
        ("35 to 44", 40),
        ("45 to 54", 50),
        ("55 or over", 60)
    ]

    private func options<T: Hashable>(
        _ values: [T],
        label: KeyPath<T, String>,
        isSelected: @escaping (T) -> Bool,
        select: @escaping (T) -> Void
    ) -> some View {
        VStack(spacing: 10) {
            ForEach(values, id: \.self) { value in
                optionRow(
                    title: value[keyPath: label],
                    isSelected: isSelected(value),
                    action: { select(value) }
                )
            }
        }
    }

    private func optionRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Theme.recovering : Theme.textTertiary)
                Text(title)
                    .font(.system(.body, design: .rounded, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? Theme.recovering : .clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
