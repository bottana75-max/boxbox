import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    var storeKit = StoreKitManager.shared

    private let packageDescriptions: [String: String] = [
        "com.bottana.racecall.credits3": "3 Race Calls",
        "com.bottana.racecall.credits10": "10 Race Calls",
        "com.bottana.racecall.credits25": "25 Race Calls"
    ]

    private let packageCaptions: [String: String] = [
        "com.bottana.racecall.credits3": "Best for trying a few extra calls",
        "com.bottana.racecall.credits10": "Best balance for active race weekends",
        "com.bottana.racecall.credits25": "Best value for heavy use across the season"
    ]

    private var sortedProducts: [Product] {
        storeKit.products.sorted { lhs, rhs in
            let order = StoreKitManager.productIDs
            return (order.firstIndex(of: lhs.id) ?? 99) < (order.firstIndex(of: rhs.id) ?? 99)
        }
    }

    private var purchaseStatusNote: String? {
        if let error = storeKit.purchaseError {
            return error
        }
        if storeKit.didAttemptProductLoad && storeKit.products.isEmpty {
            return "Race Call packs are not available right now."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.f1Red)

                    VStack(spacing: 8) {
                        Text("Get More Race Calls")
                            .font(.largeTitle)
                            .fontWeight(.black)
                            .foregroundStyle(.white)

                        Text("Your first Race Call is on us. Top up anytime with simple credit packs.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 12) {
                        featureRow(icon: "brain.head.profile", text: "AI-powered podium, dark horse and risk calls")
                        featureRow(icon: "chart.line.uptrend.xyaxis", text: "Race context, contender ranking and strategist-style output")
                        featureRow(icon: "cloud.sun.fill", text: "Weather, tyre and weekend scenario context where available")
                    }
                    .padding(.vertical, 4)

                    HStack(spacing: 10) {
                        F1StatPill(title: "Free", value: "1")
                        F1StatPill(title: "Left", value: "\(max(0, storeKit.credits))")
                        F1StatPill(title: "Model", value: "Credits")
                    }

                    VStack(spacing: 12) {
                        ForEach(sortedProducts, id: \.id) { product in
                            packCard(product)
                        }
                    }

                    if let purchaseStatusNote {
                        Label(purchaseStatusNote, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await storeKit.restorePurchases() }
                    } label: {
                        Text("Restore Purchases")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
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

    private func packCard(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(packageDescriptions[product.id] ?? product.displayName)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text(packageCaptions[product.id] ?? "Top up your Race Call balance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.title3)
                    .fontWeight(.black)
                    .foregroundStyle(Color.f1Red)
            }

            Button {
                Task { await storeKit.purchase(product) }
            } label: {
                Text("Buy \(packageDescriptions[product.id] ?? product.displayName)")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.f1Red)
        }
        .f1Card()
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
