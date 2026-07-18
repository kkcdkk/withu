//
//  SharedAppState.swift
//  withu (Shared: iOS app + Watch app + Widget extension)
//
//  Target Membership 을 세 타겟 모두 (withu, withu Watch App, withuComplication)
//  체크해야 함.
//

import Foundation

/// App Group UserDefaults 를 감싸는 얇은 헬퍼.
/// 메인 앱과 위젯 extension 이 같은 컨테이너를 통해 캐릭터 상태를 공유.
enum SharedAppState {
    /// Xcode 의 Capabilities → App Groups 에서 등록한 그룹 ID 와 일치해야 함.
    static let groupID = "group.com.seoyoung.withu"

    private static let messageKey = "withu.currentMessage.v1"
    private static let scheduleKey = "withu.schedule.v1"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: groupID)
    }

    /// 프로필의 시간 창(수면/식사) 요약 — 위젯이 미래 시점 상태를 스스로 계산하게 App Group 에 공유.
    /// (CharacterProfile 은 위젯 타깃에 없어서 필요한 값만 평문 blob 으로 전달.)
    struct ScheduleInfo: Codable, Equatable, Sendable {
        let manualSleepOnly: Bool
        let sleepStartMin: Int
        let sleepEndMin: Int
        let lunchMin: Int
        let dinnerMin: Int
        /// '수면 모드 기준'인데 신호원이 없어 시간창으로 폴백 중인지 (앱이 계산해 넣음).
        var scheduleFallback: Bool = false
        /// 사용자가 '상태 직접 고르기'로 수동 override 중인지 — true 면 위젯은 스케줄 예측 대신 앱 상태 유지.
        var overrideActive: Bool = false

        /// 위젯이 시간 스케줄로 미래 상태를 예측해도 되는 경우 (설정 시간 기준/폴백 + override 아님).
        var usesSchedule: Bool { (manualSleepOnly || scheduleFallback) && !overrideActive }

        /// 시간·창만으로 결정되는 스케줄 상태(수면/기상/식사/idle).
        /// **CharacterStateResolver 규칙 2(수면)·3(기상)·4(식사)·5(idle) 와 동일하게 유지.**
        func scheduledState(at date: Date, calendar: Calendar = .current) -> CharacterState {
            let comps = calendar.dateComponents([.hour, .minute], from: date)
            let nowMin = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            if Self.inRange(nowMin, sleepStartMin, sleepEndMin) { return .sleeping }
            if Self.inRange(nowMin, sleepEndMin, (sleepEndMin + 60) % (24 * 60)) { return .wakingUp }
            if (nowMin >= lunchMin && nowMin < lunchMin + 30)
                || (nowMin >= dinnerMin && nowMin < dinnerMin + 30) { return .eating }
            return .idle
        }

        private static func inRange(_ nowMin: Int, _ start: Int, _ end: Int) -> Bool {
            let s = start % (24 * 60), e = end % (24 * 60)
            return s < e ? (nowMin >= s && nowMin < e) : (nowMin >= s || nowMin < e)
        }
    }

    static func saveSchedule(_ info: ScheduleInfo) {
        guard let defaults, let data = try? JSONEncoder().encode(info) else { return }
        defaults.set(data, forKey: scheduleKey)
    }

    static func loadSchedule() -> ScheduleInfo? {
        guard let defaults, let data = defaults.data(forKey: scheduleKey) else { return nil }
        return try? JSONDecoder().decode(ScheduleInfo.self, from: data)
    }

    /// 받은 WatchMessage 를 App Group 에 저장.
    /// 저장 후 위젯에 timeline reload 알리는 책임은 caller 가 짐.
    static func save(_ message: WatchMessage) {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(message) {
            defaults.set(data, forKey: messageKey)
        }
    }

    /// 위젯이 호출. 저장된 마지막 메시지 (없으면 nil).
    static func loadMessage() -> WatchMessage? {
        guard let defaults,
              let data = defaults.data(forKey: messageKey) else { return nil }
        return try? JSONDecoder().decode(WatchMessage.self, from: data)
    }
}
