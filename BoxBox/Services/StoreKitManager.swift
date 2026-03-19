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

    var progressValue: Double {
        if isProUnlocked { return 1 }
        return min(1, Double(predictionCount) / Double(Self.freeTrialLimit))
    }

    var paywallCTA: String {
        product.map { "Unlock for \($0.displayPrice)" } ?? "Unlock BoxBox Pro"
    }

    var paywallFootnote: String {
        if let product {
            return "One-time purchase for \(product.displayPrice). No subscription nonsense."
        }
        return "One-time purchase. Price appears automatically as soon as the App Store product is available."
    }

    var purchaseStatusNote: String? {
        guard didAttemptProductLoad, product == nil else { return nil }
        return "Purchases are temporarily unavailable on this build. You can still explore the prediction flow and restore if you’ve already bought Pro."
    }

    var canPredict: Bool {
        isProUnlocked || predictionCount < Self.freeTrialLimit
    }

    private init() {
        isProUnlocked = UserDefaults.standard.bool(forKey: Self.purchasedKey)
    }

    func loadProduct() async {
        didAttemptProductLoad = true
        purchaseError = nil
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
            if product == nil {
                purchaseError = "Purchases are not available yet on this build. Please try again later."
            }
        } catch {
            purchaseError = "Could not reach the App Store right now. Please try again later."
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
            purchaseError = "Purchases are not available right now. Please try again later."
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
