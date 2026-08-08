package com.seoyoung.withu.gen

import android.graphics.Bitmap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.seoyoung.withu.R
import com.seoyoung.withu.WithuApp
import com.seoyoung.withu.camera.PhotoSaver
import com.seoyoung.withu.character.CharacterProfileStore
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.net.Entitlement
import com.seoyoung.withu.net.koreanized
import com.seoyoung.withu.quota.GenerationQuota
import com.seoyoung.withu.shared.CharacterImageStore
import com.seoyoung.withu.sync.SyncCoordinator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

/**
 * 단건 생성 상태/로직 — iOS CharacterGenView.swift 의 @State + 액션 포팅 (스펙 02 §3).
 *
 * ⚠️ 생성 자체는 여기서 돌지 않는다 — `SingleGenQueue`(WorkManager + FGS)가 주인이고
 * 이 클래스는 잡 스냅샷을 화면 상태로 비추기만 한다. 화면을 나가거나 프로세스가 정리돼도
 * 생성이 이어지고, 결과는 갤러리 자동 저장 + 다듬기 이력을 거쳐 복원 경로로 돌아온다.
 *
 * 캔디 규칙 (변경 금지 — 커밋 fd98948 교훈):
 *  - 잔액의 권위는 로컬(GenerationQuota). 서버는 차감하지 않음.
 *  - record() 는 반드시 '성공 판정' 후에만 — 이제 `SingleGenQueue.handleSuccessLocked` 한 곳뿐.
 *  - 서버가 free_consumed=true 를 준 세션(프레임 2장 포함)은 전부 미차감.
 */
class SingleGenViewModel : ViewModel() {

    // MARK: - 핵심 상태 (iOS @State 대응 — Compose 스냅샷 상태)

    var mode by mutableStateOf(GenerationMode.AI_GENERATE)
        private set
    var targetState by mutableStateOf(CharacterState.IDLE)
        private set

    /** 내 캐릭터 "설명"(정체성). 진입 시 저장된 묘사(aiPrompt)로 시작 (스펙 02 §3). */
    var prompt by mutableStateOf(CharacterProfileStore.load().aiPrompt)
    var refinementPrompt by mutableStateOf("")

    /** "항목별 입력" 도우미 — 바뀌면 자유 설명칸(prompt)에 자동 합쳐짐. */
    var subjectField by mutableStateOf("")
        private set
    var looksField by mutableStateOf("")
        private set
    var colorField by mutableStateOf("")
        private set

    /** 퀄리티는 UI 노출 없이 "low" 고정 (스펙 02 §5 주의점 — 셀렉터 추가 금지). */
    private val quality: String = "low"
    var artStyle by mutableStateOf("pixel")   // "casual" | "pixel"

    // 참고 사진 (AI 모드)
    var referenceImage by mutableStateOf<Bitmap?>(null)
        private set
    var referenceKeep by mutableStateOf("")
    var referenceChange by mutableStateOf("")

    // 이미지 첨부 모드
    var importedRawImage by mutableStateOf<Bitmap?>(null)
        private set
    var importedProcessedImage by mutableStateOf<Bitmap?>(null)
        private set
    var removeBackground by mutableStateOf(true)
    var isProcessing by mutableStateOf(false)
        private set

    // 생성 진행 — 실행 주체는 SingleGenQueue(WorkManager FGS). 여기는 표시용 미러.
    /** 큐에 올리기 직전(참고사진 base64 인코딩 등)의 짧은 준비 구간. */
    private var preparing by mutableStateOf(false)
    /** 워커 큐의 현재 단건 잡 — 진행/결과/실패의 단일 출처. */
    private var queueJob by mutableStateOf<SingleGenJob?>(null)
    /** 준비 구간의 경과 타이머 기준 (잡이 올라가면 job.queuedAt 이 이어받는다). */
    private var localStartedAt by mutableStateOf<Long?>(null)

    val isGenerating: Boolean get() = preparing || queueJob?.isActive == true

    /** 경과 초 표시 기준 (epoch millis). */
    val generationStartedAt: Long?
        get() = if (isGenerating) (queueJob?.queuedAt ?: localStartedAt) else null

    // 결과
    var resultImage by mutableStateOf<Bitmap?>(null)
        private set
    var resultFrame2 by mutableStateOf<Bitmap?>(null)
        private set
    /** frame1 정규화 앵커용 1번째 프레임 원본(1024, 투명). */
    private var lastFrame0FullRes: Bitmap? = null
    var generateAnimated by mutableStateOf(false)
    var singleDetailFrame by mutableStateOf(0)   // 결과에서 보고 있는 프레임 (0=기본, 1=움직임)
    var displayTransparent by mutableStateOf(true)   // 기본 투명 (모델이 투명으로 줌)
    var revisedPrompt by mutableStateOf<String?>(null)
        private set
    /** 마지막 성공 생성에 실제로 보낸 프롬프트 — 갤러리 '만든 기록' 저장용. */
    private var lastSentPrompt: String? = null
    var lastError by mutableStateOf<String?>(null)

    // 버전 이력 — [0] = 원본
    var versions by mutableStateOf<List<ResultVersion>>(emptyList())
        private set
    var selectedVersion by mutableStateOf(0)
        private set

    // 캔디/무료
    var remainingGenerations by mutableStateOf(GenerationQuota.remainingToday())
        private set
    var displayedCandy by mutableStateOf(GenerationQuota.displayedCandy())
        private set
    /**
     * 서버 entitlement 스냅샷 — iOS 는 AuthManager 가 들고 있으나 Android 는 로그인이
     * SCOPE 제외라 /generate 응답의 entitlement 로만 갱신되는 화면 로컬 홀더 (PLAN 위반 아님 —
     * private 해결책. 화면 진입 시 refreshEntitlement() 대응은 인증 모듈 후속).
     */
    private var entitlement by mutableStateOf<Entitlement?>(null)

    /** 계정 무료 1회 남았는지 — 서버(entitlement)가 진실. */
    val hasFreeCreation: Boolean
        get() = (entitlement?.freeSingleRemaining ?: 0) > 0

    /**
     * 이번 '만들기'가 실제로 무료인지 — 무료가 남아 있고 '사진 없이 프롬프트로만' 만들 때만.
     * 사진을 넣으면 무료를 안 쓰고 캔디로 (공짜 사진→캐릭터 남용 방지).
     */
    val creationIsFree: Boolean
        get() = hasFreeCreation && referenceImage == null

    /** 이번 확인 팝업의 동작이 무료인지 — 만들기는 사진 없을 때만, 다듬기는 무료 남았으면. */
    val pendingActionIsFree: Boolean
        get() = when (pendingAction) {
            is PendingAction.NewGeneration -> creationIsFree
            is PendingAction.Refine -> hasFreeCreation
            null -> false
        }

    /**
     * 생성 모니터링용 수정 체인 id — 새 원본 생성마다 갱신, 다듬기는 같은 값을 재사용.
     * 갤러리 '캐릭터별' batchId 로도 재사용 — 한 세션의 결과가 한 캐릭터로 묶임.
     */
    private var currentSessionId: String = UUID.randomUUID().toString()

    /** 결과에 붙일 이름 — 채우면 갤러리 '캐릭터별'에 이 이름으로 표시. (선택) */
    var characterName by mutableStateOf("")
        private set

    /**
     * 성공/실패 햅틱 원샷 이벤트 — iOS UINotificationFeedbackGenerator(.success/.error) 대응.
     * 햅틱은 Composable(LocalHapticFeedback)에서만 울릴 수 있어, VM 은 신호만 세우고
     * 화면이 관찰 후 consumeHaptic() 으로 비운다. (VIBRATE 권한 불필요한 Compose 햅틱 경로)
     */
    var hapticSignal by mutableStateOf<HapticSignal?>(null)
        private set

    fun consumeHaptic() { hapticSignal = null }

    // 오버레이/다이얼로그
    var pendingAction by mutableStateOf<PendingAction?>(null)
        private set
    var showAppliedAlert by mutableStateOf(false)
    var showSavedAlert by mutableStateOf(false)
    var showPaywall by mutableStateOf(false)
    var showGalleryRefPicker by mutableStateOf(false)
    var cropTarget by mutableStateOf<CropRequest?>(null)

    private fun str(resId: Int): String = WithuApp.context.getString(resId)

    init {
        // 진행 중인 잡 관찰 — 화면을 나갔다 와도, 프로세스가 죽었다 살아나도 여기로 이어진다.
        viewModelScope.launch {
            SingleGenQueue.state.collect { onQueueSnapshot(it) }
        }
    }

    override fun onCleared() {
        super.onCleared()
        // 화면이 사라졌으니 완료는 알림으로 (SingleGenQueue.finishRun 판단).
        SingleGenQueue.setScreenVisible(false)
    }

    /**
     * 큐 스냅샷 → 화면 상태. 끝난 잡은 여기서 한 번만 반영하고 비운다.
     * 결과는 (워커가 이미 저장해 둔) 갤러리 + 다듬기 이력에서 되읽는다 — 앱이 죽었다 살아나도 같은 경로.
     */
    private suspend fun onQueueSnapshot(snapshot: SingleGenSnapshot) {
        snapshot.entitlement?.let { entitlement = it }
        val job = snapshot.job
        queueJob = job
        if (job == null) {
            refreshQuota()
            return
        }
        preparing = false
        if (job.isActive) {
            refreshQuota()
            return
        }
        // 끝난 잡 — 결과/실패 반영
        localStartedAt = null
        if (job.paymentRequired) showPaywall = true
        if (job.isDone) {
            // 부분 실패(움직임 프레임만 실패)면 사유를 남기고, 아니면 초기화.
            lastError = job.errorMessage
            job.revisedPrompt?.let { revisedPrompt = it }
            applyChainFromDisk(guard = false)
        } else {
            job.errorMessage?.let { lastError = it }
        }
        // 다듬기 입력칸은 성공/실패 상관없이 비운다 (기존 동작).
        if (job.isRefine) refinementPrompt = ""
        queueJob = null
        withContext(Dispatchers.IO) { SingleGenQueue.clearFinished(job.id) }
        refreshQuota()
    }

    // MARK: - 파생 값

    /** 프레임 1장 기준 캔디 비용 (low = 1). */
    val unitCost: Int get() = GenerationQuota.cost(quality)

    /** 이번 '만들기' 총비용 — 움직이는 캐릭터면 frame0+frame1 각각 과금이라 2배. */
    val newGenerationCost: Int
        get() = if (generateAnimated && targetState.usesGeneratedMotion) unitCost * 2 else unitCost

    /**
     * 서버로 보낼 프롬프트 = 캐릭터 설명 + 선택한 상태의 포즈(generationHint).
     * 참고 사진이 있으면 Keep/Change 영어 템플릿 — 캐릭터는 그대로, '바꿀 것'만 바뀌게
     * (iOS composedPrompt 원문 그대로 이식 — 서버 지시문이라 리소스 아님).
     */
    private fun composedPrompt(): String {
        val desc = prompt.trim()
        val pose = targetState.generationHint
        if (referenceImage != null) {
            val keep = referenceKeep.trim()
            val change = referenceChange.trim()
            val keepClause = if (keep.isEmpty()) "" else " Keep especially: $keep."
            // '바꿀 것'·'캐릭터 프롬프트' 둘 중 하나만 채워도 됨 — 바꿀것 > 프롬프트 > 상태 포즈 순.
            val changeClause = change.ifEmpty { desc.ifEmpty { pose } }
            return "Use the reference image. Keep the EXACT same character — identity, face and " +
                "expression style, body proportions, art style, colors and shading, line thickness, " +
                "and every design detail.$keepClause Change ONLY: $changeClause. Do not change the " +
                "character design; keep all other visual details identical to the reference."
        }
        return if (desc.isEmpty()) pose else "$desc, $pose"
    }

    /** 생성 모니터링 표시용 — 사용자가 실제 입력한 원문 + 어떤 칸이었는지 라벨. */
    private fun rawUserInput(): Pair<String, String> {
        val desc = prompt.trim()
        if (referenceImage != null) {
            val keep = referenceKeep.trim()
            val change = referenceChange.trim()
            val parts = buildList {
                if (change.isNotEmpty()) add("바꿀 것: $change")
                if (keep.isNotEmpty()) add("그대로: $keep")
                if (isEmpty() && desc.isNotEmpty()) add(desc)
            }
            return parts.joinToString(" / ") to "참고사진"
        }
        return desc to "설명"
    }

    /** frame1(2번째 장면) 프롬프트 — "1번째와 동일, 포즈만 변경" 강제 (iOS 원문). */
    private fun animationFrame2Instruction(state: CharacterState): String =
        " Use the reference image as the SAME character. Keep identical: face, outfit, colors, " +
            "art/pixel style, line thickness, body proportions, size, scale, centered position, " +
            "framing, and the flat solid background. This is the SECOND frame of a 2-frame " +
            "animation loop, so the POSE MUST visibly CHANGE from the reference. Change the pose " +
            "to: ${state.animationFrame2Hint}. Change ONLY the pose — keep every design detail " +
            "and the placement identical to the reference."

    /**
     * 보여줄 이미지. raw 는 투명(모델 출력) — '배경 빼기'=원본 그대로,
     * '흰 배경'=흰색 즉시 합성 (Vision/ML 불필요 — 스펙 02 §3 배경 토글).
     */
    fun currentDisplay(frame: Int): Bitmap? {
        val raw = (if (frame == 0) resultImage else resultFrame2) ?: return null
        return if (displayTransparent) raw else ImageProcessing.flattenedOnWhite(raw)
    }

    /** import 미리보기/적용에 쓸 이미지 — 토글에 따라 배경 제거본 또는 원본. */
    fun displayedImport(): Bitmap? {
        val raw = importedRawImage ?: return null
        return if (removeBackground) importedProcessedImage ?: raw else raw
    }

    // MARK: - 단순 상태 전이

    /** 화면 진입/페이월 닫힘 시 잔량 갱신 (iOS onAppear + paywall onClose). */
    fun refreshQuota() {
        remainingGenerations = GenerationQuota.remainingToday()
        displayedCandy = GenerationQuota.displayedCandy()
    }

    /** 모드 전환 — 결과/에러/import 이미지 reset (iOS onChange(mode) 동일 범위만). */
    fun selectMode(m: GenerationMode) {
        if (mode == m) return
        mode = m
        resultImage = null
        revisedPrompt = null
        lastError = null
        importedRawImage = null
        importedProcessedImage = null
    }

    /** 상태 변경 — refinementPrompt 만 reset (설명은 상태 무관한 정체성이라 유지). */
    fun selectTargetState(s: CharacterState) {
        if (targetState == s) return
        targetState = s
        refinementPrompt = ""
    }

    /** 결과 카드의 이름칸 — 입력 즉시 현재 세션(batchId)에 반영 (생성 후 수정도 바로 저장). */
    fun updateCharacterName(v: String) {
        characterName = v
        val batchId = currentSessionId
        viewModelScope.launch(Dispatchers.IO) { CharacterImageStore.setCharacterName(v, batchId) }
    }

    fun updateSubjectField(v: String) { subjectField = v; composeFromHelper() }
    fun updateLooksField(v: String) { looksField = v; composeFromHelper() }
    fun updateColorField(v: String) { colorField = v; composeFromHelper() }

    /** 항목별 입력을 합쳐 설명칸(prompt)을 덮어씀. 모두 비면 기존 자유 입력 보존. */
    private fun composeFromHelper() {
        val parts = listOf(subjectField, looksField, colorField)
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        if (parts.isNotEmpty()) prompt = parts.joinToString(", ")
    }

    // MARK: - 사진 선택

    /** 앨범에서 고른 참고사진 — 정사각 크롭을 거쳐 참고 이미지로. */
    fun pickedAlbumReference(image: Bitmap) {
        cropTarget = CropRequest(image) { cropped -> referenceImage = cropped }
    }

    /** 내 캐릭터(갤러리)에서 고른 참고사진 — 이미 정사각이라 크롭 없이 바로. */
    fun pickedGalleryReference(image: Bitmap) {
        referenceImage = image
    }

    /** '사진 빼기' — keep/change 텍스트는 유지 (iOS 원본 동작). */
    fun removeReference() {
        referenceImage = null
    }

    /** import 모드에서 고른 사진 — 정사각 크롭 후 배경 제거 처리. */
    fun pickedImportPhoto(image: Bitmap) {
        cropTarget = CropRequest(image) { cropped ->
            viewModelScope.launch { processImport(cropped) }
        }
    }

    /** 포토피커 로드 실패. */
    fun onPhotoLoadFailed() {
        lastError = str(R.string.gen_err_photo_load)
    }

    /** 자른 이미지 배경 제거 + 정규화 (온디바이스, 무비용). */
    private suspend fun processImport(image: Bitmap) {
        isProcessing = true
        lastError = null
        try {
            importedRawImage = image
            val processed = withContext(Dispatchers.Default) {
                ImageProcessing.prepareForCharacter(image)
            }
            importedProcessedImage = processed
            if (processed == null) lastError = str(R.string.err_generic)
        } finally {
            isProcessing = false
        }
    }

    // MARK: - 캔디 팝업 → 실행

    /** 만들기 버튼 — 즉시 실행하지 않고 캔디 안내 팝업으로. */
    fun requestGenerate() {
        pendingAction = PendingAction.NewGeneration
    }

    /** 다듬기 버튼 — 보고 있는 프레임만 다듬음 (frame2 없으면 0). */
    fun requestRefine() {
        pendingAction = PendingAction.Refine(if (resultFrame2 != null) singleDetailFrame else 0)
    }

    fun dismissPendingAction() {
        pendingAction = null
    }

    /** 팝업 확인 — 실제 실행은 WorkManager(SingleGenQueue) 로 넘긴다. */
    fun confirmPendingAction() {
        when (val action = pendingAction) {
            is PendingAction.NewGeneration -> startGeneration()
            is PendingAction.Refine -> startRefine(action.frame)
            null -> Unit
        }
        pendingAction = null
    }

    /** '그만두기' — Worker 취소 + 잡 폐기. 차감 없음 (record 는 성공 후에만). */
    fun cancelGeneration() {
        preparing = false
        localStartedAt = null
        queueJob = null
        lastError = str(R.string.gen_err_cancelled)
        // 취소 정리는 파일 IO 를 동반 — 메인 스레드에서 돌리지 않는다.
        viewModelScope.launch(Dispatchers.IO) { SingleGenQueue.cancel() }
    }

    fun onPaywallClosed() {
        showPaywall = false
        refreshQuota()
    }

    // MARK: - 생성/다듬기

    /**
     * 만들기 — 큐(Worker)에 넘긴다. 화면을 나가도 계속되고 결과는 갤러리 경유로 돌아온다.
     * 캔디 가드만 여기서, 실제 차감은 워커의 성공 판정 뒤에.
     */
    private fun startGeneration() {
        val cost = unitCost
        // 가드 — 무료 1회(사진 없을 때만) 또는 로컬 캔디.
        if (!creationIsFree && !GenerationQuota.canGenerate(cost)) {
            lastError = str(R.string.gen_err_no_candy)
            return
        }
        val state = targetState
        val reference = referenceImage
        val animated = generateAnimated && state.usesGeneratedMotion
        val basePrompt = composedPrompt()
        val (rawText, rawField) = rawUserInput()
        val sessionId = UUID.randomUUID().toString()   // 새 원본 → 새 수정 체인
        val finalPrompt = withTransparentBackground(basePrompt)

        lastError = null
        resultFrame2 = null
        singleDetailFrame = 0
        currentSessionId = sessionId
        characterName = ""                             // 새 캐릭터 → 이름 초기화
        lastSentPrompt = finalPrompt                   // 갤러리 '만든 기록' 저장용
        preparing = true
        localStartedAt = System.currentTimeMillis()

        viewModelScope.launch {
            saveDescription()
            val referenceB64 = reference?.let {
                withContext(Dispatchers.Default) { ImageProcessing.toBase64Png(it) }
            }
            withContext(Dispatchers.IO) {
                SingleGenQueue.start(
                    SingleGenSpec(
                        state = state,
                        sessionId = sessionId,
                        quality = quality,
                        artStyle = artStyle,
                        isRefine = false,
                        frame = 0,
                        prompt = finalPrompt,
                        referenceBase64 = referenceB64,
                        // 사진 첨부 생성은 kind=photo → 서버가 무료 1회를 소진하지 않음(캔디로 차감).
                        serverKind = if (reference != null) "photo" else null,
                        userInput = rawText,
                        inputField = rawField,
                        // 연속 이미지 — frame0 성공 시 그 원본(1024)을 reference 로 워커가 이어서 만든다.
                        wantsFrame1 = animated,
                        frame1Prompt = if (animated) {
                            withTransparentBackground(
                                basePrompt + "." + animationFrame2Instruction(state),
                            )
                        } else {
                            null
                        },
                        galleryPrompt = finalPrompt,
                    ),
                )
            }
            preparing = false
        }
    }

    /** 보고 있는 프레임만 다듬기. frame1 은 frame0 을 앵커로 둬 캐릭터/크기 일관성 유지. */
    private fun startRefine(frame: Int) {
        val cost = unitCost
        if (!hasFreeCreation && !GenerationQuota.canGenerate(cost)) {
            lastError = str(R.string.gen_err_no_candy)
            return
        }
        val currentSlot = if (frame == 1) resultFrame2 else resultImage
        if (currentSlot == null) {
            lastError = str(R.string.gen_err_reload)
            return
        }
        // reference(앵커): frame1 다듬기 → frame0, frame0 다듬기 → 자기 자신.
        val reference = if (frame == 1) (resultImage ?: currentSlot) else currentSlot
        val state = targetState
        val sessionId = currentSessionId
        val userText = refinementPrompt
        var refinePrompt = refinementPrompt
        if (frame == 1) {
            refinePrompt += ". Animation frame 2 (for a 2-frame swap loop): " +
                "${state.animationFrame2Hint}. CRITICAL: keep the character at the EXACT " +
                "same size, scale, and centered position as the reference image; only the pose changes."
        }
        val finalPrompt = withTransparentBackground(refinePrompt)
        // 갤러리 '만든 기록' — frame0 을 새로 그릴 때만 갱신 (움직임 프레임 다듬기는 원본 기록 유지).
        val galleryPrompt = if (frame == 0) finalPrompt else lastSentPrompt
        if (frame == 0) lastSentPrompt = finalPrompt
        // 이번에 안 바뀌는 프레임은 워커가 결과를 합칠 때 그대로 쓴다.
        val baseFrame0 = resultImage
        val baseFrame1 = resultFrame2
        val matchAnchor = lastFrame0FullRes ?: resultImage

        lastError = null
        preparing = true
        localStartedAt = System.currentTimeMillis()

        viewModelScope.launch {
            val referenceB64 = withContext(Dispatchers.Default) {
                ImageProcessing.toBase64Png(reference)
            }
            withContext(Dispatchers.IO) {
                SingleGenQueue.start(
                    SingleGenSpec(
                        state = state,
                        sessionId = sessionId,
                        quality = quality,
                        artStyle = artStyle,
                        isRefine = true,
                        frame = frame,
                        prompt = finalPrompt,
                        referenceBase64 = referenceB64,
                        userInput = userText,
                        inputField = "다듬기",
                        galleryPrompt = galleryPrompt,
                        baseFrame0 = baseFrame0,
                        baseFrame1 = baseFrame1,
                        anchor = matchAnchor,
                    ),
                )
            }
            preparing = false
        }
    }

    /** 격자(체커보드) 방지 — 일부 모델이 "투명"을 격자로 그림 → 배경 지시 명시 (iOS 원문). */
    private fun withTransparentBackground(prompt: String): String =
        "$prompt. Only the character on a transparent background — " +
            "no background fill, no shadows, no extra elements."

    /** 캐릭터 설명을 프로필에 저장 — 다음에 열어도 유지, 배치 생성도 같은 설명 공유. */
    private suspend fun saveDescription() = withContext(Dispatchers.IO) {
        val p = CharacterProfileStore.load()
        val trimmed = prompt.trim()
        if (p.aiPrompt != trimmed) CharacterProfileStore.save(p.copy(aiPrompt = trimmed))
    }

    // MARK: - 버전 이력

    /** 이력에서 버전 선택 — 현재 결과 슬롯을 그 버전으로 교체 (적용 대상 변경). */
    fun selectVersion(idx: Int) {
        if (idx !in versions.indices || idx == selectedVersion || isGenerating) return
        val v = versions[idx]
        selectedVersion = idx
        resultImage = v.small
        resultFrame2 = v.frame2
        lastFrame0FullRes = v.fullRes
        if (v.frame2 == null) singleDetailFrame = 0
        // 투명 캐시는 버전별로 안 들고 있음 — Android 는 raw 자체가 투명이라 재계산 불필요.
        viewModelScope.launch { saveVersionChain() }
    }

    /** 다듬기 이력(버전 체인)을 디스크에 저장 — 화면을 나갔다 와도 복원되게. */
    private suspend fun saveVersionChain() {
        if (mode != GenerationMode.AI_GENERATE || versions.isEmpty()) return
        val stateRaw = targetState.raw
        val selected = selectedVersion
        val chain = versions.map { Triple(it.galleryId, it.isRefined, it.frame2 != null) }
        withContext(Dispatchers.IO) { RefineHistoryStore.save(stateRaw, selected, chain) }
    }

    /**
     * 저장된 다듬기 이력 복원 — 진입 시 결과가 없을 때만. 이미지는 갤러리에서 다시 읽는다.
     * 저장된 stateRaw 로 상태 선택도 되돌린다 (iOS restoreVersionChain 동일).
     */
    fun restoreVersionChain() {
        if (mode != GenerationMode.AI_GENERATE || versions.isNotEmpty() || resultImage != null) return
        viewModelScope.launch { applyChainFromDisk(guard = true) }
    }

    /**
     * 디스크의 이력(galleryId 체인)을 화면 상태로 — 진입 복원과 워커 결과 수신이 같은 경로를 쓴다.
     * 결과 이미지는 워커가 이미 갤러리에 저장했으므로 여기서 다시 읽기만 하면 된다.
     *
     * @param guard true = 로드하는 사이에 새 결과가 생겼으면 덮어쓰지 않음 (진입 복원용)
     */
    private suspend fun applyChainFromDisk(guard: Boolean) {
        val r = withContext(Dispatchers.IO) { RefineHistoryStore.load() } ?: return
        if (guard && (versions.isNotEmpty() || resultImage != null)) return
        CharacterState.fromRaw(r.stateRaw)?.let { targetState = it }
        versions = r.versions.map {
            ResultVersion(it.small, it.frame2, it.small, it.isRefined, it.galleryId)
        }
        selectedVersion = r.selected
        val v = versions[r.selected]
        resultImage = v.small
        resultFrame2 = v.frame2
        // frame1 정규화 앵커는 워커가 남긴 frame0 원본(1024)이 있으면 그걸 쓴다 (없으면 128 폴백).
        lastFrame0FullRes = withContext(Dispatchers.IO) { SingleGenQueue.loadAnchorFullRes() } ?: v.small
        if (v.frame2 == null) singleDetailFrame = 0
        // 이름/세션도 복원 — 저장된 갤러리 항목의 batchId 를 이어받아 같은 캐릭터로 유지.
        val gid = versions.firstNotNullOfOrNull { it.galleryId } ?: return
        val restored = withContext(Dispatchers.IO) {
            val bid = CharacterImageStore.loadGalleryMetadata()
                .firstOrNull { it.id == gid }?.batchId ?: return@withContext null
            bid to (CharacterImageStore.characterName(bid) ?: "")
        } ?: return
        currentSessionId = restored.first
        characterName = restored.second
    }

    // MARK: - 적용 / 사진 저장

    /** AI 결과의 현재 선택(버전/배경 모드)으로 적용. */
    fun applyCurrentSelection() {
        val img = currentDisplay(0) ?: return
        viewModelScope.launch { applyImage(img) }
    }

    /** import 미리보기 이미지로 적용. */
    fun applyImportSelection() {
        val img = displayedImport() ?: return
        viewModelScope.launch { applyImage(img) }
    }

    private suspend fun applyImage(image: Bitmap) {
        val frame1 = currentDisplay(1)   // 현재 displayTransparent 모드 존중 (iOS 동일)
        val state = targetState
        val p = lastSentPrompt
        val transparent = displayTransparent
        // 이미 자동 저장된 결과면 그 갤러리 항목을 재사용 — '적용'이 같은 결과를 또 저장하지 않게.
        val autoSavedId = if (mode == GenerationMode.AI_GENERATE) {
            versions.getOrNull(selectedVersion)?.galleryId
        } else {
            null
        }
        val ok = withContext(Dispatchers.IO) {
            if (autoSavedId != null && CharacterImageStore.applyGalleryItem(autoSavedId, state)) {
                // 갤러리 원본은 투명 raw — '흰 배경' 표시 중이면 활성 슬롯만 합성본으로 덮어씀
                // (갤러리는 raw 유지). frame0 저장이 옛 f1 을 지우므로 frame1 은 그 뒤에 쓴다.
                if (!transparent) {
                    CharacterImageStore.saveActiveSlotOnly(image, state, frame = 0)
                    if (frame1 != null) CharacterImageStore.saveActiveSlotOnly(frame1, state, frame = 1)
                }
                true
            } else {
                val saved = CharacterImageStore.save(image, state, frame = 0, prompt = p) != null
                if (saved && frame1 != null) {
                    CharacterImageStore.save(frame1, state, frame = 1)
                }
                saved
            }
        }
        if (ok) {
            // iOS WidgetCenter.reloadAllTimelines() 대응 (워치 전송은 SCOPE 제외 — 호출부 없음).
            SyncCoordinator.refreshWidgets()
            hapticSignal = HapticSignal.SUCCESS   // iOS notificationOccurred(.success)
            showAppliedAlert = true
        } else {
            lastError = str(R.string.gen_err_save_failed)
            hapticSignal = HapticSignal.ERROR     // iOS notificationOccurred(.error)
        }
    }

    /** AI 결과의 '사진 앱에 저장' — 두 프레임이 있으면 보고 있는 프레임을 저장. */
    fun saveCurrentResultToPhotos() {
        val f0 = currentDisplay(0) ?: return
        val img = if (currentDisplay(1) != null) currentDisplay(singleDetailFrame) ?: f0 else f0
        saveToPhotos(img)
    }

    fun saveToPhotos(image: Bitmap) {
        viewModelScope.launch {
            val result = PhotoSaver.save(image)
            if (result.isSuccess) {
                lastError = null
                hapticSignal = HapticSignal.SUCCESS   // iOS notificationOccurred(.success)
                showSavedAlert = true
            } else {
                lastError = result.exceptionOrNull()?.koreanized()
                    ?: str(R.string.gen_err_save_failed)
                hapticSignal = HapticSignal.ERROR     // iOS notificationOccurred(.error)
            }
        }
    }
}

/** 성공/실패 햅틱 종류 — iOS UINotificationFeedbackGenerator.FeedbackType 대응. */
enum class HapticSignal { SUCCESS, ERROR }
