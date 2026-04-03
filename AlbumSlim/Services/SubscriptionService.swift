import StoreKit

@MainActor @Observable
final class SubscriptionService {
    static let monthlyID = "com.huge.albumslim.pro.monthly"
    static let yearlyID = "com.huge.albumslim.pro.yearly"
    static let lifetimeID = "com.huge.albumslim.pro.lifetime"

    private static let allProductIDs: Set<String> = [monthlyID, yearlyID, lifetimeID]

    var isPro: Bool = false
    var products: [Product] = []
    var purchaseError: String?
    var isLoading = false

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
        Task { await checkSubscriptionStatus() }
    }

    nonisolated deinit {
        // transactionListener will be cancelled when Task is deallocated
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await Product.products(for: Self.allProductIDs)
            products = fetched.sorted { a, b in
                a.price < b.price
            }
        } catch {
            purchaseError = "无法加载产品信息"
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
            purchaseError = "购买待确认"
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
                if Self.allProductIDs.contains(transaction.productID) {
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
        var errorDescription: String? { "交易验证失败" }
    }
}
