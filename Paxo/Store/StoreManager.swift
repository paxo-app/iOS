import Combine
import Foundation
import StoreKit

enum StoreProducts {
    static let creditCounts = [30, 100, 500, 1_000]
    static let identifiers = creditCounts.map { "com.hyeseong.Paxo.credits.\($0)" }
    static let legacySubscriptionIdentifiers = [
        "com.hyeseong.Paxo.pro.monthly",
        "com.hyeseong.Paxo.pro.yearly",
    ]

    static func creditCount(for productID: String) -> Int? {
        guard let index = identifiers.firstIndex(of: productID) else { return nil }
        return creditCounts[index]
    }
}

enum ProductLoadState: Equatable {
    case idle
    case loading
    case loaded
    case unavailable
}

/// 결제 완료보다 서버 적립을 먼저 확정해 재실행 시에도 풀이권을 안전하게 전달한다.
@MainActor
final class StoreManager: ObservableObject {
    @Published private(set) var productLoadState: ProductLoadState = .idle
    @Published private(set) var products: [Product] = []
    @Published private(set) var creditBalance = 0
    @Published private(set) var creditRevision = 0
    @Published private(set) var storeEnvironment = "Production"
    @Published private(set) var isSignedIn = false
    @Published private(set) var purchaseInFlight = false
    @Published var errorMessage: String?

    var preparePurchase: (() async throws -> UUID)?
    var redeemPurchase: ((String) async throws -> CreditBalance)?
    var refreshBalance: (() async throws -> CreditBalance)?
    var onEntitlementsChanged: (() async -> Void)?
    private let productLoader: () async throws -> [Product]
    private var updatesTask: Task<Void, Never>?
    private var deliveringTransactions: Set<UInt64> = []
    private var hasLoadedEntitlements = false
    private var hasLegacySubscription = false
    private var accountRevision = 0

    init(
        productLoader: @escaping () async throws -> [Product] = {
            try await Product.products(for: StoreProducts.identifiers)
        }
    ) {
        self.productLoader = productLoader
    }

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.process(update)
            }
        }
        Task { [weak self] in
            await self?.loadProducts()
            await self?.retryPendingPurchases()
            await self?.refreshEntitlements()
        }
    }

    func updateAccount(
        creditBalance: Int, creditRevision: Int = 0, storeEnvironment: String = "Production", isSignedIn: Bool
    ) {
        if self.isSignedIn != isSignedIn {
            accountRevision &+= 1
            self.creditRevision = 0
        }
        if self.storeEnvironment != storeEnvironment { self.creditRevision = 0 }
        self.storeEnvironment = storeEnvironment
        self.isSignedIn = isSignedIn
        applyBalance(
            CreditBalance(
                creditBalance: creditBalance, creditRevision: creditRevision, storeEnvironment: storeEnvironment
            ))
    }

    func loadProducts() async {
        guard productLoadState != .loading else { return }
        productLoadState = .loading
        errorMessage = nil
        do {
            products = try await productLoader()
                .filter { StoreProducts.identifiers.contains($0.id) && $0.type == .consumable }
                .sorted { (StoreProducts.creditCount(for: $0.id) ?? 0) < (StoreProducts.creditCount(for: $1.id) ?? 0) }
            guard !products.isEmpty else {
                productLoadState = .unavailable
                errorMessage = "App Store에서 가격 정보를 받지 못했습니다. 잠시 후 다시 시도해주세요."
                return
            }
            productLoadState = .loaded
        } catch {
            products = []
            productLoadState = .unavailable
            errorMessage = "가격 정보를 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    func reloadProductsIfNeeded() async {
        guard products.isEmpty else { return }
        await loadProducts()
    }

    func refreshEntitlements(forceServerRefresh: Bool = false) async {
        var legacySubscription = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
                StoreProducts.legacySubscriptionIdentifiers.contains(transaction.productID),
                transaction.revocationDate == nil
            {
                legacySubscription = true
            }
        }
        if forceServerRefresh || (hasLoadedEntitlements && hasLegacySubscription != legacySubscription) {
            await onEntitlementsChanged?()
        }
        hasLegacySubscription = legacySubscription
        hasLoadedEntitlements = true
    }

    func purchase(_ product: Product) async {
        guard !purchaseInFlight else { return }
        guard StoreProducts.identifiers.contains(product.id), product.type == .consumable else { return }
        purchaseInFlight = true
        errorMessage = nil
        let revision = accountRevision
        defer { purchaseInFlight = false }

        do {
            guard let preparePurchase else { throw ProxySessionError.signInRequired }
            let accountToken = try await preparePurchase()
            guard revision == accountRevision, isSignedIn else { return }
            let result = try await product.purchase(options: [.appAccountToken(accountToken)])
            switch result {
            case .success(let verification):
                try await deliver(verification)
            case .pending:
                errorMessage = "구매 승인 대기 중입니다. 승인이 완료되면 풀이권이 적립돼요."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            guard revision == accountRevision else { return }
            errorMessage = "충전을 완료하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func retryPendingPurchases() async {
        for await verification in Transaction.unfinished {
            await process(verification)
        }
    }

    func restore() async {
        guard !purchaseInFlight else { return }
        purchaseInFlight = true
        errorMessage = nil
        defer { purchaseInFlight = false }
        let revision = accountRevision
        await retryPendingPurchases()
        do {
            guard let refreshBalance else { throw ProxySessionError.signInRequired }
            let balance = try await refreshBalance()
            guard revision == accountRevision, isSignedIn else { return }
            applyBalance(balance)
        } catch {
            guard revision == accountRevision else { return }
            errorMessage = "충전 내역을 확인하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func deliverPurchase(
        transactionID: UInt64,
        signedTransactionInfo: String,
        finish: () async -> Void
    ) async throws {
        guard deliveringTransactions.insert(transactionID).inserted else { return }
        defer { deliveringTransactions.remove(transactionID) }
        guard let redeemPurchase else { throw ProxySessionError.signInRequired }
        let revision = accountRevision
        let balance = try await redeemPurchase(signedTransactionInfo)
        if revision == accountRevision, isSignedIn {
            applyBalance(balance)
            errorMessage = nil
        }
        await finish()
    }

    private func applyBalance(_ balance: CreditBalance) {
        guard balance.storeEnvironment == storeEnvironment, balance.creditRevision >= creditRevision else { return }
        creditBalance = max(0, balance.creditBalance)
        creditRevision = balance.creditRevision
    }

    private func process(_ verification: VerificationResult<Transaction>) async {
        let revision = accountRevision
        do {
            try await deliver(verification)
        } catch {
            guard revision == accountRevision else { return }
            errorMessage = "결제 확인을 완료하지 못했습니다. 로그인 후 '잔액 새로고침'을 눌러주세요. \(error.localizedDescription)"
        }
    }

    private func deliver(_ verification: VerificationResult<Transaction>) async throws {
        guard case .verified(let transaction) = verification else {
            throw StorePurchaseError.unverified
        }
        if StoreProducts.legacySubscriptionIdentifiers.contains(transaction.productID) {
            await refreshEntitlements(forceServerRefresh: true)
            await transaction.finish()
            return
        }
        guard StoreProducts.identifiers.contains(transaction.productID), transaction.productType == .consumable else {
            return
        }
        try await deliverPurchase(
            transactionID: transaction.id,
            signedTransactionInfo: verification.jwsRepresentation,
            finish: { await transaction.finish() }
        )
    }
}

private enum StorePurchaseError: LocalizedError {
    case unverified

    var errorDescription: String? {
        "App Store 거래를 확인하지 못했습니다. 잠시 후 충전 내역을 다시 확인해주세요."
    }
}
