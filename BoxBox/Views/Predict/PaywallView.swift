import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    var storeKit = StoreKitManager.shared

    private var featuredProduct: Product? {
        storeKit.products.first { $0.id == "com.bottana.boxbox.unlimited" } ?? storeKit.products.last ?? storeKit.products.first
    }

    private var usedPredictions: Int {
        max(0, 3 - storeKit.credits)
    }

    private var freeLeft: Int {
        storeKit.isUnlimited ? 0 : max(0, storeKit.credits)
    }

    private var priceLabel: String {
        featuredProduct?.displayPrice ?? "—"
    }

    private var paywallFootnote: String {
        if storeKit.isUnlimited {
            return "BoxBox Pro unlocked. Unlimited predictions are active on this device."
        }
        if featuredProduct == nil {
            return "Purchases are temporarily unavailable on this build. You can still restore previous purchases."
        }
        return "One-time unlock for unlimited AI predictions. No subscription."
    }

    private var purchaseStatusNote: String? {
        if let error = storeKit.purchaseError {
            return error
        }
        if storeKit.didAttemptProductLoad && storeKit.products.isEmpty {
            return "The App Store product is not available right now."
        }
        return nil
    }

    private var paywallCTA: String {
        if storeKit.isUnlimited { return "BoxBox Pro Unlocked" }
        if featuredProduct == nil { return "Unlock Unavailable" }
        return "Unlock BoxBox Pro"
    }

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
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 12) {
                    featureRow(icon: "brain.head.profile", text: "AI-powered podium predictions")
                    featureRow(icon: "cloud.sun.fill", text: "Weekend context: timing, weather pressure and circuit cues")
                    featureRow(icon: "chart.line.uptrend.xyaxis", text: "Analysis using standings, recent form and track profile")
                    featureRow(icon: "infinity", text: "Unlimited predictions all season")
                }
                .padding(.vertical)

                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        F1StatPill(title: "Used", value: "\(usedPredictions)")
                        F1StatPill(title: "Free left", value: "\(freeLeft)")
                        F1StatPill(title: "Price", value: priceLabel)
                    }

                    Text(paywallFootnote)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    if let purchaseStatusNote {
                        Label(purchaseStatusNote, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Button {
                    guard let featuredProduct else { return }
                    Task { await storeKit.purchase(featuredProduct) }
                } label: {
                    VStack(spacing: 4) {
                        Text(paywallCTA)
                            .fontWeight(.bold)
                        Text(storeKit.isUnlimited ? "Ready to race" : "Unlock once, predict all season")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.f1Red)
                .disabled(featuredProduct == nil || storeKit.isUnlimited)
                .opacity((featuredProduct == nil || storeKit.isUnlimited) ? 0.7 : 1)

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
        }
        .task {
            await storeKit.loadProducts()
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
