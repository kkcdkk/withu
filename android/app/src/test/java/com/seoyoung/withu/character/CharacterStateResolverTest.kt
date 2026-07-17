package com.seoyoung.withu.character

import com.seoyoung.withu.health.WorkoutActivity
import com.seoyoung.withu.health.WorkoutSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

/**
 * CharacterStateResolver 순수 함수 테스트 —
 * 자정 넘김 수면 창 / focusWokeAt 존중 / 운동 1시간 윈도우 / cadence 경계 (00-PLAN §4 F1).
 */
class CharacterStateResolverTest {

    private val defaultProfile = CharacterProfile()   // 수면 22:00→07:00, 점심 12:00, 저녁 18:00

    private fun at(hour: Int, minute: Int = 0): LocalDateTime =
        LocalDateTime.of(2026, 1, 15, hour, minute)

    private fun epochMillis(dt: LocalDateTime): Long =
        dt.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()

    // MARK: - 수면 창 (자정 넘김)

    @Test
    fun `자정 전 수면 창 안이면 sleeping`() {
        assertEquals(CharacterState.SLEEPING, CharacterStateResolver.resolve(now = at(23, 30)))
    }

    @Test
    fun `자정 후 수면 창 안이면 sleeping`() {
        assertEquals(CharacterState.SLEEPING, CharacterStateResolver.resolve(now = at(3, 0)))
    }

    @Test
    fun `수면 창 밖 낮 시간은 idle`() {
        assertEquals(CharacterState.IDLE, CharacterStateResolver.resolve(now = at(15, 0)))
    }

    @Test
    fun `기상 후 60분 안이면 wakingUp`() {
        assertEquals(CharacterState.WAKING_UP, CharacterStateResolver.resolve(now = at(7, 30)))
        // 60분 경계 밖
        assertEquals(CharacterState.IDLE, CharacterStateResolver.resolve(now = at(8, 0)))
    }

    @Test
    fun `식사 시간은 eating (시작 후 30분)`() {
        assertEquals(CharacterState.EATING, CharacterStateResolver.resolve(now = at(12, 10)))
        assertEquals(CharacterState.EATING, CharacterStateResolver.resolve(now = at(18, 29)))
        assertEquals(CharacterState.IDLE, CharacterStateResolver.resolve(now = at(12, 30)))
    }

    // MARK: - focusWokeAt (이번 밤 창에서 수면 모드를 껐으면 기상 존중)

    @Test
    fun `이번 밤에 수면 모드를 껐으면 수면 창이어도 sleeping 아님`() {
        val now = at(23, 0)
        val wokeAt = at(22, 30)   // 오늘 22:00 창 시작 이후
        val result = CharacterStateResolver.resolve(now = now, focusWokeAt = wokeAt)
        assertEquals(CharacterState.IDLE, result)
    }

    @Test
    fun `어제 껐던 기록은 오늘 밤에 영향 없음`() {
        val now = at(23, 0)
        val wokeAt = at(22, 30).minusDays(1)   // 어젯밤 — 이번 창 시작(오늘 22:00) 이전
        val result = CharacterStateResolver.resolve(now = now, focusWokeAt = wokeAt)
        assertEquals(CharacterState.SLEEPING, result)
    }

    @Test
    fun `자정 넘긴 새벽에도 이번 밤 창의 woke 는 유효`() {
        val now = at(2, 0)                       // 새벽 2시 (창 시작 = 어제 22:00)
        val wokeAt = at(1, 30)                   // 창 시작 이후
        assertEquals(CharacterState.IDLE, CharacterStateResolver.resolve(now = now, focusWokeAt = wokeAt))
    }

    // MARK: - 수면 신호 우선순위

    @Test
    fun `inSleepSchedule 확정 신호는 시간대와 무관하게 sleeping`() {
        assertEquals(
            CharacterState.SLEEPING,
            CharacterStateResolver.resolve(now = at(15, 0), inSleepSchedule = true),
        )
    }

    @Test
    fun `DND(isGenericFocusActive)는 수면 창 안에서만 sleeping`() {
        assertEquals(
            CharacterState.SLEEPING,
            CharacterStateResolver.resolve(now = at(23, 0), isGenericFocusActive = true),
        )
        assertEquals(
            CharacterState.IDLE,
            CharacterStateResolver.resolve(now = at(15, 0), isGenericFocusActive = true),
        )
    }

    // MARK: - 운동 1시간 윈도우

    @Test
    fun `운동 종료 후 1시간 안이면 운동 상태 유지`() {
        val now = at(15, 0)
        // 90분 전 시작, 60분 운동 → 30분 전 종료
        val workout = WorkoutSummary(
            activity = WorkoutActivity.RUNNING,
            start = epochMillis(now.minusMinutes(90)),
            durationSeconds = 3600.0,
        )
        assertEquals(
            CharacterState.RUNNING,
            CharacterStateResolver.resolve(now = now, workouts = listOf(workout)),
        )
    }

    @Test
    fun `운동 종료 후 1시간 지나면 무시`() {
        val now = at(15, 0)
        // 3시간 전 시작, 60분 운동 → 2시간 전 종료
        val workout = WorkoutSummary(
            activity = WorkoutActivity.RUNNING,
            start = epochMillis(now.minusHours(3)),
            durationSeconds = 3600.0,
        )
        assertEquals(
            CharacterState.IDLE,
            CharacterStateResolver.resolve(now = now, workouts = listOf(workout)),
        )
    }

    @Test
    fun `mapWorkout - hiking 은 walking, 미지 종목은 energetic`() {
        val now = at(15, 0)
        fun recent(activity: WorkoutActivity) = listOf(
            WorkoutSummary(activity, epochMillis(now.minusMinutes(30)), 600.0),
        )
        assertEquals(
            CharacterState.WALKING,
            CharacterStateResolver.resolve(now = now, workouts = recent(WorkoutActivity.HIKING)),
        )
        assertEquals(
            CharacterState.CYCLING,
            CharacterStateResolver.resolve(now = now, workouts = recent(WorkoutActivity.CYCLING)),
        )
        assertEquals(
            CharacterState.ENERGETIC,
            CharacterStateResolver.resolve(now = now, workouts = recent(WorkoutActivity.YOGA)),
        )
    }

    // MARK: - cadence 경계 (HR 추론)

    @Test
    fun `cadence 130 이상이면 running, 40 이상이면 walking, 미만이면 energetic`() {
        val now = at(15, 0)
        fun resolve(spm: Double) = CharacterStateResolver.resolve(
            now = now, isLikelyInWorkout = true, recentStepsPerMinute = spm,
        )
        assertEquals(CharacterState.RUNNING, resolve(130.0))
        assertEquals(CharacterState.WALKING, resolve(129.9))
        assertEquals(CharacterState.WALKING, resolve(40.0))
        assertEquals(CharacterState.ENERGETIC, resolve(39.9))
    }

    // MARK: - 폰 모션 보조 (1.5 순위)

    @Test
    fun `phoneWorkoutState 는 수면 신호가 없을 때만 반영`() {
        assertEquals(
            CharacterState.WALKING,
            CharacterStateResolver.resolve(now = at(15, 0), phoneWorkoutState = CharacterState.WALKING),
        )
        // 수면 세션 진행 중이면 폰 모션 무시 → sleeping
        assertEquals(
            CharacterState.SLEEPING,
            CharacterStateResolver.resolve(
                now = at(23, 0),
                inSleepSchedule = true,
                phoneWorkoutState = CharacterState.WALKING,
            ),
        )
    }

    // MARK: - isNowInSleepWindow (프로필 화면 공유 판정)

    @Test
    fun `isNowInSleepWindow - 자정 넘김 창 판정`() {
        assertTrue(CharacterStateResolver.isNowInSleepWindow(at(23, 0), defaultProfile))
        assertTrue(CharacterStateResolver.isNowInSleepWindow(at(3, 0), defaultProfile))
        assertFalse(CharacterStateResolver.isNowInSleepWindow(at(7, 0), defaultProfile))
        assertFalse(CharacterStateResolver.isNowInSleepWindow(at(15, 0), defaultProfile))
    }
}
