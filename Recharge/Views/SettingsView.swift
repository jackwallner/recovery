import StoreKit
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var settings: RechargeSettings
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var engine: RecoveryEngine

    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @State private var showPaywall = false
    @State private var showReviewPrompt = false
    @State private var maxHeartRateText = ""
    @State private var notificationsDenied = false
    @State private var restoreMessage: String?
    @State private var isRestoring = false
    @State private var pendingNativeReviewAfterDismiss = false
    @State private var isRequestingHealth = false
    @State private var healthMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if !store.isPro { proSection }
                healthSection
                recoveryTimeSection
                complicationSection
                modelSection
                // Directly under Model, because that is what it feeds.
                aboutYouSection
                if store.isPro { contextSection }
                aboutSection
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle("Settings")
            // Inline, as on Today, History, and the rest of the fleet: a large
            // title draws its own bar over the page the moment the form scrolls.
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: "settings")
                    .environmentObject(store)
            }
            .sheet(isPresented: $showReviewPrompt, onDismiss: requestPendingNativeReview) {
                ReviewPromptSheet { outcome in
                    pendingNativeReviewAfterDismiss = outcome == .requestNativeReview
                }
            }
            .onAppear {
                maxHeartRateText = settings.maxHeartRate > 0
                    ? String(Int(settings.maxHeartRate))
                    : ""
            }
            .task {
                guard settings.notifyOnReady else { return }
                notificationsDenied = !(await NotificationService.isAuthorized())
            }
        }
    }

    // MARK: - Pro

    private var proSection: some View {
        Section {
            Button { showPaywall = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.badge.clock.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.pro)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(RechargeConversionCopy.proName)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Body signals, weekly load, session overrides and Ready alerts.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Apple Health

    /// What the app can actually observe about its Health access.
    ///
    /// iOS never reports whether a *read* was granted: a denial and an empty
    /// store are identical from here, which is why the request result alone can
    /// never answer "is Recharge working?". What the app can honestly report is
    /// whether Health has answered with data, so the row is phrased as an
    /// observation rather than a permission state.
    private enum HealthStatus {
        case notRequested
        case reading(Date)
        case failing
        case noDataYet

        var label: String {
            switch self {
            case .notRequested: "Not connected"
            case .reading: "Reading Apple Health"
            case .failing: "Can't read Apple Health"
            case .noDataYet: "Connected, no workouts found"
            }
        }

        var symbol: String {
            switch self {
            case .notRequested: "heart.text.square"
            case .reading: "checkmark.circle.fill"
            case .failing: "exclamationmark.triangle.fill"
            case .noDataYet: "questionmark.circle"
            }
        }

        var tint: Color {
            switch self {
            case .notRequested: Theme.textTertiary
            case .reading: Theme.ready
            case .failing: Theme.recovering
            case .noDataYet: Theme.textSecondary
            }
        }

        var detail: String {
            switch self {
            case .notRequested:
                "Recharge has not asked for Health access on this device yet."
            case .reading(let date):
                "Last read \(CountdownFormat.elapsed(since: date))."
            case .failing:
                "The last read did not complete. Open the Health app, then Sharing, then Apps, then Recharge, and check that workouts are allowed."
            case .noDataYet:
                "Health answered but returned no qualifying workouts. If you have trained recently, check that workouts are allowed for Recharge in the Health app."
            }
        }
    }

    private var healthStatus: HealthStatus {
        if settings.hasDeferredHealthAccess { return .notRequested }
        if engine.lastImportFailed { return .failing }
        guard let imported = engine.lastSuccessfulImport else { return .notRequested }
        return engine.estimates.isEmpty ? .noDataYet : .reading(imported)
    }

    private var healthSection: some View {
        Section {
            let status = healthStatus
            HStack(spacing: 10) {
                Image(systemName: status.symbol)
                    .foregroundStyle(status.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.label)
                        .foregroundStyle(Theme.textPrimary)
                    Text(status.detail)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)

            Button {
                Task { await requestHealthAccess() }
            } label: {
                HStack {
                    Text(settings.hasDeferredHealthAccess ? "Connect Apple Health" : "Request Apple Health access")
                    if isRequestingHealth {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isRequestingHealth)

            Button("Open Health settings") {
                // The read choices themselves only exist in the Health app, and
                // the in-app request sheet never reappears once answered, so a
                // user who denied has no other route back.
                if let url = URL(string: "x-apple-health://") { openURL(url) }
            }

            if let healthMessage {
                Text(healthMessage)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text("Recharge only reads Health data. Apple keeps individual read permissions private, so Recharge can report what it receives but never which categories you allowed. Review them in the Health app under Sharing, then Apps, then Recharge.")
        }
    }

    private func requestHealthAccess() async {
        isRequestingHealth = true
        healthMessage = nil
        defer { isRequestingHealth = false }
        do {
            try await HealthKitService.shared.requestAuthorization()
            settings.hasDeferredHealthAccess = false
            await engine.refresh(force: true)
            healthMessage = "Request complete. Apple keeps individual read choices private; manage them in the Health app."
        } catch {
            settings.hasDeferredHealthAccess = true
            healthMessage = "Recharge couldn't request access. Open the Health app and choose Sharing, then Apps, then Recharge."
        }
    }

    // MARK: - Complication

    private var complicationSection: some View {
        Section {
            Picker("Style", selection: $settings.complicationStyle) {
                ForEach(ComplicationStyle.allCases, id: \.self) { style in
                    Text(style.label).tag(style)
                }
            }
            // The setter reloads the iOS widgets, but the Watch has its own App
            // Group and only ever learns the style from `sendSnapshot`, which
            // nothing but `publish()` calls. Without this the wrist keeps the
            // old style until some unrelated event republishes, under a footer
            // promising it applies to all four families.
            .onChange(of: settings.complicationStyle) { _, _ in
                engine.publish()
            }
            Text(settings.complicationStyle.detail)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        } header: {
            Text("Watch complication")
        } footer: {
            Text("Applies to all four complication families. Add Recharge to a watch face from the Watch app.")
        }
    }

    // MARK: - Model

    // MARK: - Recovery time

    /// Which model is producing the countdown, and what it is doing.
    ///
    /// Shown on both tiers on purpose. A free user is entitled to know their
    /// number is the standard one rather than assuming it is about them, and it
    /// is the honest version of the upgrade pitch: here is what your own data
    /// says, and here is the number you are getting instead.
    private var recoveryTimeSection: some View {
        Section {
            HStack {
                Text("Model")
                Spacer()
                Text(store.isPro ? RecoveryTier.personalized.label : RecoveryTier.standard.label)
                    .foregroundStyle(store.isPro ? Theme.pro : Theme.textSecondary)
            }

            if engine.personalAnalysis.isPersonalised {
                HStack {
                    Text(store.isPro ? "Your adjustment" : "Your data suggests")
                    Spacer()
                    Text(personalFactorLabel)
                        .foregroundStyle(store.isPro ? Theme.textSecondary : Theme.pro)
                }
                ForEach(PersonalRecoveryModel.summary(engine.personalAnalysis).dropFirst(), id: \.self) { line in
                    Text(line)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if !store.isPro {
                Button("See Recharge+") { showPaywall = true }
            }
        } header: {
            Text("Recharge time")
        } footer: {
            Text(store.isPro
                ? "Every session is scored against your own \(RecoveryBaseline.historyDays)-day baseline, then adjusted by what the last \(PersonalRecoveryModel.windowDays) days show about how quickly you come back. It is a cardiovascular training estimate, not medical advice."
                : "The standard estimate is the same table for everyone: session type, length, and intensity in, hours out. Recharge+ scores each session against your own history instead.")
        }
    }

    private var personalFactorLabel: String {
        let percent = engine.personalAnalysis.percentDifference
        if percent == 0 { return "Same as standard" }
        return percent > 0 ? "+\(percent)% longer" : "\(percent)% shorter"
    }

    // MARK: - About you

    /// The onboarding answers, editable forever after.
    ///
    /// A one-shot questionnaire is a trap: people turn 40, start lifting, and
    /// double their weekly volume, and none of that should require a reinstall
    /// to tell the app about. Rows Health filled in say so, because a user who
    /// sees their own age here should know where it came from.
    private var aboutYouSection: some View {
        Section {
            Picker("Age", selection: ageBinding) {
                Text("Not set").tag(Int?.none)
                ForEach(Self.ageBands, id: \.midpoint) { band in
                    Text(band.label).tag(Int?.some(band.midpoint))
                }
            }
            Picker("Training for", selection: $settings.athleteProfile.experience) {
                Text("Not set").tag(TrainingExperience?.none)
                ForEach(TrainingExperience.allCases, id: \.self) { value in
                    Text(value.label).tag(TrainingExperience?.some(value))
                }
            }
            Picker("Sessions a week", selection: $settings.athleteProfile.weeklyVolume) {
                Text("Not set").tag(WeeklyVolume?.none)
                ForEach(WeeklyVolume.allCases, id: \.self) { value in
                    Text(value.label).tag(WeeklyVolume?.some(value))
                }
            }
            Picker("Ready again after", selection: $settings.athleteProfile.bounceBack) {
                Text("Not set").tag(BounceBackHabit?.none)
                ForEach(BounceBackHabit.allCases, id: \.self) { value in
                    Text(value.label).tag(BounceBackHabit?.some(value))
                }
            }
        } header: {
            Text("About you")
        } footer: {
            Text(aboutYouFooter)
        }
        // One handler for all four: every one of them changes a model-wide
        // assumption, so every one has to thaw the stored estimates rather than
        // sit in defaults being true and unused.
        .onChange(of: settings.athleteProfile) { _, _ in
            engine.rescoreAfterModelSettingChange()
        }
    }

    private var ageBinding: Binding<Int?> {
        Binding(
            get: { settings.athleteProfile.age },
            set: { newValue in
                settings.athleteProfile.age = newValue
                // Typed by hand now, so a later Health read must not silently
                // move it back.
                settings.athleteProfile.healthDerivedFields.remove(AthleteProfile.ageField)
            }
        )
    }

    private static let ageBands: [(label: String, midpoint: Int)] = [
        ("Under 25", 21), ("25 to 34", 30), ("35 to 44", 40), ("45 to 54", 50), ("55 or over", 60)
    ]

    private var aboutYouFooter: String {
        let derived = settings.athleteProfile.healthDerivedFields
        let base = "Age sets the heart-rate range every session is measured against, on both tiers. The rest shape your Recharge+ estimate until there is enough history to answer for itself."
        guard !derived.isEmpty else { return base }
        var found: [String] = []
        if derived.contains(AthleteProfile.ageField) { found.append("your age") }
        if derived.contains(AthleteProfile.weeklyVolumeField) { found.append("your weekly volume") }
        guard !found.isEmpty else { return base }
        return "Recharge read \(ListFormatterShim.join(found)) from Apple Health. \(base)"
    }

    private var modelSection: some View {
        Section {
            Picker("HYROX and CrossFit", selection: $settings.ambiguousProfile) {
                ForEach([WorkoutProfile.mixed, .strength, .endurance], id: \.self) { profile in
                    Text(profile.label).tag(profile)
                }
            }
            // Persisting the preference is not the same as applying it. Without
            // this the user picks Strength and every existing session keeps the
            // curve they just told the app was wrong.
            .onChange(of: settings.ambiguousProfile) { _, _ in
                engine.rescoreAfterModelSettingChange()
            }

            HStack {
                Text("Max heart rate")
                Spacer()
                TextField("Auto", text: $maxHeartRateText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .onChange(of: maxHeartRateText) { _, value in
                        let parsed = Double(value) ?? 0
                        let accepted = Self.maxHeartRateRange.contains(parsed) ? parsed : 0
                        guard accepted != settings.maxHeartRate else { return }
                        settings.maxHeartRate = accepted
                        engine.rescoreAfterModelSettingChange()
                    }
                Text("bpm")
                    .foregroundStyle(Theme.textTertiary)
            }

            // The field used to accept "250", store zero, and leave the number
            // on screen — so Settings said 250 while the model used its default.
            if let note = maxHeartRateNote {
                Text(note)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(maxHeartRateIsRejected ? .orange : Theme.textSecondary)
            }

            HStack {
                Text("Personal calibration")
                Spacer()
                Text(calibrationLabel)
                    .foregroundStyle(Theme.textSecondary)
            }
            if settings.calibrationFactor != RecoveryCalibration.neutral {
                Button("Reset calibration") {
                    settings.calibrationFactor = RecoveryCalibration.neutral
                    engine.rescore()
                    engine.publish()
                }
                .foregroundStyle(.red)
            }
        } header: {
            Text("Model")
        } footer: {
            Text("Apple Health reports HYROX and CrossFit sessions the same way it reports other functional training, so Recharge needs to know which curve to use. Calibration adjusts from your answers when a countdown runs out.")
        }
    }

    private static let maxHeartRateRange: ClosedRange<Double> = 120...230

    private var maxHeartRateIsRejected: Bool {
        !maxHeartRateText.isEmpty && settings.maxHeartRate == 0
    }

    private var maxHeartRateNote: String? {
        if maxHeartRateIsRejected {
            return "Enter a value between 120 and 230 bpm. Recharge is using its own estimate until then."
        }
        if maxHeartRateText.isEmpty {
            return "Auto uses the model's own estimate. Set yours for a sharper heart-rate load."
        }
        return nil
    }

    private var calibrationLabel: String {
        let percent = Int(((settings.calibrationFactor - 1) * 100).rounded())
        if percent == 0 { return "Neutral" }
        return percent > 0 ? "+\(percent)% longer" : "\(percent)% shorter"
    }

    // MARK: - Context (Pro)

    private var contextSection: some View {
        Section {
            Toggle("Use body signals", isOn: $settings.useContextSignals)
                .onChange(of: settings.useContextSignals) { _, _ in
                    engine.rescore()
                    engine.publish()
                }
            Toggle("Notify me at Ready", isOn: $settings.notifyOnReady)
                .onChange(of: settings.notifyOnReady) { _, enabled in
                    Task {
                        if enabled {
                            // The returned Bool used to be discarded, so a user
                            // who tapped Don't Allow kept an enabled toggle that
                            // could never fire.
                            await NotificationService.requestAuthorization()
                            notificationsDenied = !(await NotificationService.isAuthorized())
                        } else {
                            notificationsDenied = false
                        }
                        engine.publish()
                    }
                }
            if notificationsDenied, settings.notifyOnReady {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notifications are turned off for Recharge, so the Ready alert can't be delivered.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.orange)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Button("Open iOS Settings") { openURL(url) }
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                    }
                }
            }
        } header: {
            Text("Recharge+")
        } footer: {
            Text("Body signals fold your sleep, resting heart rate, and HRV into the estimate, within a bounded range. One reading never swings the countdown on its own.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            Button("Rate or send feedback") { showReviewPrompt = true }

            // Restore used to be a button that produced no visible change at
            // all: `StoreService` recorded the outcome in `lastError` and only
            // the paywall rendered it, so from Settings a failed restore and a
            // successful one looked identical.
            Button {
                Task {
                    isRestoring = true
                    restoreMessage = nil
                    await store.restorePurchases()
                    isRestoring = false
                    restoreMessage = store.lastError
                        ?? (store.isPro
                            ? "\(RechargeConversionCopy.proName) restored."
                            : "No purchase to restore for this Apple ID.")
                }
            } label: {
                HStack {
                    Text("Restore purchases")
                    if isRestoring {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isRestoring)

            if let restoreMessage {
                Text(restoreMessage)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(store.isPro ? Theme.textSecondary : .orange)
            }

            Link("Privacy policy", destination: URL(string: "https://jackwallner.github.io/recovery/privacy-policy.html")!)
            Link("Terms of use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)

            HStack {
                Text("Version")
                Spacer()
                Text(versionString)
                    .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            Text("About")
        } footer: {
            // "Your data stays on your devices" full stop read as "nothing ever
            // leaves", which the privacy policy already qualifies. Say the same
            // thing here rather than making the careful reader go and find it.
            Text("Recharge gives a cardiovascular training estimate from your Apple Health data. It is not medical advice and does not diagnose, treat, or prevent any condition. Your Health data stays on your devices; only purchase information is handled by Apple and RevenueCat.")
        }
    }

    private func requestPendingNativeReview() {
        guard pendingNativeReviewAfterDismiss else { return }
        pendingNativeReviewAfterDismiss = false
        requestReview()
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Debug

    #if DEBUG
    private var debugSection: some View {
        Section("Debug") {
            Toggle("Pro unlocked (local)", isOn: Binding(
                get: { store.isPro },
                set: { store.setLocalOverride(isPro: $0) }
            ))
            Button("Force refresh") {
                Task { await engine.refresh(force: true) }
            }
            HStack {
                Text("Model version")
                Spacer()
                Text("v\(recoveryModelVersion)")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
    #endif
}
