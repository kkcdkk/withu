package com.seoyoung.withu.shared

import android.graphics.Bitmap
import android.graphics.Color
import com.seoyoung.withu.character.CharacterState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * CharacterImageStore 파일 규칙 테스트 (Robolectric) —
 * 핵심: frame0 저장 시 옛 _f1 삭제 규칙 (00-PLAN 위험 #4 "옛 프레임과 섞여 움직이는 버그").
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = com.seoyoung.withu.WithuApp::class)
class CharacterImageStoreTest {

    private val state = CharacterState.IDLE

    private fun bitmap(color: Int = Color.RED): Bitmap =
        Bitmap.createBitmap(4, 4, Bitmap.Config.ARGB_8888).apply { eraseColor(color) }

    @Before
    fun setUp() {
        CharacterImageStore.wipeAll()
    }

    // MARK: - frame0 저장 → 옛 f1 삭제

    @Test
    fun `saveActiveSlotOnly frame0 는 기존 f1 을 삭제한다`() {
        CharacterImageStore.saveActiveSlotOnly(bitmap(), state, frame = 0)
        CharacterImageStore.saveActiveSlotOnly(bitmap(Color.BLUE), state, frame = 1)
        assertTrue(CharacterImageStore.hasAnimationFrames(state))

        // 새 frame0 저장 → 옛 f1 은 무효 (섞여 움직이는 버그 방지)
        CharacterImageStore.saveActiveSlotOnly(bitmap(Color.GREEN), state, frame = 0)
        assertFalse(CharacterImageStore.hasAnimationFrames(state))
        assertTrue(CharacterImageStore.hasImage(state))
    }

    @Test
    fun `save frame0 도 기존 f1 을 삭제한다`() {
        CharacterImageStore.save(bitmap(), state)
        CharacterImageStore.saveActiveSlotOnly(bitmap(Color.BLUE), state, frame = 1)
        assertTrue(CharacterImageStore.hasAnimationFrames(state))

        CharacterImageStore.save(bitmap(Color.GREEN), state)
        assertFalse(CharacterImageStore.hasAnimationFrames(state))
    }

    // MARK: - 갤러리 저장/frame1 첨부

    @Test
    fun `save frame0 는 갤러리 항목을 만들고 활성 매핑을 기록한다`() {
        val item = CharacterImageStore.save(bitmap(), state, batchId = "b1", prompt = "p")
        assertNotNull(item)
        assertEquals(state.raw, item!!.sourceState)
        assertEquals("b1", item.batchId)
        assertEquals(item.id, CharacterImageStore.currentGalleryItemId(state))
        assertEquals(listOf(state), CharacterImageStore.statesUsingGalleryItem(item.id))
    }

    @Test
    fun `save frame1 은 같은 state 최신 항목에 hasFrame1 을 붙인다`() {
        val item = CharacterImageStore.save(bitmap(), state)!!
        val updated = CharacterImageStore.save(bitmap(Color.BLUE), state, frame = 1)
        assertNotNull(updated)
        assertEquals(item.id, updated!!.id)
        assertEquals(true, updated.hasFrame1)
        assertNotNull(CharacterImageStore.loadGalleryFrame1(item.id))
    }

    @Test
    fun `frame0 없이 frame1 만 저장하면 null (정상 흐름에 없음)`() {
        assertNull(CharacterImageStore.save(bitmap(), state, frame = 1))
    }

    // MARK: - applyGalleryItem 의 f1 규칙

    @Test
    fun `f1 없는 갤러리 항목 적용 시 active 의 기존 f1 을 지운다`() {
        // 애니 캐릭터 적용 상태 만들기
        CharacterImageStore.save(bitmap(), state)
        CharacterImageStore.saveActiveSlotOnly(bitmap(Color.BLUE), state, frame = 1)
        assertTrue(CharacterImageStore.hasAnimationFrames(state))

        // f1 없는 새 갤러리 항목 (활성 미적용으로 저장)
        val plain = CharacterImageStore.save(
            bitmap(Color.GREEN), state, applyToActiveSlot = false,
        )!!
        assertTrue(CharacterImageStore.applyGalleryItem(plain.id, state))
        // 다른 캐릭터의 f1 잔재가 남으면 안 됨
        assertFalse(CharacterImageStore.hasAnimationFrames(state))
    }

    // MARK: - deleteGalleryItem

    @Test
    fun `삭제는 매핑만 끊고 활성 PNG 는 남긴다`() {
        val item = CharacterImageStore.save(bitmap(), state)!!
        CharacterImageStore.deleteGalleryItem(item.id)
        assertNull(CharacterImageStore.currentGalleryItemId(state))
        assertNull(CharacterImageStore.loadGalleryImage(item.id))
        assertTrue(CharacterImageStore.loadGalleryMetadata().isEmpty())
        // 이미 적용된 그림은 계속 보임
        assertTrue(CharacterImageStore.hasImage(state))
    }

    // MARK: - 그룹핑 정렬

    @Test
    fun `loadGalleryByCharacter 는 userFacing 순서로 정렬한다`() {
        CharacterImageStore.save(bitmap(), CharacterState.RUNNING, batchId = "b1")
        CharacterImageStore.save(bitmap(), CharacterState.IDLE, batchId = "b1")
        val groups = CharacterImageStore.loadGalleryByCharacter()
        assertEquals(1, groups.size)
        assertEquals(
            listOf(CharacterState.IDLE.raw, CharacterState.RUNNING.raw),
            groups[0].items.map { it.sourceState },
        )
    }
}
