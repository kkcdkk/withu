package com.seoyoung.withu.health

/**
 * 건강 데이터 값 모델 — 00-PLAN §2-8 계약.
 * (파일 소유는 F2 이지만 CharacterStateResolver 시그니처가 이 타입에 의존해
 *  F1 이 계약대로 먼저 생성 — F2 는 HealthManager/SleepSignals 를 별도 파일로 추가한다.)
 */

/** 수면 요약 — totalAsleepSeconds(초), 샘플 수, 마지막 밤 시각(epoch millis). */
data class SleepSummary(
    val totalAsleepSeconds: Double,
    val sampleCount: Int,
    val lastNight: Long?,
)

/** 운동 종류 — iOS HKWorkoutActivityType 대응. displayName 은 스펙 10 §2 원문. */
enum class WorkoutActivity {
    RUNNING, CYCLING, WALKING, HIKING, SWIMMING, YOGA, STRENGTH, OTHER;

    val displayName: String
        get() = when (this) {
            RUNNING -> "달리기 🏃"
            CYCLING -> "자전거 🚴"
            WALKING -> "걷기 🚶"
            HIKING -> "등산 🥾"
            SWIMMING -> "수영 🏊"
            YOGA -> "요가 🧘"
            STRENGTH -> "근력 💪"
            OTHER -> "운동"
        }
}

/** 운동 요약 — start 는 epoch millis, durationSeconds 는 초. */
data class WorkoutSummary(
    val activity: WorkoutActivity,
    val start: Long,
    val durationSeconds: Double,
    val kcal: Double? = null,
    val meters: Double? = null,
)

/** 평균 수면 창 (프로필 '건강 앱 기준' 칩에 사용). */
data class SleepWindow(
    val startHour: Int,
    val startMinute: Int,
    val endHour: Int,
    val endMinute: Int,
)
