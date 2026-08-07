import StoreKit
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var settings: RechargeSettings
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var engine: RecoveryEngine

    @Environment(\.openURL) private var openURL
    @State private var showPaywall = false
    @State private var showReviewPrompt = false
    @State private var maxHeartRateText = ""
    @State private var notificationsDenied = false
    @State private var restoreMessage: String?
    @State private var isRestoring = false

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
            Text("Recharge Pro")
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
