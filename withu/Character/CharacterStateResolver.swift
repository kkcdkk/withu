//
//  CharacterStateResolver.swift
//  withu
//

import Foundation
import HealthKit

/// HealthKit 데이터를 보고 현재 캐릭터 상태를 정해주는 순수 함수 모음.
/// 시간/데이터만 받으면 같은 결과를 내는 deterministic 한 로직 — 테스트하기 편함.
enum CharacterStateResolver {
    /// 최근 워크아웃이 "방금 끝났거나 진행 중" 으로 간주할 시간 (초)
    private static let recentWorkoutWindow: TimeInterval = 30 * 60   // 30분
    /// 활동량 많음 기준
    private static let energeticStepThreshold: Double = 8000
    /// 수면 시간대로 보는 시각 범위
    private static let sleepHours: Set<Int> = Set(0..<7).union([22, 23])

    static func resolve(
        now: Date = Date(),
        sleep: SleepSummary?,
        workouts: [WorkoutSummary],
        todaySteps: Double?,
        calendar: Calendar = .current
    ) -> CharacterState {
        // 1) 최근 워크아웃이 있고 끝난 지 얼마 안 됐으면 그 상태로
        if let latest = workouts.first {
            let endedAt = latest.start.addingTimeInterval(latest.duration)
            if now.timeIntervalSince(endedAt) <= recentWorkoutWindow {
                return mapWorkout(latest.activity)
            }
        }

        // 2) 수면 시간대 + 최근 수면 기록이 있으면 자는 중
        let hour = calendar.component(.hour, from: now)
        if sleepHours.contains(hour), let s = sleep, s.sampleCount > 0 {
            return .sleeping
        }

        // 3) 활동량 많은 날
        if let steps = todaySteps, steps >= energeticStepThreshold {
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
