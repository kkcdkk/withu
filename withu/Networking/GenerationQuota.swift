//
//  GenerationQuota.swift
//  withu (iOS)
//
//  AI 생성 횟수 관리 — 3층 구조.
//    1) 무료 하루 한도 (freeDailyLimit)        — 매일 자정 리셋
//    2) 구독자 하루 한도 (subscriberDailyLimit) — 구독 활성 시 상향, 매일 리셋
//    3) 충전 크레딧 (credits)                   — 횟수 팩 구매분, 만료 없음, 일일 한도 소진 후 사용
//
//  소비 우선순위: 오늘의 (구독/무료) 한도 → 그 다음 충전 크레딧.
//
//  ⚠️ 클라이언트 측 저장(App Group UserDefaults). 진짜 비용 방어는 서버 rate limit +
//     OpenAI 대시보드 hard cap 이 담당. 신규 키만 추가 — 기존 스키마 불변.
//

import Foundation

enum GenerationQuota {
    /// 무료 사용자 하루 한도.
    static let freeDailyLimit = 10
    /// 구독 사용자 하루 한도. (무제한으로 하려면 아주 큰 값.)
    static let subscriberDailyLimit = 100

    /// StoreManager 가 앱 시작/구매 시 갱신. true 면 구독 한도 적용.
    static var isSubscriber = false

    private static let countKey   = "withu.genQuota.count.v1"
    private static let dateKey    = "withu.genQuota.date.v1"    // yyyymmdd 정수
    private static let creditsKey = "withu.genQuota.credits.v1"

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
        max(0, dailyAllowance - usedToday()) + credits()
    }

    /// n 회를 만들 수 있나.
    static func canGenerate(_ n: Int = 1) -> Bool {
        remainingToday() >= n
    }

    /// n 회 사용 기록. 오늘 한도부터 차감, 부족분은 크레딧에서.
    static func record(_ n: Int = 1) {
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
    }

    /// 횟수 팩 구매 시 크레딧 적립.
    static func addCredits(_ n: Int) {
        guard let d = defaults, n > 0 else { return }
        d.set(credits() + n, forKey: creditsKey)
    }
}
