//
//  WeatherCondition.swift
//  withu (Shared)
//
//  Target Membership: iOS app + iOS Widget Extension (위젯에서 표시).
//  워치 쪽엔 일단 안 넣어도 됨 (iPhone 이 처리해서 메시지로 보낼 거).
//

import Foundation
import SwiftUI

/// 단순화한 날씨 조건. Open-Meteo 의 WMO weather code 에서 매핑.
enum WeatherCondition: String, Codable, Hashable, CaseIterable {
    case sunny
    case cloudy
    case rainy
    case snowy
    case foggy
    case thunder
    case unknown

    /// WMO weather_code → WeatherCondition.
    /// 참고: https://open-meteo.com/en/docs (Weather variables)
    init(wmoCode: Int) {
        switch wmoCode {
        case 0, 1:        self = .sunny       // clear / mainly clear
        case 2, 3:        self = .cloudy      // partly cloudy / overcast
        case 45, 48:      self = .foggy
        case 51...67:     self = .rainy       // drizzle / rain
        case 71...77:     self = .snowy       // snow fall
        case 80...82:     self = .rainy       // rain showers
        case 85, 86:      self = .snowy       // snow showers
        case 95...99:     self = .thunder
        default:          self = .unknown
        }
    }

    var emoji: String {
        switch self {
        case .sunny:    return "☀️"
        case .cloudy:   return "☁️"
        case .rainy:    return "🌧"
        case .snowy:    return "❄️"
        case .foggy:    return "🌫"
        case .thunder:  return "⛈"
        case .unknown:  return "❓"
        }
    }

    var caption: String {
        switch self {
        case .sunny:    return String(localized: "맑음")
        case .cloudy:   return String(localized: "흐림")
        case .rainy:    return String(localized: "비")
        case .snowy:    return String(localized: "눈")
        case .foggy:    return String(localized: "안개")
        case .thunder:  return String(localized: "뇌우")
        case .unknown:  return "?"
        }
    }

    var tint: Color {
        switch self {
        case .sunny:    return .yellow
        case .cloudy:   return .gray
        case .rainy:    return .blue
        case .snowy:    return .cyan
        case .foggy:    return .secondary
        case .thunder:  return .purple
        case .unknown:  return .gray
        }
    }
}

/// 한 번 측정한 날씨 스냅샷.
struct WeatherSnapshot: Codable, Equatable {
    let condition: WeatherCondition
    let temperatureC: Double
    let timestamp: Date
    /// 오늘 일출 (위치 local time). 옵셔널 — 이전 캐시 호환.
    var sunrise: Date? = nil
    /// 오늘 일몰 (위치 local time). 옵셔널 — 이전 캐시 호환.
    var sunset: Date? = nil

    /// 매우 더운 상태 판정 (해변 캐릭터용)
    var isHot: Bool { temperatureC >= 30 }
    /// 매우 추운 상태 판정
    var isCold: Bool { temperatureC <= 0 }
}
