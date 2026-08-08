package com.seoyoung.withu.gen

import com.seoyoung.withu.character.CharacterState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `pending_revisions/` 파일명 규칙 테스트 — iOS PendingRevisionStore
 * (BatchCharacterGenView.swift:2282-2338) 와 **바이트 동일**해야 하는 부분이라 순수 함수로 검증한다.
 *
 * iOS 규칙:
 *   썸네일  "\(state.rawValue).v\(i).png"
 *   풀해상도 "\(state.rawValue).f\(i).png"
 *   메타     "\(state.rawValue).json"
 *   삭제     lastPathComponent.hasPrefix(state.rawValue + ".")
 *   복원     pathExtension == "json" → deletingPathExtension().lastPathComponent
 */
class PendingRevisionFileNamesTest {

    @Test
    fun `파일명은 iOS 스키마 그대로`() {
        assertEquals("idle.v0.png", pendingThumbName("idle", 0))
        assertEquals("idle.f0.png", pendingFullName("idle", 0))
        assertEquals("idle.json", pendingMetaName("idle"))
        assertEquals("sleeping.v7.png", pendingThumbName("sleeping", 7))
        assertEquals("sleeping.f7.png", pendingFullName("sleeping", 7))
    }

    @Test
    fun `모든 CharacterState raw 로 파일명이 겹치지 않는다`() {
        val names = CharacterState.entries.flatMap { s ->
            listOf(pendingThumbName(s.raw, 0), pendingFullName(s.raw, 0), pendingMetaName(s.raw))
        }
        assertEquals(names.size, names.toSet().size)
    }

    @Test
    fun `삭제 접두사는 점을 포함해 접두사가 겹치는 raw 를 건드리지 않는다`() {
        // "eat" 삭제가 "eating" 파일까지 지우면 안 된다.
        val prefix = pendingFilePrefix("eat")
        assertEquals("eat.", prefix)
        assertTrue(pendingThumbName("eat", 1).startsWith(prefix))
        assertTrue(pendingMetaName("eat").startsWith(prefix))
        assertFalse(pendingThumbName("eating", 1).startsWith(prefix))
        assertFalse(pendingMetaName("eating").startsWith(prefix))
    }

    @Test
    fun `실제로 접두사가 겹치는 raw 쌍이 있어도 안전하다`() {
        val raws = CharacterState.entries.map { it.raw }
        for (a in raws) {
            val prefix = pendingFilePrefix(a)
            for (b in raws) {
                if (a == b) continue
                assertFalse(
                    "$a 삭제가 $b 파일을 지움",
                    pendingMetaName(b).startsWith(prefix) || pendingThumbName(b, 0).startsWith(prefix),
                )
            }
        }
    }

    @Test
    fun `메타 파일만 state raw 로 파싱된다`() {
        assertEquals("idle", pendingStateRawFromMetaName("idle.json"))
        assertEquals("sleeping", pendingStateRawFromMetaName(pendingMetaName("sleeping")))
        // 이미지 파일은 복원 스캔에서 제외 (iOS pathExtension == "json" 가드).
        assertNull(pendingStateRawFromMetaName("idle.v0.png"))
        assertNull(pendingStateRawFromMetaName("idle.f3.png"))
        assertNull(pendingStateRawFromMetaName("meta"))
        assertNull(pendingStateRawFromMetaName(".json"))
    }

    @Test
    fun `파싱 결과로 알려진 상태를 되찾을 수 있다`() {
        for (state in CharacterState.entries) {
            val raw = pendingStateRawFromMetaName(pendingMetaName(state.raw))
            assertEquals(state, raw?.let { CharacterState.fromRaw(it) })
        }
    }
}
