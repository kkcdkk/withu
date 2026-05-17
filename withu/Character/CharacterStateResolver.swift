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

    static func resolve(
        now: Date = Date(),
        sleep: SleepSummary?,
        workouts: [WorkoutSummary],
        todaySteps: Double?,
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

        // 2) 수면 시간대 + 수면 기록 있음 → 자는 중
        let hour = calendar.component(.hour, from: now)
        if sleepHours.contains(hour), let s = sleep, s.sampleCount > 0 {
            return .sleeping
        }

        // 3) 매우 더운 날 → 해변 (활동도 압도)
        if let w = weather, w.isHot {
            return .beach
        }

        // 4) 비 + 활동량 낮음 → 우산
        let steps = todaySteps ?? 0
        if let w = weather, w.condition == .rainy || w.condition == .thunder {
            if steps < energeticStepThreshold {
                return .rainyShelter
            }
            // 비 오는 날에 많이 걸었으면 그냥 energetic 으로 떨어짐
        }

        // 5) 눈 + 활동량 있음 → 눈 신
        if let w = weather, w.condition == .snowy, steps > 0 {
            return .snowPlay
        }

        // 6) 활동량 많은 날
        if steps >= energeticStepThreshold {
            return .energetic
        }

        return .idle
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
