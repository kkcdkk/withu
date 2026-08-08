package com.seoyoung.withu.gen

import android.graphics.Bitmap
import com.seoyoung.withu.character.CharacterState
import kotlinx.serialization.Serializable

/**
 * '하나씩 만들기'(단건) 백그라운드 잡 모델 — bggen/BgGenModels.kt 와 같은 규약을 따르되
 * **큐가 아니라 잡 1개**만 다룬다 (단건은 동시에 하나면 충분).
 *
 * 배치 큐(`bggen/`)는 건드리지 않는다 — 회귀 위험을 피하려고 단건 전용으로 새로 만든 경로다.
 */

/** 잡 상태 — SingleGenJob.status 의 rawValue (문자열 저장 — bggen BgGenStatus 동형). */
enum class SingleGenStatus(val raw: String) {
    QUEUED("queued"), RUNNING("running"), DONE("done"), FAILED("failed")
}

/**
 * 영속 잡 레코드 — filesDir/singlegen/job.json.
 *
 * 한 잡이 최대 2번 요청한다: frame 0(기본) → (움직이는 캐릭터면) frame 1.
 * frame 0 이 성공하면 같은 레코드의 `frame` 이 1 로 승격되고 `prompt` 가 `frame1Prompt` 로 바뀐다
 * — 그래서 프로세스가 죽어도 "어디까지 했는지"가 디스크에 남는다.
 */
@Serializable
data class SingleGenJob(
    val id: String,
    /** CharacterState.raw — 디스크/메시지 호환 키. */
    val stateRaw: String,
    /** 수정 체인 = 갤러리 '캐릭터별' batchId (A-1 캐릭터 이름이 붙는 단위). */
    val sessionId: String,
    val quality: String,
    val artStyle: String,
    /** true = 다듬기(이력에 버전 추가), false = 새로 만들기(이력 갈아끼움). */
    val isRefine: Boolean,
    /** 지금 요청 중인 프레임 (0 = 기본, 1 = 움직임). */
    val frame: Int,
    /** 이번 프레임에 보낼 최종 프롬프트 (투명 배경 지시 접미까지 포함된 완성본). */
    val prompt: String,
    /** 서버 body kind — "photo" 면 계정 무료 1회를 소진하지 않는다 (A-5). */
    val serverKind: String? = null,
    /** 생성 모니터링 표시용 — 사용자가 실제 입력한 원문 / 어떤 칸이었는지. */
    val userInput: String? = null,
    val inputField: String? = null,
    /** frame 0 성공 후 움직임 프레임으로 이어갈지. */
    val wantsFrame1: Boolean = false,
    val frame1Prompt: String? = null,
    /** 갤러리 '만든 기록'에 남길 프롬프트 (iOS lastSentPrompt 대응). */
    val galleryPrompt: String? = null,
    val status: String = SingleGenStatus.QUEUED.raw,
    val errorMessage: String? = null,
    /** 402 표시 — 화면이 페이월을 띄우는 근거. */
    val paymentRequired: Boolean = false,
    /** 현재 프레임의 시도 횟수 — 본문 없는 2xx 재큐잉 상한 카운터. */
    val attempts: Int = 0,
    /** 큐에 올린 시각 (epoch millis) — 화면 경과 타이머('그리는 중… N초') 기준. */
    val queuedAt: Long = 0L,
    val startedAt: Long? = null,
    /** frame 0 응답의 free_consumed — true 면 이 세션 전체(프레임 2장) 미차감. */
    val freeConsumed: Boolean = false,
    /** 서버가 실제로 쓴 프롬프트 (frame 0 응답) — 결과 카드의 '실제 사용한 설명'. */
    val revisedPrompt: String? = null,
    /** 완료 결과의 갤러리 항목 id — 화면은 이걸 통해 결과를 집어온다. */
    val resultGalleryId: String? = null,
) {
    val isActive: Boolean
        get() = status == SingleGenStatus.QUEUED.raw || status == SingleGenStatus.RUNNING.raw

    val isDone: Boolean get() = status == SingleGenStatus.DONE.raw
    val isFailed: Boolean get() = status == SingleGenStatus.FAILED.raw

    /**
     * 프레임마다 다른 Idempotency-Key — 재전송돼도 서버가 중복 처리하지 않고,
     * frame 0/1 이 서로 같은 키를 쓰지 않는다.
     */
    val idempotencyKey: String get() = "$id#$frame"
}

/** 큐 시작 입력 (뷰 → 큐). Bitmap 들은 start() 안에서 디스크로 옮겨진다. */
class SingleGenSpec(
    val state: CharacterState,
    val sessionId: String,
    val quality: String,
    val artStyle: String,
    val isRefine: Boolean,
    val frame: Int,
    val prompt: String,
    val referenceBase64: String? = null,
    val serverKind: String? = null,
    val userInput: String? = null,
    val inputField: String? = null,
    val wantsFrame1: Boolean = false,
    val frame1Prompt: String? = null,
    val galleryPrompt: String? = null,
    /** 다듬기 기준 이미지 — 이번에 안 바뀌는 쪽(결과 합성용). */
    val baseFrame0: Bitmap? = null,
    val baseFrame1: Bitmap? = null,
    /** frame 1 크기·위치·색 정규화 앵커 (frame 0 원본 1024). */
    val anchor: Bitmap? = null,
)

/** 뷰가 관찰하는 스냅샷 — 잡이 없으면 job = null (진행 중 아님). */
data class SingleGenSnapshot(
    val job: SingleGenJob?,
    /** 마지막 응답의 서버 잔액 — 화면의 무료 1회 배지(A-5) 근거. */
    val entitlement: com.seoyoung.withu.net.Entitlement?,
    val tick: Long,
)

// MARK: - 순수 규칙 (유닛테스트 대상)

/** 본문 없는 2xx 재큐잉 상한 — 1회만 재생성 (bggen 과 동일, iOS attempts < 2). */
internal const val SINGLE_GEN_MAX_ATTEMPTS = 2

/**
 * 2xx 인데 본문이 없을 때 재큐잉할지 — 앱이 죽은 사이 완료된 요청은 본문이 유실될 수 있어
 * 한 번만 다시 생성한다 (bggen 의 'iOS 한계' 대응과 같은 규칙).
 */
internal fun shouldRequeueEmptyBody(
    body: ByteArray?,
    attempts: Int,
    maxAttempts: Int = SINGLE_GEN_MAX_ATTEMPTS,
): Boolean = (body == null || body.isEmpty()) && attempts < maxAttempts

/**
 * frame 0 성공 뒤 이어갈 다음 단계 — 움직이는 캐릭터면 frame 1 잡으로 승격, 아니면 null(마무리).
 * attempts/startedAt 은 새 프레임 기준으로 리셋된다.
 */
internal fun nextFrameStage(job: SingleGenJob): SingleGenJob? {
    if (job.frame != 0 || !job.wantsFrame1) return null
    val next = job.frame1Prompt ?: return null
    return job.copy(
        frame = 1,
        prompt = next,
        status = SingleGenStatus.QUEUED.raw,
        attempts = 0,
        startedAt = null,
    )
}
