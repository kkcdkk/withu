package com.seoyoung.withu.quota

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * GenerationQuota 순수 코어 테스트 — 자정 리셋 / syncCreditsUp delta / 음수 방지 (00-PLAN §4 F1).
 * DEBUG 빌드에선 record 가 no-op 이라 SharedPreferences 경유 대신 내부 순수 함수를 검증한다.
 */
class GenerationQuotaTest {

    // MARK: - 자정 리셋 (yyyymmdd stamp 불일치 → 카운트 0)

    @Test
    fun `날짜 stamp 가 오늘과 같으면 저장된 카운트 유지`() {
        assertEquals(3, GenerationQuota.computeUsedToday(20260115, 3, 20260115))
    }

    @Test
    fun `자정 넘어 stamp 가 바뀌면 카운트 자동 리셋`() {
        assertEquals(0, GenerationQuota.computeUsedToday(20260115, 3, 20260116))
    }

    // MARK: - record (무료 한도 → 크레딧 순서 차감, 음수 방지)

    @Test
    fun `freeDailyLimit 0 이면 전액 크레딧 차감`() {
        val r = GenerationQuota.computeRecord(n = 2, usedBase = 0, credits = 5, dailyAllowance = 0)
        assertEquals(0, r.newUsed)
        assertEquals(3, r.newCredits)
        assertTrue(r.creditsChanged)
    }

    @Test
    fun `크레딧 부족 시 음수로 내려가지 않음`() {
        val r = GenerationQuota.computeRecord(n = 3, usedBase = 0, credits = 1, dailyAllowance = 0)
        assertEquals(0, r.newCredits)
    }

    @Test
    fun `무료 한도가 있으면 한도 먼저 차감`() {
        val r = GenerationQuota.computeRecord(n = 2, usedBase = 0, credits = 5, dailyAllowance = 1)
        assertEquals(1, r.newUsed)          // 무료 1
        assertEquals(4, r.newCredits)       // 크레딧 1
    }

    @Test
    fun `무료 한도로 전부 커버되면 크레딧 불변`() {
        val r = GenerationQuota.computeRecord(n = 1, usedBase = 0, credits = 5, dailyAllowance = 3)
        assertEquals(1, r.newUsed)
        assertEquals(5, r.newCredits)
        assertFalse(r.creditsChanged)
    }

    // MARK: - syncCreditsUp (delta 가산 — 절대값 덮어쓰기 금지)

    @Test
    fun `최초 동기화 - 서버가 더 클 때만 끌어올림`() {
        assertEquals(10, GenerationQuota.computeSyncedCredits(localCredits = 3, lastSynced = null, serverCredits = 10))
        // 서버가 작으면 로컬 유지 (로컬 권위)
        assertEquals(8, GenerationQuota.computeSyncedCredits(localCredits = 8, lastSynced = null, serverCredits = 5))
    }

    @Test
    fun `delta 양수만 가산 - 로컬 차감분을 되돌리지 않음`() {
        // 서버 10→12 적립: 로컬 4 + delta 2 = 6 (12 로 덮어쓰지 않음!)
        assertEquals(6, GenerationQuota.computeSyncedCredits(localCredits = 4, lastSynced = 10, serverCredits = 12))
    }

    @Test
    fun `delta 0 또는 음수는 무시`() {
        assertEquals(4, GenerationQuota.computeSyncedCredits(localCredits = 4, lastSynced = 10, serverCredits = 10))
        assertEquals(4, GenerationQuota.computeSyncedCredits(localCredits = 4, lastSynced = 10, serverCredits = 7))
    }

    // MARK: - cost

    @Test
    fun `퀄리티별 비용 - high 6, medium 3, 기본 1`() {
        assertEquals(6, GenerationQuota.cost("high"))
        assertEquals(3, GenerationQuota.cost("medium"))
        assertEquals(1, GenerationQuota.cost("low"))
        assertEquals(1, GenerationQuota.cost("auto"))
    }
}
