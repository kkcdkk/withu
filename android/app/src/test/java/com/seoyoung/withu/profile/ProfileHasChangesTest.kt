package com.seoyoung.withu.profile

import com.seoyoung.withu.character.CharacterProfile
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A-4 저장 안 한 변경 판정 (iOS CharacterProfileView.swift:209-211 hasChanges).
 * 초안(profile) 또는 애니메이션 토글이 마지막 '저장' 스냅샷과 다르면 true.
 */
class ProfileHasChangesTest {

    @Test
    fun `초안과 스냅샷이 같으면 변경 없음`() {
        val p = CharacterProfile()
        assertFalse(profileHasChanges(p, p, animationEnabled = true, savedAnimationEnabled = true))
    }

    @Test
    fun `수면 시간을 바꾸면 변경 있음`() {
        val saved = CharacterProfile()
        val draft = saved.copy(sleepEndHour = saved.sleepEndHour + 1)
        assertTrue(profileHasChanges(draft, saved, animationEnabled = true, savedAnimationEnabled = true))
    }

    @Test
    fun `이름만 바꿔도 변경 있음`() {
        val saved = CharacterProfile()
        val draft = saved.copy(name = "새싹이")
        assertTrue(profileHasChanges(draft, saved, animationEnabled = true, savedAnimationEnabled = true))
    }

    @Test
    fun `프로필이 같아도 애니메이션 토글만 바뀌면 변경 있음`() {
        val p = CharacterProfile()
        assertTrue(profileHasChanges(p, p, animationEnabled = false, savedAnimationEnabled = true))
    }

    @Test
    fun `저장 후 스냅샷을 맞추면 다시 변경 없음`() {
        val saved = CharacterProfile()
        val draft = saved.copy(lunchHour = 13, manualSleepOnly = true)
        assertTrue(profileHasChanges(draft, saved, animationEnabled = false, savedAnimationEnabled = true))
        // save() 가 스냅샷을 초안으로 끌어올린 뒤
        assertFalse(profileHasChanges(draft, draft, animationEnabled = false, savedAnimationEnabled = false))
    }
}
