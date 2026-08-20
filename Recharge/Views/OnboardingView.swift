import SwiftUI

/// Setup, in six kinds of page: what it is, what it needs, what Health actually
/// gave us, the handful of questions Health could not answer, what the number
/// means, and one decision.
///
/// Three structural rules hold across all of them, and all three were bugs
/// before they were rules:
///
/// - **The buttons never move.** Every page — the trial offer included — ends in
///   the same `OnboardingActions` block, and that block reserves *both* variable
///   rows: the secondary action whether or not the page has one, and the
///   Restore/Terms/Privacy slot whether or not the page is a purchase point.
///   Nothing that varies between pages is allowed below the primary button, so
///   its distance from the bottom of the screen is a constant.
/// - **The copy is centred in the space it has.** `OnboardingScroll` is what
///   does that, and its absence is what made the flow feel like a series of
///   half-empty pages: the scroll view took every point the buttons did not, the
///   content sat at the top of it, and the two `Spacer`s that were supposed to
///   centre it collapsed to nothing because the container had `minHeight: 0`.
///   Every page opened with a title jammed under the status bar and a hand's
///   width of nothing between the last line of copy and the button.
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
    /// What Health handed over, captured at the moment the flow was frozen.
    @State private var ingest = HealthIngestSummary()

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
        if !ingest.isEmpty { steps.append(.readout) }
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
            message: "Finish a hard session and Recharge starts a countdown. When it runs out, you get a clear Ready. It is the answer a Garmin gives you, from Apple Health.",
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
            message: "Your workouts and heart rate build the estimate. Your own highest heart rate sets the range intensity is measured against. Sleep, resting heart rate, HRV, breathing rate, cardio fitness, and weight sharpen it. Nothing is written back, and your Health data never leaves your devices.",
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
        ingest = engine.healthIngest
        questions = settings.athleteProfile.gaps
        hasResolvedHealth = true
        advance()
    }

    // MARK: - Readout

    /// What Health actually gave us, itemised.
    ///
    /// This page used to summarise three facts in the app's own words ("mostly
    /// endurance work", "age 34"). It now prints the readings themselves,
    /// because the two do different jobs: a summary asks to be believed, and a
    /// list of the user's own numbers is evidence. It is also the honest
    /// counterpart to a permission sheet asking for eleven types — the sheet is
    /// the request, and this is the account of what was done with it.
    private var readout: some View {
        OnboardingReadoutPage(
            summary: ingest,
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
            showsIngestProof: true
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

// MARK: - The container every page uses

/// Copy on top, one decision pinned to the thumb zone underneath.
///
/// **The copy is centred in whatever the buttons leave behind**, which is the
/// whole of this type. The previous version wrapped its content in a plain
/// `ScrollView` whose inner stack carried `minHeight: 0`, so the two `Spacer`s
/// meant to centre it had nothing to expand into and collapsed. The result was a
/// title against the top of the screen, the buttons against the bottom, and a
/// large empty band between them on every page whose copy was short — which was
/// most of them, and which is exactly the "lot of blank space" this flow was
/// reported for.
///
/// The scroll view is not optional even so: at an accessibility content size the
/// icon, title, and message are several times taller than the screen, and a
/// fixed `VStack` there simply clipped them — a user reached the Health prompt
/// having been shown a title ending in "on the wat…". `minHeight` is what makes
/// the same container do both jobs: centre when the copy is short, scroll when
/// it is not.
private struct OnboardingScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    /// How far the copy comes to rest above the action block.
    static var gapAboveActions: CGFloat { 32 }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    content()
                    // The slack is deliberately **not** split evenly. A centred
                    // block leaves as much room under the last line of copy as
                    // above the icon, and on a short page that is a hand's width
                    // of nothing between what the user just read and the button
                    // they are being asked to press — which is the gap this flow
                    // was reported for. Capping the lower spacer sends the
                    // surplus upward instead, so the copy always comes to rest
                    // just above the decision.
                    Spacer(minLength: 0)
                        .frame(maxHeight: Self.gapAboveActions)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - Reusable explanatory page

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
            OnboardingScroll {
                if !typeSize.isAccessibilitySize {
                    Image(systemName: symbol)
                        .font(.system(size: 64))
                        .foregroundStyle(tint)
                        .padding(.bottom, 28)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    // A largeTitle at the top accessibility sizes runs to four
                    // full-width lines and pushes the explanation off the screen
                    // entirely. Capping the *headline* keeps it large without
                    // letting it crowd out the copy that actually has to be read
                    // before the Health prompt; the body below scales all the
                    // way.
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

                // Inside the scroll view, not between it and the buttons. This
                // was the last thing in the flow that could still move the CTA:
                // three lines of explanation about a denied Health permission
                // used to shove the button up by about fifty points at the exact
                // moment the user was reaching for it.
                if let footnote {
                    Text(footnote)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                }
            }

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

private struct OnboardingReadoutPage: View {
    let summary: HealthIngestSummary
    let remainingQuestions: Int
    let primaryAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingScroll {
                Text("Here's what\nHealth gave us")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 20)

                HealthIngestList(summary: summary)
                    .padding(16)
                    .background(
                        Theme.cardSurface,
                        in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    )

                Text(footer)
                    .font(.system(.footnote, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
            }

            OnboardingActions(primaryTitle: "Continue", primaryAction: primaryAction)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }

    private var footer: String {
        switch remainingQuestions {
        case 0: "That's everything Recharge needs."
        case 1: "One question left. Health can't answer this one."
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
            OnboardingScroll {
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
            }

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
