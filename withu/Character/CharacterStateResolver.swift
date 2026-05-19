//
//  CharacterStateResolver.swift
//  withu
//

import Foundation
import HealthKit

/// HealthKit + 날씨 데이터를 보고 현재 캐릭터 상태를 정해주는 순수 함수 모음.
/// 시간/데이터/날씨를 인자로 받으면 같은 결과를 내는 deterministic 한 로직.
enum CharacterStateResolver {
    private static let recentWorkoutWindow: TimeInterval = 30 * 60
    private static let energeticStepThreshold: Double = 8000
    private static let sleepHours: Set<Int> = Set(0..<7).union([22, 23])

    /// 우선순위: 운동 진행 중 → 운동 상태. 그 외 → 날씨 기반.
    /// (수면/활동량은 명시적 무시 — "운동 우선·평소는 날씨" 정책)
    static func resolve(
        now: Date = Date(),
        sleep: SleepSummary? = nil,           // 현재 정책에서 무시 — 시그니처는 호환용
        workouts: [WorkoutSummary],
        todaySteps: Double? = nil,            // 현재 정책에서 무시
        weather: WeatherSnapshot? = nil,
        calendar: Calendar = .current
    ) -> CharacterState {
        // 1) 진행 중/방금 끝난 워크아웃이 최우선
        if let latest = workouts.first {
            let endedAt = latest.start.addingTimeInterval(latest.duration)
            if now.timeIntervalSince(endedAt) <= recentWorkoutWindow {
                return mapWorkout(latest.activity)
            }
        }

        // 2) 날씨 기반 (운동 안 할 때)
        guard let w = weather else { return .idle }
        if w.isHot { return .beach }
        switch w.condition {
        case .rainy, .thunder: return .rainyShelter
        case .snowy:           return .snowPlay
        case .sunny:           return .walking      // 햇살 받으며 산책
        case .cloudy, .foggy:  return .idle         // 평온히
        case .unknown:         return .idle
        }
    }

    private static func mapWorkout(_ type: HKWorkoutActivityType) -> CharacterState {
        switch type {
        case .running: return .running
        case .cycling: return .cycling
        case .walking, .hiking: return .walking
        default: return .energetic
        }
    }
}
