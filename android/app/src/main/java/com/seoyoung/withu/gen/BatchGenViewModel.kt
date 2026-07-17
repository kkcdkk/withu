package com.seoyoung.withu.gen

import android.graphics.Bitmap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.seoyoung.withu.R
import com.seoyoung.withu.WithuApp
import com.seoyoung.withu.bggen.BackgroundGenQueue
import com.seoyoung.withu.bggen.BgGenPhase
import com.seoyoung.withu.bggen.BgGenSpec
import com.seoyoung.withu.bggen.BgGenState
import com.seoyoung.withu.bggen.BgGenStatus
import com.seoyoung.withu.camera.PhotoSaver
import com.seoyoung.withu.character.CharacterProfileStore
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.net.ApiClient
import com.seoyoung.withu.net.ApiError
import com.seoyoung.withu.net.GenerateImageRequest
import com.seoyoung.withu.net.koreanized
import com.seoyoung.withu.quota.GenerationQuota
import com.seoyoung.withu.shared.CharacterImageStore
import com.seoyoung.withu.sync.SyncCoordinator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

/**
 * 배치(여러 모습) 생성 뷰모델 — iOS BatchCharacterGenView.swift 의 상태·로직 포팅 (스펙 03 §3).
 *
 * 핵심 구조 (iOS 와 동일):
 *  - 실제 생성은 BackgroundGenQueue(WorkManager) 가 실행 — 뷰모델은 state Flow 를 collect 해
 *    단방향으로만 동기화(syncFromManager). 화면 이탈/앱 종료에도 생성이 계속된다.
 *  - 2단계 플로우: idle(앵커) 먼저 → 사용자 승인 → 나머지를 앵커 기준으로 일관 생성.
 *  - 배치 결과는 갤러리에만 저장됨 — 홈/위젯 반영은 '적용' 버튼(applyOne)이 유일한 경로.
 *  - 캔디 차감: 큐 경유 생성은 큐(process 성공 시점)가, 직접 API 호출(reviseIdle/reviseOne)은
 *    여기서 성공 시점에 record (이중 차감 금지 — 00-PLAN §5-5).
 */
class BatchGenViewModel : ViewModel() {

    // MARK: - 입력 상태

    /** 캔디 비용 기준 quality — 원본에 선택 UI 없음, "low" 고정 (스펙 03 §6). */
    val quality: String = "low"

    var baseIdentity by mutableStateOf(CharacterProfileStore.load().aiPrompt)

    /** 상태별 포즈 hint — 기본값 generationHint (iOS Dictionary(uniqueKeysWithValues:) 동형). */
    val stateHints = mutableStateMapOf<CharacterState, String>().apply {
        CharacterState.userFacing.forEach { put(it, it.generationHint) }
    }

    var selectedStates by mutableStateOf(CharacterState.userFacing.toSet())
        private set

    var artStyle by mutableStateOf("pixel")

    /** frame1(움직임)을 만들 상태들 — 행 안 토글·칩·'모두' 토글이 같은 값 공유. */
    var animatedStates by mutableStateOf(emptySet<CharacterState>())
        private set

    /** 전역 참고 사진 — 상태별 사진이 없을 때의 fallback. */
    var referenceImage by mutableStateOf<Bitmap?>(null)

    /** 상태별 참고 사진 — 있으면 전역보다 우선. */
    val stateReferenceImages = mutableStateMapOf<CharacterState, Bitmap>()

    var referenceKeep by mutableStateOf("")
    var referenceChange by mutableStateOf("")

    // MARK: - 승인 게이트

    var awaitingIdleApproval by mutableStateOf(false)
        private set
    var idleRevisionText by mutableStateOf("")

    /**
     * 승인된 idle 앵커/원본(1024). results 는 128 썸네일이라 reference 품질이 떨어짐 —
     * 원본을 따로 들고, 재시작 후엔 큐 디스크(bggen/idle_f0.png)에서 복구 (스펙 03 §3).
     */
    private var idleAnchor: Bitmap? = null
    private var idleFullRes: Bitmap? = null

    // MARK: - 진행/결과 상태

    var isGenerating by mutableStateOf(false)
        private set
    var inProgressStates by mutableStateOf(emptySet<CharacterState>())
        private set
    val stateStartedAt = mutableStateMapOf<CharacterState, Long>()

    /** frame0/frame1 결과 (128 썸네일, 투명 원본). */
    val results = mutableStateMapOf<CharacterState, Bitmap>()
    val resultsFrame1 = mutableStateMapOf<CharacterState, Bitmap>()
    val errors = mutableStateMapOf<CharacterState, String>()

    /** '적용' 누른 상태 — 배치는 갤러리에만 저장되므로 반영 여부를 뷰가 따로 추적. */
    var appliedStates by mutableStateOf(emptySet<CharacterState>())
        private set

    /** 표시/적용 모드 — 기본 true(투명). false = 흰 배경 합성 (getOrDefault true 규칙). */
    private val displayTransparentByState = mutableStateMapOf<CharacterState, Boolean>()

    var isProcessingTransparentBulk by mutableStateOf(false)
        private set
    var isSavingPhotos by mutableStateOf(false)
        private set

    var showFinishedAlert by mutableStateOf(false)
    var saveResultMessage by mutableStateOf<String?>(null)
    var showPaywall by mutableStateOf(false)

    var remainingGenerations by mutableStateOf(GenerationQuota.remainingToday())
        private set
    var candy by mutableStateOf(GenerationQuota.displayedCandy())
        private set

    /** reviseOne 의 frame1 정규화 기준(frame0 원본) — 화면 살아있는 동안 메모리 보관. */
    private val frame0FullRes = HashMap<CharacterState, Bitmap>()

    /** 서버가 같은 세션을 free_batch 로 묶는 식별자 — '만들기 시작'마다 갱신. */
    private var batchSessionId: String = UUID.randomUUID().toString()

    /** 그만두기 표시 — 완료 알럿 억제 (iOS didCancel). */
    private var didCancel = false

    // MARK: - 상세 시트 상태

    var selectedResult by mutableStateOf<CharacterState?>(null)
        private set
    var detailFrame by mutableStateOf(0)
    var revisionText by mutableStateOf("")
    var isRevising by mutableStateOf(false)
        private set
    var revisionRefImage by mutableStateOf<Bitmap?>(null)
    var revisionError by mutableStateOf<String?>(null)
        private set

    // 흰배경 합성 캐시 — 같은 raw 비트맵의 합성을 매 프레임 반복하지 않기 위함 (메모리 전용).
    private val whiteCache = HashMap<Bitmap, Bitmap>()

    // MARK: - 파생값

    /** 실제 생성 장수 — idle 은 항상 먼저 만들므로 선택 안 했으면 +1, 움직임 상태는 +1씩 (iOS requiredCount). */
    val requiredCount: Int
        get() {
            val base =
                if (CharacterState.IDLE in selectedStates) selectedStates.size
                else selectedStates.size + 1
            val anim = animatedStates.intersect(selectedStates + CharacterState.IDLE).size
            return base + anim
        }

    val needCandy: Int get() = requiredCount * GenerationQuota.cost(quality)

    // MARK: - 큐 관찰 (iOS onChange(tick)/onChange(isActive) 대응)

    private var prevActive = false
    private var restoredOnce = false

    init {
        viewModelScope.launch {
            BackgroundGenQueue.state.collect { s ->
                syncFromManager(s)
                if (!restoredOnce) {
                    restoredOnce = true
                    prevActive = s.isActive
                    // 화면 재진입 복원 (iOS onAppear) — 승인 대기 중이던 배치 이어서 표시.
                    if (s.jobs.isNotEmpty() && !s.isActive &&
                        s.phase == BgGenPhase.ANCHOR && results[CharacterState.IDLE] != null
                    ) {
                        awaitingIdleApproval = true
                    }
                } else {
                    if (prevActive && !s.isActive) handleQueueFinished(s)
                    prevActive = s.isActive
                }
            }
        }
    }

    /** 매니저 → 뷰 단방향 동기화 (iOS syncFromManager 동형). */
    private suspend fun syncFromManager(s: BgGenState) {
        val progress = mutableSetOf<CharacterState>()
        val started = mutableMapOf<CharacterState, Long>()
        // 디스크 폴백 로드는 IO 에서 — images 맵은 메모리 전용이라 재시작 후 비어 있음 (00-PLAN §5-10).
        val doneImages = withContext(Dispatchers.IO) {
            val map = mutableMapOf<Pair<CharacterState, Int>, Bitmap>()
            for (job in s.jobs) {
                if (job.status != BgGenStatus.DONE.raw) continue
                val st = CharacterState.fromRaw(job.stateRaw) ?: continue
                val img = s.images["${job.stateRaw}#${job.frame}"]
                    ?: CharacterImageStore.loadFrame(st, job.frame)
                if (img != null) map[st to job.frame] = img
            }
            map
        }
        for (job in s.jobs) {
            val st = CharacterState.fromRaw(job.stateRaw) ?: continue
            when (job.status) {
                BgGenStatus.QUEUED.raw, BgGenStatus.RUNNING.raw -> {
                    progress += st
                    started[st] = job.startedAt ?: stateStartedAt[st] ?: System.currentTimeMillis()
                }
                BgGenStatus.DONE.raw -> {
                    doneImages[st to job.frame]?.let {
                        if (job.frame == 0) results[st] = it else resultsFrame1[st] = it
                    }
                    if (job.frame == 0) {
                        errors.remove(st)
                        if (st == CharacterState.IDLE && idleFullRes == null) {
                            idleFullRes = withContext(Dispatchers.IO) {
                                BackgroundGenQueue.loadFrame0FullRes(CharacterState.IDLE)
                            }
                        }
                    }
                }
                BgGenStatus.FAILED.raw ->
                    errors[st] = job.errorMessage ?: str(R.string.batch_err_failed_generic)
            }
        }
        inProgressStates = progress
        stateStartedAt.clear()
        stateStartedAt.putAll(started)
        // rest 단계엔 앵커(idle) job 이 목록에 없음 — 비면 활성 슬롯에서 복원 (iOS 동일).
        if (s.jobs.isNotEmpty() && s.phase != BgGenPhase.ANCHOR && results[CharacterState.IDLE] == null) {
            withContext(Dispatchers.IO) { CharacterImageStore.loadFrame(CharacterState.IDLE, 0) }
                ?.let { results[CharacterState.IDLE] = it }
        }
        isGenerating = s.isActive
        refreshQuota()
    }

    /** 큐 active true→false 전환 처리 (iOS onChange(isActive) 동형). */
    private fun handleQueueFinished(s: BgGenState) {
        if (didCancel) {
            didCancel = false
            return
        }
        when {
            s.phase == BgGenPhase.ANCHOR -> {
                if (results[CharacterState.IDLE] != null) awaitingIdleApproval = true
            }
            s.phase == BgGenPhase.REST && s.jobs.isNotEmpty() -> {
                // 캔디 소진(402)으로 실패한 게 있으면 완료 알럿 대신 충전 안내 (스펙 03 플로우 ③).
                if (s.jobs.any { it.paymentRequired == true }) showPaywall = true
                else showFinishedAlert = true
                // 햅틱은 생략 (스펙 03: Android 진동 또는 생략)
            }
            else -> Unit   // RETRY — 단건 재시도는 배치처럼 알럿을 띄우지 않음
        }
    }

    // MARK: - 선택/옵션 조작

    fun setSelected(state: CharacterState, on: Boolean) {
        selectedStates = if (on) selectedStates + state else selectedStates - state
    }

    fun selectAll() { selectedStates = CharacterState.userFacing.toSet() }

    fun deselectAll() { selectedStates = emptySet() }

    fun setAnimated(state: CharacterState, on: Boolean) {
        animatedStates = if (on) animatedStates + state else animatedStates - state
    }

    /** '모두 움직이는 캐릭터로' — usesGeneratedMotion 인 선택 상태에만 적용 (iOS 동일). */
    fun setAllAnimated(on: Boolean) {
        val animatable = selectedStates.filter { it.usesGeneratedMotion }.toSet()
        animatedStates = if (on) animatedStates + animatable else animatedStates - animatable
    }

    fun resetHint(state: CharacterState) { stateHints[state] = state.generationHint }

    fun setStateReference(state: CharacterState, image: Bitmap) { stateReferenceImages[state] = image }

    fun removeStateReference(state: CharacterState) { stateReferenceImages.remove(state) }

    /** 전역 참고사진 로드 실패 — iOS 는 errors[.idle] 에 표기 (상태별/수정용은 조용히 무시). */
    fun reportGlobalReferenceLoadFailed() {
        errors[CharacterState.IDLE] = str(R.string.batch_err_ref_load)
    }

    fun refreshQuota() {
        remainingGenerations = GenerationQuota.remainingToday()
        candy = GenerationQuota.displayedCandy()
    }

    fun closePaywall() {
        showPaywall = false
        refreshQuota()
    }

    // MARK: - 플로우 ① 만들기 시작

    fun startBatch() {
        if (isGenerating) return
        viewModelScope.launch {
            isGenerating = true
            batchSessionId = UUID.randomUUID().toString()   // 새 세션 — 서버가 free_batch 로 묶음
            saveDescription()                               // 설명을 프로필에 저장 — 단건 생성과 공유
            results.clear()
            resultsFrame1.clear()
            errors.clear()
            appliedStates = emptySet()
            frame0FullRes.clear()
            displayTransparentByState.clear()
            synchronized(whiteCache) { whiteCache.clear() }
            inProgressStates = emptySet()
            stateStartedAt.clear()
            idleAnchor = null
            idleFullRes = null
            awaitingIdleApproval = false
            didCancel = false

            // 알림 권한 요청은 화면(BatchGenScreen)이 런처로 처리 — Android 는 Activity 필요.

            try {
                ApiClient.preflightPing()
            } catch (e: Exception) {
                errors[CharacterState.IDLE] = str(R.string.batch_err_server)
                isGenerating = false
                return@launch
            }

            // idle(앵커, frame0)만 먼저. 사용자 참고사진(상태별→전역)이 있으면 그걸 reference 로.
            val idleRef = withContext(Dispatchers.Default) { resolveUserReference(CharacterState.IDLE) }
            val spec = BgGenSpec(
                state = CharacterState.IDLE,
                frame = 0,
                prompt = buildPrompt(
                    CharacterState.IDLE,
                    consistencyPrefix = idleRef != null,
                    keepNote = userRefKeep(CharacterState.IDLE),
                    changeNote = userRefChange(CharacterState.IDLE),
                    frame = 0,
                ),
                referenceImageBase64 = idleRef,
            )
            withContext(Dispatchers.IO) {
                BackgroundGenQueue.start(listOf(spec), quality, artStyle, batchSessionId, BgGenPhase.ANCHOR)
            }
        }
    }

    /** 그만두기 — didCancel 로 완료 알럿/알림 억제 + 큐 전체 취소. */
    fun stopBatch() {
        didCancel = true
        viewModelScope.launch(Dispatchers.IO) { BackgroundGenQueue.cancelAll() }
    }

    // MARK: - 플로우 ② 승인 화면 3버튼

    /** 이 모습으로 나머지 만들기 — 승인된 idle 을 앵커로 나머지 상태를 백그라운드 생성. */
    fun approveIdleAndContinue() {
        // 연타 재진입 차단 — awaitingIdleApproval 을 suspend 전에 동기로 끔 (스펙 03 주의점).
        if (!awaitingIdleApproval) return
        awaitingIdleApproval = false
        viewModelScope.launch {
            // 앵커 = 원본(1024) 우선 — 128 썸네일은 reference 품질이 나쁨.
            val idle = idleFullRes
                ?: withContext(Dispatchers.IO) { BackgroundGenQueue.loadFrame0FullRes(CharacterState.IDLE) }
                ?: results[CharacterState.IDLE]
            if (idle == null) {
                awaitingIdleApproval = true
                return@launch
            }
            idleAnchor = idle
            isGenerating = true
            val anchorB64 = withContext(Dispatchers.Default) { ImageProcessing.toBase64Png(idle) }

            val specs = mutableListOf<BgGenSpec>()
            // (iOS 파리티 메모: idle 자신의 frame1 스펙 분기는 idle.usesGeneratedMotion == false 라
            //  절대 실행되지 않는 죽은 코드 — 여기선 생략. idle 은 절차적 모션으로 애니메이션.)
            // 나머지 선택 상태 (idle 제외) — 전역 첨부사진·keep/change 는 idle 만들 때만 반영,
            // 그 상태에 '명시적으로' 붙인 사진이 있으면 그 상태만 예외로 그 사진을 참고.
            val rest = CharacterState.entries.filter { it in selectedStates && it != CharacterState.IDLE }
            for (state in rest) {
                val perStatePhoto = withContext(Dispatchers.Default) { perStateReferenceB64(state) }
                val refB64 = perStatePhoto ?: anchorB64
                // 미세 모션 상태는 2프레임 생성 안 함 — 색·이목구비 드리프트 방지 (절차적 모션).
                val animated = state in animatedStates && state.usesGeneratedMotion
                specs += BgGenSpec(
                    state = state,
                    frame = 0,
                    prompt = buildPrompt(state, consistencyPrefix = true, frame = 0),
                    referenceImageBase64 = refB64,
                    wantsFrame1 = animated,
                    frame1Prompt = if (animated) buildPrompt(state, consistencyPrefix = true, frame = 1) else null,
                    // 앵커 기반이면 idle 색에 통일. 상태별 명시 사진은 그 사진 색 존중.
                    matchIdleColor = perStatePhoto == null,
                )
            }
            // 만들 게 없음 (idle 만 선택 + 움직임 없음) — 즉시 완료 처리.
            if (specs.isEmpty()) {
                isGenerating = false
                showFinishedAlert = true
                SyncCoordinator.refreshWidgets()
                return@launch
            }
            withContext(Dispatchers.IO) {
                BackgroundGenQueue.start(specs, quality, artStyle, batchSessionId, BgGenPhase.REST)
            }
        }
    }

    /**
     * 수정해서 생성하기 — 승인 대기를 유지한 채 idle 만 재생성.
     * 큐 경유가 아니라 APIClient 직접 호출 (kind:"batch", batchId 동봉) — iOS reviseIdle 동형.
     */
    fun reviseIdle() {
        val trimmed = idleRevisionText.trim()
        val current = idleFullRes ?: results[CharacterState.IDLE]
        if (trimmed.isEmpty() || current == null || isGenerating) return
        viewModelScope.launch {
            isGenerating = true
            errors.remove(CharacterState.IDLE)
            try {
                val refB64 = withContext(Dispatchers.Default) { ImageProcessing.toBase64Png(current) }
                val pose = stateHints[CharacterState.IDLE] ?: CharacterState.IDLE.generationHint
                val desc = baseIdentity.trim()
                val base = if (desc.isEmpty()) pose else "$desc, $pose"
                val prompt = "$base. User modification: $trimmed. " +
                    "Transparent background — only the character, no background fill, no shadows."
                val req = GenerateImageRequest(
                    prompt = prompt, referenceImageBase64 = refB64,
                    quality = quality, artStyle = artStyle, style = "auto", model = "gpt-image-2",
                )
                val resp = ApiClient.generateImage(req, kind = "batch", batchId = batchSessionId)
                val raw = withContext(Dispatchers.Default) { ImageProcessing.fromBase64(resp.imageBase64) }
                if (raw != null) {
                    // gpt-image-2 마젠타 배경 → 크로마키 투명화 (투명 결과엔 no-op)
                    val flat = withContext(Dispatchers.Default) { ImageProcessing.chromaKeyRemoved(raw) }
                    val small = withContext(Dispatchers.Default) { ImageProcessing.downsampled(flat, 128) }
                    results[CharacterState.IDLE] = small
                    idleFullRes = flat
                    withContext(Dispatchers.IO) {
                        // iOS 동일: 갤러리 + 활성 슬롯 동시 저장 (applyToActiveSlot 기본 true)
                        CharacterImageStore.save(
                            small, CharacterState.IDLE, frame = 0,
                            batchId = batchSessionId, prompt = prompt,
                        )
                    }
                    // 워치 전송(sendCharacterImage)은 SCOPE 제외 — no-op.
                    // entitlement 서버 잔액 동기화는 로그인 제외 범위라 생략 (bggen 큐와 동일 정책).
                    GenerationQuota.record(GenerationQuota.cost(quality))   // 직접 호출 성공 — 여기서 차감
                    idleRevisionText = ""
                    SyncCoordinator.refreshWidgets()
                } else {
                    errors[CharacterState.IDLE] = str(R.string.batch_err_no_image)
                }
            } catch (e: ApiError.PaymentRequired) {
                showPaywall = true
            } catch (e: Exception) {
                errors[CharacterState.IDLE] = e.koreanized()
            } finally {
                isGenerating = false
                inProgressStates = emptySet()
                stateStartedAt.clear()
                refreshQuota()
            }
            // awaitingIdleApproval 유지 — 수정본을 다시 승인/수정 가능
        }
    }

    /**
     * 프롬프트 수정해서 다시 — API 호출 없이 결과/앵커를 전부 비우고 입력 화면 복귀.
     * 캔디는 다음 '만들기 시작'에서 차감 (스펙 03 승인 화면 3버튼).
     */
    fun backToPromptEdit() {
        awaitingIdleApproval = false
        results.clear()
        resultsFrame1.clear()
        frame0FullRes.clear()
        synchronized(whiteCache) { whiteCache.clear() }
        idleFullRes = null
        idleAnchor = null
        idleRevisionText = ""
        errors.clear()
    }

    // MARK: - 재시도

    /** 실패 카드 탭 — 같은 조건으로 큐에 재추가 (iOS retryOne 동형). */
    fun retryOne(state: CharacterState) {
        errors.remove(state)
        viewModelScope.launch {
            val spec = withContext(Dispatchers.Default) {
                if (state == CharacterState.IDLE) {
                    // idle: 전역 첨부사진 + keep/change, matchIdleColor=false
                    val ref = resolveUserReference(CharacterState.IDLE)
                    BgGenSpec(
                        state = state, frame = 0,
                        prompt = buildPrompt(
                            state, consistencyPrefix = ref != null,
                            keepNote = userRefKeep(state), changeNote = userRefChange(state), frame = 0,
                        ),
                        referenceImageBase64 = ref,
                    )
                } else {
                    // 나머지: 상태별 명시 사진 ?? 앵커(메모리→디스크→results 복구). keep/change 없음.
                    val perStatePhoto = perStateReferenceB64(state)
                    val ref = perStatePhoto ?: anchorReferenceB64()
                    BgGenSpec(
                        state = state, frame = 0,
                        prompt = buildPrompt(state, consistencyPrefix = ref != null, frame = 0),
                        referenceImageBase64 = ref,
                        matchIdleColor = perStatePhoto == null,
                    )
                }
            }
            withContext(Dispatchers.IO) {
                BackgroundGenQueue.retry(spec, quality, artStyle, batchSessionId)
            }
        }
    }

    // MARK: - 적용/배경/저장

    /** 프레임별 표시 이미지 — 투명(raw) 기본, '흰 배경'이면 즉시 흰색 합성 (iOS displayedImage). */
    fun displayedImage(state: CharacterState, frame: Int = 0): Bitmap? {
        val raw = (if (frame == 1) resultsFrame1[state] else results[state]) ?: return null
        val transparent = displayTransparentByState[state] ?: true
        return if (transparent) raw else whiteOf(raw)
    }

    fun displayTransparent(state: CharacterState): Boolean = displayTransparentByState[state] ?: true

    /**
     * 이 상태를 홈/위젯에 적용 — 활성 슬롯 쓰기 + 위젯 reload.
     * 배치 생성은 갤러리에만 저장되므로 실제 반영은 이 버튼이 유일한 경로 (스펙 03 핵심 규칙).
     */
    fun applyOne(state: CharacterState) {
        viewModelScope.launch {
            applyOneInternal(state)
            SyncCoordinator.refreshWidgets()
        }
    }

    private suspend fun applyOneInternal(state: CharacterState) {
        val img0 = displayedImage(state, 0) ?: return
        val img1 = displayedImage(state, 1)
        withContext(Dispatchers.IO) {
            // saveActiveSlotOnly(frame0) 가 stale frame1 을 정리 — f1 은 그 뒤에 저장.
            CharacterImageStore.saveActiveSlotOnly(img0, state, 0)
            if (img1 != null) CharacterImageStore.saveActiveSlotOnly(img1, state, 1)
        }
        // 워치 전송은 SCOPE 제외 — no-op.
        appliedStates = appliedStates + state
    }

    fun applyAll() {
        viewModelScope.launch {
            for (state in CharacterState.entries) {
                if (results[state] != null) applyOneInternal(state)
            }
            SyncCoordinator.refreshWidgets()
        }
    }

    /** 배경 모두 지우기 — raw(모델 출력=투명 원본)를 그대로 활성 슬롯 적용, 표시모드 true. */
    fun applyTransparentToAll() {
        if (isProcessingTransparentBulk) return
        viewModelScope.launch {
            isProcessingTransparentBulk = true
            withContext(Dispatchers.IO) {
                for (state in CharacterState.entries) {
                    val raw = results[state] ?: continue
                    CharacterImageStore.saveActiveSlotOnly(raw, state, 0)
                    resultsFrame1[state]?.let { CharacterImageStore.saveActiveSlotOnly(it, state, 1) }
                }
            }
            for (state in CharacterState.entries) {
                if (results[state] != null) displayTransparentByState[state] = true
            }
            SyncCoordinator.refreshWidgets()
            isProcessingTransparentBulk = false
        }
    }

    /** 처음 그림으로 — 흰색 합성본을 활성 슬롯 적용, 표시모드 false. */
    fun restoreOriginalToAll() {
        if (isProcessingTransparentBulk) return
        viewModelScope.launch {
            isProcessingTransparentBulk = true
            withContext(Dispatchers.IO) {
                for (state in CharacterState.entries) {
                    val raw = results[state] ?: continue
                    CharacterImageStore.saveActiveSlotOnly(whiteOf(raw), state, 0)
                    resultsFrame1[state]?.let {
                        CharacterImageStore.saveActiveSlotOnly(whiteOf(it), state, 1)
                    }
                }
            }
            for (state in CharacterState.entries) {
                if (results[state] != null) displayTransparentByState[state] = false
            }
            SyncCoordinator.refreshWidgets()
            isProcessingTransparentBulk = false
        }
    }

    /**
     * 개별 배경 토글 (상세 시트 세그먼트) — 표시만 바꾸는 게 아니라
     * 활성 슬롯 적용까지 즉시 일어남 (스펙 03 주의점).
     */
    fun applyTransparentOne(state: CharacterState, on: Boolean) {
        val raw = results[state] ?: return
        viewModelScope.launch {
            withContext(Dispatchers.IO) {
                CharacterImageStore.saveActiveSlotOnly(if (on) raw else whiteOf(raw), state, 0)
                resultsFrame1[state]?.let { f1 ->
                    CharacterImageStore.saveActiveSlotOnly(if (on) f1 else whiteOf(f1), state, 1)
                }
            }
            displayTransparentByState[state] = on
            SyncCoordinator.refreshWidgets()
        }
    }

    // MARK: - 상세 시트

    fun openDetail(state: CharacterState) {
        selectedResult = state
        revisionText = ""
        revisionError = null
        detailFrame = 0
    }

    fun closeDetail() { selectedResult = null }

    /** 프레임 바꾸기 — f0↔f1 스왑, 이미 적용된 상태였으면 즉시 재적용 (iOS 동형). */
    fun swapDetailFrames(state: CharacterState) {
        val f0 = results[state] ?: return
        val f1 = resultsFrame1[state] ?: return
        results[state] = f1
        resultsFrame1[state] = f0
        if (state in appliedStates) applyOne(state)
    }

    /** 상세 시트 '움직임' 토글 — 상태별 애니 재생 끄기/켜기 + 위젯 reload. */
    fun isMotionOn(state: CharacterState): Boolean = !CharacterImageStore.isAnimationDisabled(state)

    fun setMotionOn(state: CharacterState, on: Boolean) {
        viewModelScope.launch(Dispatchers.IO) {
            CharacterImageStore.setAnimationDisabled(!on, state)
            SyncCoordinator.refreshWidgets()
        }
    }

    /**
     * 상세 시트 '바꾸기' — 기존 결과 + 자연어 수정으로 재생성 (프레임별).
     * reference 우선순위: 수정용 첨부사진 > (frame1 이면 frame0 앵커) > 해당 프레임 기존본.
     * 성공 시 갤러리에만 저장 + appliedStates 에서 제거 (아직 적용 전이므로 배지 리셋).
     */
    fun reviseOne(state: CharacterState, frame: Int, text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty() || isRevising) return
        revisionError = null
        val cost = GenerationQuota.cost(quality)
        if (!GenerationQuota.canGenerate(cost)) {
            showPaywall = true
            return
        }
        viewModelScope.launch {
            isRevising = true
            inProgressStates = inProgressStates + state
            stateStartedAt[state] = System.currentTimeMillis()
            try {
                // frame1 은 frame0 을 앵커로 두면 캐릭터/크기 일관성이 유지됨 (iOS 동일)
                val anchor = if (frame == 1) (results[state] ?: resultsFrame1[state]) else results[state]
                val refBmp = revisionRefImage ?: anchor
                val refB64 = refBmp?.let { withContext(Dispatchers.Default) { ImageProcessing.toBase64Png(it) } }
                val pose = stateHints[state] ?: state.generationHint
                val desc = baseIdentity.trim()
                val basePrompt = if (desc.isEmpty()) pose else "$desc, $pose"
                var modifiedPrompt = "$basePrompt. User modification: $trimmed"
                if (frame == 1) {
                    modifiedPrompt += ". Animation frame 2 (for a 2-frame swap loop): " +
                        "${state.animationFrame2Hint}. CRITICAL: keep the character at the EXACT " +
                        "same size, scale, and centered position as the reference image; " +
                        "only the pose changes."
                }
                modifiedPrompt += ". Transparent background — only the character, no shadows."
                val req = GenerateImageRequest(
                    prompt = modifiedPrompt, referenceImageBase64 = refB64,
                    quality = quality, artStyle = artStyle, style = "auto", model = "gpt-image-2",
                )
                val resp = ApiClient.generateImage(req)
                val rawImg = withContext(Dispatchers.Default) { ImageProcessing.fromBase64(resp.imageBase64) }
                if (rawImg != null) {
                    // frame1 정규화 기준 — frame0 원본 (메모리 → 큐 디스크 → 128 결과 순 복구)
                    val ref0 = if (frame == 1) {
                        frame0FullRes[state]
                            ?: withContext(Dispatchers.IO) { BackgroundGenQueue.loadFrame0FullRes(state) }
                            ?: results[state]
                    } else null
                    val (flat, small) = withContext(Dispatchers.Default) {
                        val img = ImageProcessing.chromaKeyRemoved(rawImg)
                        val f = if (ref0 != null) ImageProcessing.matchedToReference(img, ref0) else img
                        var s128 = ImageProcessing.downsampled(f, 128)
                        // frame1 색 드리프트 제거 — frame0 색에 맞춤
                        if (ref0 != null) {
                            s128 = ImageProcessing.colorMatched(s128, ImageProcessing.downsampled(ref0, 128))
                        }
                        f to s128
                    }
                    if (frame == 1) {
                        resultsFrame1[state] = small
                    } else {
                        results[state] = small
                        frame0FullRes[state] = flat
                        if (state == CharacterState.IDLE) idleFullRes = flat
                    }
                    displayTransparentByState[state] = false   // 새 raw → 흰배경 기준으로 리셋
                    withContext(Dispatchers.IO) {
                        // 갤러리에만 저장 — 반영은 '적용' 버튼 (바꾼 결과는 아직 적용 전)
                        CharacterImageStore.save(
                            small, state, frame = frame, applyToActiveSlot = false,
                            batchId = batchSessionId, prompt = modifiedPrompt,
                        )
                    }
                    appliedStates = appliedStates - state
                    GenerationQuota.record(cost)   // 바꾸기도 실제 생성 — 직접 호출이라 여기서 차감
                    refreshQuota()
                    revisionText = ""
                } else {
                    revisionError = str(R.string.batch_err_no_image_retry)
                }
            } catch (e: ApiError.PaymentRequired) {
                showPaywall = true
            } catch (e: Exception) {
                // 조용한 실패 금지 — 시트 안에 주황 캡션으로 표시 (스펙 03 (H)7)
                revisionError = e.koreanized()
            } finally {
                isRevising = false
                inProgressStates = inProgressStates - state
                stateStartedAt.remove(state)
            }
        }
    }

    // MARK: - 사진 앱 저장 (권한 게이트는 화면이 담당 — PhotoSaver 계약)

    /** 상세 시트 '저장' — 현재 보는 프레임 한 장. */
    fun saveOneToPhotos(state: CharacterState, frame: Int) {
        val img = displayedImage(state, frame) ?: results[state] ?: return
        viewModelScope.launch {
            val ok = PhotoSaver.save(img).isSuccess
            saveResultMessage = str(
                if (ok) R.string.batch_photos_saved_one else R.string.batch_photos_save_failed,
            )
        }
    }

    /** 전체 저장 — CharacterState 선언 순서로 frame0→frame1 (사진 앱에서도 같은 순서). */
    fun saveAllToPhotos() {
        if (isSavingPhotos) return
        viewModelScope.launch {
            isSavingPhotos = true
            val items = CharacterState.entries.flatMap { s ->
                listOfNotNull(results[s], resultsFrame1[s])
            }
            var allOk = true
            for (img in items) {
                if (PhotoSaver.save(img).isFailure) {
                    allOk = false
                    break
                }
            }
            saveResultMessage =
                if (allOk) str(R.string.batch_photos_saved_n, items.size)
                else str(R.string.batch_photos_save_failed)
            isSavingPhotos = false
        }
    }

    /** API 28 저장 권한 거부 — iOS PHPhotoLibrary 거부 문구와 동일하게 표기. */
    fun reportPhotosPermissionDenied() {
        saveResultMessage = str(R.string.batch_photos_denied)
    }

    fun dismissSaveResult() { saveResultMessage = null }

    // MARK: - 프롬프트 조립 (iOS buildPrompt 원문 포팅 — 서버 지시문이라 코드 상수)

    private fun buildPrompt(
        state: CharacterState,
        consistencyPrefix: Boolean,
        keepNote: String = "",
        changeNote: String = "",
        frame: Int = 0,
    ): String {
        val pose = stateHints[state] ?: state.generationHint
        val desc = baseIdentity.trim()
        val keepClause = if (keepNote.isEmpty()) "" else " Keep especially: $keepNote."
        // '바꿀 것'은 상태별 포즈에 '추가'로 적용 (포즈는 상태마다 다르므로 대체가 아니라 더함).
        val changeScene = if (changeNote.isEmpty()) pose else "$pose, and also $changeNote"
        var prompt = when {
            frame == 1 ->
                // frame1 — 디자인·크기·위치는 그대로, 포즈는 '확실히' 바뀌게.
                // (예전 "tiny hint of life" 문구가 큰 포즈 변화를 억눌렀던 문제의 해소 — iOS 주석)
                "Use the reference image as the SAME character. Keep identical: face, outfit, " +
                    "colors, art/pixel style, line thickness, body proportions, size, scale, " +
                    "centered position, framing, and the flat solid white background. This is the " +
                    "SECOND frame of a 2-frame animation loop, so the POSE MUST visibly CHANGE " +
                    "from the reference. Change the pose to: ${state.animationFrame2Hint}. " +
                    "Change ONLY the pose — keep every design detail and the placement identical " +
                    "to the reference."
            consistencyPrefix -> {
                // frame0 + 참고(idle 앵커/사용자 사진) — Keep=캐릭터 전부, Change=이 state 의 포즈(+바꿀것).
                val charNote = if (desc.isEmpty()) "" else " The character is: $desc."
                "Use the reference image. Keep the EXACT same character — identity, face and " +
                    "expression style, body proportions, art style, colors and shading, line " +
                    "thickness, and every design detail.$charNote$keepClause " +
                    "Change ONLY: $changeScene. Do not change the character design; keep all " +
                    "other visual details identical to the reference."
            }
            else -> {
                // frame0, 참고 없음 (보통 idle 최초 생성) — 설명 + 포즈 (+바꿀것).
                val base = if (desc.isEmpty()) pose else "$desc, $pose"
                if (changeNote.isEmpty()) base else "$base, $changeNote"
            }
        }
        // 격자(체커보드) 방지: "투명"을 격자로 그리는 모델 대비 명시 지시 (iOS 공통 접미).
        prompt += ". Transparent background — only the character, no background fill, no shadows."
        return prompt
    }

    // MARK: - 참고사진 헬퍼 (PNG 인코딩 포함 — Default/IO 에서 호출)

    /** state 의 reference b64 — 사용자가 직접 넣은 사진만 (상태별 → 전역). idle 앵커 제외. */
    private fun resolveUserReference(state: CharacterState): String? =
        (stateReferenceImages[state] ?: referenceImage)?.let { ImageProcessing.toBase64Png(it) }

    /** 그 상태에 '명시적으로' 첨부한 사진만 (전역 X). 없으면 null → 호출부가 idle 앵커 사용. */
    private fun perStateReferenceB64(state: CharacterState): String? =
        stateReferenceImages[state]?.let { ImageProcessing.toBase64Png(it) }

    /** 승인된 idle 앵커 b64 — 앱 재시작 후엔 큐 디스크에서 복구 (iOS anchorReferenceB64). */
    private fun anchorReferenceB64(): String? =
        (idleAnchor
            ?: BackgroundGenQueue.loadFrame0FullRes(CharacterState.IDLE)
            ?: results[CharacterState.IDLE])
            ?.let { ImageProcessing.toBase64Png(it) }

    /** '그대로 둘 것' — 사용자 참고사진이 실제로 쓰일 때만 반영 (idle 앵커엔 미적용). */
    private fun userRefKeep(state: CharacterState): String =
        if (stateReferenceImages[state] != null || referenceImage != null) referenceKeep.trim() else ""

    private fun userRefChange(state: CharacterState): String =
        if (stateReferenceImages[state] != null || referenceImage != null) referenceChange.trim() else ""

    // MARK: - 기타

    /** 설명을 프로필에 저장 — 값이 바뀐 경우만 (단건 생성과 공유, iOS saveDescription). */
    private suspend fun saveDescription() = withContext(Dispatchers.IO) {
        val p = CharacterProfileStore.load()
        val trimmed = baseIdentity.trim()
        if (p.aiPrompt != trimmed) CharacterProfileStore.save(p.copy(aiPrompt = trimmed))
    }

    /** 흰배경 합성 캐시 — 같은 raw 의 반복 합성 방지. IO/메인 양쪽 접근이라 synchronized. */
    private fun whiteOf(raw: Bitmap): Bitmap = synchronized(whiteCache) {
        whiteCache.getOrPut(raw) { ImageProcessing.flattenedOnWhite(raw) }
    }

    private fun str(id: Int, vararg args: Any): String =
        if (args.isEmpty()) WithuApp.context.getString(id)
        else WithuApp.context.getString(id, *args)
}
