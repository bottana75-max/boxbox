import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    var storeKit = StoreKitManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.f1Red)

                Text("Unlock BoxBox Pro")
                    .font(.largeTitle)
                    .fontWeight(.black)
                    .foregroundStyle(.white)

                Text("Unlimited AI race predictions after your first 3 free shots")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    featureRow(icon: "brain.head.profile", text: "GPT-4o powered podium predictions")
                    featureRow(icon: "cloud.sun.fill", text: "Weekend context: timing, weather pressure and circuit cues")
                    featureRow(icon: "chart.line.uptrend.xyaxis", text: "Analysis using live standings, recent form and track profile")
                    featureRow(icon: "infinity", text: "Unlimited predictions all season")
                }
                .padding(.vertical)

                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        F1StatPill(title: "Used", value: "\(storeKit.predictionCount)")
                        F1StatPill(title: "Free left", value: "\(storeKit.remainingFreePredictions)")
                        F1StatPill(title: "Price", value: storeKit.product?.displayPrice ?? "$2.99")
                    }

                    Text(storeKit.paywallFootnote)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await storeKit.purchase() }
                } label: {
                    VStack(spacing: 4) {
                        Text(storeKit.paywallCTA)
                            .fontWeight(.bold)
                        Text(storeKit.product == nil ? "Placeholder paywall flow" : "One-time purchase")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.f1Red)

                Button {
                    Task { await storeKit.restorePurchases() }
                } label: {
                    Text("Restore Purchases")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let error = storeKit.purchaseError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding()
            .background(Color.f1Background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: storeKit.isProUnlocked) {
                if storeKit.isProUnlocked { dismiss() }
            }
        }
        .task {
            await storeKit.loadProduct()
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.f1Red)
                .frame(width: 32)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal)
    }
}

#Preview {
    PaywallView()
        .preferredColorScheme(.dark)
}
