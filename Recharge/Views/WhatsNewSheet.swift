import SwiftUI

/// The one-time announcement after an update. Purely an awareness surface —
/// nothing it mentions changes behaviour until the user turns it on.
struct WhatsNewSheet: View {
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.recovering)
                        Text("What's new")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.top, 20)

                    VStack(spacing: 16) {
                        ForEach(WhatsNew.items) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 19))
                                    .frame(width: 28)
                                    .foregroundStyle(Theme.recovering)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(item.detail)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    if !store.isPro {
                        Button { showPaywall = true } label: {
                            Text(RechargeConversionCopy.shortCTALabel(eligibleForTrial: store.canPitchFreeTrial))
                                .font(.system(.headline, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(Theme.pro, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Continue") { dismiss() }
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: "whats_new")
                    .environmentObject(store)
            }
        }
    }
}
