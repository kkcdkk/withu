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

    /// 우선순위: HR 추론 → HKWorkout → 프로필 수면 → Focus/inBed → 기상 → 식사 → 날씨.
    /// 운동 감지는 Apple 워치 운동 앱 (HR stream 또는 HKWorkout sample) 에서만 받음.
    /// 캐주얼한 걸음 (CMMotion) 은 무시 — "운동 모드 = 명시적 시작" 정책.
    static func resolve(
        now: Date = Date(),
        sleep: SleepSummary? = nil,           // 현재 정책에서 무시 — 시그니처는 호환용
        workouts: [WorkoutSummary],
        todaySteps: Double? = nil,            // 현재 정책에서 무시
        weather: WeatherSnapshot? = nil,
        inSleepSchedule: Bool = false,
        hasSleepSchedule: Bool = false,
        isFocusActive: Bool = false,
        isLikelyInWorkout: Bool = false,
        profile: CharacterProfile = CharacterProfile(),
        calendar: Calendar = .current
    ) -> CharacterState {
        // 0) HKWorkout 종료 후 1시간 윈도우 — 가장 신뢰성 있는 신호 (실제 운동 끝남 확정).
        //    HR 추론보다 앞에 둠 — 운동 종료 후에도 HR 이 일시적으로 stream 되면서
        //    isLikelyInWorkout 이 stale true 인 상황 대응.
        if let latest = workouts.first {
            let endedAt = latest.start.addingTimeInterval(latest.duration)
            if now.timeIntervalSince(endedAt) <= recentWorkoutWindow {
                return mapWorkout(latest.activity)
            }
        }

        // 1) 워치 HR stream 패턴이 운동중으로 보이면 — 진행 중인 운동, 아직 HKWorkout 미commit.
        //    타입 모르므로 .energetic.
        if isLikelyInWorkout {
            return .energetic
        }

        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let nowMin = hour * 60 + minute

        let sleepStartMin = profile.sleepStartHour * 60 + profile.sleepStartMinute
        let sleepEndMin = profile.sleepEndHour * 60 + profile.sleepEndMinute

        // 2) 수면 — 새 우선순위:
        //    (1순위) iOS Sleep Focus (Filter OR INFocusStatusCenter) OR HealthKit inBed
        //            → 사용자/시스템 의 명시적 "지금 자" 신호
        //    (2순위) 프로필 sleep window 안 → 사용자 정의 fallback 시간
        //  manualSleepOnly 면 caller 가 isFocusActive/inSleepSchedule 둘 다 false 로 넘김.
        if isFocusActive || inSleepSchedule {
            return .sleeping
        }
        if isInRange(nowMin: nowMin, start: sleepStartMin, end: sleepEndMin) {
            return .sleeping
        }
        _ = hasSleepSchedule  // 시그니처 호환만 유지

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
        case .sunny:           return .idle         // 날씨 좋다고 자동으로 산책 X — walking 은 운동 분기에서만
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
