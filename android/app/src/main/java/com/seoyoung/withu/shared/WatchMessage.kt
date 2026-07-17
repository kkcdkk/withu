package com.seoyoung.withu.shared

import com.seoyoung.withu.character.CharacterState
import kotlinx.serialization.Serializable

/**
 * "현재 적용 스냅샷" — iOS WatchMessage 포팅 (스펙 09 §3-10).
 * Android 에선 Watch 전송은 없지만 홈/위젯(Glance)이 같은 데이터를 읽는
 * 단일 소스 역할은 동일 — 파리티를 위해 이름 유지.
 * 필수는 state/timestamp 뿐 — 나머지는 옛 메시지 디코드 호환을 위해 전부 nullable.
 */
@Serializable
data class WatchMessage(
    val state: String,                       // CharacterState.raw
    val todaySteps: Double? = null,
    val lastSleepHours: Double? = null,
    val todayActiveMinutes: Double? = null,  // 오늘 활동(운동) 분
    val todayActiveKcal: Double? = null,     // 오늘 활성 칼로리
    val weatherEmoji: String? = null,        // 예: ☀️
    val weatherTempC: Double? = null,        // 섭씨
    val weatherSunrise: Long? = null,        // epoch millis
    val weatherSunset: Long? = null,         // epoch millis
    val timestamp: Long,
) {
    /** raw 가 알 수 없는 값이어도 깨지지 않게 IDLE fallback. */
    val characterState: CharacterState
        get() = CharacterState.fromRaw(state) ?: CharacterState.IDLE
}
