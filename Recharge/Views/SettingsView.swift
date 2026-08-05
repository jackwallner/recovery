import StoreKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: RechargeSettings
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var engine: RecoveryEngine

    @Environment(\.openURL) private var openURL
    @State private var showPaywall = false
    @State private var showReviewPrompt = false
    @State private var maxHeartRateText = ""

    var body: some View {
        NavigationStack {
            Form {
                if !store.isPro { proSection }
                complicationSection
                modelSection
                if store.isPro { contextSection }
                aboutSection
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: "settings")
                    .environmentObject(store)
            }
            .sheet(isPresented: $showReviewPrompt) {
                ReviewPromptSheet()
            }
            .onAppear {
                maxHeartRateText = settings.maxHeartRate > 0
                    ? String(Int(settings.maxHeartRate))
                    : ""
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
                        Text("Body signals, personal bands, history and weekly load.")
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

    // MARK: - Complication

    private var complicationSection: some View {
        Section {
            Picker("Style", selection: $settings.complicationStyle) {
                ForEach(ComplicationStyle.allCases, id: \.self) { style in
                    Text(style.label).tag(style)
                }
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

    private var modelSection: some View {
        Section {
            Picker("HYROX and CrossFit", selection: $settings.ambiguousProfile) {
                ForEach([WorkoutProfile.mixed, .strength, .endurance], id: \.self) { profile in
                    Text(profile.label).tag(profile)
                }
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
                        settings.maxHeartRate = (120...230).contains(parsed) ? parsed : 0
                    }
                Text("bpm")
                    .foregroundStyle(Theme.textTertiary)
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
                        if enabled { await NotificationService.requestAuthorization() }
                        engine.publish()
                    }
                }
        } header: {
            Text("Recharge Pro")
        } footer: {
            Text("Body signals fold your sleep, resting heart rate, and HRV into the estimate, within a bounded range. One reading never swings the countdown on its own.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            Button("Rate or send feedback") { showReviewPrompt = true }

            Button("Restore purchases") {
                Task { await store.restorePurchases() }
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
            Text("Recharge gives a cardiovascular training estimate from your Apple Health data. It is not medical advice and does not diagnose, treat, or prevent any condition. Your data stays on your devices.")
        }
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
