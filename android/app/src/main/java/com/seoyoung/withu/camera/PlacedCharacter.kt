package com.seoyoung.withu.camera

import android.graphics.RectF
import androidx.compose.ui.geometry.Offset
import com.seoyoung.withu.character.CharacterState
import java.util.UUID

/**
 * 카메라 화면에 배치된 캐릭터 한 마리 — iOS PlacedCharacter.swift 포팅 (스펙 12 A-3).
 *
 * 모든 좌표/사이즈는 화면 크기로 **정규화(0~1)**.
 * '왜': 프리뷰 뷰 좌표계와 실제 사진 픽셀 좌표계가 다르므로, 0~1 로 들고 있다가
 * 합성 시 사진 크기에 다시 매핑 — 화면에서 보던 상대 위치가 결과 사진에 그대로 재현됨.
 */
data class PlacedCharacter(
    val id: String = UUID.randomUUID().toString(),
    val state: CharacterState,
    /** 정규화 중심 좌표 (0~1, (0.5, 0.5) = 화면 정중앙) */
    val position: Offset = Offset(0.5f, 0.55f),
    /** 정규화 사이즈 (정사각). 0.35 면 화면 너비의 35% */
    val size: Float = 0.35f,
    /** 회전 (라디안). 시계방향 +. */
    val rotation: Float = 0f,
) {
    /** 정규화 좌표를 실제 pixel 좌표계로 변환. 높이도 너비 기준(정사각) — iOS 동일. */
    fun rect(containerWidth: Float, containerHeight: Float): RectF {
        val w = size * containerWidth
        val h = w // 정사각
        val left = position.x * containerWidth - w / 2f
        val top = position.y * containerHeight - h / 2f
        return RectF(left, top, left + w, top + h)
    }
}
