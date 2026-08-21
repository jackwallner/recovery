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
                VStack(spacing: Theme.Space.xl) {
                    VStack(spacing: Theme.Space.xs) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.recovering)
                        Text("What's new")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.top, Theme.Space.lg)

                    VStack(spacing: Theme.Space.md) {
                        ForEach(WhatsNew.items) { item in
                            HStack(alignment: .top, spacing: Theme.Space.sm) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 19))
                                    .frame(width: 28)
                                    .foregroundStyle(Theme.recovering)
                                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
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
                                .padding(.vertical, Theme.Space.md)
                                .background(Theme.pro, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                                .foregroundStyle(.white)
                        }
                        .pressable()
                    }

                    Button("Continue") { dismiss() }
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, Theme.Space.xl)
                .padding(.bottom, Theme.Space.xl)
            }
            .background(Theme.background)
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: "whats_new")
                    .environmentObject(store)
            }
        }
    }
}
