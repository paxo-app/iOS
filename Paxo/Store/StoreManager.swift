import Combine
import Foundation
import StoreKit

/// StoreKit 2 구독 관리.
/// - 로컬 테스트: Config/Paxo.storekit (스킴 → Run → Options → StoreKit Configuration에서 선택)
/// - 출시 전: App Store Connect에 동일한 product ID로 구독 상품 생성 필요
@MainActor
final class StoreManager: ObservableObject {
    static let productIDs = [
        "com.hyeseong.Paxo.pro.monthly",
        "com.hyeseong.Paxo.pro.yearly",
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro = false
    @Published private(set) var purchaseInFlight = false
    @Published var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    func start() {
        // 앱 실행 중 들어오는 트랜잭션(갱신, 환불, 다른 기기 구매 등) 반영
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { $0.price < $1.price }
        } catch {
            products = []
            errorMessage = "가격 정보를 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        var pro = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
                Self.productIDs.contains(transaction.productID),
                transaction.revocationDate == nil
            {
                pro = true
            }
        }
        isPro = pro
    }

    func purchase(_ product: Product) async {
        guard !purchaseInFlight else { return }
        purchaseInFlight = true
        errorMessage = nil
        defer { purchaseInFlight = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlements()
                case .unverified:
                    errorMessage = "구매를 확인하지 못했습니다. 잠시 후 '구매 복원'을 눌러주세요."
                }
            case .pending:
                // 가족 승인 요청(Ask to Buy) 등 — 승인되면 Transaction.updates가 자동 반영
                errorMessage = "구매 승인 대기 중입니다. 승인이 완료되면 자동으로 적용돼요."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "구매에 실패했습니다: \(error.localizedDescription)"
        }
    }

    func restore() async {
        errorMessage = nil
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = "복원에 실패했습니다: \(error.localizedDescription)"
        }
        await refreshEntitlements()
    }
}
