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
import com.seoyoung.withu.gallery.appendRefineVersion
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

/**
 * 캔디 소모 전 확인 팝업 대상 — 단건 생성과 동일한 안내를 배치에도 (iOS PendingBatchAction).
 * 상세 시트 '바꾸기'는 시트 위에 확인이 떠야 해서 별도 플래그(pendingReviseConfirm)로 다룬다.
 */
sealed class PendingBatchAction {
    /** 만들기 시작 (전체) */
    data object Start : PendingBatchAction()
    /** 이 모습으로 나머지 만들기 */
    data object ApproveRest : PendingBatchAction()
    /** 수정해서 생성하기(기준 모습) */
    data object ReviseIdle : PendingBatchAction()
}

/**
 * 기준 모습(idle) 다듬기 무료 정책 — iOS BatchCharacterGenView 의 idleRevisionCost/복원 규칙을 순수 함수로.
 * 화면/뷰모델 밖에서 테스트할 수 있게 분리했다.
 */
object IdleRevisionPolicy {
    /** 1번째 다듬기는 무료(0), 2번째부터 캔디 차감 (iOS idleRevisionCost). */
    fun cost(used: Int, unitCost: Int): Int = if (used == 0) 0 else unitCost

    /**
     * 재진입 복원 — 저장된 이력의 버전 개수로 이미 쓴 횟수를 보수적으로 유도 (iOS restorePendingRevisions).
     * versions[0] 은 다듬기 전 원본이므로 다듬은 횟수 = versions.size - 1.
     * 안 하면 화면을 나갔다 올 때마다 '무료'가 다시 떠 무료를 무한히 쓸 수 있다.
     */
    fun restoredUsed(current: Int, versionCount: Int): Int = maxOf(current, versionCount - 1)
}

/**
 * 다듬기 완료 후 '적용' 전까지 보관하는 버전 이력 (iOS BatchCharacterGenView.BatchRevision).
 * versions[0] = 다듬기 전 원본, 이후 = 다듬은 버전. 하나씩 만들기·갤러리와 같은 이력 모델.
 *
 * - `versions`     128 썸네일 — 스트립/그리드 표시 + 적용 시 갤러리 저장본
 * - `fullVersions` 대응 1024 원본 — 이어서 다듬을 때의 참조(화질 유지) + 적용 시 frame0FullRes
 */
data class BatchRevision(
    val frame: Int,
    val versions: List<Bitmap>,
    val fullVersions: List<Bitmap>,
    val selected: Int,
    /** 갤러리 '만든 기록' 저장용 — 마지막으로 보낸 프롬프트. */
    val prompt: String,
) {
    val current: Bitmap get() = versions[selected.coerceIn(0, versions.size - 1)]
    val currentFull: Bitmap get() = fullVersions[selected.coerceIn(0, fullVersions.size - 1)]
}

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

    /**
     * 이 캐릭터에 붙일 이름 — 갤러리 '캐릭터별'에 표시 (선택). iOS characterName.
     * 생성 후에 고쳐도 같은 batchSessionId 에 즉시 반영된다.
     */
    var characterName by mutableStateOf("")
        private set

    fun updateCharacterName(value: String) {
        characterName = value
        val bid = batchSessionId
        viewModelScope.launch(Dispatchers.IO) { CharacterImageStore.setCharacterName(value, bid) }
    }

    // MARK: - 승인 게이트

    var awaitingIdleApproval by mutableStateOf(false)
        private set
    var idleRevisionText by mutableStateOf("")

    /** 기준 모습 확인 화면에서 이미 쓴 다듬기 횟수 — 1번은 무료, 2번째부터 캔디 차감 (iOS idleRevisionsUsed). */
    var idleRevisionsUsed by mutableStateOf(0)
        private set

    /** 이번 기준 모습 다듬기 비용 — 0 이면 무료 (iOS idleRevisionCost). */
    val idleRevisionCost: Int
        get() = IdleRevisionPolicy.cost(idleRevisionsUsed, GenerationQuota.cost(quality))

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

    /**
     * '배경 모두 지우기/흰 배경으로'·상세 개별 토글은 이제 그리드 미리보기만 바꾼다 —
     * 홈/위젯엔 아직 반영 안 됐다는 안내용 (iOS bgPreviewChanged).
     */
    var bgPreviewChanged by mutableStateOf(false)
        private set
    var isSavingPhotos by mutableStateOf(false)
        private set

    var showFinishedAlert by mutableStateOf(false)
    var saveResultMessage by mutableStateOf<String?>(null)
    var showPaywall by mutableStateOf(false)

    /** 성공 햅틱 원샷 이벤트 — SingleGenViewModel 과 같은 HapticSignal 재사용 (화면이 consumeHaptic 으로 비움). */
    var hapticSignal by mutableStateOf<HapticSignal?>(null)
        private set
    fun consumeHaptic() { hapticSignal = null }

    /** 캔디 소모 확인 팝업 대상 (배치) — 확인해야 실제 액션 실행 (iOS pendingAction). */
    var pendingAction by mutableStateOf<PendingBatchAction?>(null)
        private set
    /** 상세 시트 '바꾸기' 전용 확인 플래그 — 확인 시 selectedResult/detailFrame/revisionText 그대로 사용. */
    var pendingReviseConfirm by mutableStateOf(false)
        private set

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

    /**
     * 상세 시트에서 '바꾸기'로 재생성 중인 프레임(state→frame). 시트를 닫아도 결과 그리드가
     * 처음 만들 때처럼 로딩을 보여주도록(고치는 프레임에만) 추적 (iOS revisingFrame).
     */
    val revisingFrame = mutableStateMapOf<CharacterState, Int>()

    /**
     * 다듬기 완료 후 '적용' 전까지의 버전 이력 (state → 체인). 상세 시트에선 스트립(원본/다듬음 N),
     * 결과 카드엔 '다듬음' 배지로 보인다. 적용/취소 전까지 results 는 건드리지 않는다 (iOS revisedDone).
     */
    val revisedDone = mutableStateMapOf<CharacterState, BatchRevision>()

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

    // MARK: - 캔디 소모 확인 팝업 (iOS pendingAction/pendingActionMessage/pendingActionConfirmLabel)

    fun requestStart() { pendingAction = PendingBatchAction.Start }
    fun requestApproveRest() { pendingAction = PendingBatchAction.ApproveRest }
    fun requestReviseIdle() { pendingAction = PendingBatchAction.ReviseIdle }
    fun dismissPendingAction() { pendingAction = null }

    fun requestReviseOne() { pendingReviseConfirm = true }
    fun dismissReviseConfirm() { pendingReviseConfirm = false }

    /** 확인 버튼 라벨 — '바꾸기'(수정)만 다르고 나머지는 '만들기' (iOS pendingActionConfirmLabel). */
    fun pendingActionConfirmLabel(action: PendingBatchAction): Int =
        if (action is PendingBatchAction.ReviseIdle) R.string.batch_candy_confirm_revise
        else R.string.batch_candy_confirm_make

    /** 확인 팝업 본문 — iOS pendingActionMessage 그대로. */
    fun pendingActionMessage(action: PendingBatchAction): String {
        val unit = GenerationQuota.cost(quality)
        return when (action) {
            PendingBatchAction.Start -> str(R.string.batch_candy_body_start, requiredCount * unit)
            PendingBatchAction.ApproveRest -> {
                // idle(기준)은 이미 만들었으니 나머지 모습분만.
                val rest = maxOf(1, requiredCount - 1)
                str(R.string.batch_candy_body_rest, rest * unit)
            }
            // 첫 다듬기는 무료 — 캔디 안내 대신 무료 안내 (iOS pendingActionMessage).
            PendingBatchAction.ReviseIdle ->
                if (idleRevisionCost == 0) str(R.string.batch_candy_body_revise_free)
                else str(R.string.batch_candy_body_revise, idleRevisionCost)
        }
    }

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
        // done job 이미지는 '이 배치'의 실제 출력만 쓴다 — in-memory(s.images) 우선, 앱 재시작으로
        // 비었으면 큐가 디스크에 남긴 이 배치의 frame0 원본(BackgroundGenQueue.loadFrame0FullRes).
        // 활성 슬롯(CharacterImageStore.loadFrame)은 예전에 '적용'한 다른(전전) 배치일 수 있어
        // 폴백에서 제외 — 안 그러면 재진입 시 전전 결과가 이번 결과인 척 그리드에 뜬다.
        val doneImages = withContext(Dispatchers.IO) {
            val map = mutableMapOf<Pair<CharacterState, Int>, Bitmap>()
            for (job in s.jobs) {
                if (job.status != BgGenStatus.DONE.raw) continue
                val st = CharacterState.fromRaw(job.stateRaw) ?: continue
                val img = s.images["${job.stateRaw}#${job.frame}"]
                    ?: (if (job.frame == 0) BackgroundGenQueue.loadFrame0FullRes(st) else null)
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
        // rest 단계엔 앵커(idle) job 이 목록에 없음 — 이 배치의 큐 디스크 원본에서 복원.
        // (활성 슬롯은 전전 배치일 수 있어 마지막 수단으로만 — iOS 동일 주석.)
        if (s.jobs.isNotEmpty() && s.phase != BgGenPhase.ANCHOR && results[CharacterState.IDLE] == null) {
            withContext(Dispatchers.IO) {
                BackgroundGenQueue.loadFrame0FullRes(CharacterState.IDLE)
                    ?: CharacterImageStore.loadFrame(CharacterState.IDLE, 0)
            }?.let { results[CharacterState.IDLE] = it }
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
            // 갤러리 '캐릭터별' 이름 — 새 세션에 옮겨 붙인다 (iOS startBatch:1384).
            withContext(Dispatchers.IO) {
                CharacterImageStore.setCharacterName(characterName, batchSessionId)
            }
            saveDescription()                               // 설명을 프로필에 저장 — 단건 생성과 공유
            results.clear()
            resultsFrame1.clear()
            errors.clear()
            appliedStates = emptySet()
            frame0FullRes.clear()
            displayTransparentByState.clear()
            bgPreviewChanged = false
            synchronized(whiteCache) { whiteCache.clear() }
            inProgressStates = emptySet()
            stateStartedAt.clear()
            revisingFrame.clear()
            // 다듬기 이력 초기화는 '새 캐릭터로 덮어쓸 때'뿐 — 화면 재진입으론 지우지 않는다 (iOS:1401-1402).
            revisedDone.clear()
            idleRevisionsUsed = 0                       // 새 캐릭터 — 무료 1회 다시 (iOS:1400)
            withContext(Dispatchers.IO) { PendingRevisionStore.clearAll() }
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
                val resp = ApiClient.generateImage(req, kind = "batch", batchId = batchSessionId, state = CharacterState.IDLE.raw)
                val raw = withContext(Dispatchers.Default) { ImageProcessing.fromBase64(resp.imageBase64) }
                if (raw != null) {
                    // gpt-image-2 마젠타 배경 → 크로마키 투명화 (투명 결과엔 no-op)
                    val flat = withContext(Dispatchers.Default) { ImageProcessing.chromaKeyRemoved(raw) }
                    val small = withContext(Dispatchers.Default) { ImageProcessing.downsampled(flat, 128) }
                    // 즉시 덮어쓰지 않고 이력에 이어붙임 — 골라서 '적용'해야 기준 모습이 바뀜 (iOS:1581).
                    appendRevision(CharacterState.IDLE, frame = 0, small = small, full = flat, prompt = prompt)
                    // 워치 전송(sendCharacterImage)은 SCOPE 제외 — no-op.
                    // entitlement 서버 잔액 동기화는 로그인 제외 범위라 생략 (bggen 큐와 동일 정책).
                    // 1번째 다듬기는 무료, 2번째부터 차감 (iOS reviseIdle). 성공 판정 뒤라 실패 땐 차감 없음.
                    if (idleRevisionsUsed > 0) {
                        GenerationQuota.record(GenerationQuota.cost(quality))   // 직접 호출 성공 — 여기서 차감
                    }
                    idleRevisionsUsed += 1
                    idleRevisionText = ""
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

    /** 완성된 모든 상태 적용 — 이제 미리보기가 홈/위젯에 실제로 반영됨 (iOS applyAll). */
    fun applyAll() {
        viewModelScope.launch {
            for (state in CharacterState.entries) {
                if (results[state] != null) applyOneInternal(state)
            }
            bgPreviewChanged = false
            SyncCoordinator.refreshWidgets()
            hapticSignal = HapticSignal.SUCCESS
        }
    }

    /**
     * bulk — 모든 모습을 '배경 빼기(투명)' 미리보기로만. 홈/위젯엔 아직 반영 안 함
     * (실제 반영은 '모두 적용하기' 또는 카드별 '적용'). 눌린 걸 알 수 있게 피드백(햅틱).
     * (iOS previewTransparentAll — 예전엔 즉시 활성 슬롯에 썼으나 미리보기 전용으로 변경.)
     */
    fun previewTransparentAll() {
        for (state in CharacterState.entries) {
            if (results[state] != null) {
                displayTransparentByState[state] = true
                appliedStates = appliedStates - state   // 미리보기가 적용본과 달라짐 → '적용' 다시 뜨게
            }
        }
        bgPreviewChanged = true
        hapticSignal = HapticSignal.SUCCESS
    }

    /** bulk — 모든 모습을 '흰 배경' 미리보기로만. 홈/위젯엔 아직 반영 안 함 (iOS previewWhiteAll). */
    fun previewWhiteAll() {
        for (state in CharacterState.entries) {
            if (results[state] != null) {
                displayTransparentByState[state] = false
                appliedStates = appliedStates - state
            }
        }
        bgPreviewChanged = true
        hapticSignal = HapticSignal.SUCCESS
    }

    /**
     * 한 모습만 배경 미리보기 토글(상세 시트 세그먼트) — on=투명, off=흰 배경. 홈/위젯엔 아직
     * 반영 안 함(카드 '적용' 또는 '모두 적용하기'로 반영). 벌크 토글과 동작을 일치시킴
     * (iOS previewTransparentOne — 예전엔 즉시 활성 슬롯에 썼으나 미리보기 전용으로 변경).
     */
    fun previewTransparentOne(state: CharacterState, on: Boolean) {
        if (results[state] == null) return
        displayTransparentByState[state] = on
        appliedStates = appliedStates - state
        bgPreviewChanged = true
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
            // 시트를 닫아도 결과 카드의 '고치는 프레임'에 로딩을 표시 (iOS revisingFrame).
            revisingFrame[state] = frame
            try {
                // 다듬기 참고는 1024 원본으로 — 128 썸네일을 반복 참고하면 화질이 계속 떨어진다 (A-3-f).
                // 이력이 있으면 고른 버전(frame1 은 썸네일뿐이라 current), 없으면 이 상태의 frame0 원본.
                val chain = revisedDone[state]?.takeIf { it.frame == frame }
                val anchor = if (chain != null) {
                    if (frame == 1) chain.current else chain.currentFull
                } else if (frame == 1) {
                    // frame1 은 frame0 을 앵커로 두면 캐릭터/크기 일관성이 유지됨 (iOS 동일)
                    results[state] ?: resultsFrame1[state]
                } else {
                    frame0FullRes[state]
                        ?: withContext(Dispatchers.IO) { BackgroundGenQueue.loadFrame0FullRes(state) }
                        ?: results[state]
                }
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
                val resp = ApiClient.generateImage(req, state = state.raw)
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
                    // 즉시 덮어쓰지 않고 버전 이력에 이어붙임 — 상세 시트에서 골라 '적용'해야 반영 (iOS:2081).
                    appendRevision(state, frame = frame, small = small, full = flat, prompt = modifiedPrompt)
                    GenerationQuota.record(cost)   // 바꾸기도 실제 생성 — 직접 호출이라 여기서 차감
                    refreshQuota()
                    revisionText = ""
                    revisionRefImage = null        // 다음 다듬기가 옛 참고사진을 물고 가지 않게 (iOS:2086)
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
                revisingFrame.remove(state)
            }
        }
    }

    /** 상세 시트 '바꾸기' 캔디 확인 → 실행 (iOS 시트 로컬 alert 의 확인 버튼 동작). */
    fun confirmReviseOne() {
        val state = selectedResult ?: return
        pendingReviseConfirm = false
        reviseOne(state, detailFrame, revisionText)
    }

    // MARK: - 다듬기 버전 이력 (iOS appendRevision/selectRevisionVersion/acceptRevision/rejectRevision)

    /**
     * 다듬기 결과를 버전 이력에 이어붙임 — 없으면 [원본, 새버전], 있으면 append. 저장까지.
     * 상한 8, 초과 시 [0](원본)은 보존하고 가장 오래된 다듬기부터 밀어낸다 (appendRefineVersion 공통 규칙).
     */
    private suspend fun appendRevision(
        state: CharacterState,
        frame: Int,
        small: Bitmap,
        full: Bitmap,
        prompt: String,
    ) {
        val existing = revisedDone[state]?.takeIf { it.frame == frame }
        val chain = if (existing != null) {
            val versions = appendRefineVersion(existing.versions, small)
            val fulls = appendRefineVersion(existing.fullVersions, full)
            existing.copy(
                versions = versions,
                fullVersions = fulls,
                selected = versions.size - 1,
                prompt = prompt,
            )
        } else {
            // 이력 시작 — [0] 은 '다듬기 전' 결과. frame1 은 1024 원본이 없어 썸네일을 그대로 둔다.
            val before = (if (frame == 1) resultsFrame1[state] else results[state]) ?: small
            val beforeFull = if (frame == 1) before else (frame0FullRes[state] ?: results[state] ?: small)
            BatchRevision(
                frame = frame,
                versions = listOf(before, small),
                fullVersions = listOf(beforeFull, full),
                selected = 1,
                prompt = prompt,
            )
        }
        revisedDone[state] = chain
        withContext(Dispatchers.IO) { PendingRevisionStore.save(state, chain) }
    }

    /** 스트립에서 버전 선택 — 고른 버전이 '적용'·'이어서 다듬기'의 기준이 된다. */
    fun selectRevisionVersion(state: CharacterState, index: Int) {
        val chain = revisedDone[state] ?: return
        if (index !in chain.versions.indices) return
        val next = chain.copy(selected = index)
        revisedDone[state] = next
        viewModelScope.launch(Dispatchers.IO) { PendingRevisionStore.save(state, next) }
    }

    /**
     * 이력에서 고른 버전으로 적용 — 이때 처음으로 결과를 교체하고 갤러리에 저장한다.
     * [0](원본)을 고른 채 적용하면 바꿀 게 없어 이력만 정리한다 (iOS acceptRevision).
     */
    fun acceptRevision(state: CharacterState) {
        val rev = revisedDone[state] ?: return
        viewModelScope.launch {
            if (rev.selected != 0) {
                if (rev.frame == 1) {
                    resultsFrame1[state] = rev.current
                } else {
                    results[state] = rev.current
                    frame0FullRes[state] = rev.currentFull
                    if (state == CharacterState.IDLE) idleFullRes = rev.currentFull
                }
                displayTransparentByState[state] = false   // 새 raw → 흰배경 기준으로 리셋
                withContext(Dispatchers.IO) {
                    // 갤러리에만 저장 — 홈/위젯 반영은 아래 applyOne 이 담당.
                    CharacterImageStore.save(
                        rev.current, state, frame = rev.frame, applyToActiveSlot = false,
                        batchId = batchSessionId, prompt = rev.prompt,
                    )
                }
                if (state == CharacterState.IDLE) {
                    // idle 은 앵커 — 홈/워치 반영은 '나머지 만들기' 단계에서 (iOS:2146-2150).
                    appliedStates = appliedStates - state
                } else {
                    applyOneInternal(state)
                    SyncCoordinator.refreshWidgets()
                }
            }
            revisedDone.remove(state)
            withContext(Dispatchers.IO) { PendingRevisionStore.remove(state) }
            selectedResult = null   // 그리드로 — 바뀐 게 보이게
        }
    }

    /** 이력 버리고 원래 결과 유지 (iOS rejectRevision). */
    fun rejectRevision(state: CharacterState) {
        revisedDone.remove(state)
        selectedResult = null
        viewModelScope.launch(Dispatchers.IO) { PendingRevisionStore.remove(state) }
    }

    /**
     * 완전히 나갔다 온 뒤 저장된 다듬기 이력 복원 — 카드 '다듬음'/기준 모습 이력이 다시 뜨게.
     * 기준 모습을 이미 다듬었으면 무료 1회는 쓴 것 — 재진입해도 '무료'로 잘못 뜨지 않게 같이 복원한다
     * (iOS restorePendingRevisions). PendingRevisionStore 스키마는 그대로 두고 버전 개수로 유도.
     */
    fun restorePendingRevisions() {
        viewModelScope.launch {
            val restored = withContext(Dispatchers.IO) { PendingRevisionStore.loadAll() }
            for (r in restored) {
                if (revisedDone[r.state] != null) continue
                revisedDone[r.state] = BatchRevision(
                    frame = r.frame,
                    versions = r.versions,
                    fullVersions = r.fullVersions,
                    selected = r.selected,
                    prompt = r.prompt,
                )
            }
            revisedDone[CharacterState.IDLE]?.let {
                idleRevisionsUsed = IdleRevisionPolicy.restoredUsed(idleRevisionsUsed, it.versions.size)
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
