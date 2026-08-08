package com.seoyoung.withu.gen

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.seoyoung.withu.R
import com.seoyoung.withu.WithuApp
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.gallery.appendRefineVersion
import com.seoyoung.withu.net.ApiErrorDetail
import com.seoyoung.withu.net.Entitlement
import com.seoyoung.withu.net.GenerateImageRequest
import com.seoyoung.withu.net.GenerateImageResponse
import com.seoyoung.withu.net.PaymentRequiredResponse
import com.seoyoung.withu.net.koreanized
import com.seoyoung.withu.notify.NotificationHelper
import com.seoyoung.withu.quota.GenerationQuota
import com.seoyoung.withu.shared.CharacterImageStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.util.UUID

/**
 * '하나씩 만들기'(단건) 영속 잡 — 화면(ViewModel)이 아니라 여기가 생성의 주인이다.
 *
 * 왜: 예전엔 `SingleGenViewModel.viewModelScope` 에서 돌아서 화면을 나가거나 OS 가 프로세스를
 * 정리하면 1~3분짜리 생성이 통째로 사라졌다. 이제 실행은 WorkManager(`GenSingleWorker`,
 * unique "singlegen") + `setForeground(dataSync)` 라 화면 꺼짐/앱 전환/화면 이탈에도 이어진다.
 * (배치 큐 `bggen/` 은 손대지 않았다 — 같은 패턴을 단건 전용으로 새로 옮긴 것.)
 *
 * 핵심 semantics:
 *  - 잡은 filesDir/singlegen/job.json 에 영속 — 프로세스 사망 후 `resumeIfNeeded()` 로 재개.
 *  - 동시에 1개만. 새 요청은 이전 잡을 교체한다.
 *  - 요청 본문은 `<jobId>.body.json` 파일 (base64 참고사진이 커서 파일이 안전).
 *  - **결과 전달은 갤러리 자동 저장 경유** — 성공하면 갤러리에 저장(A-3-c)하고
 *    다듬기 이력(A-3-b, `RefineHistoryStore`)까지 여기서 갱신한다. 화면은 복원 경로로 집어간다.
 *  - **캔디 차감(GenerationQuota.record)은 성공 판정 뒤에만** — 실패/취소는 차감 없음.
 *    (취소는 OkHttp 요청까지 끊겨 `process()` 자체가 안 불리고, 늦게 불려도 running 가드에 걸린다.)
 */
object SingleGenQueue {
    private const val WORK_NAME = "singlegen"
    private const val FOLDER = "singlegen"

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = false; explicitNulls = false }
    // 요청 본문 — snake_case 는 DTO 의 @SerialName 이 담당. 기본값(steps/width/…)도 전송.
    private val bodyJson = Json { ignoreUnknownKeys = true; encodeDefaults = true; explicitNulls = false }

    private val lock = Any()
    private var job: SingleGenJob? = null
    private var entitlement: Entitlement? = null
    private var wasCancelled = false
    private var restored = false
    private var tick = 0L
    /** 화면이 보이는 동안엔 완료 알림을 띄우지 않는다 (화면이 곧바로 결과를 보여주므로). */
    private var screenVisible = false

    private val _state = MutableStateFlow(SingleGenSnapshot(null, null, 0L))
    val state: StateFlow<SingleGenSnapshot> = _state

    // MARK: - 공개 API (화면 → 큐)

    /** 새 생성/다듬기 시작 — 이전 잡과 중간 산출물을 버리고 Worker 실행. */
    fun start(spec: SingleGenSpec) {
        val prepared: Boolean
        synchronized(lock) {
            restoreLocked()
            clearWorkFilesLocked()
            anchorFile().delete()
            wasCancelled = false
            val fresh = SingleGenJob(
                id = UUID.randomUUID().toString(),
                stateRaw = spec.state.raw,
                sessionId = spec.sessionId,
                quality = spec.quality,
                artStyle = spec.artStyle,
                isRefine = spec.isRefine,
                frame = spec.frame,
                prompt = spec.prompt,
                serverKind = spec.serverKind,
                userInput = spec.userInput,
                inputField = spec.inputField,
                wantsFrame1 = spec.wantsFrame1,
                frame1Prompt = spec.frame1Prompt,
                galleryPrompt = spec.galleryPrompt,
                queuedAt = System.currentTimeMillis(),
            )
            prepared = writeBodyLocked(fresh, spec.referenceBase64)
            spec.baseFrame0?.let { writePng(it, baseFrame0File()) }
            spec.baseFrame1?.let { writePng(it, baseFrame1File()) }
            spec.anchor?.let { writePng(it, anchorFile()) }
            job = if (prepared) {
                fresh
            } else {
                fresh.copy(
                    status = SingleGenStatus.FAILED.raw,
                    errorMessage = str(R.string.bggen_err_prepare),
                )
            }
            persistLocked()
            publishLocked()
        }
        if (prepared) enqueueWorker(ExistingWorkPolicy.REPLACE)
    }

    /**
     * '그만두기' — Worker 취소 + 잡 폐기. **캔디는 차감되지 않는다** (record 는 성공 시점에만).
     * 단, 움직이는 캐릭터에서 frame 0 이 이미 성공(=차감)했다면 그 결과는 살려서 마무리한다
     * — 차감만 하고 그림을 잃는 상황을 막는다.
     */
    fun cancel() {
        WorkManager.getInstance(WithuApp.context).cancelUniqueWork(WORK_NAME)
        synchronized(lock) {
            wasCancelled = true
            val current = job
            if (current != null && !current.isDone && outFrame0File().exists()) {
                finalizeLocked(current.copy(errorMessage = str(R.string.gen_err_cancelled)))
            } else {
                job = null
                clearWorkFilesLocked()
                persistLocked()
                publishLocked()
            }
        }
    }

    /** 화면이 끝난 잡(완료/실패)을 읽어 반영한 뒤 호출 — 같은 결과가 반복 적용되지 않게 비운다. */
    fun clearFinished(jobId: String) {
        synchronized(lock) {
            val current = job ?: return
            if (current.id != jobId || current.isActive) return
            job = null
            persistLocked()
            publishLocked()
        }
    }

    /** 단건 생성 화면이 보이는 중인지 — 보이는 동안엔 완료 알림 대신 화면이 결과를 보여준다. */
    fun setScreenVisible(visible: Boolean) {
        synchronized(lock) { screenVisible = visible }
    }

    /**
     * 앱 런치 시 재개 — job.json 복원 후 running 잡을 queued 로 강등.
     * (WorkManager 가 프로세스 사망 시 Worker 를 재시작하므로 강등이 곧 재실행.
     *  Idempotency-Key = "<id>#<frame>" 라 서버 중복 처리 없음.)
     */
    fun resumeIfNeeded() {
        val active: Boolean
        synchronized(lock) {
            restoreLocked()
            job?.let {
                if (it.status == SingleGenStatus.RUNNING.raw) {
                    job = it.copy(status = SingleGenStatus.QUEUED.raw, startedAt = null)
                }
            }
            persistLocked()
            publishLocked()
            active = job?.status == SingleGenStatus.QUEUED.raw
        }
        // KEEP — WorkManager 에 이미 남아 있는 같은 이름의 작업을 중복 실행하지 않게.
        if (active) enqueueWorker(ExistingWorkPolicy.KEEP)
    }

    /** frame 0 원본(1024, 투명) — 다듬기/움직임 프레임의 정규화 앵커. 없으면 null. */
    fun loadAnchorFullRes(): Bitmap? = decodePng(anchorFile())

    // MARK: - Worker 전용 내부 API (GenSingleWorker 만 호출)

    /** queued 잡을 running 으로 전환해 반환 — 없으면 null (Worker 루프 종료 신호). */
    internal fun nextQueuedAndMarkRunning(): SingleGenJob? = synchronized(lock) {
        val current = job ?: return@synchronized null
        if (current.status != SingleGenStatus.QUEUED.raw) return@synchronized null
        val running = current.copy(
            status = SingleGenStatus.RUNNING.raw,
            startedAt = System.currentTimeMillis(),
            attempts = current.attempts + 1,
        )
        job = running
        persistLocked()
        publishLocked()
        running
    }

    internal fun bodyFileFor(jobId: String): File = File(folder(), "$jobId.body.json")

    /** preflight 실패 — 30분 timeout 세션에 매달리지 않고 즉시 안내 (iOS preflightPing 동일). */
    internal fun failOffline() {
        synchronized(lock) {
            val current = job ?: return
            if (!current.isActive) return
            failLocked(current, str(R.string.gen_err_offline), paymentRequired = false)
        }
    }

    /** 실행 시점에 body 파일이 없을 때 — 즉시 실패. */
    internal fun failMissingBody(jobId: String) {
        synchronized(lock) {
            val current = job ?: return
            if (current.id != jobId || current.status != SingleGenStatus.RUNNING.raw) return
            failLocked(current, str(R.string.bggen_err_no_body_file), paymentRequired = false)
        }
    }

    /**
     * 완료 콜백 — bggen `process()` 동형.
     * 가드: running 이 아니면 무시 — 취소/재시작으로 겹친 늦은 콜백이 이중 차감을 만들지 않는다.
     *
     * @param httpCode null 이면 transport 에러 (error 필수)
     * @param body 응답 본문 (2xx 인데 비어 있으면 재큐잉 후보)
     */
    internal fun process(jobId: String, httpCode: Int?, body: ByteArray?, error: Throwable?) {
        synchronized(lock) {
            val current = job ?: return
            if (current.id != jobId || current.status != SingleGenStatus.RUNNING.raw) return

            var failure: String? = null
            var payment = false
            if (error != null) {
                failure = error.koreanized()
            } else if (httpCode != null && httpCode !in 200..299) {
                when (httpCode) {
                    // 402 — 무료/캔디 소진. 화면은 에러 배너 대신 페이월을 띄운다 (기존 동작).
                    402 -> {
                        payment = true
                        parseBalance(body)?.let { applyEntitlementLocked(it) }
                    }
                    // 422 — 서버(Moderation) 안내 문구를 그대로. 없을 때만 폴백 (ApiError.koreanized 규칙).
                    422 -> failure = detailOf(body).ifEmpty { str(R.string.err_unsafe_prompt) }
                    else -> failure = str(R.string.err_server_generic, httpCode)
                }
            }

            if (failure == null && !payment) {
                val decoded = decodeSuccess(body)
                if (decoded != null) {
                    handleSuccessLocked(current, decoded)
                    return
                }
                if (shouldRequeueEmptyBody(body, current.attempts)) {
                    // 2xx 인데 본문 없음 — 한 번만 재큐잉해 다시 생성 (본문 파일은 남겨 둔다).
                    job = current.copy(status = SingleGenStatus.QUEUED.raw, startedAt = null)
                    persistLocked()
                    publishLocked()
                    return
                }
                failure = str(R.string.gen_err_image_load)
            }
            failLocked(current, failure, payment)
        }
    }

    /** Worker 루프가 끝날 때 1회 — 화면이 안 보이는 상태였다면 완료/실패 알림. */
    internal fun finishRun() {
        val notify: SingleGenJob?
        synchronized(lock) {
            val current = job
            notify = if (wasCancelled || screenVisible || current == null || current.isActive) {
                null
            } else {
                current
            }
            if (wasCancelled) {
                wasCancelled = false
                persistLocked()
            }
        }
        val finished = notify ?: return
        NotificationHelper.notifySingleGenFinished(
            success = finished.isDone,
            detail = finished.errorMessage,
        )
    }

    // MARK: - 성공/실패 처리 (lock 안에서만 호출)

    /**
     * 성공 응답 — 크로마키 → (frame 1) 앵커 정규화 → 128 썸네일 → (frame 1) 색 정렬
     * → 캔디 차감 → 다음 프레임 or 마무리. 화면의 옛 `send()` 후처리와 같은 순서다.
     */
    private fun handleSuccessLocked(current: SingleGenJob, resp: GenerateImageResponse) {
        val raw = ImageProcessing.fromBase64(resp.imageBase64)
        if (raw == null) {
            failLocked(current, str(R.string.gen_err_image_load), paymentRequired = false)
            return
        }
        // 1) gpt-image-2 마젠타 배경 → 크로마키 투명화 (이미 투명이면 no-op)
        val img = ImageProcessing.chromaKeyRemoved(raw)
        // 2) frame 1 은 frame 0 원본 기준으로 크기·위치 정규화
        val anchor = if (current.frame == 1) loadAnchorFullRes() else null
        val processed = if (anchor != null) ImageProcessing.matchedToReference(img, anchor) else img
        // 3) 128 썸네일 (메인 200 / 워치 64 / 위젯 60 커버)
        var small = ImageProcessing.downsampled(processed, 128)
        // 4) frame 1 색 드리프트 제거 — frame 0 색에 맞춤
        if (anchor != null) {
            small = ImageProcessing.colorMatched(small, ImageProcessing.downsampled(anchor, 128))
        }

        // 5) 캔디 — **여기(성공 판정 뒤)에서만** 차감. 서버가 무료로 소진한 세션은 프레임 2장 모두 미차감.
        val freeConsumed =
            if (current.frame == 0) (resp.freeConsumed ?: false) else current.freeConsumed
        if (!freeConsumed) GenerationQuota.record(GenerationQuota.cost(current.quality))
        resp.entitlement?.let { applyEntitlementLocked(it) }

        var updated = current.copy(freeConsumed = freeConsumed)
        if (current.frame == 0) {
            writePng(small, outFrame0File())
            writePng(processed, anchorFile())   // 다음 프레임/다듬기의 앵커 = frame 0 원본
            updated = updated.copy(revisedPrompt = resp.revisedPrompt ?: current.revisedPrompt)
            val next = nextFrameStage(updated)
            if (next != null) {
                if (writeBodyLocked(next, ImageProcessing.toBase64Png(processed))) {
                    job = next
                    persistLocked()
                    publishLocked()
                    return
                }
                // 본문 준비 실패 — frame 0 만으로 마무리하고 사유는 경고로 남긴다.
                updated = updated.copy(errorMessage = str(R.string.bggen_err_prepare))
            }
        } else {
            writePng(small, outFrame1File())
        }
        finalizeLocked(updated)
    }

    /**
     * 실패 확정. 단, **새로 만들기의 frame 1 실패는 잡을 죽이지 않는다** —
     * frame 0 은 이미 성공(차감)했으므로 그 결과를 저장하고 사유만 경고로 남긴다 (기존 화면 동작).
     */
    private fun failLocked(current: SingleGenJob, message: String?, paymentRequired: Boolean) {
        if (current.frame == 1 && !current.isRefine && outFrame0File().exists()) {
            finalizeLocked(current.copy(errorMessage = message, paymentRequired = paymentRequired))
            return
        }
        job = current.copy(
            status = SingleGenStatus.FAILED.raw,
            errorMessage = message,
            paymentRequired = paymentRequired,
        )
        bodyFileFor(current.id).delete()
        persistLocked()
        publishLocked()
    }

    /**
     * 마무리 — 결과를 갤러리에 저장(A-3-c)하고 다듬기 이력(A-3-b)까지 디스크에 남긴다.
     * 화면은 이 galleryId 체인을 복원 경로로 읽어 결과를 보여준다.
     */
    private fun finalizeLocked(current: SingleGenJob) {
        val state = CharacterState.fromRaw(current.stateRaw)
        // 이번에 안 바뀐 프레임은 다듬기 기준 이미지(base_*)에서 채운다.
        val frame0 = decodePng(outFrame0File()) ?: decodePng(baseFrame0File())
        val frame1 = decodePng(outFrame1File()) ?: decodePng(baseFrame1File())
        if (state == null || frame0 == null) {
            job = current.copy(
                status = SingleGenStatus.FAILED.raw,
                errorMessage = current.errorMessage ?: str(R.string.gen_err_image_load),
            )
            clearWorkFilesLocked()
            persistLocked()
            publishLocked()
            return
        }
        // 갤러리에만 저장 — 활성 슬롯 적용은 사용자가 '적용'을 눌렀을 때 (기존 규칙 유지).
        val item = CharacterImageStore.save(
            frame0, state, frame = 0,
            applyToActiveSlot = false, batchId = current.sessionId, prompt = current.galleryPrompt,
        )
        if (item == null) {
            job = current.copy(
                status = SingleGenStatus.FAILED.raw,
                errorMessage = str(R.string.gen_err_save_failed),
            )
            clearWorkFilesLocked()
            persistLocked()
            publishLocked()
            return
        }
        if (frame1 != null) CharacterImageStore.attachGalleryFrame1(item.id, frame1)
        saveChainLocked(current, item.id, hasFrame2 = frame1 != null)
        job = current.copy(status = SingleGenStatus.DONE.raw, resultGalleryId = item.id)
        clearWorkFilesLocked()
        persistLocked()
        publishLocked()
    }

    /**
     * 다듬기 이력 갱신 — 새로 만들기는 체인을 갈아끼우고([0] = 원본),
     * 다듬기는 뒤에 붙인다 (상한 8, 초과 시 [0]은 보존하고 가장 오래된 다듬기부터 — 화면과 동일 규칙).
     */
    private fun saveChainLocked(current: SingleGenJob, galleryId: String, hasFrame2: Boolean) {
        val entry = Triple<String?, Boolean, Boolean>(galleryId, current.isRefine, hasFrame2)
        val chain: List<Triple<String?, Boolean, Boolean>> = if (!current.isRefine) {
            listOf(entry)
        } else {
            val existing = RefineHistoryStore.loadMeta()?.versions
                ?.map { Triple<String?, Boolean, Boolean>(it.galleryId, it.isRefined, it.hasFrame2) }
                .orEmpty()
            // 저장본이 사라졌으면 이 결과를 새 원본으로 (인덱스가 어긋난 체인을 만들지 않는다).
            if (existing.isEmpty()) listOf(entry.copy(second = false)) else appendRefineVersion(existing, entry)
        }
        RefineHistoryStore.save(current.stateRaw, chain.size - 1, chain)
    }

    private fun applyEntitlementLocked(ent: Entitlement) {
        entitlement = ent
        // 로컬이 캔디의 권위 — 서버 잔액은 '끌어올리기'만 (로컬 적립분을 덮어쓰지 않음).
        GenerationQuota.syncCreditsUp(ent.credits)
    }

    // MARK: - 요청 본문 / 파싱

    private fun writeBodyLocked(target: SingleGenJob, reference: String?): Boolean {
        val request = GenerateImageRequest(
            prompt = target.prompt,
            referenceImageBase64 = reference,
            steps = 30, width = 1024, height = 1024,
            quality = target.quality, artStyle = target.artStyle, style = "auto",
            kind = target.serverKind,
            model = "gpt-image-2",
            userInput = target.userInput?.trim(),
            inputField = target.inputField,
        )
        return runCatching {
            bodyFileFor(target.id).writeText(
                bodyJson.encodeToString(GenerateImageRequest.serializer(), request),
            )
        }.isSuccess
    }

    private fun decodeSuccess(body: ByteArray?): GenerateImageResponse? {
        if (body == null || body.isEmpty()) return null
        return runCatching {
            json.decodeFromString(GenerateImageResponse.serializer(), body.decodeToString())
        }.getOrNull()
    }

    private fun parseBalance(body: ByteArray?): Entitlement? {
        if (body == null || body.isEmpty()) return null
        return runCatching {
            json.decodeFromString(PaymentRequiredResponse.serializer(), body.decodeToString()).balance
        }.getOrNull()
    }

    /** 오류 응답 본문의 detail 추출 — ApiClient.detailOf 와 동형. */
    private fun detailOf(body: ByteArray?): String {
        if (body == null || body.isEmpty()) return ""
        val text = body.decodeToString()
        return runCatching { json.decodeFromString(ApiErrorDetail.serializer(), text).detail }
            .getOrElse { text.take(300) }
            .trim()
    }

    // MARK: - 파일/영속

    private fun folder(): File = File(WithuApp.context.filesDir, FOLDER).apply { mkdirs() }
    private fun jobFile(): File = File(folder(), "job.json")
    private fun outFrame0File(): File = File(folder(), "out_f0.png")
    private fun outFrame1File(): File = File(folder(), "out_f1.png")
    private fun baseFrame0File(): File = File(folder(), "base_f0.png")
    private fun baseFrame1File(): File = File(folder(), "base_f1.png")
    private fun anchorFile(): File = File(folder(), "anchor.png")

    /** 중간 산출물 정리 — anchor 는 남긴다 (다음 다듬기의 정규화 기준). */
    private fun clearWorkFilesLocked() {
        job?.let { bodyFileFor(it.id).delete() }
        folder().listFiles()?.forEach { f ->
            if (f.name.endsWith(".body.json")) f.delete()
        }
        outFrame0File().delete()
        outFrame1File().delete()
        baseFrame0File().delete()
        baseFrame1File().delete()
    }

    private fun writePng(bitmap: Bitmap, file: File) {
        runCatching {
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
    }

    private fun decodePng(file: File): Bitmap? {
        if (!file.exists()) return null
        val opts = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
        return runCatching { BitmapFactory.decodeFile(file.absolutePath, opts) }.getOrNull()
    }

    /** job.json 스키마 — 잡 1개 + 취소 표시(재시작 후 완료 알림 억제). */
    @Serializable
    private data class Persisted(
        val job: SingleGenJob? = null,
        val wasCancelled: Boolean = false,
    )

    private fun persistLocked() {
        runCatching {
            jobFile().writeText(
                json.encodeToString(Persisted.serializer(), Persisted(job, wasCancelled)),
            )
        }
    }

    private fun restoreLocked() {
        if (restored) return
        restored = true
        val file = jobFile()
        if (!file.exists()) return
        val saved = runCatching {
            json.decodeFromString(Persisted.serializer(), file.readText())
        }.getOrNull() ?: return
        job = saved.job
        wasCancelled = saved.wasCancelled
    }

    private fun publishLocked() {
        tick += 1
        _state.value = SingleGenSnapshot(job, entitlement, tick)
    }

    private fun enqueueWorker(policy: ExistingWorkPolicy) {
        // 네트워크 제약을 걸지 않는다 — 오프라인이면 Worker 가 preflight 로 즉시 안내한다
        // (제약을 걸면 오프라인에서 아무 피드백 없이 '그리는 중'에 멈춘다).
        val request = OneTimeWorkRequestBuilder<GenSingleWorker>().build()
        WorkManager.getInstance(WithuApp.context).enqueueUniqueWork(WORK_NAME, policy, request)
    }

    private fun str(resId: Int): String = WithuApp.context.getString(resId)
    private fun str(resId: Int, arg: Any): String = WithuApp.context.getString(resId, arg)
}
