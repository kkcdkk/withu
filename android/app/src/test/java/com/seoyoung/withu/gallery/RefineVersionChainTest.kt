package com.seoyoung.withu.gallery

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * 다듬기 버전 체인 상한 규칙 테스트 (A-3 공통 규칙 — iOS CharacterGalleryView.swift:1194).
 * 상한 8, 초과 시 [0](원본)은 보존하고 가장 오래된 '다듬음'(index 1)부터 밀어낸다.
 */
class RefineVersionChainTest {

    @Test
    fun `상한 아래면 그냥 뒤에 붙는다`() {
        assertEquals(listOf("o", "r1"), appendRefineVersion(listOf("o"), "r1"))
        assertEquals(listOf("o", "r1", "r2"), appendRefineVersion(listOf("o", "r1"), "r2"))
    }

    @Test
    fun `정확히 상한까지는 밀어내지 않는다`() {
        val seven = listOf("o", "r1", "r2", "r3", "r4", "r5", "r6")
        val result = appendRefineVersion(seven, "r7")
        assertEquals(8, result.size)
        assertEquals(seven + "r7", result)
    }

    @Test
    fun `상한 초과 시 원본은 보존하고 가장 오래된 다듬기를 버린다`() {
        val full = listOf("o", "r1", "r2", "r3", "r4", "r5", "r6", "r7")
        val result = appendRefineVersion(full, "r8")
        assertEquals(8, result.size)
        assertEquals("o", result.first())          // [0] 원본은 항상 남는다
        assertEquals("r8", result.last())
        assertEquals(listOf("o", "r2", "r3", "r4", "r5", "r6", "r7", "r8"), result)
    }

    @Test
    fun `상한을 반복해서 넘겨도 원본은 계속 살아남는다`() {
        var chain = listOf("o")
        repeat(20) { i -> chain = appendRefineVersion(chain, "r${i + 1}") }
        assertEquals(8, chain.size)
        assertEquals("o", chain.first())
        assertEquals("r20", chain.last())
        assertEquals(listOf("o", "r14", "r15", "r16", "r17", "r18", "r19", "r20"), chain)
    }

    @Test
    fun `상한이 2면 원본 + 최신 다듬기 1개만 남는다`() {
        var chain = listOf("o")
        repeat(5) { i -> chain = appendRefineVersion(chain, "r${i + 1}", limit = 2) }
        assertEquals(listOf("o", "r5"), chain)
    }
}
