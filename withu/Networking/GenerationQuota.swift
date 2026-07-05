//
//  GenerationQuota.swift
//  withu (iOS)
//
//  AI 생성 횟수 관리.
//    1) 무료 하루 한도 (freeDailyLimit)        — 0 (무료 없음, 캔디로만 생성)
//    2) 구독자 하루 한도 (subscriberDailyLimit) — 구독 활성 시, 매일 리셋
//    3) 충전 크레딧 = 캔디 (credits)            — 캔디 팩 구매분, 만료 없음
//
//  소비 우선순위: 오늘의 (구독) 한도 → 그 다음 캔디.
//
//  ⚠️ 클라이언트 측 저장(App Group UserDefaults). 진짜 비용 방어는 서버 rate limit +
//     OpenAI 대시보드 hard cap 이 담당. 신규 키만 추가 — 기존 스키마 불변.
//

import Foundation

enum GenerationQuota {
    /// 무료 사용자 하루 한도. 0 = 무료 없음 — 생성은 캔디(credits)로만.
    static let freeDailyLimit = 0
    /// 구독 사용자 하루 한도. (무제한으로 하려면 아주 큰 값.)
    static let subscriberDailyLimit = 100

    /// StoreManager 가 앱 시작/구매 시 갱신. true 면 구독 한도 적용.
    static var isSubscriber = false

    private static let countKey   = "withu.genQuota.count.v1"
    private static let dateKey    = "withu.genQuota.date.v1"    // yyyymmdd 정수
    private static let creditsKey = "withu.genQuota.credits.v1"
    /// 마지막으로 로컬에 반영한 서버 잔액 기준선 — 서버 잔액 '증가분'만 로컬에 더하기 위함.
    private static let lastSyncedServerCreditsKey = "withu.genQuota.lastSyncedServer.v1"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedAppState.groupID)
    }

    /// 오늘 날짜 yyyymmdd. 자정 넘으면 값이 바뀌어 일일 카운트 자동 리셋.
    private static func todayStamp(_ calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: Date())
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// 오늘의 한도 (구독 여부에 따라).
    static var dailyAllowance: Int {
        isSubscriber ? subscriberDailyLimit : freeDailyLimit
    }

    /// 오늘 일일 한도에서 사용한 횟수.
    static func usedToday() -> Int {
        guard let d = defaults else { return 0 }
        return d.integer(forKey: dateKey) == todayStamp() ? d.integer(forKey: countKey) : 0
    }

    /// 충전 크레딧 잔액 (만료 없음).
    static func credits() -> Int {
        defaults?.integer(forKey: creditsKey) ?? 0
    }

    /// 지금 더 만들 수 있는 총 횟수 = (오늘 남은 일일 한도) + 크레딧.
    static func remainingToday() -> Int {
        #if DEBUG
        return 9999   // 개발 빌드 — 무제한 테스트 (출시 빌드는 실제 한도)
        #else
        return max(0, dailyAllowance - usedToday()) + credits()
        #endif
    }

    /// n 회를 만들 수 있나.
    static func canGenerate(_ n: Int = 1) -> Bool {
        remainingToday() >= n
    }

    /// n 회 사용 기록. 오늘 한도부터 차감, 부족분은 크레딧에서.
    static func record(_ n: Int = 1) {
        #if DEBUG
        return   // 개발 빌드 — 차감 안 함 (무제한 테스트)
        #else
        guard let d = defaults, n > 0 else { return }
        let today = todayStamp()
        let usedBase = d.integer(forKey: dateKey) == today ? d.integer(forKey: countKey) : 0

        let dailyLeft = max(0, dailyAllowance - usedBase)
        let fromDaily = min(n, dailyLeft)
        let fromCredits = n - fromDaily

        d.set(today, forKey: dateKey)
        d.set(usedBase + fromDaily, forKey: countKey)
        if fromCredits > 0 {
            d.set(max(0, credits() - fromCredits), forKey: creditsKey)
        }
        #endif
    }

    /// 퀄리티별 캔디 비용 — 낮음 1 · 보통 2 · 높음 3.
    static func cost(forQuality quality: String) -> Int {
        switch quality {
        case "high":   return 3
        case "medium": return 2
        default:       return 1   // low
        }
    }

    /// 횟수 팩 구매 시 크레딧 적립.
    static func addCredits(_ n: Int) {
        guard let d = defaults, n > 0 else { return }
        d.set(credits() + n, forKey: creditsKey)
    }

    /// 서버 잔액(entitlement.credits)을 로컬에 반영.
    /// 서버는 /generate 로 캔디를 차감하지 않으므로(로컬 권위) 서버 잔액은 '누적 적립 총액'.
    /// 따라서 절대값으로 덮어쓰면 로컬 차감이 재실행/새로고침마다 되돌아온다(캔디 안 닳는 버그).
    /// → 서버 잔액이 '증가한 만큼(새 구매/적립분)'만 로컬에 더한다.
    static func syncCreditsUp(to serverCredits: Int) {
        guard let d = defaults else { return }
        if d.object(forKey: lastSyncedServerCreditsKey) == nil {
            // 최초 동기화: 서버 적립을 한 번 끌어옴(신규 로그인 대비). 이후엔 증가분만.
            if serverCredits > credits() { d.set(serverCredits, forKey: creditsKey) }
            d.set(serverCredits, forKey: lastSyncedServerCreditsKey)
            return
        }
        let lastSynced = d.integer(forKey: lastSyncedServerCreditsKey)
        let delta = serverCredits - lastSynced
        if delta > 0 {
            d.set(credits() + delta, forKey: creditsKey)   // 새로 적립된 만큼만 더함
        }
        d.set(serverCredits, forKey: lastSyncedServerCreditsKey)
    }

    /// 화면 표시용 보유 캔디 = 실제로 쓸 수 있는 로컬 잔액(credits).
    /// canGenerate 가 로컬 credits 만 보므로, 배지도 같은 값을 보여 과대표시(쓸 수 없는데 숫자만 큼)를 막는다.
    /// 서버 적립분은 syncCreditsUp 으로 이미 로컬에 반영됨.
    static func displayedCandy() -> Int {
        credits()
    }

    // MARK: - 테스트 캔디 코드 (TestFlight/샌드박스 전용)

    /// 입력하면 +20 캔디(로컬). 운영 App Store 빌드에서는 동작 안 함 → 무료 캔디 악용 방지.
    static let testCandyCode = "CANDY20"
    static let testCandyAmount = 20

    /// 테스트 캔디 코드 허용 여부. App Store 운영 빌드(receipt)는 false, TestFlight/샌드박스(sandboxReceipt)·DEBUG 만 true.
    static var allowsTestCandyCode: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
