import SwiftUI
import WatchKit

/// The whole Watch app: the countdown, and a way to answer the effort question.
///
/// It reads the App Group snapshot the phone wrote. The Watch deliberately does
/// **not** recompute — it cannot see the full HealthKit history, so anything it
/// calculated locally would disagree with the phone.
struct WatchTodayView: View {
    @State private var snapshot = WatchTodayView.currentSnapshot()
    @State private var now = Date.now
    @State private var showEffort = false

    /// Screenshot runs have no paired phone to write the App Group, so the
    /// capture scene supplies the snapshot instead.
    static func currentSnapshot() -> RecoverySnapshot {
        #if DEBUG
        if ScreenshotConfig.isEnabled { return ScreenshotFixtures.snapshot() }
        #endif
        return RecoverySnapshotStore.load()
    }

    @StateObject private var connectivity = PhoneWatchSession.shared

    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var phase: RecoveryPhase { snapshot.phase(at: now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ring
                    detail
                    if let status = connectivity.statusMessage {
                        Text(status)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Recharge")
            .onReceive(ticker) { date in
                now = date
                snapshot = WatchTodayView.currentSnapshot()
            }
            .onAppear {
                now = .now
                snapshot = WatchTodayView.currentSnapshot()
                connectivity.activate()
            }
            .sheet(isPresented: $showEffort) {
                WatchEffortPrompt(activityLabel: snapshot.activityLabel) { effort in
                    if let sessionID = pendingEffortSessionID {
                        connectivity.sendEffort(effort, forSessionID: sessionID)
                    }
                }
            }
        }
    }

    // MARK: - Ring

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Theme.ringTrack, style: StrokeStyle(lineWidth: 9, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(snapshot.progress(at: now), phase == .noRecentWorkout ? 0 : 0.01))
                .stroke(
                    Theme.gradient(for: phase),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                switch phase {
                case .noRecentWorkout:
                    Image(systemName: "figure.run.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.idle)
                case .ready:
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.ready)
                    Text("Ready")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                default:
                    Text(CountdownFormat.compactRemaining(snapshot.remainingSeconds(at: now)))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(Theme.textPrimary)
                    Text("left")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(width: 120, height: 120)
        .padding(.top, 4)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 4) {
            Text(headline)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            if snapshot.hasSession, let category = snapshot.category {
                Text("\(category.shortLabel) · \(snapshot.activityLabel)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }

            if pendingEffortSessionID != nil {
                Button {
                    showEffort = true
                } label: {
                    Label("Rate effort", systemImage: "hand.raised.fill")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.recovering)
                .padding(.top, 4)
            }
        }
    }

    private var headline: String {
        switch phase {
        case .noRecentWorkout: "No recent workout"
        case .ready: "Ready for another hard session"
        case .readySoon, .recovering:
            snapshot.readyAt.map { "Ready \(CountdownFormat.readyAt($0, now: now))" } ?? "Recovering"
        }
    }

    /// The Watch only knows about a pending effort question through the
    /// snapshot: the phone sets `pendingEffortSessionID` when it imports a
    /// session it cannot score confidently.
    private var pendingEffortSessionID: String? {
        UserDefaults(suiteName: rechargeAppGroupID)?.string(forKey: "pendingEffortSessionID")
    }
}

/// Three taps, matched to the phone's bands so the same answer means the same
/// thing on either device.
struct WatchEffortPrompt: View {
    let activityLabel: String
    let onSelect: (Double) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("How hard was that \(activityLabel.isEmpty ? "session" : activityLabel)?")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                ForEach([(4.0, "Easy"), (7.0, "Moderate"), (9.0, "Hard")], id: \.0) { effort, title in
                    Button {
                        onSelect(effort)
                        dismiss()
                    } label: {
                        Text(title)
                            .font(.system(.headline, design: .rounded))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.recovering)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
