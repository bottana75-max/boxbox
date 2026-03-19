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

    var predictionCount: Int {
        UserDefaults.standard.integer(forKey: Self.predictionCountKey)
    }

    var remainingFreePredictions: Int {
        max(0, Self.freeTrialLimit - predictionCount)
    }

    var canPredict: Bool {
        isProUnlocked || predictionCount < Self.freeTrialLimit
    }

    private init() {
        isProUnlocked = UserDefaults.standard.bool(forKey: Self.purchasedKey)
    }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            purchaseError = "Could not load product. Please try again later."
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
            purchaseError = "Product not available. Please try again later."
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
