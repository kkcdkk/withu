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
import com.seoyoung.withu.net.ApiClient
import com.seoyoung.withu.net.ApiError
import com.seoyoung.withu.net.Entitlement
import com.seoyoung.withu.net.GenerateImageRequest
import com.seoyoung.withu.net.koreanized
import com.seoyoung.withu.quota.GenerationQuota
import com.seoyoung.withu.shared.CharacterImageStore
import com.seoyoung.withu.sync.SyncCoordinator
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID
import kotlin.coroutines.coroutineContext

/**
 * 단건 생성 상태/로직 — iOS CharacterGenView.swift 의 @State + 액션 포팅 (스펙 02 §3).
 *
 * 캔디 규칙 (변경 금지 — 커밋 fd98948 교훈):
 *  - 잔액의 권위는 로컬(GenerationQuota). 서버는 차감하지 않음.
 *  - record() 는 반드시 '성공 판정' 후에만 — 성공 = 결과 슬롯의 Bitmap 인스턴스(!==)가 바뀜.
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

    // 생성 진행
    var isGenerating by mutableStateOf(false)
        private set
    var generationStartedAt by mutableStateOf<Long?>(null)   // epoch millis
        private set
    private var generateJob: Job? = null

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

    /** 직전 send() 를 서버가 무료로 소진했는지 (응답 free_consumed). */
    private var lastFreeConsumed: Boolean = false

    /** 생성 모니터링용 수정 체인 id — 새 원본 생성마다 갱신, 다듬기는 같은 값을 재사용. */
    private var currentSessionId: String = UUID.randomUUID().toString()

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

    /** 팝업 확인 — 생성은 취소 가능하도록 Job 보관, 다듬기는 iOS 처럼 미보관. */
    fun confirmPendingAction() {
        when (val action = pendingAction) {
            is PendingAction.NewGeneration -> generateJob = viewModelScope.launch { generate() }
            is PendingAction.Refine -> viewModelScope.launch { refine(action.frame) }
            null -> Unit
        }
        pendingAction = null
    }

    /** '그만두기' — Job 취소 + 상태 원복. 차감 없음 (record 는 성공 후에만). */
    fun cancelGeneration() {
        generateJob?.cancel()
        generateJob = null
        isGenerating = false
        generationStartedAt = null
        lastError = str(R.string.gen_err_cancelled)
    }

    fun onPaywallClosed() {
        showPaywall = false
        refreshQuota()
    }

    // MARK: - 생성/다듬기

    private suspend fun generate() {
        val cost = unitCost
        // 가드 — 무료 1회 또는 로컬 캔디.
        if (!hasFreeCreation && !GenerationQuota.canGenerate(cost)) {
            lastError = str(R.string.gen_err_no_candy)
            return
        }
        isGenerating = true
        generationStartedAt = System.currentTimeMillis()
        lastError = null
        resultFrame2 = null
        singleDetailFrame = 0
        currentSessionId = UUID.randomUUID().toString()   // 새 원본 → 새 수정 체인
        try {
            // 사전 reachability 체크 — 30분 timeout 세션에 매달리지 않도록 (iOS preflightPing 동일).
            try {
                ApiClient.preflightPing()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                lastError = str(R.string.gen_err_offline)
                return
            }
            saveDescription()
            val referenceB64 = referenceImage?.let {
                withContext(Dispatchers.Default) { ImageProcessing.toBase64Png(it) }
            }
            // 성공 판정 = 결과 슬롯 '인스턴스'가 바뀌었는지 — 실패 시 이전 런 이미지가 남아
            // frame1 생성/캔디 차감으로 새는 것 방지 (값 비교 금지, iOS !== 동일 의미론).
            val prevResult = resultImage
            send(composedPrompt(), referenceB64, frame = 0)
            val frame0Succeeded = resultImage !== prevResult
            // 서버가 이번 생성을 계정 무료 1회로 소진했으면 세션 전체(프레임 2장까지) 미차감.
            val freeSession = lastFreeConsumed
            if (frame0Succeeded && !freeSession) GenerationQuota.record(cost)
            // 연속 이미지 — frame0 성공 시 그 원본(1024)을 reference 로 frame1 추가.
            if (generateAnimated && targetState.usesGeneratedMotion && frame0Succeeded) {
                val f0Full = lastFrame0FullRes ?: resultImage
                if (f0Full != null) {
                    val f0Ref = withContext(Dispatchers.Default) { ImageProcessing.toBase64Png(f0Full) }
                    val animPrompt = composedPrompt() + "." + animationFrame2Instruction(targetState)
                    send(animPrompt, f0Ref, frame = 1, matchReference = f0Full)
                    if (resultFrame2 != null && !freeSession) GenerationQuota.record(cost)
                }
            }
            if (frame0Succeeded) {
                // 새 결과 = 이력 리셋. [0] = 원본.
                resultImage?.let { img ->
                    versions = listOf(ResultVersion(img, resultFrame2, lastFrame0FullRes, isRefined = false))
                    selectedVersion = 0
                }
            }
        } finally {
            isGenerating = false
            generationStartedAt = null
            generateJob = null
            refreshQuota()
        }
    }

    /** 보고 있는 프레임만 다듬기. frame1 은 frame0 을 앵커로 둬 캐릭터/크기 일관성 유지. */
    private suspend fun refine(frame: Int) {
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
        val anchor = if (frame == 1) (resultImage ?: currentSlot) else currentSlot
        isGenerating = true
        generationStartedAt = System.currentTimeMillis()
        lastError = null
        try {
            val referenceB64 = withContext(Dispatchers.Default) { ImageProcessing.toBase64Png(anchor) }
            var refinePrompt = refinementPrompt
            if (frame == 1) {
                refinePrompt += ". Animation frame 2 (for a 2-frame swap loop): " +
                    "${targetState.animationFrame2Hint}. CRITICAL: keep the character at the EXACT " +
                    "same size, scale, and centered position as the reference image; only the pose changes."
            }
            val prevSlot = if (frame == 1) resultFrame2 else resultImage
            send(
                refinePrompt, referenceB64, frame,
                matchReference = if (frame == 1) (lastFrame0FullRes ?: resultImage) else null,
            )
            val succeeded = (if (frame == 1) resultFrame2 else resultImage) !== prevSlot
            if (succeeded) {
                // 서버가 무료로 소진한 다듬기는 미차감.
                if (!lastFreeConsumed) GenerationQuota.record(cost)
                // 다듬은 버전을 이력에 추가하고 선택 — 이전 버전으로 언제든 복귀 가능.
                resultImage?.let { img ->
                    val appended = versions + ResultVersion(img, resultFrame2, lastFrame0FullRes, isRefined = true)
                    // 8개 초과 시 index 1 제거 — 원본([0])은 항상 보존, 오래된 다듬기부터 정리.
                    versions = if (appended.size > 8) {
                        appended.toMutableList().also { it.removeAt(1) }
                    } else {
                        appended
                    }
                    selectedVersion = versions.size - 1
                }
            }
            refinementPrompt = ""
            // '배경 빼기' 보기 중 stale 방지 재처리 — Android 는 raw 자체가 투명이라
            // bestEffortTransparent 가 no-op(동일 인스턴스)으로 계약돼 있어 실질 no-op (파리티 유지).
        } finally {
            isGenerating = false
            generationStartedAt = null
            refreshQuota()
        }
    }

    /**
     * 서버 전송 + 응답 후처리 — 크로마키 투명화 → (frame1) 참조 정규화 → 128px 다운샘플
     * → (frame1) 색 매칭. 실패 시 결과 슬롯을 건드리지 않아 caller 의 !== 판정이 실패로 남는다.
     */
    private suspend fun send(
        prompt: String,
        reference: String?,
        frame: Int = 0,
        matchReference: Bitmap? = null,
    ) {
        // 격자(체커보드) 방지 — 일부 모델이 "투명"을 격자로 그림 → 배경 지시 명시 (iOS 원문).
        val finalPrompt = "$prompt. Only the character on a transparent background — " +
            "no background fill, no shadows, no extra elements."
        try {
            val req = GenerateImageRequest(
                prompt = finalPrompt,
                referenceImageBase64 = reference,
                steps = 30,
                width = 1024,
                height = 1024,
                quality = quality,
                artStyle = artStyle,
                style = "auto",
                model = "gpt-image-2",
            )
            // frame 0 만 수정 체인(session)에 넣는다 — frame 1(자동 애니메이션)은 수정 횟수에서 제외.
            val resp = ApiClient.generateImage(
                req,
                sessionId = if (frame == 0) currentSessionId else null,
                state = targetState.raw,
            )
            coroutineContext.ensureActive()   // '그만두기' 후엔 결과 반영 없이 종료
            val processedPair = withContext(Dispatchers.Default) {
                val rawImg = ImageProcessing.fromBase64(resp.imageBase64) ?: return@withContext null
                // gpt-image-2 는 마젠타 단색 배경으로 옴 → 크로마키 투명화 (이미 투명이면 no-op).
                val img = ImageProcessing.chromaKeyRemoved(rawImg)
                // frame1 은 1번째 기준 크기·위치 정규화.
                val processed = if (frame == 1 && matchReference != null) {
                    ImageProcessing.matchedToReference(img, matchReference)
                } else {
                    img
                }
                // 128px 다운샘플 — 메인 200/워치 64/위젯 60 커버 + 디스크 절약.
                var small = ImageProcessing.downsampled(processed, 128)
                // frame1 색 드리프트 제거 — frame0 색에 맞춤.
                if (frame == 1 && matchReference != null) {
                    val refSmall = ImageProcessing.downsampled(matchReference, 128)
                    small = ImageProcessing.colorMatched(small, refSmall)
                }
                small to processed
            }
            if (processedPair == null) {
                lastError = str(R.string.gen_err_image_load)
                return
            }
            val (small, processed) = processedPair
            if (frame == 0) {
                resultImage = small
                lastFrame0FullRes = processed   // frame1 정규화 reference (1024 투명)
                revisedPrompt = resp.revisedPrompt
                lastSentPrompt = finalPrompt    // 갤러리 '만든 기록' 저장용
            } else {
                resultFrame2 = small
            }
            lastFreeConsumed = resp.freeConsumed ?: false
            resp.entitlement?.let { applyEntitlement(it) }
        } catch (e: CancellationException) {
            throw e   // 취소는 상위(취소 버튼)가 처리 — koreanized 로 삼키지 말 것
        } catch (e: ApiError.PaymentRequired) {
            e.balance?.let { applyEntitlement(it) }
            showPaywall = true
        } catch (e: Exception) {
            lastError = e.koreanized()
        }
    }

    /** 서버 잔액 반영 — syncCreditsUp 은 '증가분만' 가산 (로컬 차감을 덮어쓰지 않음). */
    private fun applyEntitlement(ent: Entitlement) {
        entitlement = ent
        GenerationQuota.syncCreditsUp(ent.credits)
        refreshQuota()
    }

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
        val ok = withContext(Dispatchers.IO) {
            val saved = CharacterImageStore.save(image, targetState, frame = 0, prompt = lastSentPrompt) != null
            if (saved && frame1 != null) {
                CharacterImageStore.save(frame1, targetState, frame = 1)
            }
            saved
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
