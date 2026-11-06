import Foundation
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

    @Test("기존 구독 상태가 같아도 요청 시 서버 권한을 다시 확인한다")
    func refreshesServerAfterRestoreWhenLocalTierIsUnchanged() async {
        let manager = StoreManager(productLoader: { [] })
        var refreshCount = 0
        manager.onEntitlementsChanged = { refreshCount += 1 }

        await manager.refreshEntitlements()
        await manager.refreshEntitlements(forceServerRefresh: true)

        #expect(refreshCount == 1)
    }

    @Test("서버 적립을 확인한 뒤에만 거래를 완료한다")
    func finishesOnlyAfterServerDelivery() async throws {
        let manager = StoreManager(productLoader: { [] })
        manager.updateAccount(creditBalance: 0, isSignedIn: true)
        var events: [String] = []
        manager.redeemPurchase = { jws in
            #expect(jws == "signed-purchase")
            events.append("redeem")
            return CreditBalance(creditBalance: 30, creditRevision: 1)
        }

        try await manager.deliverPurchase(transactionID: 1, signedTransactionInfo: "signed-purchase") {
            #expect(manager.creditBalance == 30)
            events.append("finish")
        }

        #expect(events == ["redeem", "finish"])
        #expect(manager.creditBalance == 30)
    }

    @Test("서버 적립 실패 시 거래를 미완료로 남기고 재시도 후에 완료한다")
    func preservesFailedTransactionForRetry() async throws {
        let manager = StoreManager(productLoader: { [] })
        manager.updateAccount(creditBalance: 0, isSignedIn: true)
        var finishCount = 0
        manager.redeemPurchase = { _ in throw ProxySessionError.serviceUnavailable }

        await #expect(throws: ProxySessionError.self) {
            try await manager.deliverPurchase(transactionID: 2, signedTransactionInfo: "signed-purchase") {
                finishCount += 1
            }
        }
        #expect(finishCount == 0)
        #expect(manager.creditBalance == 0)

        manager.redeemPurchase = { _ in CreditBalance(creditBalance: 100, creditRevision: 1) }
        try await manager.deliverPurchase(transactionID: 2, signedTransactionInfo: "signed-purchase") {
            finishCount += 1
        }
        #expect(finishCount == 1)
        #expect(manager.creditBalance == 100)
    }

    @Test("로그인 연결이 없는 거래를 임의로 완료하지 않는다")
    func requiresServerDeliveryConnection() async {
        let manager = StoreManager(productLoader: { [] })
        var finished = false
        await #expect(throws: ProxySessionError.self) {
            try await manager.deliverPurchase(transactionID: 3, signedTransactionInfo: "signed-purchase") {
                finished = true
            }
        }
        #expect(!finished)
    }

    @Test("충전 내역 확인은 서버 잔액을 반영한다")
    func refreshesWalletWithoutGrantingLocalEntitlements() async {
        let manager = StoreManager(productLoader: { [] })
        manager.updateAccount(creditBalance: 0, isSignedIn: true)
        manager.refreshBalance = { CreditBalance(creditBalance: 500, creditRevision: 1) }

        await manager.restore()

        #expect(manager.creditBalance == 500)
        #expect(!manager.purchaseInFlight)
    }

    @Test("로그아웃 뒤 도착한 적립 응답은 거래만 완료하고 잔액을 표시하지 않는다")
    func doesNotApplyDeliveryToAnotherAccount() async throws {
        let manager = StoreManager(productLoader: { [] })
        manager.updateAccount(creditBalance: 10, creditRevision: 2, isSignedIn: true)
        var finished = false
        manager.redeemPurchase = { _ in
            manager.updateAccount(creditBalance: 0, isSignedIn: false)
            manager.updateAccount(creditBalance: 3, creditRevision: 1, isSignedIn: true)
            return CreditBalance(creditBalance: 40, creditRevision: 3)
        }

        try await manager.deliverPurchase(transactionID: 4, signedTransactionInfo: "signed-purchase") {
            finished = true
        }

        #expect(finished)
        #expect(manager.creditBalance == 3)
        #expect(manager.creditRevision == 1)
    }

    @Test("늦게 도착한 이전 잔액은 충전 후 잔액을 덮어쓰지 않는다")
    func ignoresOlderWalletRevisions() async throws {
        let manager = StoreManager(productLoader: { [] })
        manager.updateAccount(creditBalance: 129, creditRevision: 3, isSignedIn: true)
        manager.updateAccount(creditBalance: 99, creditRevision: 2, isSignedIn: true)
        #expect(manager.creditBalance == 129)
        manager.redeemPurchase = { _ in CreditBalance(creditBalance: 100, creditRevision: 1) }
        var finished = false

        try await manager.deliverPurchase(transactionID: 5, signedTransactionInfo: "signed-purchase") {
            finished = true
        }

        #expect(finished)
        #expect(manager.creditBalance == 129)
        #expect(manager.creditRevision == 3)
    }

    @Test("잔액 새로고침 중 계정을 바꾸면 이전 계정의 잔액을 버린다")
    func discardsRefreshForPreviousAccount() async {
        let manager = StoreManager(productLoader: { [] })
        manager.updateAccount(creditBalance: 10, creditRevision: 2, isSignedIn: true)
        manager.refreshBalance = {
            manager.updateAccount(creditBalance: 0, isSignedIn: false)
            return CreditBalance(creditBalance: 500, creditRevision: 3)
        }

        await manager.restore()

        #expect(manager.creditBalance == 0)
        #expect(!manager.isSignedIn)
    }

    @Test("환경 전환 시 잔액 버전을 분리하고 다른 환경의 적립 응답은 표시하지 않는다")
    func separatesWalletRevisionsByEnvironment() async throws {
        let manager = StoreManager(productLoader: { [] })
        manager.updateAccount(creditBalance: 129, creditRevision: 30, isSignedIn: true)
        manager.updateAccount(creditBalance: 5, creditRevision: 1, storeEnvironment: "Sandbox", isSignedIn: true)
        #expect(manager.creditBalance == 5)
        #expect(manager.creditRevision == 1)
        manager.redeemPurchase = { _ in CreditBalance(creditBalance: 1_000, creditRevision: 31) }
        var finished = false

        try await manager.deliverPurchase(transactionID: 6, signedTransactionInfo: "signed-purchase") {
            finished = true
        }

        #expect(finished)
        #expect(manager.storeEnvironment == "Sandbox")
        #expect(manager.creditBalance == 5)
        #expect(manager.creditRevision == 1)
    }

}

private enum ProductLoadingTestError: Error {
    case failed
}
