import StoreKit

@MainActor @Observable
final class SubscriptionService {
    static let productID = "com.hao.doushan.pro.lifetime"

    var isPro: Bool = false
    var product: Product?
    var purchaseError: String?
    var isLoading = false

    nonisolated(unsafe) private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
        Task { await checkSubscriptionStatus() }
    }

    nonisolated deinit {
        transactionListener?.cancel()
    }

    func loadProduct() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await Product.products(for: [Self.productID])
            product = fetched.first
        } catch {
            purchaseError = String(localized: "无法加载产品信息")
        }
    }

    func purchase(_ product: Product) async throws {
        purchaseError = nil
        isLoading = true
        defer { isLoading = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await checkSubscriptionStatus()
        case .userCancelled:
            break
        case .pending:
            purchaseError = String(localized: "购买待确认")
        @unknown default:
            break
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        try? await AppStore.sync()
        await checkSubscriptionStatus()
    }

    func checkSubscriptionStatus() async {
        var hasPro = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                if transaction.productID == Self.productID {
                    hasPro = true
                }
            }
        }
        isPro = hasPro
    }

    func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                let transaction: Transaction? = switch result {
                case .verified(let t): t
                case .unverified: nil
                }
                if let transaction {
                    await transaction.finish()
                    await self?.checkSubscriptionStatus()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: LocalizedError {
        case verificationFailed
        var errorDescription: String? { String(localized: "交易验证失败") }
    }
}
