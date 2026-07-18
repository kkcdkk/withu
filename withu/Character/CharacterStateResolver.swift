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
        isGenericFocusActive: Bool = false,
        isLikelyInWorkout: Bool = false,
        recentStepsPerMinute: Double = 0,
        phoneWorkoutState: CharacterState? = nil,
        // '수면 모드 기준'인데 실제 수면 신호원(취침 Focus/건강앱 수면 일정)이 하나도 없을 때 true.
        // 이때는 하단 안내 약속대로 설정 시간 창으로 재운다 (신호 없이 절대 안 자던 문제 해결).
        scheduleFallback: Bool = false,
        profile: CharacterProfile = CharacterProfile(),
        calendar: Calendar = .current
    ) -> CharacterState {
        // 0) HKWorkout 종료 후 1시간 윈도우 — 가장 신뢰성 있는 신호 (실제 운동 끝남 확정).
        //    HR 추론보다 앞에 둠 — 운동 종료 후에도 HR 이 일시적으로 stream 되면서
        //    isLikelyInWorkout 이 stale true 인 상황 대응.
        //    날씨는 background layer 가 별도로 처리하므로 여기선 base state 만 반환.
        if let latest = workouts.first {
            let endedAt = latest.start.addingTimeInterval(latest.duration)
            if now.timeIntervalSince(endedAt) <= recentWorkoutWindow {
                return mapWorkout(latest.activity)
            }
        }

        // 1) 워치 HR stream 패턴이 운동중으로 보이면 — 진행 중인 운동, 아직 HKWorkout 미commit.
        //    최근 걸음 페이스(분당 걸음수)로 타입 추정: 달리기 cadence 는 보통 150+,
        //    걷기 90~120(빠른 걸음 ~140). 걸음이 거의 없으면(자전거 등) .energetic.
        //    임계값 145 — 130 은 빠른 걸음(120~140)을 달리기로 오인해서 상향(2026-07 버그픽스).
        if isLikelyInWorkout {
            if recentStepsPerMinute >= 145 { return .running }
            if recentStepsPerMinute >= 40  { return .walking }
            return .energetic
        }

        // 1.5) 폰 전용 보조 — 워치 심박 신호가 없어도 CoreMotion 활동 분류가
        //     "10분간 지속되는 걷기/달리기/자전거" 로 판단하면 반영.
        //     (지속 조건은 MotionActivityManager 가 검사 — 일상 걸음 오탐 방지)
        //     단 시스템 수면 신호(Focus/수면 일정)가 켜져 있으면 무시 — 밤중에 폰 들고
        //     서성이는 정도로 수면 상태를 덮지 않는다. (워치 HR 경로는 '명시적 운동
        //     시작' 신호라 수면보다 우선하는 기존 정책 유지 — 폰 모션은 부수 신호.)
        if let phoneWorkoutState, !isFocusActive, !inSleepSchedule {
            return phoneWorkoutState
        }

        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let nowMin = hour * 60 + minute

        let sleepStartMin = profile.sleepStartHour * 60 + profile.sleepStartMinute
        let sleepEndMin = profile.sleepEndHour * 60 + profile.sleepEndMinute

        // 2) 수면 — 두 갈래 (프로필의 manualSleepOnly = 기준 칩 선택):
        //    · '수면 모드 기준'(manualSleepOnly=false): 실제 수면 신호만 재운다.
        //        (1순위) iOS Sleep Focus 필터 OR HealthKit inBed → 확정 수면.
        //        (2순위) 아무 집중 모드(INFocusStatusCenter) + 수면 시간대 —
        //                예약 수면 모드가 잠긴 폰에서 필터 인텐트를 못 깨운 경우의 보조 신호.
        //        → Sleep Focus 를 꺼두면 밤이어도 깨어 있다 (사용자가 고른 '수면 모드 기준' 의도 그대로).
        //    · '설정 시간 기준'(manualSleepOnly=true): caller 가 Focus/inBed 신호를 모두
        //        false 로 넘기므로 위 1·2순위는 안 걸리고, 아래 3순위 시간창만으로 재운다.
        if isFocusActive || inSleepSchedule {
            return .sleeping
        }
        if isGenericFocusActive,
           isInRange(nowMin: nowMin, start: sleepStartMin, end: sleepEndMin) {
            return .sleeping
        }
        // 3순위 — 시간창 자체가 수면 신호. '설정 시간 기준' 이거나,
        // '수면 모드 기준'인데 실제 수면 신호원이 없어 시간으로 폴백해야 할 때.
        if profile.isManualSleepOnly || scheduleFallback,
           isInRange(nowMin: nowMin, start: sleepStartMin, end: sleepEndMin) {
            return .sleeping
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

        // 5) 비운동 / 비수면 / 비기상 / 비식사 시간은 모두 idle.
        //    날씨는 운동 중일 때만 매핑에 사용 (mapWorkout 안에서).
        return .idle
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

    /// 운동 타입 → base state. 날씨는 background layer 가 별도 표시.
    /// 12 combo case (.walkingSunny 등) 는 enum 에 남아있지만 resolver 가 안 반환.
    private static func mapWorkout(_ type: HKWorkoutActivityType) -> CharacterState {
        switch type {
        case .running:          return .running
        case .cycling:          return .cycling
        case .walking, .hiking: return .walking
        default:                return .energetic
        }
    }
}
