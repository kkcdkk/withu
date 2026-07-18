//
//  WatchMessage.swift
//  withu (Shared between iOS and watchOS targets)
//
//  Xcode UI 에서 이 파일의 Target Membership 을 iOS + watchOS 둘 다 체크해야 함.
//

import Foundation

/// iPhone → Watch 로 보내는 캐릭터 스냅샷 메시지.
/// `updateApplicationContext` 로 직렬화돼 전달됨.
struct WatchMessage: Codable, Equatable, Sendable {
    let state: CharacterState
    let todaySteps: Double?
    let lastSleepHours: Double?
    /// 오늘 활동(운동) 분
    let todayActiveMinutes: Double?
    /// 오늘 활성 칼로리
    let todayActiveKcal: Double?
    /// 현재 날씨 이모지 (예: ☀️)
    let weatherEmoji: String?
    /// 현재 기온 (섭씨)
    let weatherTempC: Double?
    /// 오늘 일출 (위치 local time). 옵셔널.
    var weatherSunrise: Date? = nil
    /// 오늘 일몰 (위치 local time). 옵셔널.
    var weatherSunset: Date? = nil
    /// 프로필 시간 창 요약 — 워치 컴플리케이션이 미래 수면/기상 전환을 스스로 계산하게 함께 전송.
    var schedule: SharedAppState.ScheduleInfo? = nil
    let timestamp: Date

    /// 직렬화/역직렬화 키. 양쪽이 같은 이름을 쓰게 명시.
    static let payloadKey = "withu.watchMessage.v1"

    // 옛 메시지와 호환: 새 필드는 옵셔널, 디코드 시 nil 허용
    init(state: CharacterState,
         todaySteps: Double? = nil,
         lastSleepHours: Double? = nil,
         todayActiveMinutes: Double? = nil,
         todayActiveKcal: Double? = nil,
         weatherEmoji: String? = nil,
         weatherTempC: Double? = nil,
         weatherSunrise: Date? = nil,
         weatherSunset: Date? = nil,
         schedule: SharedAppState.ScheduleInfo? = nil,
         timestamp: Date = Date()) {
        self.state = state
        self.todaySteps = todaySteps
        self.lastSleepHours = lastSleepHours
        self.todayActiveMinutes = todayActiveMinutes
        self.todayActiveKcal = todayActiveKcal
        self.weatherEmoji = weatherEmoji
        self.weatherTempC = weatherTempC
        self.weatherSunrise = weatherSunrise
        self.weatherSunset = weatherSunset
        self.schedule = schedule
        self.timestamp = timestamp
    }
}
