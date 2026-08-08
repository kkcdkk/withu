package com.seoyoung.withu.gen

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 단건 생성 잡의 **영속 직렬화 + 상태 전이** 규칙 테스트.
 * 이 규칙들이 깨지면 "앱이 죽어도 생성이 이어진다"가 성립하지 않으므로 순수 함수로 떼어내 검증한다.
 * (네트워크/Bitmap 이 섞인 SingleGenQueue 본체는 실기기 검증 몫.)
 */
class SingleGenJobTest {

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = false; explicitNulls = false }

    private fun job(
        frame: Int = 0,
        wantsFrame1: Boolean = false,
        frame1Prompt: String? = null,
        attempts: Int = 0,
    ) = SingleGenJob(
        id = "job-1",
        stateRaw = "idle",
        sessionId = "session-1",
        quality = "low",
        artStyle = "pixel",
        isRefine = false,
        frame = frame,
        prompt = "a cat",
        wantsFrame1 = wantsFrame1,
        frame1Prompt = frame1Prompt,
        attempts = attempts,
        queuedAt = 1_700_000_000_000L,
    )

    // MARK: - 영속 (프로세스 사망 후 이어가기)

    @Test
    fun `잡은 JSON 왕복 후에도 진행 정보를 잃지 않는다`() {
        val original = job(frame = 1, wantsFrame1 = true, frame1Prompt = "pose B", attempts = 1).copy(
            status = SingleGenStatus.RUNNING.raw,
            freeConsumed = true,
            galleryPrompt = "a cat. transparent",
            revisedPrompt = "revised",
            startedAt = 1_700_000_001_000L,
        )
        val text = json.encodeToString(SingleGenJob.serializer(), original)
        val restored = json.decodeFromString(SingleGenJob.serializer(), text)
        assertEquals(original, restored)
    }

    @Test
    fun `옛 스키마에 없던 필드는 기본값으로 복원된다`() {
        // 필수 필드만 있는 최소 JSON — 앱 업데이트로 필드가 늘어도 저장본을 못 읽으면 안 된다.
        val minimal = """
            {"id":"j","stateRaw":"idle","sessionId":"s","quality":"low",
             "artStyle":"pixel","isRefine":false,"frame":0,"prompt":"p"}
        """.trimIndent()
        val restored = json.decodeFromString(SingleGenJob.serializer(), minimal)
        assertEquals(SingleGenStatus.QUEUED.raw, restored.status)
        assertEquals(0, restored.attempts)
        assertFalse(restored.freeConsumed)
        assertFalse(restored.paymentRequired)
        assertNull(restored.resultGalleryId)
        assertTrue(restored.isActive)
    }

    @Test
    fun `Idempotency 키는 프레임마다 다르다`() {
        // 같은 잡의 frame0 과 frame1 이 같은 키를 쓰면 서버가 두 번째를 중복으로 버린다.
        assertEquals("job-1#0", job(frame = 0).idempotencyKey)
        assertEquals("job-1#1", job(frame = 1).idempotencyKey)
    }

    // MARK: - 상태 전이

    @Test
    fun `queued 와 running 만 진행 중이다`() {
        assertTrue(job().copy(status = SingleGenStatus.QUEUED.raw).isActive)
        assertTrue(job().copy(status = SingleGenStatus.RUNNING.raw).isActive)
        assertFalse(job().copy(status = SingleGenStatus.DONE.raw).isActive)
        assertFalse(job().copy(status = SingleGenStatus.FAILED.raw).isActive)
        assertTrue(job().copy(status = SingleGenStatus.DONE.raw).isDone)
        assertTrue(job().copy(status = SingleGenStatus.FAILED.raw).isFailed)
    }

    @Test
    fun `움직이는 캐릭터는 frame0 성공 후 frame1 로 승격된다`() {
        val running = job(frame = 0, wantsFrame1 = true, frame1Prompt = "pose B", attempts = 1)
            .copy(status = SingleGenStatus.RUNNING.raw, startedAt = 1L)
        val next = nextFrameStage(running)
        assertNotNull(next)
        assertEquals(1, next!!.frame)
        assertEquals("pose B", next.prompt)
        assertEquals(SingleGenStatus.QUEUED.raw, next.status)
        // 새 프레임은 재시도 카운터/시작시각을 새로 센다.
        assertEquals(0, next.attempts)
        assertNull(next.startedAt)
        // 잡 id 는 유지 — 같은 세션(수정 체인)의 두 프레임이다.
        assertEquals(running.id, next.id)
    }

    @Test
    fun `움직임을 원하지 않거나 프롬프트가 없으면 승격하지 않는다`() {
        assertNull(nextFrameStage(job(frame = 0, wantsFrame1 = false, frame1Prompt = "pose B")))
        assertNull(nextFrameStage(job(frame = 0, wantsFrame1 = true, frame1Prompt = null)))
    }

    @Test
    fun `frame1 은 다시 승격되지 않는다`() {
        // 무한 체이닝 방지 — frame1 성공은 언제나 마무리다.
        assertNull(nextFrameStage(job(frame = 1, wantsFrame1 = true, frame1Prompt = "pose B")))
    }

    // MARK: - 본문 없는 2xx 재큐잉 (앱이 죽은 사이 완료된 요청)

    @Test
    fun `본문 없는 2xx 는 1회만 재큐잉한다`() {
        assertTrue(shouldRequeueEmptyBody(null, attempts = 1))
        assertTrue(shouldRequeueEmptyBody(ByteArray(0), attempts = 1))
        // 이미 2번 시도했으면 더 돌리지 않는다 (무한 재생성 방지).
        assertFalse(shouldRequeueEmptyBody(null, attempts = 2))
        assertFalse(shouldRequeueEmptyBody(null, attempts = 3))
    }

    @Test
    fun `본문이 있으면 재큐잉 대상이 아니다`() {
        assertFalse(shouldRequeueEmptyBody("{}".toByteArray(), attempts = 0))
    }
}
