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
    case energetic   // 활동량 많음 (워크아웃은 아니지만 걸음 많은 날)

    /// SF Symbols 이름. 실제 캐릭터 이미지로 교체될 placeholder.
    var symbolName: String {
        switch self {
        case .idle:      return "face.smiling"
        case .sleeping:  return "moon.zzz.fill"
        case .walking:   return "figure.walk"
        case .running:   return "figure.run"
        case .cycling:   return "bicycle"
        case .energetic: return "sparkles"
        }
    }

    var caption: String {
        switch self {
        case .idle:      return "느긋한 하루"
        case .sleeping:  return "쿨쿨… 자고 있어요"
        case .walking:   return "산책 중 🚶"
        case .running:   return "달리는 중 🏃"
        case .cycling:   return "자전거 타는 중 🚴"
        case .energetic: return "에너지 넘치는 하루!"
        }
    }

    var tint: Color {
        switch self {
        case .idle:      return .gray
        case .sleeping:  return .indigo
        case .walking:   return .green
        case .running:   return .orange
        case .cycling:   return .blue
        case .energetic: return .pink
        }
    }
}
