//
//  StoreManager.swift
//  withu (iOS)
//
//  StoreKit 2 인앱 결제 — 캔디 팩(consumable)만. 구독 없음(원가 손실 위험으로 제거).
//    - 구매 시 GenerationQuota.addCredits(n) → 만료 없는 캔디 적립.
//    - 로그인 상태면 서버 /iap/verify 로 계정 귀속(재설치에도 유지).
//
//  ⚠️ 상품 ID 는 App Store Connect 에 등록한 ID 와 정확히 일치해야 한다.
//  ⚠️ consumable 은 Apple 정책상 복원되지 않음 — 미로그인 적립 캔디는 기기 로컬에
//     남는다(앱 삭제 시 소실).
//

import Foundation
import StoreKit

@MainActor
@Observable
final class StoreManager {
    static let shared = StoreManager()

    // MARK: 상품 ID (App Store Connect 등록값과 일치)
    enum ProductID {
        static let credits10  = "com.seoyoung.withu.credits.10"
        static let credits30  = "com.seoyoung.withu.credits.30"
        static let credits50  = "com.seoyoung.withu.credits.50"
        // ⚠️ credits.100 은 예전에 사용돼 영구 소각된 ID — candy.100 으로 대체 (ASC 등록값)
        static let credits100 = "com.seoyoung.withu.candy.100"

        static let all: [String] = [credits10, credits30, credits50, credits100]
        /// consumable 상품 → 적립 캔디 수
        static let creditAmount: [String: Int] = [
            credits10: 10, credits30: 30, credits50: 50, credits100: 100,
        ]
        /// 팩 표시 이름 (미니 < 포켓 < 파우치 < 파티).
        static var packName: [String: String] { [
            credits10: String(localized: "미니 팩"), credits30: String(localized: "포켓 팩"),
            credits50: String(localized: "파우치 팩"), credits100: String(localized: "파티 팩"),
        ] }
    }

    private(set) var products: [Product] = []
    private(set) var didAttemptLoad = false   // 로드 시도 완료 여부 — 무한 로딩 방지
    private(set) var lastError: String?
    private(set) var isPurchasing = false

    /// 구매 상품 중 횟수 팩만 (정렬: 적은 것부터).
    var creditPacks: [Product] {
        products
            .filter { ProductID.creditAmount[$0.id] != nil }
            .sorted { ($0.price) < ($1.price) }
    }

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    private init() {}

    /// 앱 시작 시 1회 호출 — 상품 로드 + 트랜잭션 감시 시작.
    func start() {
        updatesTask = listenForTransactions()
        Task {
            await loadProducts()
        }
    }

    func loadProducts() async {
        do {
            // 시뮬레이터에서 StoreKit 구성 미연결이면 요청이 영영 안 돌아올 수 있음
            // (페이월이 '불러오는 중'으로 멈춘 듯 보임) → 10초 타임아웃으로 탈출.
            let ids = ProductID.all
            products = try await withThrowingTaskGroup(of: [Product].self) { group in
                group.addTask { try await Product.products(for: ids) }
                group.addTask {
                    try await Task.sleep(for: .seconds(10))
                    throw StoreError.timeout
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
            lastError = nil
        } catch {
            lastError = "상품 정보를 불러오지 못했어요."
        }
        didAttemptLoad = true
    }

    /// 구매. 성공 시 캔디 적립. 반환: 적립까지 성공했는지 —
    /// 호출부(페이월)가 성공일 때만 시트를 닫고, 취소/실패면 열어 둬 에러를 보여준다.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
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
                return true
            case .userCancelled:
                return false
            case .pending:
                lastError = "결제 승인을 기다리고 있어요."
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = "결제를 완료하지 못했어요. 다시 시도해 주세요."
            return false
        }
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
            }
        }
    }

    /// 적립까지 '완료'한 transactionId — UserDefaults 영속(append 순서 유지 배열).
    /// grant 도중(적립 전) 앱이 죽으면 여기 없음 → finish 도 안 됐으니 다음 실행 때
    /// Transaction.updates 로 재전달돼 재시도된다 (결제됐는데 영구 미적립 방지).
    private static let processedKey = "withu.iap.processedTransactionIds.v1"
    private var processedTransactionIds: [String] =
        UserDefaults.standard.stringArray(forKey: StoreManager.processedKey) ?? []
    /// 지금 grant 진행 중인 transactionId — purchase() 와 updates 리스너가 같은
    /// 트랜잭션을 동시에 들고 와도(Apple 문서화된 동작) 한쪽만 처리 (메모리만, 재시작 시 소멸).
    private var inFlightTransactionIds: Set<String> = []

    /// 적립 완료 영속 기록. 200개 초과 시 오래된 것(배열 앞)부터 버림.
    private func recordProcessed(_ transactionId: String) {
        processedTransactionIds.append(transactionId)
        if processedTransactionIds.count > 200 {
            processedTransactionIds.removeFirst(processedTransactionIds.count - 200)
        }
        UserDefaults.standard.set(processedTransactionIds, forKey: StoreManager.processedKey)
    }

    /// 검증된 트랜잭션에 따라 적립.
    /// 로그인 상태면 서버 권위(/iap/verify)로 — 크레딧이 계정에 귀속돼 재설치에도 유지.
    /// 로그인 전이면 로컬 fallback(점진).
    private func grant(for transaction: Transaction, jws: String) async {
        let txId = String(transaction.id)
        // 이미 적립 완료거나 다른 경로가 처리 중이면 skip (@MainActor 라 check-and-mark 원자적).
        guard !processedTransactionIds.contains(txId),
              !inFlightTransactionIds.contains(txId) else { return }
        inFlightTransactionIds.insert(txId)
        defer { inFlightTransactionIds.remove(txId) }

        if KeychainStore.sessionToken() != nil {
            if let ent = try? await APIClient.shared.verifyPurchase(
                signedTransaction: jws
            ) {
                AuthManager.shared.applyEntitlement(ent)
                recordProcessed(txId)   // 적립 '성공 후'에만 영속 — 도중 종료 시 재시도 가능
                return
            }
            // 서버 적립 실패 — 아래 로컬 fallback 으로 이 기기에는 적립됨(계정 귀속은 안 됨).
        }
        // 로그인 전 / 서버 실패 — 로컬 fallback
        if let amount = ProductID.creditAmount[transaction.productID] {
            GenerationQuota.addCredits(amount)
        }
        recordProcessed(txId)
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: Error { case failedVerification, timeout }
}
