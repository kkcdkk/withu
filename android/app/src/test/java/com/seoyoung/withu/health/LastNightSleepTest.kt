package com.seoyoung.withu.health

import androidx.health.connect.client.records.SleepSessionRecord
import com.seoyoung.withu.health.HealthManager.SleepInterval
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * '오늘 활동' 수면 = 지난 밤 한 밤 분량만 — HealthManager.lastNightSummary 순수 함수 테스트.
 * 규칙(iOS HealthKitManager 포팅): 36시간 이내 종료 + 그 종료 기준 14시간 창 + asleep 계열만.
 */
class LastNightSleepTest {

    private val hour = 60L * 60L * 1000L
    private val now = 1_800_000_000_000L   // 기준 시각 (임의)

    /** now 기준 h 시간 전 시점. */
    private fun ago(h: Double): Long = now - (h * hour).toLong()

    private fun interval(startAgoH: Double, endAgoH: Double) =
        SleepInterval(ago(startAgoH), ago(endAgoH))

    // MARK: - 지난밤 집계

    @Test
    fun `지난밤 세션들만 합산한다`() {
        // 어젯밤 23시~오늘 07시 (= 11시간 전 시작, 3시간 전 종료) 를 두 구간으로 쪼갠 경우
        val summary = HealthManager.lastNightSummary(
            listOf(interval(11.0, 7.0), interval(7.0, 3.0)),
            now,
        )
        assertEquals(8.0, summary.totalAsleepSeconds / 3600.0, 0.001)
        assertEquals(2, summary.sampleCount)
        // lastNight 은 '가장 이른 시작' (iOS min)
        assertEquals(ago(11.0), summary.lastNight)
    }

    @Test
    fun `여러 stage 를 합산한다`() {
        // light 2h + deep 3h + rem 1.5h = 6.5h (사이사이 깬 구간은 caller 가 이미 제외)
        val summary = HealthManager.lastNightSummary(
            listOf(interval(11.0, 9.0), interval(9.0, 6.0), interval(5.0, 3.5)),
            now,
        )
        assertEquals(6.5, summary.totalAsleepSeconds / 3600.0, 0.001)
        assertEquals(3, summary.sampleCount)
    }

    // MARK: - 36시간 규칙

    @Test
    fun `마지막 수면이 36시간보다 오래됐으면 기록 없음`() {
        // 40시간 전에 끝난 수면만 남아 있는 경우 → 0 / null (홈은 '-' 표시)
        val summary = HealthManager.lastNightSummary(listOf(interval(48.0, 40.0)), now)
        assertEquals(0.0, summary.totalAsleepSeconds, 0.0)
        assertEquals(0, summary.sampleCount)
        assertNull(summary.lastNight)
    }

    @Test
    fun `35시간 전 종료는 아직 유효`() {
        val summary = HealthManager.lastNightSummary(listOf(interval(43.0, 35.0)), now)
        assertEquals(8.0, summary.totalAsleepSeconds / 3600.0, 0.001)
        assertEquals(1, summary.sampleCount)
    }

    @Test
    fun `구간이 아예 없으면 기록 없음`() {
        val summary = HealthManager.lastNightSummary(emptyList(), now)
        assertEquals(0.0, summary.totalAsleepSeconds, 0.0)
        assertEquals(0, summary.sampleCount)
        assertNull(summary.lastNight)
    }

    // MARK: - 14시간 창 규칙

    @Test
    fun `14시간 창 밖에서 시작한 그저께 수면은 제외`() {
        val summary = HealthManager.lastNightSummary(
            listOf(
                interval(34.0, 26.0),   // 그저께 밤 8시간 — 마지막 종료(3h 전) 기준 창 밖
                interval(11.0, 3.0),    // 지난 밤 8시간
            ),
            now,
        )
        assertEquals(8.0, summary.totalAsleepSeconds / 3600.0, 0.001)
        assertEquals(1, summary.sampleCount)
        assertEquals(ago(11.0), summary.lastNight)
    }

    @Test
    fun `같은 밤 안의 낮잠은 창 안이라 포함된다`() {
        // 마지막 종료가 3시간 전 → 창 시작 = 17시간 전. 13시간 전 낮잠은 창 안.
        val summary = HealthManager.lastNightSummary(
            listOf(interval(13.0, 12.0), interval(11.0, 3.0)),
            now,
        )
        assertEquals(9.0, summary.totalAsleepSeconds / 3600.0, 0.001)
        assertEquals(2, summary.sampleCount)
    }

    // MARK: - asleep 계열 필터 (inBed/AWAKE 제외)

    @Test
    fun `isAsleepStage 는 AWAKE 침대밖 계열을 제외한다`() {
        assertTrue(HealthManager.isAsleepStage(SleepSessionRecord.STAGE_TYPE_SLEEPING))
        assertTrue(HealthManager.isAsleepStage(SleepSessionRecord.STAGE_TYPE_LIGHT))
        assertTrue(HealthManager.isAsleepStage(SleepSessionRecord.STAGE_TYPE_DEEP))
        assertTrue(HealthManager.isAsleepStage(SleepSessionRecord.STAGE_TYPE_REM))
        // iOS 가 inBed 를 빼는 것과 같은 자리 — 깨어 있는 stage 는 수면 시간에 안 들어간다
        assertFalse(HealthManager.isAsleepStage(SleepSessionRecord.STAGE_TYPE_AWAKE))
        assertFalse(HealthManager.isAsleepStage(SleepSessionRecord.STAGE_TYPE_AWAKE_IN_BED))
        assertFalse(HealthManager.isAsleepStage(SleepSessionRecord.STAGE_TYPE_OUT_OF_BED))
        assertFalse(HealthManager.isAsleepStage(SleepSessionRecord.STAGE_TYPE_UNKNOWN))
    }
}
