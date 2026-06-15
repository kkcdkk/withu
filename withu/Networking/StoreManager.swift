//
//  StoreManager.swift
//  withu (iOS)
//
//  StoreKit 2 인앱 결제.
//    - 구독(auto-renewable): 활성 시 GenerationQuota.isSubscriber = true → 하루 한도 상향
//    - 횟수 팩(consumable): 구매 시 GenerationQuota.addCredits(n) → 만료 없는 크레딧 적립
//
//  ⚠️ 상품 ID 는 App Store Connect 에 등록한 ID 와 정확히 일치해야 한다.
//  ⚠️ consumable 은 Apple 정책상 복원되지 않음 — 적립 크레딧은 기기 로컬에 남는다
//     (앱 삭제 시 소실). 구독은 currentEntitlements 로 복원됨.
//

import Foundation
import StoreKit

@MainActor
@Observable
final class StoreManager {
    static let shared = StoreManager()

    // MARK: 상품 ID (App Store Connect 등록값과 일치)
    enum ProductID {
        static let credits30  = "com.seoyoung.withu.credits.30"
        static let credits100 = "com.seoyoung.withu.credits.100"
        static let monthlySub = "com.seoyoung.withu.subscription.monthly"

        static let all: [String] = [credits30, credits100, monthlySub]
        /// consumable 상품 → 적립 횟수
        static let creditAmount: [String: Int] = [credits30: 30, credits100: 100]
    }

    private(set) var products: [Product] = []
    private(set) var isSubscriber = false
    private(set) var lastError: String?
    private(set) var isPurchasing = false

    /// 구매 상품 중 횟수 팩만 (정렬: 적은 것부터).
    var creditPacks: [Product] {
        products
            .filter { ProductID.creditAmount[$0.id] != nil }
            .sorted { ($0.price) < ($1.price) }
    }

    /// 구독 상품.
    var subscription: Product? {
        products.first { $0.id == ProductID.monthlySub }
    }

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    private init() {}

    /// 앱 시작 시 1회 호출 — 상품 로드 + 구독 상태 동기화 + 트랜잭션 감시 시작.
    func start() {
        updatesTask = listenForTransactions()
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: ProductID.all)
            lastError = nil
        } catch {
            lastError = "상품 정보를 불러오지 못했어요."
        }
    }

    /// 구매. 성공 시 크레딧 적립 또는 구독 활성화.
    func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await grant(for: transaction, jws: verification.jwsRepresentation)
                await transaction.finish()
                lastError = nil
            case .userCancelled:
                break
            case .pending:
                lastError = "결제 승인을 기다리고 있어요."
            @unknown default:
                break
            }
        } catch {
            lastError = "결제를 완료하지 못했어요. 다시 시도해 주세요."
        }
    }

    /// 구매 복원 (구독). 횟수 팩은 consumable 이라 복원 대상 아님.
    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            lastError = nil
        } catch {
            lastError = "복원하지 못했어요. 다시 시도해 주세요."
        }
    }

    /// 현재 유효한 권리 확인 → 구독 상태 갱신.
    func refreshEntitlements() async {
        var subscribed = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == ProductID.monthlySub, transaction.revocationDate == nil {
                subscribed = true
            }
        }
        isSubscriber = subscribed
        GenerationQuota.isSubscriber = subscribed
    }

    // MARK: - Private

    /// 백그라운드 트랜잭션(가족 공유, 환불, 다른 기기 구매 등) 감시.
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { continue }
                guard let transaction = try? await self.checkVerified(result) else { continue }
                await self.grant(for: transaction, jws: result.jwsRepresentation)
                await transaction.finish()
                await self.refreshEntitlements()
            }
        }
    }

    /// 검증된 트랜잭션에 따라 적립.
    /// 로그인 상태면 서버 권위(/iap/verify)로 — 크레딧이 계정에 귀속돼 재설치에도 유지.
    /// 로그인 전이면 로컬 fallback(점진).
    private func grant(for transaction: Transaction, jws: String) async {
        if KeychainStore.sessionToken() != nil {
            if let ent = try? await APIClient.shared.verifyPurchase(
                signedTransaction: jws
            ) {
                AuthManager.shared.applyEntitlement(ent)
                isSubscriber = ent.subActive
                GenerationQuota.isSubscriber = ent.subActive
                return
            }
            // 서버 적립 실패 — 다음 앱 시작 시 currentEntitlements 재전송으로 복구 시도
        }
        // 로그인 전 / 서버 실패 — 로컬 fallback
        if let amount = ProductID.creditAmount[transaction.productID] {
            GenerationQuota.addCredits(amount)
        } else if transaction.productID == ProductID.monthlySub {
            await refreshEntitlements()
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: Error { case failedVerification }
}
