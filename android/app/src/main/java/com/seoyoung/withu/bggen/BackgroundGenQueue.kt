package com.seoyoung.withu.bggen

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.seoyoung.withu.R
import com.seoyoung.withu.WithuApp
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.gen.ImageProcessing
import com.seoyoung.withu.net.ApiErrorDetail
import com.seoyoung.withu.net.GenerateImageRequest
import com.seoyoung.withu.net.GenerateImageResponse
import com.seoyoung.withu.net.koreanized
import com.seoyoung.withu.notify.NotificationHelper
import com.seoyoung.withu.quota.GenerationQuota
import com.seoyoung.withu.shared.CharacterImageStore
import com.seoyoung.withu.sync.SyncCoordinator
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.util.UUID

/**
 * 배치 생성 영속 큐 — iOS BackgroundGenerationManager.swift 포팅 (스펙 11 §4).
 *
 * 핵심 semantics (iOS 와 동일):
 *  - 잡 목록은 filesDir/bggen/jobs.json 에 영속 — 프로세스 사망 후 복원.
 *  - 순차 1개(maxConcurrent = 1) — 서버 부하/일관성.
 *  - 요청 본문은 <jobId>.body.json 파일 (base64 참고사진이 커서 파일이 안전).
 *  - 본문 없는 2xx 는 attempts < 2 까지 1회 재큐잉 (OkHttp 는 사실상 안 타지만 스키마 호환 유지).
 *  - 캔디 차감(GenerationQuota.record)은 process() 성공 시점 — 뷰가 아니라 여기.
 *  - 실행은 WorkManager(GenBatchWorker, unique "bggen") — 화면 꺼짐/앱 종료에도 진행.
 */
object BackgroundGenQueue {
    private const val WORK_NAME = "bggen"
    private const val FOLDER = "bggen"
    /** 본문 없는 2xx 재큐잉 상한 — 1회만 재생성 (iOS attempts < 2). */
    private const val MAX_ATTEMPTS = 2

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = false; explicitNulls = false }
    // 요청 본문 — snake_case 는 DTO 의 @SerialName 이 담당. 기본값(steps/width/…)도 전송.
    private val bodyJson = Json { ignoreUnknownKeys = true; encodeDefaults = true; explicitNulls = false }

    private val lock = Any()
    private var jobs: MutableList<BgGenJob> = mutableListOf()
    private var phase: BgGenPhase = BgGenPhase.REST
    private var wasCancelled = false
    /** 메모리 전용 결과 썸네일 — 재시작 후엔 빈 맵. 뷰는 CharacterImageStore.loadFrame fallback. */
    private val images = mutableMapOf<String, Bitmap>()
    private var tick = 0L
    private var restored = false

    private val _state = MutableStateFlow(BgGenState(emptyList(), BgGenPhase.REST, emptyMap(), 0L))
    val state: StateFlow<BgGenState> = _state

    // MARK: - 공개 API (00-PLAN §2-9)

    /** 새 배치 시작 — 이전 잡 목록 교체 + images 클리어 후 Worker 실행 (iOS start 동형). */
    fun start(specs: List<BgGenSpec>, quality: String, artStyle: String, batchId: String, phase: BgGenPhase) {
        synchronized(lock) {
            wasCancelled = false
            this.phase = phase
            jobs = mutableListOf()
            images.clear()
            for (spec in specs) appendJobLocked(spec, quality, artStyle, batchId)
            persistLocked()
            publishLocked()
        }
        enqueueWorker(ExistingWorkPolicy.REPLACE)
    }

    /**
     * 실패한 한 장 재시도 — 같은 state·frame 의 failed 잡 제거 후 새 잡 추가.
     * 큐가 이미 끝난 배치면 phase=RETRY 전환 (완료 알림/알럿을 배치처럼 띄우지 않음).
     */
    fun retry(spec: BgGenSpec, quality: String, artStyle: String, batchId: String) {
        synchronized(lock) {
            val active = jobs.any {
                it.status == BgGenStatus.QUEUED.raw || it.status == BgGenStatus.RUNNING.raw
            }
            if (!active) phase = BgGenPhase.RETRY
            jobs.removeAll {
                it.stateRaw == spec.state.raw && it.frame == spec.frame &&
                    it.status == BgGenStatus.FAILED.raw
            }
            appendJobLocked(spec, quality, artStyle, batchId)
            persistLocked()
            publishLocked()
        }
        enqueueWorker(ExistingWorkPolicy.APPEND_OR_REPLACE)
    }

    /** 전부 취소 — queued/running → failed(취소했어요). wasCancelled 로 완료 알림 억제. */
    fun cancelAll() {
        WorkManager.getInstance(WithuApp.context).cancelUniqueWork(WORK_NAME)
        synchronized(lock) {
            wasCancelled = true
            jobs = jobs.map { job ->
                if (job.status == BgGenStatus.QUEUED.raw || job.status == BgGenStatus.RUNNING.raw) {
                    job.copy(
                        status = BgGenStatus.FAILED.raw,
                        errorMessage = WithuApp.context.getString(R.string.bggen_err_cancelled),
                    )
                } else job
            }.toMutableList()
            persistLocked()
            publishLocked()
        }
    }

    /**
     * 앱 런치 시 재개 — jobs.json 복원 후 running 잡을 무조건 queued 로 강등.
     * (WorkManager 가 프로세스 사망 시 Worker 를 재시작하므로 iOS 의 살아있는 태스크
     *  대조가 필요 없음 — 강등이 동일 효과. Idempotency-Key = job.id 라 서버 중복 처리 없음.)
     */
    fun resumeIfNeeded() {
        val active: Boolean
        synchronized(lock) {
            restoreLocked()
            jobs = jobs.map { job ->
                if (job.status == BgGenStatus.RUNNING.raw) {
                    job.copy(status = BgGenStatus.QUEUED.raw, startedAt = null)
                } else job
            }.toMutableList()
            persistLocked()
            publishLocked()
            active = jobs.any { it.status == BgGenStatus.QUEUED.raw }
        }
        // KEEP — WorkManager 에 이미 남아 있는 같은 이름의 작업을 중복 실행하지 않게.
        if (active) enqueueWorker(ExistingWorkPolicy.KEEP)
    }

    /** frame0 원본(1024) 로드 — 승인 앵커/frame1 정규화 기준 (bggen/<raw>_f0.png). */
    fun loadFrame0FullRes(state: CharacterState): Bitmap? {
        val file = frame0File(state)
        if (!file.exists()) return null
        val opts = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
        return BitmapFactory.decodeFile(file.absolutePath, opts)
    }

    // MARK: - Worker 전용 내부 API (GenBatchWorker 만 호출)

    /** 다음 queued 잡을 running 으로 전환해 반환 — 없으면 null (Worker 루프 종료 신호). */
    internal fun nextQueuedAndMarkRunning(): BgGenJob? = synchronized(lock) {
        // running 이 남아 있으면 실행하지 않음 — maxConcurrent = 1
        if (jobs.any { it.status == BgGenStatus.RUNNING.raw }) return@synchronized null
        val idx = jobs.indexOfFirst { it.status == BgGenStatus.QUEUED.raw }
        if (idx < 0) return@synchronized null
        val job = jobs[idx].copy(
            status = BgGenStatus.RUNNING.raw,
            startedAt = System.currentTimeMillis(),
            attempts = (jobs[idx].attempts ?: 0) + 1,
        )
        jobs[idx] = job
        persistLocked()
        publishLocked()
        job
    }

    internal fun bodyFileFor(jobId: String): File = File(folder(), "$jobId.body.json")

    /** 실행 시점에 body 파일이 없을 때 — 즉시 실패 후 다음 잡으로. */
    internal fun failMissingBody(jobId: String) {
        synchronized(lock) {
            val idx = jobs.indexOfFirst { it.id == jobId }
            if (idx < 0) return
            jobs[idx] = jobs[idx].copy(
                status = BgGenStatus.FAILED.raw,
                errorMessage = WithuApp.context.getString(R.string.bggen_err_no_body_file),
            )
            persistLocked()
            publishLocked()
        }
    }

    /**
     * 완료 콜백 — iOS process(jobId:data:response:error:) 동형.
     * 가드: 해당 잡이 running 이 아니면 무시 — 재시작 후 재큐잉본과 원래 요청의 늦은
     * 콜백이 겹쳐도 이중 차감/이중 frame1 체이닝이 없다 (취소된 잡도 여기서 걸러짐).
     *
     * @param httpCode null 이면 transport 에러 (error 필수)
     * @param body 응답 본문 (2xx 인데 비어 있으면 재큐잉 후보)
     */
    internal fun process(jobId: String, httpCode: Int?, body: ByteArray?, error: Throwable?) {
        val ctx = WithuApp.context
        synchronized(lock) {
            val idx = jobs.indexOfFirst { it.id == jobId }
            if (idx < 0 || jobs[idx].status != BgGenStatus.RUNNING.raw) return

            var job = jobs[idx]
            var failure: String? = null
            if (error != null) {
                failure = error.koreanized()
            } else if (httpCode != null && httpCode !in 200..299) {
                failure = when {
                    httpCode == 402 -> {
                        job = job.copy(paymentRequired = true)
                        ctx.getString(R.string.bggen_err_payment)
                    }
                    // 422 — 서버 안내 문구를 그대로 (없을 때만 폴백). ApiError.koreanized 와 동일 규칙.
                    httpCode == 422 ->
                        detailOf(body).ifEmpty { ctx.getString(R.string.err_unsafe_prompt) }
                    else -> ctx.getString(R.string.err_server_generic, httpCode)
                }
            }

            var requeued = false
            if (failure == null) {
                val decoded = decodeSuccess(body)
                val state = CharacterState.fromRaw(job.stateRaw)
                if (decoded != null && state != null) {
                    handleSuccessLocked(idx, job, state, decoded)
                    job = jobs[idx]
                } else if ((body == null || body.isEmpty()) && (job.attempts ?: 1) < MAX_ATTEMPTS) {
                    // 2xx 인데 본문 없음 — 앱이 죽은 사이 완료된 요청은 본문이 유실될 수 있어
                    // 한 번만 재큐잉해 다시 생성 (iOS 한계 대응 — 스키마 호환 유지).
                    jobs[idx] = job.copy(status = BgGenStatus.QUEUED.raw, startedAt = null)
                    requeued = true
                } else {
                    failure = ctx.getString(R.string.bggen_err_no_image)
                }
            }

            if (failure != null) {
                jobs[idx] = job.copy(status = BgGenStatus.FAILED.raw, errorMessage = failure)
            }
            // 재큐잉이면 body 파일을 남겨야 재실행 가능 — 그 외엔 삭제.
            if (!requeued) bodyFileFor(jobId).delete()
            persistLocked()
            publishLocked()
        }
    }

    /** 큐가 빌 때 1회 (Worker 루프 종료 후) — 위젯 갱신 + phase 별 완료 알림. */
    internal suspend fun finishRun() {
        SyncCoordinator.refreshWidgets()
        val (cancelled, currentPhase, done, failed) = synchronized(lock) {
            val c = wasCancelled
            if (c) {
                wasCancelled = false
                persistLocked()
            }
            FinishSnapshot(c, phase, _state.value.doneCount, _state.value.failedCount)
        }
        if (cancelled) return   // 사용자 취소 — 알림 없이 종료
        NotificationHelper.notifyBatchFinished(done, failed, currentPhase)
    }

    private data class FinishSnapshot(
        val cancelled: Boolean,
        val phase: BgGenPhase,
        val done: Int,
        val failed: Int,
    )

    // MARK: - 내부 (lock 안에서만 호출)

    /** 잡 생성 + 요청 본문 파일 저장. 쓰기 실패 시 즉시 failed 로 추가 (iOS appendJob 동형). */
    private fun appendJobLocked(spec: BgGenSpec, quality: String, artStyle: String, batchId: String) {
        val job = BgGenJob(
            id = UUID.randomUUID().toString(),
            stateRaw = spec.state.raw,
            frame = spec.frame,
            quality = quality,
            artStyle = artStyle,
            batchId = batchId,
            wantsFrame1 = spec.wantsFrame1,
            frame1Prompt = spec.frame1Prompt,
            status = BgGenStatus.QUEUED.raw,
            matchIdleColor = spec.matchIdleColor,
            prompt = spec.prompt,
        )
        val request = GenerateImageRequest(
            prompt = spec.prompt,
            referenceImageBase64 = spec.referenceImageBase64,
            steps = 30, width = 1024, height = 1024,
            quality = quality, artStyle = artStyle, style = "auto",
            model = "gpt-image-2",
        )
        val written = runCatching {
            bodyFileFor(job.id).writeText(
                bodyJson.encodeToString(GenerateImageRequest.serializer(), request),
            )
        }.isSuccess
        if (!written) {
            jobs.add(
                job.copy(
                    status = BgGenStatus.FAILED.raw,
                    errorMessage = WithuApp.context.getString(R.string.bggen_err_prepare),
                ),
            )
            return
        }
        // frame1 직접 작업(재시도 등)의 정규화 기준 — f0 원본이 없으면 reference 로 채워 둔다.
        if (spec.frame == 1 && spec.referenceImageBase64 != null && !frame0File(spec.state).exists()) {
            ImageProcessing.fromBase64(spec.referenceImageBase64)?.let { ref ->
                saveFrame0FullRes(ref, spec.state)
            }
        }
        jobs.add(job)
    }

    /** 성공 응답 처리 — 크로마키 → (frame1) 정규화 → 128 썸네일 → 색 정렬 → 갤러리 저장 → 차감 → 체이닝. */
    private fun handleSuccessLocked(
        idx: Int,
        job: BgGenJob,
        state: CharacterState,
        response: GenerateImageResponse,
    ) {
        val raw = ImageProcessing.fromBase64(response.imageBase64)
        if (raw == null) {
            jobs[idx] = job.copy(
                status = BgGenStatus.FAILED.raw,
                errorMessage = WithuApp.context.getString(R.string.bggen_err_no_image),
            )
            return
        }
        // 1) gpt-image-2 마젠타 배경 → 크로마키 투명화 (투명 결과엔 no-op)
        val img = ImageProcessing.chromaKeyRemoved(raw)
        // 2) frame1: frame0 원본 기준으로 크기·위치 정규화
        val ref0 = if (job.frame == 1) loadFrame0FullRes(state) else null
        val flat = if (ref0 != null) ImageProcessing.matchedToReference(img, ref0) else img
        // 3) 128 썸네일
        var small = ImageProcessing.downsampled(flat, 128)
        // 4) 색 정렬 — matchIdleColor==true 면 idle 앵커 색에 통일(상태 간 색 어긋남 해소),
        //    아니면 자기 frame0 색 기준으로 frame1 드리프트만 제거 (iOS 동일).
        val colorRef = if (job.matchIdleColor == true) loadFrame0FullRes(CharacterState.IDLE) else ref0
        if (colorRef != null) {
            small = ImageProcessing.colorMatched(small, ImageProcessing.downsampled(colorRef, 128))
        }
        // 5) 갤러리에만 저장 — 활성 슬롯 적용은 사용자가 '적용' 누를 때 (배치 핵심 규칙).
        CharacterImageStore.save(
            small, state, frame = job.frame,
            applyToActiveSlot = false, batchId = job.batchId, prompt = job.prompt,
        )
        // 6) entitlement 반영 — 로그인 제외 범위라 서버 잔액 동기화는 생략 (스펙 11 §7: 파싱만).
        // 7) 캔디 차감은 이 성공 시점 (low 1 / medium 3 / high 6 — 프레임마다 각각)
        GenerationQuota.record(GenerationQuota.cost(job.quality))
        // 8) 메모리 썸네일 갱신 (뷰 관찰용)
        images["${job.stateRaw}#${job.frame}"] = small
        // 9) frame0 원본 보존 → 움직임(frame1) 체이닝
        jobs[idx] = job.copy(status = BgGenStatus.DONE.raw)
        if (job.frame == 0) {
            saveFrame0FullRes(flat, state)
            val f1Prompt = job.frame1Prompt
            if (job.wantsFrame1 && f1Prompt != null) {
                val spec = BgGenSpec(
                    state = state, frame = 1, prompt = f1Prompt,
                    referenceImageBase64 = ImageProcessing.toBase64Png(flat),
                    wantsFrame1 = false, frame1Prompt = null,
                    matchIdleColor = job.matchIdleColor ?: false,
                )
                appendJobLocked(spec, job.quality, job.artStyle, job.batchId)
            }
        }
    }

    /** 오류 응답 본문의 detail 추출 — ApiClient.detailOf 와 동형 (파싱 실패/본문 없음 → 빈 문자열). */
    private fun detailOf(body: ByteArray?): String {
        if (body == null || body.isEmpty()) return ""
        val text = body.decodeToString()
        return runCatching { json.decodeFromString(ApiErrorDetail.serializer(), text).detail }
            .getOrElse { text.take(300) }
            .trim()
    }

    private fun decodeSuccess(body: ByteArray?): GenerateImageResponse? {
        if (body == null || body.isEmpty()) return null
        return runCatching {
            json.decodeFromString(GenerateImageResponse.serializer(), body.decodeToString())
        }.getOrNull()
    }

    // MARK: - 파일/영속

    private fun folder(): File = File(WithuApp.context.filesDir, FOLDER).apply { mkdirs() }
    private fun jobsFile(): File = File(folder(), "jobs.json")
    private fun frame0File(state: CharacterState): File = File(folder(), "${state.raw}_f0.png")

    private fun saveFrame0FullRes(bitmap: Bitmap, state: CharacterState) {
        runCatching {
            frame0File(state).outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
        }
    }

    /** jobs.json 스키마 — iOS Persisted { phase, jobs } + wasCancelled (취소 후 재시작 알림 억제). */
    @Serializable
    private data class Persisted(
        val phase: String,
        val wasCancelled: Boolean = false,
        val jobs: List<BgGenJob>,
    )

    private fun persistLocked() {
        runCatching {
            jobsFile().writeText(
                json.encodeToString(
                    Persisted.serializer(),
                    Persisted(phase.raw, wasCancelled, jobs),
                ),
            )
        }
    }

    private fun restoreLocked() {
        if (restored) return
        restored = true
        val file = jobsFile()
        if (!file.exists()) return
        val saved = runCatching {
            json.decodeFromString(Persisted.serializer(), file.readText())
        }.getOrNull() ?: return
        phase = BgGenPhase.fromRaw(saved.phase)
        wasCancelled = saved.wasCancelled
        jobs = saved.jobs.toMutableList()
    }

    private fun publishLocked() {
        tick += 1
        _state.value = BgGenState(jobs.toList(), phase, images.toMap(), tick)
    }

    private fun enqueueWorker(policy: ExistingWorkPolicy) {
        val request = OneTimeWorkRequestBuilder<GenBatchWorker>()
            .setConstraints(
                Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build(),
            )
            .build()
        WorkManager.getInstance(WithuApp.context)
            .enqueueUniqueWork(WORK_NAME, policy, request)
    }
}
