package com.seoyoung.withu.home

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * B-4 '잠 깨는 중' 구간 끝 계산 (iOS ContentView.swift:1307-1308).
 * 일어나는 시간 + 60분, 24시 wrap.
 */
class WakingWindowEndTest {

    @Test
    fun `정시 기상은 한 시간 뒤`() {
        assertEquals(8 to 0, wakingWindowEnd(7, 0))
    }

    @Test
    fun `분이 있으면 그대로 한 시간 더한다`() {
        assertEquals(7 to 30, wakingWindowEnd(6, 30))
    }

    @Test
    fun `자정을 넘으면 다음 날로 wrap`() {
        assertEquals(0 to 0, wakingWindowEnd(23, 0))
        assertEquals(0 to 45, wakingWindowEnd(23, 45))
    }

    @Test
    fun `자정 기상은 새벽 1시`() {
        assertEquals(1 to 0, wakingWindowEnd(0, 0))
    }
}
