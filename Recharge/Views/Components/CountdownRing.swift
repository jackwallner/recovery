import SwiftUI

/// The hero ring. Fills as the window runs down, so a nearly-complete ring reads
/// as "almost there" rather than "almost gone".
struct CountdownRing: View {
    let progress: Double
    let phase: RecoveryPhase
    var lineWidth: CGFloat = 18
    var showsGlow = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.ringTrack, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            Circle()
                .trim(from: 0, to: max(min(progress, 1), phase == .noRecentWorkout ? 0 : 0.005))
                .stroke(
                    Theme.gradient(for: phase),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(
                    color: showsGlow ? Theme.color(for: phase).opacity(0.35) : .clear,
                    radius: showsGlow ? 10 : 0
                )
                .animation(.easeInOut(duration: 0.6), value: progress)
        }
    }
}

/// A compact profile + category chip, used on the Today "why" card and in
/// history rows.
struct ProfileChip: View {
    let profile: WorkoutProfile
    let category: LoadCategory?
    var activityLabel: String = ""

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: Theme.symbol(forActivityLabel: activityLabel, profile: profile))
                .font(.caption2)
            Text(category?.shortLabel ?? profile.label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.cardSurfaceLight, in: Capsule())
        .foregroundStyle(Theme.textSecondary)
    }
}

/// Confidence as a three-pip meter. Cheaper to read than a word, and it keeps
/// the app honest about how much it actually knows.
struct ConfidencePips: View {
    let confidence: RecoveryConfidence
    var showsLabel = true

    private var filled: Int {
        switch confidence {
        case .buildingBaseline: 1
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }

    private var tint: Color {
        switch confidence {
        case .buildingBaseline, .low: Theme.textTertiary
        case .medium: Theme.readySoon
        case .high: Theme.ready
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index < filled ? tint : Theme.ringTrack)
                        .frame(width: 10, height: 4)
                }
            }
            if showsLabel {
                Text(confidence.label)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(confidence.label)
    }
}

/// Standard card chrome, so every surface in the app has the same edges.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.cardPadding
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// The lock badge on Pro-only rows.
struct ProBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill")
            Text("Recharge+")
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Theme.pro.opacity(0.15), in: Capsule())
        .foregroundStyle(Theme.pro)
    }
}
