package com.seoyoung.withu.shared

import com.seoyoung.withu.character.CharacterState
import kotlinx.serialization.Serializable

/**
 * 갤러리 한 항목 — gallery/metadata.json 의 원소. iOS GalleryItem 과 동형 스키마.
 * createdAt 은 epoch millis (iOS 는 referenceDate 초지만 Android 파일은 자체 소유 — 필드명만 동일).
 * 옵셔널 3개는 옛 메타에 키가 없을 수 있어 null 허용 (스펙 09 §3-1).
 */
@Serializable
data class GalleryItem(
    val id: String,
    val sourceState: String,
    val createdAt: Long,
    /** 연속 이미지(frame 1) 동봉 여부. null/false 면 frame 0 만. */
    val hasFrame1: Boolean? = null,
    /** '한번에 만들기'(배치) 세션 id. 단건/옛 항목 null. */
    val batchId: String? = null,
    /** 생성 당시 서버로 보낸 프롬프트 — '만든 기록' 표시용. 옛 항목 null. */
    val prompt: String? = null,
)

/** 상태별 그룹핑 결과 — legacy 는 더 이상 노출 안 하는 옛 상태의 "기타" 버킷. */
data class GalleryGrouped(
    val byState: Map<CharacterState, List<GalleryItem>>,
    val legacy: List<GalleryItem>,
)

/** '캐릭터별'(batchId) 그룹 — createdAt 은 그룹 내 최대값. */
data class GalleryCharacterGroup(
    val batchId: String,
    val createdAt: Long,
    val items: List<GalleryItem>,
)
