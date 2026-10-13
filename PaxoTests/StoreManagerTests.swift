import StoreKit
import Testing

@testable import Paxo

@MainActor
struct StoreManagerTests {
    @Test("빈 상품 응답을 로딩 완료 후 오류로 표시한다")
    func reportsEmptyProductResponse() async {
        let manager = StoreManager(productLoader: { [] })

        await manager.loadProducts()

        #expect(manager.productLoadState == .unavailable)
        #expect(manager.products.isEmpty)
        #expect(manager.errorMessage == "App Store에서 가격 정보를 받지 못했습니다. 잠시 후 다시 시도해주세요.")
    }

    @Test("상품 조회 실패를 재시도 가능한 오류로 표시한다")
    func reportsProductLoadFailure() async {
        let manager = StoreManager(productLoader: { throw ProductLoadingTestError.failed })

        await manager.loadProducts()

        #expect(manager.productLoadState == .unavailable)
        #expect(manager.products.isEmpty)
        #expect(manager.errorMessage?.contains("가격 정보를 불러오지 못했습니다") == true)
    }

    @Test("복원 시 로컬 Pro 상태가 같아도 서버 권한을 다시 확인한다")
    func refreshesServerAfterRestoreWhenLocalTierIsUnchanged() async {
        let manager = StoreManager(productLoader: { [] })
        var refreshCount = 0
        manager.onEntitlementsChanged = { refreshCount += 1 }

        await manager.refreshEntitlements()
        await manager.refreshEntitlements(forceServerRefresh: true)

        #expect(refreshCount == 1)
    }
}

private enum ProductLoadingTestError: Error {
    case failed
}
