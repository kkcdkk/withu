package com.seoyoung.withu.bggen

import android.graphics.Bitmap
import com.seoyoung.withu.character.CharacterState
import kotlinx.serialization.Serializable

/**
 * 배치 백그라운드 생성 큐 모델 — iOS BackgroundGenerationManager.swift 의
 * BackgroundGenJob/Spec/Phase 포팅 (00-PLAN §2-9, 스펙 11 §4.2).
 */

/** 배치 단계 — anchor(기준 idle 1장) / rest(승인 후 나머지) / retry(한 장만 — 완료 알림 억제). */
enum class BgGenPhase(val raw: String) {
    ANCHOR("anchor"), REST("rest"), RETRY("retry");

    companion object {
        fun fromRaw(raw: String): BgGenPhase = entries.firstOrNull { it.raw == raw } ?: REST
    }
}

/** 잡 상태 — BgGenJob.status 의 rawValue (스키마는 문자열 저장 — iOS Codable enum 동형). */
enum class BgGenStatus(val raw: String) {
    QUEUED("queued"), RUNNING("running"), DONE("done"), FAILED("failed")
}

/**
 * 영속 잡 레코드 — filesDir/bggen/jobs.json 의 원소 (필드명 iOS 와 동일, camelCase).
 * id 는 Idempotency-Key 로도 사용 — 재전송돼도 서버가 중복 처리하지 않는다.
 */
@Serializable
data class BgGenJob(
    val id: String,
    val stateRaw: String,          // CharacterState.raw — 디스크/메시지 호환 키
    val frame: Int,                // 0 = 기본, 1 = 움직임 프레임
    val quality: String,
    val artStyle: String,
    val batchId: String,
    val wantsFrame1: Boolean = false,
    val frame1Prompt: String? = null,
    val status: String = "queued",       // BgGenStatus.raw
    val errorMessage: String? = null,
    val startedAt: Long? = null,         // epoch millis
    /** 402 실패 표시 — 뷰가 완료 알럿 대신 페이월을 띄우는 근거. */
    val paymentRequired: Boolean? = null,
    /** 본문 없는 2xx 재큐잉 상한(2) 카운터. */
    val attempts: Int? = null,
    /** true = 색을 idle 앵커에 맞춤. idle 자신·per-state 사진은 false. */
    val matchIdleColor: Boolean? = null,
    /** 갤러리 '만든 기록' 저장용. 옛 잡은 null. */
    val prompt: String? = null,
)

/** 큐 시작/재시도 입력 스펙 (뷰 → 큐). */
data class BgGenSpec(
    val state: CharacterState,
    val frame: Int = 0,
    val prompt: String,
    val referenceImageBase64: String? = null,
    val wantsFrame1: Boolean = false,
    val frame1Prompt: String? = null,
    val matchIdleColor: Boolean = false,
)

/**
 * 뷰가 관찰하는 스냅샷 — StateFlow 로 노출 (iOS @Observable + tick 대응).
 * images 는 "raw#frame" → 128px 썸네일, **메모리 전용** — 프로세스 재시작 후엔 비어 있고
 * 뷰는 반드시 CharacterImageStore.loadFrame fallback (스펙 03 syncFromManager).
 */
data class BgGenState(
    val jobs: List<BgGenJob>,
    val phase: BgGenPhase,
    val images: Map<String, Bitmap>,
    val tick: Long,
) {
    val isActive: Boolean
        get() = jobs.any { it.status == BgGenStatus.QUEUED.raw || it.status == BgGenStatus.RUNNING.raw }
    val doneCount: Int get() = jobs.count { it.status == BgGenStatus.DONE.raw }
    val failedCount: Int get() = jobs.count { it.status == BgGenStatus.FAILED.raw }
}
