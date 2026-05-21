//
//  CharacterStateResolver.swift
//  withu
//

import Foundation
import HealthKit

/// HealthKit + 날씨 데이터를 보고 현재 캐릭터 상태를 정해주는 순수 함수 모음.
/// 시간/데이터/날씨를 인자로 받으면 같은 결과를 내는 deterministic 한 로직.
enum CharacterStateResolver {
    private static let recentWorkoutWindow: TimeInterval = 60 * 60  // 1시간
    private static let energeticStepThreshold: Double = 8000
    private static let sleepHours: Set<Int> = Set(0..<7).union([22, 23])

    /// 우선순위: 운동 → 수면 (일정 또는 기본 22-07) → 날씨.
    /// 운동 중에는 수면 시간이어도 깨어있는 거니까 운동 최우선.
    static func resolve(
        now: Date = Date(),
        sleep: SleepSummary? = nil,           // 현재 정책에서 무시 — 시그니처는 호환용
        workouts: [WorkoutSummary],
        todaySteps: Double? = nil,            // 현재 정책에서 무시
        weather: WeatherSnapshot? = nil,
        inSleepSchedule: Bool = false,
        hasSleepSchedule: Bool = false,
        profile: CharacterProfile = CharacterProfile(),
        calendar: Calendar = .current
    ) -> CharacterState {
        // 1) 운동 최우선 — 진행 중/방금 끝난 워크아웃이면 깨어있음
        if let latest = workouts.first {
            let endedAt = latest.start.addingTimeInterval(latest.duration)
            if now.timeIntervalSince(endedAt) <= recentWorkoutWindow {
                return mapWorkout(latest.activity)
            }
        }

        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let nowMin = hour * 60 + minute

        let sleepStartMin = profile.sleepStartHour * 60 + profile.sleepStartMinute
        let sleepEndMin = profile.sleepEndHour * 60 + profile.sleepEndMinute

        // 2) 수면
        if inSleepSchedule {
            return .sleeping
        } else if !hasSleepSchedule {
            if isInRange(nowMin: nowMin, start: sleepStartMin, end: sleepEndMin) {
                return .sleeping
            }
        }

        // 3) 기상 직후 — 기상 시점부터 1시간
        let wakeStart = sleepEndMin
        let wakeEnd = (sleepEndMin + 60) % (24 * 60)
        if isInRange(nowMin: nowMin, start: wakeStart, end: wakeEnd) {
            return .wakingUp
        }

        // 4) 식사 시간 — profile 의 점심/저녁 (시작 후 30분)
        let lunchStart = profile.lunchHour * 60 + profile.lunchMinute
        let dinnerStart = profile.dinnerHour * 60 + profile.dinnerMinute
        if (nowMin >= lunchStart && nowMin < lunchStart + 30)
            || (nowMin >= dinnerStart && nowMin < dinnerStart + 30) {
            return .eating
        }

        // 5) 날씨 기반
        guard let w = weather else { return .idle }
        if w.isHot { return .beach }
        switch w.condition {
        case .rainy, .thunder: return .rainyShelter
        case .snowy:           return .snowPlay
        case .sunny:           return .walking      // 햇살 받으며 산책
        case .cloudy:          return .cloudy       // 캐릭터 위에 작은 구름
        case .foggy:           return .idle
        case .unknown:         return .idle
        }
    }

    /// 현재 분(0~1439) 이 [start, end) 안에 있는지. start > end 면 자정 넘김.
    private static func isInRange(nowMin: Int, start: Int, end: Int) -> Bool {
        let s = start % (24 * 60)
        let e = end % (24 * 60)
        if s < e {
            return nowMin >= s && nowMin < e
        } else {
            return nowMin >= s || nowMin < e
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
