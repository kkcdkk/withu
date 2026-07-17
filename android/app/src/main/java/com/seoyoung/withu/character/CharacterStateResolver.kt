package com.seoyoung.withu.character

import com.seoyoung.withu.health.SleepSummary
import com.seoyoung.withu.health.WorkoutActivity
import com.seoyoung.withu.health.WorkoutSummary
import com.seoyoung.withu.weather.WeatherSnapshot
import java.time.LocalDateTime
import java.time.ZoneId

/**
 * 시간/운동/수면 신호/프로필 → CharacterState 를 정해주는 순수 함수 —
 * iOS CharacterStateResolver.swift 포팅 (스펙 08 §3.2). 같은 입력 = 같은 결과 (deterministic).
 *
 * Android 신호 대응 (스펙 08 §5):
 *  - isFocusActive (iOS Sleep Focus) → 직접 대응 없음, caller 가 항상 false.
 *  - isGenericFocusActive → 방해금지(DND) on 근사.
 *  - isLikelyInWorkout/recentStepsPerMinute (워치 HR) → Wear 제외라 항상 false/0.
 *    로직은 후속 Wear 연동을 위해 그대로 유지.
 */
object CharacterStateResolver {
    /** HKWorkout 종료 후 이 시간 안이면 운동 상태 유지 (1시간). */
    private const val RECENT_WORKOUT_WINDOW_SECONDS = 60L * 60L

    // 현재 미사용 — iOS 원본에도 선언만 존재 (파리티 기록).
    @Suppress("unused")
    private const val ENERGETIC_STEP_THRESHOLD = 8000.0

    /**
     * 우선순위: 종료된 운동 1시간 → HR 추론 → 폰 모션 보조 → 수면 3단 → 기상 → 식사 → idle.
     * sleep/todaySteps/weather/hasSleepSchedule 파라미터는 현재 정책에서 무시 —
     * iOS 시그니처 호환용으로만 유지 (호출부 diff 최소화).
     */
    fun resolve(
        now: LocalDateTime = LocalDateTime.now(),
        sleep: SleepSummary? = null,                    // 미사용 (시그니처 호환)
        workouts: List<WorkoutSummary> = emptyList(),   // 최신순 전제 (first = 가장 최근)
        todaySteps: Double? = null,                     // 미사용
        weather: WeatherSnapshot? = null,               // 미사용
        inSleepSchedule: Boolean = false,
        hasSleepSchedule: Boolean = false,              // 미사용
        isFocusActive: Boolean = false,                 // Android: 항상 false
        isGenericFocusActive: Boolean = false,          // Android: DND on 근사
        focusWokeAt: LocalDateTime? = null,
        isLikelyInWorkout: Boolean = false,             // Android: 항상 false (Wear 제외)
        recentStepsPerMinute: Double = 0.0,
        phoneWorkoutState: CharacterState? = null,
        profile: CharacterProfile = CharacterProfile(),
    ): CharacterState {
        // 미사용 파라미터 명시 (iOS 도 동일하게 무시). focusWokeAt 은 caller 호환용으로만
        // 남긴 파라미터 — 아래 수면 3순위가 manualSleepOnly 전용으로 바뀌며 미사용이 됨.
        @Suppress("UNUSED_EXPRESSION") sleep; todaySteps; weather; hasSleepSchedule; focusWokeAt

        // 0) HKWorkout(운동 세션) 종료 후 1시간 윈도우 — 가장 신뢰성 있는 신호.
        //    HR 추론보다 앞 — 운동 종료 후에도 HR 이 잠시 stream 되어 isLikelyInWorkout 이
        //    stale true 인 상황 대응. 날씨는 배경 layer 별도 처리라 base state 만 반환.
        val latest = workouts.firstOrNull()
        if (latest != null) {
            val nowEpochSec = now.atZone(ZoneId.systemDefault()).toEpochSecond()
            val endedAtSec = latest.start / 1000 + latest.durationSeconds.toLong()
            if (nowEpochSec - endedAtSec <= RECENT_WORKOUT_WINDOW_SECONDS) {
                return mapWorkout(latest.activity)
            }
        }

        // 1) 진행 중 운동 (HR stream 추론) — 분당 걸음수로 타입 추정.
        //    달리기 cadence 는 보통 150+, 걷기 90~120. 걸음 거의 없으면(자전거 등) energetic.
        if (isLikelyInWorkout) {
            if (recentStepsPerMinute >= 130) return CharacterState.RUNNING
            if (recentStepsPerMinute >= 40) return CharacterState.WALKING
            return CharacterState.ENERGETIC
        }

        // 1.5) 폰 전용 보조 — 활동 분류가 "10분 지속 걷기/달리기/자전거"로 판단하면 반영.
        //      (지속 조건은 caller 가 검사 — 일상 걸음 오탐 방지)
        //      단 수면 신호가 켜져 있으면 무시 — 밤중에 폰 들고 서성이는 정도로 수면을 덮지 않는다.
        if (phoneWorkoutState != null && !isFocusActive && !inSleepSchedule) {
            return phoneWorkoutState
        }

        val nowMin = now.hour * 60 + now.minute
        val sleepStartMin = profile.sleepStartHour * 60 + profile.sleepStartMinute
        val sleepEndMin = profile.sleepEndHour * 60 + profile.sleepEndMinute

        // 2) 수면 — 프로필의 manualSleepOnly(기준 칩)가 규칙을 가른다 (iOS 파리티):
        //    · '수면 모드 기준'(manualSleepOnly=false): 실제 수면 신호만 재운다.
        //        (1순위) iOS Sleep Focus 또는 수면 세션(inBed) 진행 중 → 확정 수면.
        //        (2순위) 아무 집중/DND + 수면 창 안 — 예약 수면 모드가 신호를 안 깨우는 보조.
        //        → 수면 신호가 하나도 없으면 밤이어도 깨어 있다 (시간창만으로는 안 잔다).
        //    · '설정 시간 기준'(manualSleepOnly=true): caller 가 Focus/inBed 신호를 전부
        //        false/null 로 넘기므로 1·2순위는 안 걸리고, 3순위 시간창만으로 재운다.
        if (isFocusActive || inSleepSchedule) {
            return CharacterState.SLEEPING
        }
        if (isGenericFocusActive && isInRange(nowMin, sleepStartMin, sleepEndMin)) {
            return CharacterState.SLEEPING
        }
        // 3순위 — '설정 시간 기준' 전용: 시간창 자체가 수면 신호.
        if (profile.isManualSleepOnly && isInRange(nowMin, sleepStartMin, sleepEndMin)) {
            return CharacterState.SLEEPING
        }

        // 3) 기상 직후 — 기상 시점부터 60분 (자정 넘김 안전)
        val wakeStart = sleepEndMin
        val wakeEnd = (sleepEndMin + 60) % (24 * 60)
        if (isInRange(nowMin, wakeStart, wakeEnd)) {
            return CharacterState.WAKING_UP
        }

        // 4) 식사 시간 — 점심/저녁 시작 후 30분 (wrap 없음 — iOS 동일)
        val lunchStart = profile.lunchHour * 60 + profile.lunchMinute
        val dinnerStart = profile.dinnerHour * 60 + profile.dinnerMinute
        if ((nowMin >= lunchStart && nowMin < lunchStart + 30) ||
            (nowMin >= dinnerStart && nowMin < dinnerStart + 30)
        ) {
            return CharacterState.EATING
        }

        // 5) 그 외 전부 idle. 날씨는 idle 상태에 영향 없음 (데코 layer 별도).
        return CharacterState.IDLE
    }

    /**
     * 지금이 프로필 수면 창 안인지 — 프로필 화면 '자는 중' 판정과 resolver 수면 분기가
     * 공유하는 함수 (스펙 05 §3-2: 두 판정이 어긋나면 안 됨).
     */
    fun isNowInSleepWindow(now: LocalDateTime, profile: CharacterProfile): Boolean {
        val nowMin = now.hour * 60 + now.minute
        return isInRange(
            nowMin,
            profile.sleepStartHour * 60 + profile.sleepStartMinute,
            profile.sleepEndHour * 60 + profile.sleepEndMinute,
        )
    }

    /** 현재 분(0~1439)이 [start, end) 안인지. start > end 면 자정 넘김. */
    private fun isInRange(nowMin: Int, start: Int, end: Int): Boolean {
        val s = start % (24 * 60)
        val e = end % (24 * 60)
        return if (s < e) nowMin in s until e else nowMin >= s || nowMin < e
    }

    /** 운동 타입 → base state. 12 조합 case 는 resolver 가 반환하지 않는다. */
    private fun mapWorkout(type: WorkoutActivity): CharacterState = when (type) {
        WorkoutActivity.RUNNING -> CharacterState.RUNNING
        WorkoutActivity.CYCLING -> CharacterState.CYCLING
        WorkoutActivity.WALKING, WorkoutActivity.HIKING -> CharacterState.WALKING
        else -> CharacterState.ENERGETIC
    }
}
