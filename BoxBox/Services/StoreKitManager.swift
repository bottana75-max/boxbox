import Foundation
import StoreKit

@MainActor
@Observable
class StoreKitManager {
    static let shared = StoreKitManager()

    private static let creditsKey = "prediction_credits"
    private static let initializedKey = "prediction_credits_initialized"
    private static let unlimitedKey = "prediction_unlimited"
    private static let initialCredits = 3

    static let productIDs: [String] = [
        "com.bottana.boxbox.credits5",
        "com.bottana.boxbox.credits20",
        "com.bottana.boxbox.unlimited"
    ]

    var products: [Product] = []
    var purchaseError: String?
    var didAttemptProductLoad = false

    var credits: Int {
        UserDefaults.standard.integer(forKey: Self.creditsKey)
    }

    var isUnlimited: Bool {
        UserDefaults.standard.bool(forKey: Self.unlimitedKey)
    }

    var canPredict: Bool {
        isUnlimited || credits > 0
    }

    var creditsLabel: String {
        if isUnlimited { return "Unlimited" }
        return "\(credits) prediction\(credits == 1 ? "" : "s") remaining"
    }

    private init() {
        initializeCreditsIfNeeded()
    }

    private func initializeCreditsIfNeeded() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.initializedKey) {
            defaults.set(Self.initialCredits, forKey: Self.creditsKey)
            defaults.set(true, forKey: Self.initializedKey)
        }
    }

    func consumeCredit() {
        guard !isUnlimited else { return }
        let current = UserDefaults.standard.integer(forKey: Self.creditsKey)
        UserDefaults.standard.set(max(0, current - 1), forKey: Self.creditsKey)
    }

    func loadProducts() async {
        didAttemptProductLoad = true
        purchaseError = nil
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { a, b in
                Self.productIDs.firstIndex(of: a.id)! < Self.productIDs.firstIndex(of: b.id)!
            }
            if products.isEmpty {
                purchaseError = "Purchases are not available yet on this build."
            }
        } catch {
            purchaseError = "Could not reach the App Store right now. Please try again later."
        }
    }

    func purchase(_ product: Product) async {
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    applyCredits(for: transaction.productID)
                    await transaction.finish()
                } else {
                    purchaseError = "Purchase could not be verified. Please contact support."
                }
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed. Please try again later."
        }
    }

    func restorePurchases() async {
        purchaseError = nil
        var restored = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == "com.bottana.boxbox.unlimited" {
                    UserDefaults.standard.set(true, forKey: Self.unlimitedKey)
                    restored = true
                }
            }
        }
        if !restored {
            purchaseError = "No previous purchase found."
        }
    }

    private func applyCredits(for productID: String) {
        let defaults = UserDefaults.standard
        switch productID {
        case "com.bottana.boxbox.credits5":
            let current = defaults.integer(forKey: Self.creditsKey)
            defaults.set(current + 5, forKey: Self.creditsKey)
        case "com.bottana.boxbox.credits20":
            let current = defaults.integer(forKey: Self.creditsKey)
            defaults.set(current + 20, forKey: Self.creditsKey)
        case "com.bottana.boxbox.unlimited":
            defaults.set(true, forKey: Self.unlimitedKey)
        default:
            break
        }
    }
}
