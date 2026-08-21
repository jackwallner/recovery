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
#if DEBUG
    @State private var showEffort = ScreenshotConfig.wantsEffortPrompt
#else
    @State private var showEffort = false
#endif

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

    /// The phone's Health read failing does not invalidate a `readyAt` it
    /// already computed, so the countdown keeps running and `note` says what
    /// went wrong. This is the same call the phone makes in `TodayView`.
    private var phase: RecoveryPhase { snapshot.phase(at: now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ring
                    // Above the headline, not below it. The effort tap is the
                    // only Watch to phone write in the app, and after the ring,
                    // the ready time, and the category line it sat off the
                    // bottom of the screen: a user could open the Watch
                    // specifically to answer, see an ordinary countdown, and
                    // leave. The ring gives up the height it needs.
                    if wantsEffortPrompt { effortButton }
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
            }
            // A snapshot arriving from the phone has to repaint immediately.
            // Waiting for the 60-second ticker means the user watches a stale
            // countdown for up to a minute after raising their wrist.
            .onChange(of: connectivity.snapshotRevision) { _, _ in
                now = .now
                snapshot = WatchTodayView.currentSnapshot()
            }
            .navigationDestination(isPresented: $showEffort) {
                WatchEffortPrompt(activityLabel: snapshot.activityLabel) { effort in
                    showEffort = false
                    guard let sessionID = pendingEffortSessionID else { return }
                    if let effort {
                        connectivity.sendEffort(effort, forSessionID: sessionID)
                    } else {
                        // A decline is an answer. Without this the request stays
                        // pending and the button comes back on every launch.
                        connectivity.declineEffort(forSessionID: sessionID)
                    }
                }
                .navigationTitle("Rate effort")
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
                    Image(systemName: hasHeardFromPhone || snapshot.hasSession
                          ? "figure.run.circle"
                          : "antenna.radiowaves.left.and.right")
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
        .frame(width: ringSize, height: ringSize)
        .padding(.top, 4)
    }

    /// The ring shrinks while a request is pending so the button and its
    /// headline both land inside the first viewport on the smallest watch.
    private var ringSize: CGFloat { wantsEffortPrompt ? 72 : 120 }

    // MARK: - Effort

    private var effortButton: some View {
        Button {
            showEffort = true
        } label: {
            Label("Rate effort", systemImage: "hand.raised.fill")
                .font(.system(.caption, design: .rounded, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(Theme.recovering)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 4) {
            Text(headline)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            // Gated on the phase, not on `hasSession`: past the staleness cutoff
            // the headline says there is no recent workout, and naming the
            // session that no longer counts contradicts it.
            if phase != .noRecentWorkout, let category = snapshot.category {
                Text("\(category.shortLabel) · \(snapshot.activityLabel)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }

            if let staleness = connectionNote {
                Text(staleness)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
    }

    private var wantsEffortPrompt: Bool {
        #if DEBUG
        // The `watchEffort` capture scene existed but nothing read it, so the
        // scene rendered the plain recovering screen and could never prove the
        // feature it was created for.
        if ScreenshotConfig.wantsEffortPrompt { return true }
        #endif
        return pendingEffortSessionID != nil
    }

    /// An empty ring means "no workout" only if the phone has actually said so.
    /// Until the two have talked, it means "I don't know yet", and saying so is
    /// the difference between a bug report and a user who opens their phone.
    private var hasHeardFromPhone: Bool {
        #if DEBUG
        if ScreenshotConfig.isEnabled { return true }
        #endif
        return connectivity.lastSnapshotReceived != nil
    }

    private var connectionNote: String? {
        #if DEBUG
        if ScreenshotConfig.isEnabled { return nil }
        #endif
        // Annotates the countdown rather than replacing it: what a failed read
        // costs is the certainty that nothing newer is missing, not the window
        // already on screen.
        if snapshot.healthDataState == .stale {
            return "Your iPhone couldn't read Apple Health. Open Recharge there."
        }
        guard let received = connectivity.lastSnapshotReceived else {
            return "Open Recharge on your iPhone if this doesn't clear."
        }
        guard Date.now.timeIntervalSince(received) > 6 * 3600 else { return nil }
        return "Last synced \(CountdownFormat.remaining(Date.now.timeIntervalSince(received))) ago."
    }

    private var headline: String {
        // Cold start: the phone's snapshot takes a moment to arrive, and until
        // it does the Watch knows nothing. Announcing "No recent workout" in
        // that window tells the user their data is gone when it is merely late.
        if !hasHeardFromPhone && !snapshot.hasSession { return "Syncing with iPhone" }
        switch phase {
        case .noRecentWorkout: return "No recent workout"
        case .ready: return "Ready for another hard session"
        case .readySoon, .recovering:
            return snapshot.readyAt.map { "Ready \(CountdownFormat.readyAt($0, now: now))" } ?? "Recovering"
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
    /// `nil` means the user declined. The phone sheet has always had a Skip; the
    /// Watch relied on an undiscoverable swipe-to-dismiss.
    let onSelect: (Double?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("How hard was that \(activityLabel.isEmpty ? "session" : activityLabel)?")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                Text("Your answer goes to your iPhone and updates the estimate.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 6) {
                    ForEach([(4.0, "Easy"), (7.0, "Moderate"), (9.0, "Hard")], id: \.0) { effort, title in
                        Button {
                            onSelect(effort)
                            dismiss()
                        } label: {
                            Text(title)
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.recovering)
                    }
                }

                // Named to match the phone sheet, and now durable on both: the
                // request does not come back for this session.
                Button("Skip") {
                    onSelect(nil)
                    dismiss()
                }
                .font(.system(.caption, design: .rounded))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 4)
        }
    }
}
