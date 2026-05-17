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
    case walking
    case running
    case cycling
    case energetic       // 활동량 많음 (워크아웃은 아니지만 걸음 많은 날)
    case beach           // 매우 더운 날 — 해변 일광욕
    case rainyShelter    // 비 + 휴식 — 우산
    case snowPlay        // 눈 + 활동 — 눈사람/스노우보드

    /// SF Symbols 이름. 실제 캐릭터 이미지로 교체될 placeholder.
    var symbolName: String {
        switch self {
        case .idle:           return "face.smiling"
        case .sleeping:       return "moon.zzz.fill"
        case .walking:        return "figure.walk"
        case .running:        return "figure.run"
        case .cycling:        return "bicycle"
        case .energetic:      return "sparkles"
        case .beach:          return "sun.max.fill"
        case .rainyShelter:   return "umbrella.fill"
        case .snowPlay:       return "snowflake"
        }
    }

    var caption: String {
        switch self {
        case .idle:           return "느긋한 하루"
        case .sleeping:       return "쿨쿨… 자고 있어요"
        case .walking:        return "산책 중 🚶"
        case .running:        return "달리는 중 🏃"
        case .cycling:        return "자전거 타는 중 🚴"
        case .energetic:      return "에너지 넘치는 하루!"
        case .beach:          return "해변에서 일광욕 🏖️"
        case .rainyShelter:   return "우산 쓰고 비 구경 ☔️"
        case .snowPlay:       return "눈 속에서 신나게 ❄️"
        }
    }

    var tint: Color {
        switch self {
        case .idle:           return .gray
        case .sleeping:       return .indigo
        case .walking:        return .green
        case .running:        return .orange
        case .cycling:        return .blue
        case .energetic:      return .pink
        case .beach:          return .yellow
        case .rainyShelter:   return .teal
        case .snowPlay:       return .cyan
        }
    }

    /// Asset Catalog 에 해당 캐릭터 PNG 가 있을 경우 이 이름으로 등록.
    /// 예: `character_idle`, `character_beach`. 없으면 자동으로 SF Symbol 로 fallback.
    var imageAssetName: String { "character_\(rawValue)" }

    /// 인라인 위젯/짧은 슬롯용 표시 이모지.
    var symbolEmoji: String {
        switch self {
        case .idle:           return "🙂"
        case .sleeping:       return "💤"
        case .walking:        return "🚶"
        case .running:        return "🏃"
        case .cycling:        return "🚴"
        case .energetic:      return "✨"
        case .beach:          return "🏖️"
        case .rainyShelter:   return "☔️"
        case .snowPlay:       return "❄️"
        }
    }
}
