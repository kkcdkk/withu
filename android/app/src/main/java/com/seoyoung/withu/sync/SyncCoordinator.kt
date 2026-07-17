package com.seoyoung.withu.sync

import com.seoyoung.withu.character.CharacterProfileStore
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.character.CharacterStateResolver
import com.seoyoung.withu.health.HealthManager
import com.seoyoung.withu.health.SleepSignals
import com.seoyoung.withu.shared.SharedAppState
import com.seoyoung.withu.shared.WatchMessage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import java.time.LocalDateTime

/**
 * 상태 동기화 조정자 — iOS 의 SyncCoordinator(SharedAppState 갱신 + 워치 push + 위젯 reload) 대응.
 * Android 파리티: 워치 push 는 SCOPE 제외, SharedAppState 저장 + 위젯 갱신 트리거까지.
 */
object SyncCoordinator {

    /**
     * 진단 화면의 상태 강제 오버라이드 — 홈/진단이 공유하는 '단일 홀더' (00-PLAN §2-8).
     * 비영속: 앱 재시작 시 null. null 이면 resolver 자동 판정.
     */
    val overrideState = MutableStateFlow<CharacterState?>(null)

    /** 지금 캐릭터 상태 — override 우선, 없으면 현재 신호 전부로 resolve. */
    fun currentState(): CharacterState {
        overrideState.value?.let { return it }
        val profile = CharacterProfileStore.load()
        // manualSleepOnly: 수면 신호(DND/수면 세션)를 전부 끄고 프로필 시간만 적용 —
        // resolver 계약상 caller 가 신호를 false/null 로 넘긴다 (스펙 08 §3.2).
        val manual = profile.isManualSleepOnly
        return CharacterStateResolver.resolve(
            now = LocalDateTime.now(),
            sleep = HealthManager.sleep.value,
            workouts = HealthManager.recentWorkouts.value,
            todaySteps = HealthManager.todaySteps.value,
            weather = com.seoyoung.withu.weather.WeatherManager.snapshot.value,
            inSleepSchedule = if (manual) false else HealthManager.isInBedSchedule.value,
            hasSleepSchedule = HealthManager.hasSleepSchedule.value,
            isFocusActive = false,   // Sleep Focus 확정 신호는 Android 에 없음 (스펙 08 §5)
            isGenericFocusActive = if (manual) false else SleepSignals.isDndOn(),
            focusWokeAt = if (manual) null else SleepSignals.lastDndOffAt(),
            isLikelyInWorkout = HealthManager.isLikelyInWorkout.value,
            recentStepsPerMinute = HealthManager.recentStepsPerMinute.value,
            phoneWorkoutState = null,   // 폰 모션 활동 분류는 후속 (호출 지점만 유지)
            profile = profile,
        )
    }

    /**
     * 현재 상태 + 활동/날씨 스냅샷을 SharedAppState 에 저장하고 위젯 갱신을 트리거.
     * iOS 의 syncNow() (SharedAppState 갱신 + 워치 push + WidgetCenter reload) 대응 —
     * 워치 push 는 SCOPE 제외.
     */
    suspend fun syncNow() = withContext(Dispatchers.IO) {
        val weather = com.seoyoung.withu.weather.WeatherManager.snapshot.value
        val message = WatchMessage(
            state = currentState().raw,
            todaySteps = HealthManager.todaySteps.value,
            lastSleepHours = HealthManager.sleep.value?.let { it.totalAsleepSeconds / 3600.0 },
            todayActiveMinutes = HealthManager.todayActiveMinutes.value,
            todayActiveKcal = HealthManager.todayActiveKcal.value,
            weatherEmoji = weather?.condition?.emoji,
            weatherTempC = weather?.temperatureC,
            weatherSunrise = weather?.sunrise,
            weatherSunset = weather?.sunset,
            timestamp = System.currentTimeMillis(),
        )
        SharedAppState.save(message)
        refreshWidgets()
    }

    /**
     * 위젯 갱신 트리거 — iOS WidgetCenter.reloadAllTimelines() 대응 호출 지점.
     * Glance 위젯(CharacterWidget)은 Phase S6 산출물이라 지금은 no-op.
     * S6/Phase I 에서 아래 주석을 실제 호출로 바꾼다:
     *   CharacterWidget().updateAll(WithuApp.context)
     */
    suspend fun refreshWidgets() {
        // no-op — 위젯 미구현 (00-PLAN §4 Phase S6 에서 연결)
    }
}
