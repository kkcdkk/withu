//
//  CharacterState.swift
//  withu
//

import SwiftUI

/// 캐릭터가 가질 수 있는 상태. 각 상태마다 표시용 정보를 가짐.
/// `String` raw value + `Codable` 이라 watchOS 와 메시지로 직렬화/공유 가능.
enum CharacterState: String, Codable, Hashable, CaseIterable {
    case idle
    case sleeping
    case wakingUp        // 기상 직후 (07:00-08:00) — 베개 + 졸린 표정
    case walking
    case running
    case cycling
    case energetic       // 활동량 많음 (워크아웃은 아니지만 걸음 많은 날)
    case eating          // 식사 시간 (12:00-12:30, 18:00-18:30)
    case beach           // 매우 더운 날 — 해변 일광욕
    case cloudy          // 흐림 — 캐릭터 위에 작은 구름
    case rainyShelter    // 비 + 휴식 — 우산
    case snowPlay        // 눈 + 활동 — 눈사람/스노우보드

    /// SF Symbols 이름. 실제 캐릭터 이미지로 교체될 placeholder.
    var symbolName: String {
        switch self {
        case .idle:           return "face.smiling"
        case .sleeping:       return "moon.zzz.fill"
        case .wakingUp:       return "bed.double.fill"
        case .walking:        return "figure.walk"
        case .running:        return "figure.run"
        case .cycling:        return "bicycle"
        case .energetic:      return "sparkles"
        case .eating:         return "fork.knife"
        case .beach:          return "sun.max.fill"
        case .cloudy:         return "cloud.fill"
        case .rainyShelter:   return "umbrella.fill"
        case .snowPlay:       return "snowflake"
        }
    }

    var caption: String {
        switch self {
        case .idle:           return "느긋한 하루"
        case .sleeping:       return "쿨쿨… 자고 있어요"
        case .wakingUp:       return "잠 깨는 중 🥱"
        case .walking:        return "산책 중 🚶"
        case .running:        return "달리는 중 🏃"
        case .cycling:        return "자전거 타는 중 🚴"
        case .energetic:      return "에너지 넘치는 하루!"
        case .eating:         return "맛있게 식사 중 🍽️"
        case .beach:          return "해변에서 일광욕 🏖️"
        case .cloudy:         return "구름 낀 하루 ☁️"
        case .rainyShelter:   return "우산 쓰고 비 구경 ☔️"
        case .snowPlay:       return "눈 속에서 신나게 ❄️"
        }
    }

    var tint: Color {
        switch self {
        case .idle:           return .gray
        case .sleeping:       return .indigo
        case .wakingUp:       return .purple
        case .walking:        return .green
        case .running:        return .orange
        case .cycling:        return .blue
        case .energetic:      return .pink
        case .eating:         return .red
        case .beach:          return .yellow
        case .cloudy:         return .gray
        case .rainyShelter:   return .teal
        case .snowPlay:       return .cyan
        }
    }

    /// Asset Catalog 에 해당 캐릭터 PNG 가 있을 경우 이 이름으로 등록.
    /// 예: `character_idle`, `character_beach`. 없으면 자동으로 SF Symbol 로 fallback.
    var imageAssetName: String { "character_\(rawValue)" }

    /// AI 생성 시 사용자에게 채워주는 시작 프롬프트 (상태에 맞는 동작/표정).
    /// 사용자가 자유롭게 수정 가능. 그림체/가드레일은 서버가 자동 추가.
    var generationHint: String {
        switch self {
        case .idle:         return "standing peacefully, hands folded, looking calm with a small smile"
        case .sleeping:     return "sleeping on a small pillow, eyes closed, with a 'zzz' bubble nearby"
        case .wakingUp:     return "just woken up, holding a pillow, half-closed sleepy eyes, messy hair, yawning"
        case .walking:      return "walking happily with one foot up, motion lines, friendly expression"
        case .running:      return "running with arms swinging energetically, dynamic pose"
        case .cycling:      return "riding a small bicycle, wearing a tiny helmet, friendly smile"
        case .energetic:    return "jumping in the air with sparkles around, super happy"
        case .eating:       return "sitting at a small table, happily eating a meal with fork and spoon, food on plate"
        case .beach:        return "lying on a beach towel with sunglasses, sun overhead"
        case .cloudy:       return "standing calmly with small fluffy clouds floating above the head, soft cloudy sky background, peaceful expression"
        case .rainyShelter: return "holding an umbrella, wearing rain boots, raindrops around"
        case .snowPlay:     return "standing in snow, making a snowball, wearing mittens and scarf"
        }
    }

    /// 연속 이미지 생성 시 frame 2 변화 힌트.
    /// frame 1 (= frame 0) 과 명백히 다른 pose 를 만들어야 swap 했을 때 애니메이션이 살아남.
    /// "slightly different pose" 같은 모호한 표현은 OpenAI 가 거의 같은 그림으로 만들어 버림.
    /// 그래서 state 별로 구체적인 변화 방향을 미리 정의.
    var animationFrame2Hint: String {
        switch self {
        case .idle:
            return "eyes blinking (closed eyelids) instead of open, or head tilted to the opposite side. Keep everything else identical."
        case .sleeping:
            return "breathing in (slightly puffed chest / cheeks) instead of out, or 'z' bubble in a different position. Same closed eyes, same pillow."
        case .wakingUp:
            return "yawning with wide open mouth, or one eye fully open. Same messy hair and pillow."
        case .walking:
            return "the OPPOSITE foot stepping forward (mirror the leg/arm swing). Same direction of walking, same outfit."
        case .running:
            return "arms and legs in the OPPOSITE swing phase — if frame 1 had right arm forward, frame 2 has left arm forward. Same speed, same expression."
        case .cycling:
            return "pedals rotated half a turn — opposite foot at the top. Same helmet, same direction, same bicycle."
        case .energetic:
            return "jumping at the higher peak with arms wider, or sparkles in a different position. Same big smile."
        case .eating:
            return "spoon/fork at a different position — mid-bite vs after-bite. Same table, same food, same outfit."
        case .beach:
            return "waving one hand, or sunglasses pushed slightly up — small but visible change. Same beach towel, same sun overhead."
        case .cloudy:
            return "small cloud floating to the other side above the head. Same calm expression, same background."
        case .rainyShelter:
            return "umbrella tilted to the opposite angle, or rain drops in different positions. Same boots and outfit."
        case .snowPlay:
            return "snowball mid-toss (in the air) instead of in hands, or scarf flowing the other direction. Same mittens, same snow ground."
        }
    }

    /// 인라인 위젯/짧은 슬롯용 표시 이모지.
    var symbolEmoji: String {
        switch self {
        case .idle:           return "🙂"
        case .sleeping:       return "💤"
        case .wakingUp:       return "🥱"
        case .walking:        return "🚶"
        case .running:        return "🏃"
        case .cycling:        return "🚴"
        case .energetic:      return "✨"
        case .eating:         return "🍽️"
        case .beach:          return "🏖️"
        case .cloudy:         return "☁️"
        case .rainyShelter:   return "☔️"
        case .snowPlay:       return "❄️"
        }
    }
}
