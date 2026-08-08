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
    case beach           // 매우 더운 날 — 해변 일광욕 (legacy, resolver 가 자동 반환 안 함)
    case cloudy          // 흐림 — 캐릭터 위에 작은 구름 (legacy)
    case rainyShelter    // 비 + 휴식 — 우산 (legacy)
    case snowPlay        // 눈 + 활동 — 눈사람/스노우보드 (legacy)

    // MARK: - 운동 × 날씨 조합 (테마)
    // resolver 가 active workout + weather 알 때 자동 반환.
    // 이미지 없으면 baseFallback 으로 폴백.

    case walkingSunny
    case walkingCloudy
    case walkingRainy
    case walkingSnowy

    case runningSunny
    case runningCloudy
    case runningRainy
    case runningSnowy

    case cyclingSunny
    case cyclingCloudy
    case cyclingRainy
    case cyclingSnowy

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
        case .walkingSunny, .walkingCloudy, .walkingRainy, .walkingSnowy: return "figure.walk"
        case .runningSunny, .runningCloudy, .runningRainy, .runningSnowy: return "figure.run"
        case .cyclingSunny, .cyclingCloudy, .cyclingRainy, .cyclingSnowy: return "bicycle"
        }
    }

    /// 사용자 픽커에 보여줄 핵심 state 들 — resolver 가 실제로 자동 반환하는 것.
    /// 레거시 4 (.beach/.cloudy/.rainyShelter/.snowPlay) 와 12 운동×날씨 조합은 제외 —
    /// 자동으로 안 잡히고, 날씨는 배경 layer 가 따로 처리.
    /// 디버그 / 내부 iteration 은 allCases 그대로 사용.
    static let userFacing: [CharacterState] = [
        .idle, .sleeping, .wakingUp, .eating,
        .walking, .running, .cycling, .energetic,
    ]

    /// 조합 state 의 기본 운동 state (이미지 폴백 + 매핑용).
    /// 조합 아닌 case 는 nil.
    var baseFallback: CharacterState? {
        switch self {
        case .walkingSunny, .walkingCloudy, .walkingRainy, .walkingSnowy: return .walking
        case .runningSunny, .runningCloudy, .runningRainy, .runningSnowy: return .running
        case .cyclingSunny, .cyclingCloudy, .cyclingRainy, .cyclingSnowy: return .cycling
        default: return nil
        }
    }

    /// UI picker/리스트에 쓰는 짧고 깔끔한 한글 라벨. 이모지 없음.
    var koreanShortLabel: String {
        switch self {
        case .idle:           return String(localized: "기본")
        case .sleeping:       return String(localized: "수면")
        case .wakingUp:       return String(localized: "기상")
        case .eating:         return String(localized: "식사")
        case .walking:        return String(localized: "산책")
        case .running:        return String(localized: "달리기")
        case .cycling:        return String(localized: "자전거")
        case .energetic:      return String(localized: "활기찬")
        case .beach:          return String(localized: "해변")
        case .cloudy:         return String(localized: "흐림")
        case .rainyShelter:   return String(localized: "우산")
        case .snowPlay:       return String(localized: "눈놀이")
        case .walkingSunny, .walkingCloudy, .walkingRainy, .walkingSnowy: return String(localized: "산책")
        case .runningSunny, .runningCloudy, .runningRainy, .runningSnowy: return String(localized: "달리기")
        case .cyclingSunny, .cyclingCloudy, .cyclingRainy, .cyclingSnowy: return String(localized: "자전거")
        }
    }

    /// 이름을 '{이름}의 ~' 로 앞에 붙여도 자연스러운 문구인지.
    /// 명사구만 true — '자고 있어요' · '산책 중' 같은 동사구는 '코코의 산책 중' 처럼 어색해진다.
    var captionAllowsNamePrefix: Bool {
        switch self {
        case .idle, .energetic, .cloudy, .rainyShelter,
             .walkingCloudy, .walkingRainy, .walkingSnowy,
             .runningSunny, .runningCloudy, .runningSnowy,
             .cyclingSunny, .cyclingCloudy, .cyclingRainy, .cyclingSnowy:
            return true
        default:
            return false
        }
    }

    var caption: String {
        switch self {
        case .idle:           return String(localized: "느긋한 하루")
        case .sleeping:       return String(localized: "쿨쿨… 자고 있어요")
        case .wakingUp:       return String(localized: "잠 깨는 중")
        case .walking:        return String(localized: "산책 중")
        case .running:        return String(localized: "달리는 중")
        case .cycling:        return String(localized: "자전거 타는 중")
        case .energetic:      return String(localized: "에너지 넘치는 하루!")
        case .eating:         return String(localized: "맛있게 식사 중")
        case .beach:          return String(localized: "해변에서 일광욕")
        case .cloudy:         return String(localized: "구름 낀 하루")
        case .rainyShelter:   return String(localized: "비 구경")
        case .snowPlay:       return String(localized: "눈 놀이 중")
        case .walkingSunny:   return String(localized: "햇살 받으며 산책")
        case .walkingCloudy:  return String(localized: "흐린 날 산책")
        case .walkingRainy:   return String(localized: "우중 산책")
        case .walkingSnowy:   return String(localized: "눈길 산책")
        case .runningSunny:   return String(localized: "햇살 아래 달리기")
        case .runningCloudy:  return String(localized: "흐린 날 달리기")
        case .runningRainy:   return String(localized: "비 맞으며 달리기")
        case .runningSnowy:   return String(localized: "눈 속 달리기")
        case .cyclingSunny:   return String(localized: "햇살 자전거")
        case .cyclingCloudy:  return String(localized: "흐린 날 자전거")
        case .cyclingRainy:   return String(localized: "우중 자전거")
        case .cyclingSnowy:   return String(localized: "눈 속 자전거")
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
        case .walkingSunny, .runningSunny, .cyclingSunny:   return .yellow
        case .walkingCloudy, .runningCloudy, .cyclingCloudy: return .gray
        case .walkingRainy, .runningRainy, .cyclingRainy:    return .blue
        case .walkingSnowy, .runningSnowy, .cyclingSnowy:    return .cyan
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
        case .wakingUp:     return "just woken up, holding a pillow, messy hair, mouth wide open in a big yawn, sleepy half-closed eyes"
        case .walking:      return "walking happily with one foot up, motion lines, friendly expression"
        case .running:      return "running with arms swinging energetically, dynamic pose"
        case .cycling:      return "riding a small bicycle, wearing a tiny helmet, friendly smile"
        case .energetic:    return "jumping in the air with sparkles around, super happy"
        case .eating:       return "sitting at a small table, holding a fork with food on it down near the plate, food on plate, happy expression"
        case .beach:        return "lying on a beach towel with sunglasses, sun overhead"
        case .cloudy:       return "standing calmly with small fluffy clouds floating above the head, soft cloudy sky background, peaceful expression"
        case .rainyShelter: return "holding an umbrella, wearing rain boots, raindrops around"
        case .snowPlay:     return "standing in snow, making a snowball, wearing mittens and scarf"
        case .walkingSunny: return "walking happily under bright sunshine, sunny clear sky background, motion lines"
        case .walkingCloudy: return "walking calmly with soft cloudy sky background, motion lines"
        case .walkingRainy: return "walking while holding an umbrella, light rain falling, wet pavement reflection"
        case .walkingSnowy: return "walking in snow wearing a scarf and mittens, snowflakes around, snow on ground"
        case .runningSunny: return "running energetically under bright sunshine, sunny clear sky, motion blur"
        case .runningCloudy: return "running with arms swinging under cloudy sky, motion blur"
        case .runningRainy: return "running in light rain, raindrops around, wet pavement"
        case .runningSnowy: return "running through snow, scarf flowing, snowflakes falling"
        case .cyclingSunny: return "riding a small bicycle under bright sunshine, sunny clear sky, helmet on"
        case .cyclingCloudy: return "riding a bicycle under cloudy sky, helmet on, calm expression"
        case .cyclingRainy: return "riding a bicycle in light rain wearing a raincoat or hood, raindrops around"
        case .cyclingSnowy: return "riding a bicycle through light snow, bundled up with scarf and mittens"
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
            return "mouth fully closed with relaxed lips (NOT yawning), and both eyes closed (relaxed, resting). Same messy hair, same pillow, same pose and size."
        case .walking:
            return "a full stride swap: the clearly OPPOSITE leg forward — if frame 1's LEFT leg is forward, now the RIGHT leg is forward and the left leg is back, with arm swing mirrored to match. Same direction of walking, same outfit, same size and position."
        case .running:
            return "a full stride swap: arms and legs in the clearly OPPOSITE swing phase — if frame 1 had the right leg and left arm forward, frame 2 has the left leg and right arm forward. Same speed, same expression, same size and position."
        case .cycling:
            return "pedals rotated half a turn — opposite foot at the top. Same helmet, same direction, same bicycle."
        case .energetic:
            return "jumping at the higher peak with arms wider, or sparkles in a different position. Same big smile."
        case .eating:
            return "the fork raised all the way up to the mouth, taking a bite — mouth open around the food, cheeks a little full. Same table, same food, same outfit, same size and position."
        case .beach:
            return "waving one hand, or sunglasses pushed slightly up — small but visible change. Same beach towel, same sun overhead."
        case .cloudy:
            return "small cloud floating to the other side above the head. Same calm expression, same background."
        case .rainyShelter:
            return "umbrella tilted to the opposite angle, or rain drops in different positions. Same boots and outfit."
        case .snowPlay:
            return "snowball mid-toss (in the air) instead of in hands, or scarf flowing the other direction. Same mittens, same snow ground."
        // 조합 — 운동 base 의 hint 와 동일한 변화 패턴 사용
        case .walkingSunny, .walkingCloudy, .walkingRainy, .walkingSnowy:
            return "a full stride swap: the clearly OPPOSITE leg forward — if frame 1's LEFT leg is forward, now the RIGHT leg is forward and the left leg is back, arm swing mirrored. Same direction, same outfit, same weather conditions, same size and position."
        case .runningSunny, .runningCloudy, .runningRainy, .runningSnowy:
            return "a full stride swap: arms and legs in the clearly OPPOSITE swing phase (left leg forward becomes right leg forward). Same speed, same expression, same weather conditions, same size and position."
        case .cyclingSunny, .cyclingCloudy, .cyclingRainy, .cyclingSnowy:
            return "pedals rotated half a turn — opposite foot at the top. Same helmet, same direction, same bicycle, same weather conditions."
        }
    }

    /// 프레임2(움직임)를 실제로 새로 생성할지 여부.
    /// true  — 다리 교차·하품·냠·페달처럼 절차적 변형(scale/offset/rotation)으로 흉내낼 수
    ///         없는 포즈 변화 → 2프레임 생성이 필요.
    /// false — 숨쉬기·까닥 등 미세 모션. 홈/워치의 절차적 모션으로 충분하고, 2프레임을 새로
    ///         그리면 이목구비·색이 흔들려(드리프트) 오히려 나빠짐 → 1장 + 절차적 모션.
    var usesGeneratedMotion: Bool {
        switch self {
        case .idle, .sleeping, .beach, .cloudy, .rainyShelter:
            return false
        case .wakingUp, .walking, .running, .cycling, .eating, .energetic, .snowPlay,
             .walkingSunny, .walkingCloudy, .walkingRainy, .walkingSnowy,
             .runningSunny, .runningCloudy, .runningRainy, .runningSnowy,
             .cyclingSunny, .cyclingCloudy, .cyclingRainy, .cyclingSnowy:
            return true
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
        case .walkingSunny:   return "🚶☀️"
        case .walkingCloudy:  return "🚶☁️"
        case .walkingRainy:   return "🚶☔"
        case .walkingSnowy:   return "🚶❄️"
        case .runningSunny:   return "🏃☀️"
        case .runningCloudy:  return "🏃☁️"
        case .runningRainy:   return "🏃☔"
        case .runningSnowy:   return "🏃❄️"
        case .cyclingSunny:   return "🚴☀️"
        case .cyclingCloudy:  return "🚴☁️"
        case .cyclingRainy:   return "🚴☔"
        case .cyclingSnowy:   return "🚴❄️"
        }
    }
}
