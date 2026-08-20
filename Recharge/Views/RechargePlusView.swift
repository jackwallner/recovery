import SwiftUI

/// The third tab, once it has been paid for.
///
/// The tab is the paywall before purchase and this after it, which is the Vitals
/// arrangement and the reason it works: the thing somebody bought keeps a place
/// in the navigation instead of dissolving into settings rows they will never
/// find. It answers one question — what is this doing for me — in the order
/// somebody would ask it: what your number is, what it is built on, and what
/// Recharge has actually read to build it.
struct RechargePlusView: View {
    @EnvironmentObject private var settings: RechargeSettings
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var engine: RecoveryEngine

    @State private var isRestoring = false
    @State private var restoreMessage: String?

    private var analysis: PersonalRecoveryModel.Analysis { engine.personalAnalysis }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    comparisonCard
                    if !analysisLines.isEmpty { analysisCard }
                    loadCard
                    if !engine.healthIngest.isEmpty { ingestCard }
                    accountCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle(RechargeConversionCopy.proName)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await engine.refresh(force: true) }
            .alert(
                RechargeConversionCopy.proName,
                isPresented: Binding(
                    get: { restoreMessage != nil },
                    set: { if !$0 { restoreMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreMessage ?? "")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.pro)
                    .frame(width: 48, height: 48)
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(RechargeConversionCopy.proName) active")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your countdowns are measured, not looked up.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    // MARK: - The comparison

    /// The same two figures Today shows under a blur for everyone else, with
    /// nothing hidden. It is the receipt for the purchase, so it is the first
    /// thing on the page.
    private var comparisonCard: some View {
        let preview = engine.personalizedPreview
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(preview.isExample ? "A hard 60-minute session" : preview.label)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                HStack(alignment: .center, spacing: 16) {
                    figure("Average", CountdownFormat.hours(preview.standardHours), Theme.textSecondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                    figure("Yours", CountdownFormat.hours(preview.personalizedHours), Theme.pro)
                    Spacer(minLength: 0)
                }

                Text(preview.isExample
                     ? "An example on the real curve until you have recorded a qualifying session. The arithmetic is the same one your own sessions get."
                     : "The standard estimate for your training level, beside the one measured from your own history.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func figure(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(Theme.bigNumber(30))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - What moved the number

    private var analysisLines: [String] { PersonalRecoveryModel.summary(analysis) }

    private var analysisCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("What your last \(PersonalRecoveryModel.windowDays) days show")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    Text(factorLabel)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.pro)
                }
                ForEach(analysisLines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Theme.textTertiary)
                            .frame(width: 4, height: 4)
                            .padding(.top, 7)
                        Text(line)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var factorLabel: String {
        let percent = analysis.percentDifference
        if percent == 0 { return "Same as standard" }
        return percent > 0 ? "+\(percent)%" : "\(percent)%"
    }

    // MARK: - Training load

    private var loadCard: some View {
        let balance = engine.loadBalance()
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Training load")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 20) {
                    figure("This week", "\(Int(balance.acute.rounded()))", Theme.textPrimary)
                    figure("4-week avg", "\(Int(balance.chronic.rounded()))", Theme.textSecondary)
                    Spacer(minLength: 0)
                }
                Text("Load is a proxy built from your own sessions, not a measurement.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: - The receipt

    /// Everything Health handed over, printed back.
    ///
    /// It is on this page rather than only in onboarding because the permission
    /// sheet is a one-off and the reading is continuous: somebody who granted
    /// eleven types six weeks ago is entitled to see, without leaving the app,
    /// that all eleven are still being used for something.
    private var ingestCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Read from Apple Health")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Everything below is going into your estimate.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                HealthIngestList(summary: engine.healthIngest)
            }
        }
    }

    // MARK: - Account

    private var accountCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Account")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Button {
                    guard !isRestoring else { return }
                    isRestoring = true
                    Task {
                        defer { isRestoring = false }
                        await store.restorePurchases()
                        restoreMessage = store.lastError
                            ?? "Your \(RechargeConversionCopy.proName) purchase is active."
                    }
                } label: {
                    HStack {
                        Text(isRestoring ? "Restoring…" : "Restore purchases")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.pro)
                        Spacer()
                        if isRestoring { ProgressView() }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isRestoring)

                Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                    Text("Manage subscription")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.pro)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// The ingest rows, laid out once. Three surfaces show this list — onboarding,
/// the Recharge+ tab, and Settings — and they must not drift apart, because all
/// three are making the same argument to the same person at different moments.
struct HealthIngestList: View {
    let summary: HealthIngestSummary
    var showsDetail = true
    /// How many rows to draw. The trial page has a price block under it that
    /// must not be pushed off the screen, so it takes the first few and says how
    /// many it left out.
    var limit: Int?

    private var rows: [HealthIngestSummary.Row] {
        guard let limit else { return summary.rows }
        return Array(summary.rows.prefix(limit))
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: row.symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.pro)
                        .frame(width: 22)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.title)
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: 0)
                            Text(row.value)
                                .font(.system(.footnote, design: .rounded, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                        }
                        if showsDetail {
                            Text(row.detail)
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
