//
//  CharacterProfile.swift
//  withu (Shared)
//
//  사용자가 설정하는 캐릭터 프로필 — 이름, 설명, 수면/식사 시간.
//  App Group UserDefaults 에 저장. resolver 가 시간 정보 사용.
//

import Foundation

struct CharacterProfile: Codable, Equatable {
    var name: String = "내 캐릭터"
    var description: String = ""
    /// AI 캐릭터 생성 시 baseIdentity 의 default — 외형/성격 한 줄 정의.
    /// 비어있으면 hardcoded fallback 사용.
    var aiPrompt: String = ""
    /// 수면 시작 시 (0-23). 기본 22 = 22:00
    var sleepStartHour: Int = 22
    var sleepStartMinute: Int = 0
    /// 기상 시 (0-23). 기본 7 = 07:00
    var sleepEndHour: Int = 7
    var sleepEndMinute: Int = 0
    /// 점심 시작. 30분 동안 식사
    var lunchHour: Int = 12
    var lunchMinute: Int = 0
    /// 저녁 시작. 30분 동안 식사
    var dinnerHour: Int = 18
    var dinnerMinute: Int = 0
    /// true 면 Focus 모드 / HealthKit 수면 일정을 무시하고 위의 sleepStart/End 시간만으로 sleeping 판정.
    /// Optional 인 이유: 옛 저장 데이터엔 이 키가 없어 nil → false 로 fallback (자동 감지 사용).
    var manualSleepOnly: Bool?
    // 애니메이션 사용 토글은 CharacterImageStore.animationEnabled 로 분리 — widget target 도 읽어야 함.
}

enum CharacterProfileStore {
    private static let key = "withu.characterProfile.v1"
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedAppState.groupID)
    }

    static func load() -> CharacterProfile {
        guard let defaults,
              let data = defaults.data(forKey: key),
              let profile = try? JSONDecoder().decode(CharacterProfile.self, from: data) else {
            return CharacterProfile()
        }
        return profile
    }

    static func save(_ profile: CharacterProfile) {
        guard let defaults,
              let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: key)
        // 메인 화면 등에 알려서 즉시 갱신
        NotificationCenter.default.post(name: .characterProfileChanged, object: nil)
    }
}

extension Notification.Name {
    static let characterProfileChanged = Notification.Name("withu.characterProfileChanged")
}
