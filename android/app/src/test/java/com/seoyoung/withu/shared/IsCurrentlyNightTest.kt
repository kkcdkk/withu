package com.seoyoung.withu.shared

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * isCurrentlyNight 순수 함수 테스트 — 일출일몰 / 스테일 날짜(분만 비교) / fallback wrap.
 */
class IsCurrentlyNightTest {

    private fun m(hour: Int, minute: Int = 0) = hour * 60 + minute

    // MARK: - 일출/일몰 기준 (둘 다 있을 때)

    @Test
    fun `일출 전은 밤`() {
        assertTrue(CharacterImageStore.isCurrentlyNight(m(5), sunriseMinuteOfDay = m(6, 30), sunsetMinuteOfDay = m(19)))
    }

    @Test
    fun `낮 시간은 밤 아님`() {
        assertFalse(CharacterImageStore.isCurrentlyNight(m(12), sunriseMinuteOfDay = m(6, 30), sunsetMinuteOfDay = m(19)))
    }

    @Test
    fun `일몰 시각부터 밤 (경계 포함)`() {
        assertTrue(CharacterImageStore.isCurrentlyNight(m(19), sunriseMinuteOfDay = m(6, 30), sunsetMinuteOfDay = m(19)))
        assertFalse(CharacterImageStore.isCurrentlyNight(m(18, 59), sunriseMinuteOfDay = m(6, 30), sunsetMinuteOfDay = m(19)))
    }

    @Test
    fun `일출 시각부터 낮 (경계)`() {
        assertFalse(CharacterImageStore.isCurrentlyNight(m(6, 30), sunriseMinuteOfDay = m(6, 30), sunsetMinuteOfDay = m(19)))
        assertTrue(CharacterImageStore.isCurrentlyNight(m(6, 29), sunriseMinuteOfDay = m(6, 30), sunsetMinuteOfDay = m(19)))
    }

    /** 저장된 일출/일몰의 절대 날짜가 어제여도 분만 비교하므로 결과가 같다 (스테일 안전). */
    @Test
    fun `스테일 날짜여도 분 비교라 안전 - 분 값만 같으면 결과 동일`() {
        // 같은 분 값 → 같은 판정 (절대 날짜는 시그니처에 아예 없음 — 분만 받는 설계 자체가 방어)
        val night = CharacterImageStore.isCurrentlyNight(m(23), sunriseMinuteOfDay = m(7), sunsetMinuteOfDay = m(18))
        assertTrue(night)
    }

    // MARK: - fallback (일출/일몰 없음 — 기본 20:00~06:00, 자정 넘김 wrap)

    @Test
    fun `fallback - 자정 넘김 wrap 판정`() {
        assertTrue(CharacterImageStore.isCurrentlyNight(m(23)))    // 밤
        assertTrue(CharacterImageStore.isCurrentlyNight(m(20)))    // 시작 경계 포함
        assertTrue(CharacterImageStore.isCurrentlyNight(m(5, 59))) // 종료 직전
        assertFalse(CharacterImageStore.isCurrentlyNight(m(6)))    // 종료 경계 제외
        assertFalse(CharacterImageStore.isCurrentlyNight(m(12)))
        assertFalse(CharacterImageStore.isCurrentlyNight(m(19, 59)))
    }

    @Test
    fun `fallback - wrap 없는 커스텀 구간 (start 가 end 보다 작을 때)`() {
        // 01:00 ~ 05:00
        assertTrue(CharacterImageStore.isCurrentlyNight(m(2), fallbackStartMinute = m(1), fallbackEndMinute = m(5)))
        assertFalse(CharacterImageStore.isCurrentlyNight(m(6), fallbackStartMinute = m(1), fallbackEndMinute = m(5)))
        assertFalse(CharacterImageStore.isCurrentlyNight(m(0, 59), fallbackStartMinute = m(1), fallbackEndMinute = m(5)))
    }

    @Test
    fun `fallback - 1440 넘는 입력도 정규화`() {
        // 시작 26:00(=02:00) → 02:00~06:00
        assertTrue(CharacterImageStore.isCurrentlyNight(m(3), fallbackStartMinute = 26 * 60, fallbackEndMinute = m(6)))
        assertFalse(CharacterImageStore.isCurrentlyNight(m(1), fallbackStartMinute = 26 * 60, fallbackEndMinute = m(6)))
    }
}
