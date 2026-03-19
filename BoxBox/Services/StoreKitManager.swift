import Foundation
import StoreKit

@MainActor
@Observable
class StoreKitManager {
    static let shared = StoreKitManager()

    private static let productID = "com.boxbox.unlock"
    private static let predictionCountKey = "prediction_count"
    private static let purchasedKey = "boxbox_pro_purchased"
    static let freeTrialLimit = 3

    var isProUnlocked = false
    var product: Product?
    var purchaseError: String?
    var didAttemptProductLoad = false

    var predictionCount: Int {
        UserDefaults.standard.integer(forKey: Self.predictionCountKey)
    }

    var remainingFreePredictions: Int {
        max(0, Self.freeTrialLimit - predictionCount)
    }

    var progressText: String {
        if isProUnlocked { return "Unlimited predictions unlocked" }
        return "\(predictionCount)/\(Self.freeTrialLimit) free predictions used"
    }

    var paywallCTA: String {
        product.map { "Unlock for \($0.displayPrice)" } ?? "Unlock BoxBox Pro"
    }

    var paywallFootnote: String {
        product == nil
            ? "StoreKit product not loaded yet. The paywall still shows the intended unlock flow so the UX doesn’t dead-end."
            : "One-time purchase. No subscription nonsense."
    }

    var canPredict: Bool {
        isProUnlocked || predictionCount < Self.freeTrialLimit
    }

    private init() {
        isProUnlocked = UserDefaults.standard.bool(forKey: Self.purchasedKey)
    }

    func loadProduct() async {
        didAttemptProductLoad = true
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
            if product == nil {
                purchaseError = "Pro purchase is configured as a placeholder until the App Store product is live."
            }
        } catch {
            purchaseError = "Could not load product. Showing placeholder paywall instead."
        }
    }

    func checkEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID {
                isProUnlocked = true
                UserDefaults.standard.set(true, forKey: Self.purchasedKey)
                return
            }
        }
    }

    func purchase() async {
        guard let product else {
            purchaseError = "StoreKit product not available yet. Keep the paywall copy and CTA; wire the product before release."
            return
        }

        purchaseError = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified = verification {
                    isProUnlocked = true
                    UserDefaults.standard.set(true, forKey: Self.purchasedKey)
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
        await checkEntitlements()
        if !isProUnlocked {
            purchaseError = "No previous purchase found."
        }
    }

    func incrementPredictionCount() {
        let current = UserDefaults.standard.integer(forKey: Self.predictionCountKey)
        UserDefaults.standard.set(current + 1, forKey: Self.predictionCountKey)
    }
}
