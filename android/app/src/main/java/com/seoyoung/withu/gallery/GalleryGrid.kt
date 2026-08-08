package com.seoyoung.withu.gallery

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.text.format.DateUtils
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowCircleRight
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.AutoFixHigh
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material.icons.filled.SaveAlt
import androidx.compose.material.icons.filled.Square
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.seoyoung.withu.R
import com.seoyoung.withu.camera.PhotoSaver
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.gen.ImageProcessing
import com.seoyoung.withu.net.ApiClient
import com.seoyoung.withu.net.GenerateImageRequest
import com.seoyoung.withu.net.koreanized
import com.seoyoung.withu.quota.GenerationQuota
import com.seoyoung.withu.shared.CharacterImageStore
import com.seoyoung.withu.shared.GalleryItem
import com.seoyoung.withu.sync.SyncCoordinator
import com.seoyoung.withu.ui.CapsuleToast
import com.seoyoung.withu.ui.FrostedCard
import com.seoyoung.withu.ui.PixelToggle
import com.seoyoung.withu.ui.StatusKind
import com.seoyoung.withu.ui.StatusPill
import com.seoyoung.withu.ui.WithuCTAButton
import com.seoyoung.withu.ui.WithuTopBarTitle
import com.seoyoung.withu.ui.pixelInputField
import com.seoyoung.withu.ui.plainCard
import com.seoyoung.withu.ui.rememberBackgroundGradient
import com.seoyoung.withu.ui.theme.WithuColors
import com.seoyoung.withu.ui.theme.withuCTAGreen
import com.seoyoung.withu.ui.theme.withuPink
import com.seoyoung.withu.ui.theme.withuPinkText
import com.seoyoung.withu.ui.withuInputColors
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 재사용 갤러리 그리드 — iOS GalleryGrid(CharacterGalleryView.swift) 포팅 (스펙 04 §1.3).
 * 적용/삭제/사진 저장/다중 선택/상세 시트(배경 보기·다듬기·프레임 스왑)를 한 곳에 모음.
 * StateFolderScreen/BatchGroupScreen 이 items 를 넘겨 재사용 — route 화면이 아니다.
 *
 * iOS 와의 의도적 차이 (스펙 04 §5·§6):
 * - 카드 컨텍스트 메뉴 미이식 — 롱프레스=선택모드 진입(주 동작)과 충돌. 동일 기능이 상세 시트에 있음.
 * - 워치 전송(ConnectivityManager.sendCharacterImage)은 Wear OS 후속 — 호출 위치는 주석으로 유지.
 */

/** 상세 시트 배경 미리보기 — nil(null) = 저장된 그대로 (iOS BGPreview). */
private enum class BgPreview { TRANSPARENT, WHITE }

/**
 * 다듬기 결과 임시 보관 — '적용' 전까지 갤러리 원본을 덮어쓰지 않는다 (iOS RefineCompareContext).
 * versions[0] = 원본, 이후 = 다듬은 버전.
 */
private data class RefineCompareContext(
    val itemId: String,
    val versions: List<Bitmap>,
    val selected: Int,
) {
    val current: Bitmap get() = versions[selected.coerceIn(0, versions.size - 1)]
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GalleryGrid(
    items: List<GalleryItem>,
    backgroundState: CharacterState,
    title: String,
    onChange: () -> Unit,
    header: (@Composable () -> Unit)? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var selectedItem by remember { mutableStateOf<GalleryItem?>(null) }
    // 프레임 스왑·배경 저장은 '파일만 바뀌고 메타데이터 동일' — diffing 이 감지 못해 tick 으로 강제 재로드
    var frameSwapTick by remember { mutableIntStateOf(0) }
    // 적용/삭제 후 카드의 '적용 중' 점 등 파생 상태 재계산용
    var changeTick by remember { mutableIntStateOf(0) }
    var showApplySheet by remember { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var showBulkDeleteConfirm by remember { mutableStateOf(false) }
    var saveResultMessage by remember { mutableStateOf<String?>(null) }
    var toastText by remember { mutableStateOf<String?>(null) }
    var toastJob by remember { mutableStateOf<Job?>(null) }
    var isSelectionMode by remember { mutableStateOf(false) }
    var selectedIDs by remember { mutableStateOf(setOf<String>()) }

    // 상세 시트 — 배경 보기/다듬기 상태 (항목 바뀔 때 리셋, 아래 LaunchedEffect)
    var bgPreview by remember { mutableStateOf<BgPreview?>(null) }
    var bgCutout by remember { mutableStateOf<Bitmap?>(null) }      // 배경제거 결과 캐시 (frame 0)
    var bgCutoutF1 by remember { mutableStateOf<Bitmap?>(null) }    // 배경제거 결과 캐시 (frame 1)
    var isRemovingBackground by remember { mutableStateOf(false) }
    var refineText by remember { mutableStateOf("") }
    var isRefining by remember { mutableStateOf(false) }
    var showRefineConfirm by remember { mutableStateOf(false) }
    // 다듬기 버전 이력 — null 이면 상세 본문, 있으면 같은 시트 안에서 비교 화면을 대신 보여준다
    // (iOS 는 상세 시트 위에 sheet 를 하나 더 띄우지만, Compose 는 ModalBottomSheet 중첩이 불안정)
    var refineCompare by remember { mutableStateOf<RefineCompareContext?>(null) }
    // 이 항목에 저장된 다듬기 이력이 있는지 — 상세 시트의 '다듬기 이력 보기' 노출용
    var hasStoredRefineHistory by remember { mutableStateOf(false) }
    // 저장 안 한 편집이 있는 채로 상세 시트를 닫으려 할 때 확인 (iOS showDetailDiscardConfirm)
    var showDetailDiscardConfirm by remember { mutableStateOf(false) }

    fun showToast(text: String, seconds: Double) {
        toastJob?.cancel()
        toastText = text
        toastJob = scope.launch {
            delay((seconds * 1000).toLong())
            toastText = null
        }
    }

    fun notifyChange() {
        changeTick++
        onChange()
    }

    /** 갤러리 항목을 state 자리에 적용 — 위젯 갱신 + 토스트 (iOS apply(_:to:)). */
    suspend fun applyItem(item: GalleryItem, state: CharacterState) {
        val ok = withContext(Dispatchers.IO) { CharacterImageStore.applyGalleryItem(item.id, state) }
        if (ok) {
            SyncCoordinator.refreshWidgets()   // iOS WidgetCenter.reloadAllTimelines()
            // 워치 전송 지점 — iOS: ConnectivityManager.sendCharacterImage(frame0/frame1). Wear OS 후속.
            notifyChange()
            showToast(context.getString(R.string.gallery_apply_success_toast, state.koreanShortLabel), 1.6)
        } else {
            showToast(context.getString(R.string.gallery_apply_fail_toast), 1.6)
        }
    }

    /**
     * 다듬기 실행 — 성공하면 원본을 덮지 않고 버전 이력에 이어붙인다 (iOS refineItem).
     * ⚠️ 결과가 도착했을 때 상세 시트가 이미 닫혀 있으면(selectedItem == null) 비교 화면을 띄울 곳이
     * 없으므로, 예전처럼 갤러리에 새 항목으로 저장한다 — 캔디 쓴 결과 유실 방지 (iOS :1180-1189).
     */
    fun runRefine(item: GalleryItem) {
        scope.launch {
            // 이어서 다듬기면 지금 고른 버전을, 아니면 갤러리 원본을 기준으로
            val base = refineCompare?.takeIf { it.itemId == item.id }?.current
            val result = refineItem(
                item = item,
                refineTextValue = refineText,
                base = base,
                onStart = { isRefining = true },
                onFinish = { isRefining = false },
                onToast = { text, sec -> showToast(text, sec) },
            ) ?: return@launch
            val (small, prompt) = result
            refineText = ""

            if (selectedItem == null) {
                val state = CharacterState.fromRaw(item.sourceState) ?: return@launch
                withContext(Dispatchers.IO) {
                    // 갤러리에 새 항목으로 저장 — 활성 슬롯 불변, 원본과 같은 batchId 유지
                    CharacterImageStore.save(
                        image = small,
                        state = state,
                        frame = 0,
                        applyToActiveSlot = false,
                        batchId = item.batchId,
                        prompt = prompt,
                    )
                }
                notifyChange()
                showToast(context.getString(R.string.gallery_refine_success_toast), 2.0)
                return@launch
            }

            val prev = refineCompare?.takeIf { it.itemId == item.id }
            val next = if (prev != null) {
                val versions = appendRefineVersion(prev.versions, small)
                prev.copy(versions = versions, selected = versions.size - 1)
            } else {
                val orig = withContext(Dispatchers.IO) { CharacterImageStore.loadGalleryImage(item.id) }
                    ?: base ?: small
                RefineCompareContext(itemId = item.id, versions = listOf(orig, small), selected = 1)
            }
            refineCompare = next
            withContext(Dispatchers.IO) {
                GalleryRefineHistoryStore.save(next.itemId, next.versions, next.selected)
            }
            hasStoredRefineHistory = true
        }
    }

    /** 스트립에서 버전 선택 — 큰 미리보기·적용 대상 변경 + 저장 (iOS selectRefineVersion). */
    fun selectRefineVersion(idx: Int) {
        val ctx = refineCompare ?: return
        if (idx !in ctx.versions.indices) return
        val next = ctx.copy(selected = idx)
        refineCompare = next
        scope.launch {
            withContext(Dispatchers.IO) {
                GalleryRefineHistoryStore.save(next.itemId, next.versions, next.selected)
            }
        }
    }

    /** 이력 버리기 — 원본 그대로 두고 저장된 버전 체인을 지운다 ('닫기'는 이력 보존). */
    fun rejectRefined(ctx: RefineCompareContext) {
        refineCompare = null
        hasStoredRefineHistory = false
        scope.launch { withContext(Dispatchers.IO) { GalleryRefineHistoryStore.clear(ctx.itemId) } }
    }

    /**
     * '다듬은 걸로 바꾸기' — 이때 처음으로 갤러리 원본을 교체 (iOS adoptRefined).
     * 이 항목이 쓰이는 자리(활성 슬롯)가 있으면 그 자리와 위젯에도 반영.
     */
    fun adoptRefined(ctx: RefineCompareContext) {
        scope.launch {
            // 원본([0])을 고른 채 '적용' = 바꿀 게 없음 — 이력만 정리하고 닫는다
            if (ctx.selected == 0) {
                rejectRefined(ctx)
                return@launch
            }
            val ok = withContext(Dispatchers.IO) {
                CharacterImageStore.replaceGalleryImage(ctx.itemId, ctx.current)
            }
            if (!ok) {
                refineCompare = null
                showToast(context.getString(R.string.gallery_apply_fail_toast), 1.6)
                return@launch
            }
            // 워치 전송 지점 — iOS: ConnectivityManager.sendCharacterImage(frame0/frame1). Wear OS 후속.
            // iOS 는 여기서 GallerySyncManager.forceUpload 로 서버 백업도 강제 갱신하지만
            // Android 는 갤러리 클라우드 백업 자체가 미구현(PARITY-GAPS B-11) — 해당 없음.
            val active = withContext(Dispatchers.IO) {
                GalleryRefineHistoryStore.clear(ctx.itemId)
                val states = CharacterImageStore.statesUsingGalleryItem(ctx.itemId)
                for (s in states) CharacterImageStore.applyGalleryItem(ctx.itemId, s)
                states
            }
            hasStoredRefineHistory = false
            if (active.isNotEmpty()) SyncCoordinator.refreshWidgets()
            refineCompare = null
            selectedItem = null   // 상세도 닫기 — 그리드에서 바뀐 썸네일이 보이게
            frameSwapTick++
            notifyChange()
            showToast(context.getString(R.string.gallery_refine_adopted_toast), 1.6)
        }
    }

    /** 사진 앱 저장 실행 — 단건/다중 공용 (iOS saveOneToPhotos/saveSelected). */
    suspend fun performSave(ids: List<String>, multi: Boolean) {
        val imgs = withContext(Dispatchers.IO) { ids.mapNotNull { CharacterImageStore.loadGalleryImage(it) } }
        var failed = imgs.isEmpty()
        for (img in imgs) {
            if (PhotoSaver.save(img).isFailure) failed = true
        }
        saveResultMessage = when {
            failed -> context.getString(R.string.gallery_save_failed)
            multi -> context.getString(R.string.gallery_saved_multi, imgs.size)
            else -> context.getString(R.string.gallery_saved_single)
        }
        // iOS: 다중 저장 성공/실패 후 선택모드 종료 (권한 거부 때는 유지)
        if (multi) {
            isSelectionMode = false
            selectedIDs = emptySet()
        }
    }

    // API 28 은 WRITE_EXTERNAL_STORAGE 런타임 권한 필요 — 거부 시 iOS 권한 문구 그대로
    var pendingSave by remember { mutableStateOf<Pair<List<String>, Boolean>?>(null) }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        val req = pendingSave
        pendingSave = null
        if (req != null) {
            if (granted) {
                scope.launch { performSave(req.first, req.second) }
            } else {
                saveResultMessage = context.getString(R.string.gallery_photos_permission_denied)
            }
        }
    }

    fun requestSave(ids: List<String>, multi: Boolean) {
        if (PhotoSaver.needsLegacyWritePermission() &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            pendingSave = ids to multi
            permissionLauncher.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        } else {
            scope.launch { performSave(ids, multi) }
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(rememberBackgroundGradient(backgroundState)),
    ) {
        Scaffold(
            containerColor = Color.Transparent,
            topBar = {
                CenterAlignedTopAppBar(
                    title = { WithuTopBarTitle(title) },
                    actions = {
                        if (isSelectionMode) {
                            TextButton(onClick = {
                                isSelectionMode = false
                                selectedIDs = emptySet()
                            }) { Text(stringResource(R.string.common_cancel)) }
                        } else {
                            TextButton(onClick = { isSelectionMode = true }) {
                                Text(stringResource(R.string.common_select))
                            }
                        }
                    },
                    colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = Color.Transparent),
                )
            },
            bottomBar = {
                if (isSelectionMode) {
                    SelectionBottomBar(
                        count = selectedIDs.size,
                        onSave = { requestSave(selectedIDs.toList(), multi = true) },
                        onDelete = { showBulkDeleteConfirm = true },
                    )
                }
            },
        ) { padding ->
            LazyVerticalGrid(
                columns = GridCells.Adaptive(110.dp),
                contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 24.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            ) {
                if (header != null) {
                    item(span = { GridItemSpan(maxLineSpan) }) { header() }
                }
                items(items, key = { it.id }) { item ->
                    GalleryCard(
                        item = item,
                        changeTick = changeTick,
                        isSelectionMode = isSelectionMode,
                        isSelected = selectedIDs.contains(item.id),
                        onTap = {
                            if (isSelectionMode) {
                                selectedIDs =
                                    if (selectedIDs.contains(item.id)) selectedIDs - item.id
                                    else selectedIDs + item.id
                            } else {
                                selectedItem = item
                            }
                        },
                        onLongPress = {
                            // iOS 주 동작 유지: 롱프레스 = 선택모드 진입 + 해당 항목 선택 (컨텍스트 메뉴 미이식)
                            if (!isSelectionMode) {
                                isSelectionMode = true
                                selectedIDs = setOf(item.id)
                            }
                        },
                    )
                }
            }
        }

        CapsuleToast(
            text = toastText,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 40.dp),
        )
    }

    // MARK: 상세 시트 (iOS galleryDetailSheet)

    selectedItem?.let { item ->
        // iOS .sheet(item:) onAppear — 항목별로 미리보기/입력 리셋 (이전 항목의 잔재 방지)
        LaunchedEffect(item.id) {
            bgPreview = null
            bgCutout = null
            bgCutoutF1 = null
            refineText = ""
            hasStoredRefineHistory = withContext(Dispatchers.IO) {
                GalleryRefineHistoryStore.exists(item.id)
            }
        }

        // 저장 안 된 편집 — 배경 미리보기 / 입력한 다듬기 문구 (iOS detailHasChanges).
        // 다듬기 이력(refineCompare)은 제외한다 — 디스크에 남아 '다듬기 이력 보기'로 되돌아올 수 있어
        // 닫아도 잃는 게 없다. iOS 도 비교 시트는 그냥 내려간다.
        val detailHasChanges = bgPreview != null || refineText.trim().isNotEmpty()
        val detailSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

        /**
         * 닫기 요청 — 편집 중이면 확인부터 (iOS interactiveDismissDisabled + confirmationDialog).
         * 스와이프/뒤로로 들어오면 시트는 이미 내려간 상태라, '계속 편집'을 고르면 다시 올려준다.
         */
        fun requestClose() {
            if (detailHasChanges) showDetailDiscardConfirm = true else { selectedItem = null; refineCompare = null }
        }

        ModalBottomSheet(
            // 스와이프로 닫으면 비교 화면도 같이 닫는다 — 이력은 디스크에 남아 '다듬기 이력 보기'로 다시 열 수 있다
            onDismissRequest = { requestClose() },
            sheetState = detailSheetState,
        ) {
            val compare = refineCompare?.takeIf { it.itemId == item.id }
            if (compare != null) {
                // 다듬기 이력 — 큰 미리보기 + 버전 스트립 + 이어서 다듬기 + 적용/취소.
                // '닫기'는 이력을 남긴 채 상세로 돌아간다 ('취소'만 이력을 버림).
                RefineCompareContent(
                    ctx = compare,
                    refineText = refineText,
                    isRefining = isRefining,
                    onRefineTextChange = { refineText = it },
                    onSelectVersion = { selectRefineVersion(it) },
                    onContinueRefine = { runRefine(item) },
                    onAdopt = { adoptRefined(compare) },
                    onReject = { rejectRefined(compare) },
                    onClose = { refineCompare = null },
                )
                return@ModalBottomSheet
            }
            GalleryDetailContent(
                item = item,
                backgroundState = backgroundState,
                frameSwapTick = frameSwapTick,
                changeTick = changeTick,
                bgPreview = bgPreview,
                bgCutout = bgCutout,
                bgCutoutF1 = bgCutoutF1,
                isRemovingBackground = isRemovingBackground,
                refineText = refineText,
                isRefining = isRefining,
                onRefineTextChange = { refineText = it },
                onClose = { requestClose() },
                onDelete = { showDeleteConfirm = true },
                onApplyHere = {
                    scope.launch {
                        applyItem(item, backgroundState)
                        selectedItem = null
                    }
                },
                onSaveToPhotos = { requestSave(listOf(item.id), multi = false) },
                onOpenApplySheet = { showApplySheet = true },
                onSwapFrames = {
                    scope.launch {
                        val ok = withContext(Dispatchers.IO) { CharacterImageStore.swapGalleryFrames(item.id) }
                        if (ok) {
                            // 이 항목이 쓰이는 자리에 바뀐 순서로 다시 적용 (+워치 재전송 — 후속)
                            val active = withContext(Dispatchers.IO) {
                                CharacterImageStore.statesUsingGalleryItem(item.id)
                            }
                            for (s in active) applyItem(item, s)
                            frameSwapTick++
                            notifyChange()
                        }
                    }
                },
                onToggleMotion = { on ->
                    scope.launch {
                        withContext(Dispatchers.IO) {
                            // 첫 적용 상태의 값을 읽고 모든 적용 상태에 일괄 쓰기 (스펙 04 §3.8)
                            for (s in CharacterImageStore.statesUsingGalleryItem(item.id)) {
                                CharacterImageStore.setAnimationDisabled(!on, s)
                            }
                        }
                        SyncCoordinator.refreshWidgets()
                        changeTick++
                    }
                },
                onShowTransparent = { base ->
                    scope.launch {
                        // '배경 빼기' — 원본이 이미 투명이면 즉시, 아니면 배경제거 1회 후 캐시 (iOS showTransparentPreview)
                        if (bgCutout == null &&
                            !withContext(Dispatchers.Default) { ImageProcessing.hasTransparentPixels(base) }
                        ) {
                            isRemovingBackground = true
                            try {
                                val cut = withContext(Dispatchers.Default) {
                                    ImageProcessing.bestEffortTransparent(base)
                                }
                                if (cut === base) {
                                    // 제거 실패(동일 인스턴스 반환) — 미리보기 전환 안 함
                                    showToast(context.getString(R.string.gallery_bg_fail_toast), 1.6)
                                    return@launch
                                }
                                bgCutout = cut
                                val f1 = withContext(Dispatchers.IO) {
                                    CharacterImageStore.loadGalleryFrame1(item.id)
                                }
                                if (f1 != null) {
                                    val cutF1 = withContext(Dispatchers.Default) {
                                        ImageProcessing.bestEffortTransparent(f1)
                                    }
                                    bgCutoutF1 = if (cutF1 !== f1) cutF1 else null
                                }
                            } finally {
                                isRemovingBackground = false
                            }
                        }
                        bgPreview = BgPreview.TRANSPARENT
                    }
                },
                onShowWhite = { bgPreview = BgPreview.WHITE },
                onSaveBackground = {
                    scope.launch {
                        // frame0/frame1 둘 다 같은 배경으로 교체 — 어긋나면 애니메이션이 깜빡임 (iOS saveBackgroundChoice)
                        val applied = withContext(Dispatchers.IO) {
                            val img = CharacterImageStore.loadGalleryImage(item.id)
                                ?: return@withContext null
                            val f1 = CharacterImageStore.loadGalleryFrame1(item.id)
                            val newImg = detailDisplay(img, bgCutout, bgPreview)
                            val newF1 = f1?.let { detailDisplay(it, bgCutoutF1, bgPreview) }
                            CharacterImageStore.replaceGalleryImage(item.id, newImg)
                            if (newF1 != null) CharacterImageStore.replaceGalleryImage(item.id, newF1, frame = 1)
                            // 지금 적용 중인 자리에도 새 그림 반영 (+워치 전송 — Wear OS 후속)
                            val active = CharacterImageStore.statesUsingGalleryItem(item.id)
                            for (s in active) CharacterImageStore.applyGalleryItem(item.id, s)
                            active.isNotEmpty()
                        } ?: return@launch
                        if (applied) SyncCoordinator.refreshWidgets()
                        bgPreview = null
                        bgCutout = null
                        bgCutoutF1 = null
                        frameSwapTick++
                        notifyChange()
                        showToast(context.getString(R.string.gallery_bg_saved_toast), 1.6)
                    }
                },
                onRefineRequest = { showRefineConfirm = true },
                hasStoredRefineHistory = hasStoredRefineHistory,
                onOpenRefineHistory = {
                    scope.launch {
                        val restored = withContext(Dispatchers.IO) {
                            GalleryRefineHistoryStore.load(item.id)
                        }
                        if (restored == null) {
                            hasStoredRefineHistory = false
                        } else {
                            refineCompare = RefineCompareContext(
                                itemId = item.id,
                                versions = restored.first,
                                selected = restored.second,
                            )
                        }
                    }
                },
                onCopyPromptToast = null,
            )
        }

        // 다듬기 확인 — 캔디를 사용해요 (iOS alert)
        if (showRefineConfirm) {
            val cost = GenerationQuota.cost("low")
            AlertDialog(
                onDismissRequest = { showRefineConfirm = false },
                title = { Text(stringResource(R.string.gallery_refine_confirm_title)) },
                text = { Text(stringResource(R.string.gallery_refine_confirm_body, cost)) },
                confirmButton = {
                    TextButton(onClick = {
                        showRefineConfirm = false
                        runRefine(item)
                    }) { Text(stringResource(R.string.gallery_refine_confirm_button)) }
                },
                dismissButton = {
                    TextButton(onClick = { showRefineConfirm = false }) {
                        Text(stringResource(R.string.common_cancel))
                    }
                },
            )
        }

        // 다른 자리에 적용 — userFacing 상태 목록 시트 (iOS confirmationDialog)
        if (showApplySheet) {
            ModalBottomSheet(onDismissRequest = { showApplySheet = false }) {
                Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
                    Text(
                        text = stringResource(
                            R.string.gallery_apply_sheet_title,
                            stateKoreanLabel(item.sourceState),
                        ),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 10.dp),
                    )
                    CharacterState.userFacing.forEach { state ->
                        Text(
                            text = stringResource(R.string.gallery_apply_sheet_slot, state.koreanShortLabel),
                            style = MaterialTheme.typography.bodyLarge,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .clickable {
                                    showApplySheet = false
                                    scope.launch { applyItem(item, state) }
                                }
                                .padding(vertical = 14.dp, horizontal = 4.dp),
                        )
                    }
                    Text(
                        text = stringResource(R.string.common_cancel),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp))
                            .clickable { showApplySheet = false }
                            .padding(vertical = 14.dp, horizontal = 4.dp),
                    )
                    Spacer(Modifier.height(16.dp))
                }
            }
        }

        // 저장 안 한 배경/다듬기 편집이 있는 채로 닫으려 할 때 확인 (iOS confirmationDialog)
        if (showDetailDiscardConfirm) {
            // 다이얼로그를 그냥 닫는 것도 '계속 편집' — 내려간 시트를 다시 올려야 사라진 것처럼 안 보인다.
            val keepEditing = {
                showDetailDiscardConfirm = false
                scope.launch { detailSheetState.show() }
                Unit
            }
            AlertDialog(
                onDismissRequest = keepEditing,
                title = { Text(stringResource(R.string.gallery_discard_title)) },
                text = { Text(stringResource(R.string.gallery_discard_message)) },
                confirmButton = {
                    TextButton(onClick = {
                        showDetailDiscardConfirm = false
                        refineCompare = null
                        selectedItem = null
                    }) {
                        Text(
                            stringResource(R.string.gallery_discard_close),
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                },
                dismissButton = {
                    // 스와이프/뒤로로 내려간 시트를 다시 올린다 (이미 떠 있으면 no-op).
                    TextButton(onClick = keepEditing) {
                        Text(stringResource(R.string.gallery_discard_keep))
                    }
                },
            )
        }

        // 단건 삭제 확인 (iOS alert)
        if (showDeleteConfirm) {
            AlertDialog(
                onDismissRequest = { showDeleteConfirm = false },
                title = { Text(stringResource(R.string.gallery_delete_confirm_title)) },
                confirmButton = {
                    TextButton(onClick = {
                        showDeleteConfirm = false
                        scope.launch {
                            withContext(Dispatchers.IO) { CharacterImageStore.deleteGalleryItem(item.id) }
                            selectedItem = null
                            notifyChange()
                            showToast(context.getString(R.string.gallery_delete_toast), 1.0)
                        }
                    }) {
                        Text(stringResource(R.string.common_delete), color = MaterialTheme.colorScheme.error)
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showDeleteConfirm = false }) {
                        Text(stringResource(R.string.common_cancel))
                    }
                },
            )
        }
    }

    // 다중 삭제 확인 (iOS alert)
    if (showBulkDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showBulkDeleteConfirm = false },
            title = { Text(stringResource(R.string.gallery_bulk_delete_confirm_title, selectedIDs.size)) },
            confirmButton = {
                TextButton(onClick = {
                    showBulkDeleteConfirm = false
                    scope.launch {
                        val ids = selectedIDs.toList()
                        withContext(Dispatchers.IO) { ids.forEach { CharacterImageStore.deleteGalleryItem(it) } }
                        selectedIDs = emptySet()
                        isSelectionMode = false
                        notifyChange()
                        showToast(context.getString(R.string.gallery_bulk_delete_toast, ids.size), 1.2)
                    }
                }) {
                    Text(stringResource(R.string.common_delete), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showBulkDeleteConfirm = false }) {
                    Text(stringResource(R.string.common_cancel))
                }
            },
        )
    }

    // 사진 저장 결과 알림 (iOS "사진 저장" alert)
    saveResultMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { saveResultMessage = null },
            title = { Text(stringResource(R.string.gallery_save_alert_title)) },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { saveResultMessage = null }) {
                    Text(stringResource(R.string.common_confirm))
                }
            },
        )
    }
}

// MARK: - 카드

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun GalleryCard(
    item: GalleryItem,
    changeTick: Int,
    isSelectionMode: Boolean,
    isSelected: Boolean,
    onTap: () -> Unit,
    onLongPress: () -> Unit,
) {
    // 파일 I/O 는 IO 디스패처 (00-PLAN §0-3)
    val bitmap by produceState<Bitmap?>(initialValue = null, item.id, changeTick) {
        value = withContext(Dispatchers.IO) { CharacterImageStore.loadGalleryImage(item.id) }
    }
    val isActive by produceState(initialValue = false, item.id, changeTick) {
        value = withContext(Dispatchers.IO) {
            CharacterImageStore.statesUsingGalleryItem(item.id).isNotEmpty()
        }
    }
    val hasFrame1 = item.hasFrame1 == true
    val shape = RoundedCornerShape(14.dp)
    val pink = withuPink()

    Column {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .clip(shape)
                .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.72f))
                .border(
                    width = if (isSelected) 3.dp else 0.5.dp,
                    color = if (isSelected) pink
                    else MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                    shape = shape,
                )
                .combinedClickable(onClick = onTap, onLongClick = onLongPress),
        ) {
            val bmp = bitmap
            if (bmp != null) {
                Image(
                    bitmap = bmp.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(6.dp),
                )
            } else {
                // 파일 유실 fallback — photo 심볼 (스펙 04 §3.8)
                Icon(
                    Icons.Filled.Photo,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.align(Alignment.Center),
                )
            }
            if (isSelectionMode) {
                Icon(
                    imageVector = if (isSelected) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                    contentDescription = null,
                    tint = if (isSelected) pink else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(6.dp)
                        .size(22.dp),
                )
            }
            // 지금 적용 중 표시 — 우상단 초록 점
            if (isActive && !isSelectionMode) {
                Box(
                    Modifier
                        .align(Alignment.TopEnd)
                        .padding(8.dp)
                        .size(10.dp)
                        .background(WithuColors.systemGreen, androidx.compose.foundation.shape.CircleShape)
                        .border(
                            1.5.dp,
                            MaterialTheme.colorScheme.background,
                            androidx.compose.foundation.shape.CircleShape,
                        ),
                )
            }
            // 연속 이미지 배지
            if (hasFrame1 && !isSelectionMode) {
                Text(
                    text = stringResource(R.string.gallery_badge_sequence),
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(6.dp)
                        .clip(androidx.compose.foundation.shape.CircleShape)
                        .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.7f))
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                )
            }
        }
        Text(
            text = relativeTime(item.createdAt),
            fontSize = 10.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 6.dp),
        )
    }
}

// MARK: - 선택모드 하단 바 (iOS selectionBottomBar)

@Composable
private fun SelectionBottomBar(
    count: Int,
    onSave: () -> Unit,
    onDelete: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.92f))
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TextButton(onClick = onSave, enabled = count > 0) {
            Icon(Icons.Filled.SaveAlt, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.size(6.dp))
            Text(stringResource(R.string.common_save))
        }
        Spacer(Modifier.weight(1f))
        Text(
            text = stringResource(R.string.gallery_selection_count, count),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.weight(1f))
        TextButton(onClick = onDelete, enabled = count > 0) {
            Icon(
                Icons.Filled.Delete,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(18.dp),
            )
            Spacer(Modifier.size(6.dp))
            Text(stringResource(R.string.common_delete), color = MaterialTheme.colorScheme.error)
        }
    }
}

// MARK: - 상세 시트 본문 (iOS galleryDetailSheet 위→아래 순서 그대로)

@Composable
private fun GalleryDetailContent(
    item: GalleryItem,
    backgroundState: CharacterState,
    frameSwapTick: Int,
    changeTick: Int,
    bgPreview: BgPreview?,
    bgCutout: Bitmap?,
    bgCutoutF1: Bitmap?,
    isRemovingBackground: Boolean,
    refineText: String,
    isRefining: Boolean,
    onRefineTextChange: (String) -> Unit,
    onClose: () -> Unit,
    onDelete: () -> Unit,
    onApplyHere: () -> Unit,
    onSaveToPhotos: () -> Unit,
    onOpenApplySheet: () -> Unit,
    onSwapFrames: () -> Unit,
    onToggleMotion: (Boolean) -> Unit,
    onShowTransparent: (Bitmap) -> Unit,
    onShowWhite: () -> Unit,
    onSaveBackground: () -> Unit,
    onRefineRequest: () -> Unit,
    hasStoredRefineHistory: Boolean,
    onOpenRefineHistory: () -> Unit,
    onCopyPromptToast: (() -> Unit)?,
) {
    val clipboard = LocalClipboardManager.current
    val pinkText = withuPinkText()

    // frameSwapTick 을 키에 포함 — 파일만 바뀌는 스왑/배경저장 후 강제 재로드 (스펙 04 §3.4)
    val frames by produceState<Pair<Bitmap?, Bitmap?>?>(initialValue = null, item.id, frameSwapTick) {
        value = withContext(Dispatchers.IO) {
            CharacterImageStore.loadGalleryImage(item.id) to CharacterImageStore.loadGalleryFrame1(item.id)
        }
    }
    // 표시 이미지 — bgPreview 반영 (flattenedOnWhite 는 CPU 연산이라 Default 디스패처)
    val displayed by produceState<Pair<Bitmap?, Bitmap?>?>(
        initialValue = null,
        frames, bgPreview, bgCutout, bgCutoutF1,
    ) {
        val f = frames ?: return@produceState
        value = withContext(Dispatchers.Default) {
            val base = f.first
            val d0 = base?.let { detailDisplay(it, bgCutout, bgPreview) }
            val d1 = f.second?.let { detailDisplay(it, bgCutoutF1, bgPreview) }
            d0 to d1
        }
    }
    val activeStates by produceState(initialValue = emptyList<CharacterState>(), item.id, changeTick) {
        value = withContext(Dispatchers.IO) { CharacterImageStore.statesUsingGalleryItem(item.id) }
    }
    val hasFrame1 = item.hasFrame1 == true

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(bottom = 32.dp),
    ) {
        // 툴바 — 좌 trash(destructive), 중앙 타이틀, 우 저장(다운로드 아이콘)+닫기.
        // 사진 앱 저장은 맨 아래 전체폭 버튼에서 여기(닫기 옆)로 이동 (iOS 파리티).
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onDelete) {
                Icon(Icons.Filled.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
            }
            Text(
                text = stringResource(R.string.gallery_detail_title, stateKoreanLabel(item.sourceState)),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.weight(1f),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
            IconButton(onClick = onSaveToPhotos) {
                Icon(Icons.Filled.SaveAlt, contentDescription = stringResource(R.string.common_save))
            }
            TextButton(onClick = onClose) { Text(stringResource(R.string.common_close)) }
        }

        val base = frames?.first
        if (frames != null && base == null) {
            // 이미지 파일 유실 — photo 심볼만 (iOS else 분기)
            Icon(
                Icons.Filled.Photo,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .padding(32.dp)
                    .size(48.dp),
            )
            return@Column
        }
        if (base == null) return@Column   // 로딩 중

        Column(
            modifier = Modifier.padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // 1. 이미지 영역 — frame1 있으면 2장 나란히, 없으면 단일
            val d0 = displayed?.first ?: base
            val d1 = displayed?.second
            if (hasFrame1 && frames?.second != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                        Image(
                            bitmap = d0.asImageBitmap(),
                            contentDescription = null,
                            contentScale = ContentScale.Fit,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp)),
                        )
                        Text(
                            stringResource(R.string.gallery_frame_first),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 4.dp),
                        )
                    }
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                        Image(
                            bitmap = (d1 ?: frames!!.second!!).asImageBitmap(),
                            contentDescription = null,
                            contentScale = ContentScale.Fit,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp)),
                        )
                        Text(
                            stringResource(R.string.gallery_frame_second),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 4.dp),
                        )
                    }
                }
            } else {
                Image(
                    bitmap = d0.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 320.dp)
                        .clip(RoundedCornerShape(16.dp))
                        .align(Alignment.CenterHorizontally),
                )
            }

            // 2. 상태 행 — 적용 중이면 필 + 오른쪽에 컴팩트 '다른 자리에' 메뉴 버튼(iOS 동일 배치).
            // 아직 적용 안 했으면 연속 캡션 + 상대 시각만 (적용 CTA 는 아래 4-b 블록에서).
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (activeStates.isNotEmpty()) {
                    StatusPill(
                        kind = StatusKind.OK,
                        text = stringResource(
                            R.string.gallery_applied_pill,
                            activeStates.joinToString(", ") { it.koreanShortLabel },
                        ),
                    )
                    Spacer(Modifier.weight(1f))
                    TextButton(onClick = onOpenApplySheet) {
                        Text(stringResource(R.string.gallery_other_slot))
                    }
                } else {
                    if (hasFrame1) {
                        Text(
                            stringResource(R.string.gallery_sequence_caption),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Spacer(Modifier.weight(1f))
                    Text(
                        text = relativeTime(item.createdAt),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // 3. 만든 기록 — 프롬프트 전문 + 복사 (iOS DisclosureGroup)
            val prompt = item.prompt
            if (!prompt.isNullOrEmpty()) {
                var expanded by remember(item.id) { mutableStateOf(false) }
                Column {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp))
                            .clickable { expanded = !expanded }
                            .padding(vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            Icons.Filled.FormatQuote,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(Modifier.size(8.dp))
                        Text(
                            stringResource(R.string.gallery_prompt_history),
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Bold,
                        )
                        Spacer(Modifier.weight(1f))
                        Icon(
                            if (expanded) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    AnimatedVisibility(visible = expanded) {
                        Column {
                            androidx.compose.foundation.text.selection.SelectionContainer {
                                Text(
                                    text = prompt,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.fillMaxWidth(),
                                )
                            }
                            TextButton(onClick = {
                                clipboard.setText(AnnotatedString(prompt))
                                onCopyPromptToast?.invoke()
                            }) {
                                Icon(
                                    Icons.Filled.ContentCopy,
                                    contentDescription = null,
                                    modifier = Modifier.size(14.dp),
                                )
                                Spacer(Modifier.size(6.dp))
                                Text(
                                    stringResource(R.string.gallery_copy_prompt),
                                    style = MaterialTheme.typography.labelSmall,
                                )
                            }
                        }
                    }
                }
            }

            // 4. 연속 이미지 컨트롤 — 프레임 바꾸기 + (적용 중일 때만) 움직임 토글
            if (hasFrame1) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    OutlinedButton(onClick = onSwapFrames, modifier = Modifier.weight(1f)) {
                        Icon(Icons.Filled.SwapHoriz, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.size(6.dp))
                        Text(stringResource(R.string.gallery_swap_frames))
                    }
                    val first = activeStates.firstOrNull()
                    if (first != null) {
                        // on = 첫 적용 상태 기준, set 은 모든 적용 상태에 일괄 (스펙 04 §1.3.4)
                        // initialValue=null 로 두어 IO 로드 완료 전엔 스위치 미노출 — 기본값 true 가
                        // 먼저 그려지는 첫 프레임 ON 플래시 방지 (iOS 동기 읽기와 동일한 무깜빡, 스펙 04 B-10)
                        val motionOn by produceState<Boolean?>(initialValue = null, first, changeTick) {
                            value = withContext(Dispatchers.IO) {
                                !CharacterImageStore.isAnimationDisabled(first)
                            }
                        }
                        motionOn?.let { on ->
                            // 라벨 없는 인라인 토글 — 스크린리더용 라벨을 붙인다 ('움직임')
                            PixelToggle(
                                checked = on,
                                onCheckedChange = onToggleMotion,
                                contentDescription = stringResource(R.string.gallery_motion_toggle),
                            )
                        }
                    }
                }
            }

            // 5. 아직 어디에도 적용 안 함 — 큰 적용 CTA + 아래 전체폭 '다른 자리에 적용하기'.
            // 적용 중이면 위 2번 상태 행의 컴팩트 '다른 자리에' 버튼이 그 역할을 하므로 생략
            // (iOS: activeStates 비었을 때만 CTA+풀사이즈 메뉴, 아니면 상태 행에 컴팩트 메뉴).
            if (activeStates.isEmpty()) {
                WithuCTAButton(
                    text = stringResource(R.string.gallery_apply_cta, backgroundState.koreanShortLabel),
                    onClick = onApplyHere,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedButton(onClick = onOpenApplySheet, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Filled.ArrowCircleRight, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.size(6.dp))
                    Text(stringResource(R.string.gallery_other_slot_apply))
                }
            }

            // 6. 배경 보기 블록 — 빼기/있기 미리보기 → 이대로 저장
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedButton(
                        onClick = { onShowTransparent(base) },
                        enabled = !isRemovingBackground,
                        modifier = Modifier.weight(1f),
                    ) {
                        val tint = if (bgPreview == BgPreview.TRANSPARENT) pinkText
                        else MaterialTheme.colorScheme.onSurfaceVariant
                        Icon(
                            Icons.Filled.AutoFixHigh,
                            contentDescription = null,
                            tint = tint,
                            modifier = Modifier.size(16.dp),
                        )
                        Spacer(Modifier.size(6.dp))
                        Text(stringResource(R.string.gallery_bg_remove), color = tint)
                    }
                    OutlinedButton(
                        onClick = onShowWhite,
                        enabled = !isRemovingBackground,
                        modifier = Modifier.weight(1f),
                    ) {
                        val tint = if (bgPreview == BgPreview.WHITE) pinkText
                        else MaterialTheme.colorScheme.onSurfaceVariant
                        Icon(
                            Icons.Filled.Square,
                            contentDescription = null,
                            tint = tint,
                            modifier = Modifier.size(16.dp),
                        )
                        Spacer(Modifier.size(6.dp))
                        Text(stringResource(R.string.gallery_bg_keep), color = tint)
                    }
                }
                if (isRemovingBackground) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        Text(
                            stringResource(R.string.gallery_bg_removing),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                if (bgPreview != null) {
                    WithuCTAButton(
                        text = stringResource(R.string.gallery_bg_save_cta),
                        onClick = onSaveBackground,
                        enabled = !isRemovingBackground,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }

            // 8. 다듬기 블록
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Filled.AutoAwesome,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(Modifier.size(8.dp))
                    Text(
                        stringResource(R.string.gallery_refine_label),
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Bold,
                    )
                }
                OutlinedTextField(
                    value = refineText,
                    onValueChange = onRefineTextChange,
                    placeholder = { Text(stringResource(R.string.gallery_refine_placeholder)) },
                    textStyle = MaterialTheme.typography.bodyMedium,
                    colors = withuInputColors(),
                    modifier = Modifier.fillMaxWidth().pixelInputField(),
                )
                OutlinedButton(
                    onClick = onRefineRequest,
                    enabled = !isRefining && refineText.trim().isNotEmpty(),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (isRefining) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.size(8.dp))
                        Text(stringResource(R.string.gallery_refine_running), color = pinkText)
                    } else {
                        Icon(
                            Icons.Filled.AutoFixHigh,
                            contentDescription = null,
                            tint = pinkText,
                            modifier = Modifier.size(16.dp),
                        )
                        Spacer(Modifier.size(6.dp))
                        Text(stringResource(R.string.gallery_refine_button), color = pinkText)
                    }
                }
                Text(
                    text = stringResource(R.string.gallery_refine_footer),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                // 저장된 다듬기 이력이 있으면 다시 열기 (iOS '다듬기 이력 보기')
                if (hasStoredRefineHistory) {
                    TextButton(onClick = onOpenRefineHistory) {
                        Icon(
                            Icons.Filled.History,
                            contentDescription = null,
                            tint = withuCTAGreen(),
                            modifier = Modifier.size(16.dp),
                        )
                        Spacer(Modifier.size(6.dp))
                        Text(
                            stringResource(R.string.gallery_refine_history_open),
                            style = MaterialTheme.typography.labelMedium,
                            color = withuCTAGreen(),
                        )
                    }
                }
            }
        }
    }
}

// MARK: - 다듬기 이력 (버전 스트립) — iOS refineCompareSheet

/**
 * 다듬기 이력 화면 — 큰 미리보기 + 원본/다듬음 N 스트립 + 이어서 다듬기 + 적용/취소.
 * '닫기'는 이력을 남긴 채 상세로 돌아가고, '취소'만 이력을 버린다 (iOS 동일).
 */
@Composable
private fun RefineCompareContent(
    ctx: RefineCompareContext,
    refineText: String,
    isRefining: Boolean,
    onRefineTextChange: (String) -> Unit,
    onSelectVersion: (Int) -> Unit,
    onContinueRefine: () -> Unit,
    onAdopt: () -> Unit,
    onReject: () -> Unit,
    onClose: () -> Unit,
) {
    val green = withuCTAGreen()
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(bottom = 32.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = stringResource(R.string.gallery_refine_history_title),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.weight(1f),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
            TextButton(onClick = onClose) { Text(stringResource(R.string.common_close)) }
        }

        Column(
            modifier = Modifier.padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // 큰 미리보기 — 지금 고른 버전
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(1f)
                    .plainCard(cornerRadius = 16.dp),
                contentAlignment = Alignment.Center,
            ) {
                Image(
                    bitmap = ctx.current.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(12.dp),
                )
            }

            // 버전 스트립 — 탭해서 고른 버전이 적용 대상이 된다
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                ctx.versions.forEachIndexed { idx, bmp ->
                    val selected = idx == ctx.selected
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.clickable { onSelectVersion(idx) },
                    ) {
                        Image(
                            bitmap = bmp.asImageBitmap(),
                            contentDescription = null,
                            contentScale = ContentScale.Fit,
                            modifier = Modifier
                                .size(68.dp)
                                .clip(RoundedCornerShape(10.dp))
                                .background(MaterialTheme.colorScheme.background)
                                .border(
                                    width = 2.5.dp,
                                    color = if (selected) green else Color.Transparent,
                                    shape = RoundedCornerShape(10.dp),
                                ),
                        )
                        Spacer(Modifier.size(4.dp))
                        Text(
                            text = if (idx == 0) {
                                stringResource(R.string.gallery_refine_version_original)
                            } else {
                                stringResource(R.string.gallery_refine_version_n, idx)
                            },
                            style = MaterialTheme.typography.labelSmall,
                            color = if (selected) green else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            // 이어서 다듬기 — 고른 버전을 기준으로 한 번 더
            FrostedCard(modifier = Modifier.fillMaxWidth()) {
                OutlinedTextField(
                    value = refineText,
                    onValueChange = onRefineTextChange,
                    placeholder = { Text(stringResource(R.string.gallery_refine_placeholder)) },
                    textStyle = MaterialTheme.typography.bodyMedium,
                    colors = withuInputColors(),
                    modifier = Modifier.fillMaxWidth().pixelInputField(),
                )
                Spacer(Modifier.size(8.dp))
                OutlinedButton(
                    onClick = onContinueRefine,
                    enabled = !isRefining && refineText.trim().isNotEmpty(),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (isRefining) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.size(8.dp))
                        Text(stringResource(R.string.gallery_refine_running), color = green)
                    } else {
                        Text(stringResource(R.string.gallery_refine_continue), color = green)
                    }
                }
            }
            Text(
                text = stringResource(R.string.gallery_refine_base_hint),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            WithuCTAButton(
                text = stringResource(R.string.gallery_refine_adopt),
                onClick = onAdopt,
                enabled = !isRefining,
                modifier = Modifier.fillMaxWidth(),
            )
            TextButton(
                onClick = onReject,
                enabled = !isRefining,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    stringResource(R.string.common_cancel),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// MARK: - 로직 (순수/suspend 헬퍼)

/**
 * 상세 시트 표시 이미지 — 미리보기 선택 반영 (iOS detailDisplay).
 * 배경 빼기 = 배경제거 결과(원본이 이미 투명이면 그대로), 배경 있기 = 흰색 합성.
 */
private fun detailDisplay(base: Bitmap, cutout: Bitmap?, preview: BgPreview?): Bitmap = when (preview) {
    null -> base
    BgPreview.TRANSPARENT -> cutout ?: base
    BgPreview.WHITE -> ImageProcessing.flattenedOnWhite(base)
}

/**
 * 다듬기 — 기준 이미지를 참고로 한 번 더 생성 (iOS refineItem 의 네트워크 부분).
 * kind=refine → 서버가 '계정 무료 1회'를 소진하지 않음. 차감은 성공 시에만 (스펙 04 §3.6).
 *
 * 결과 반영(버전 이력 append / 시트 닫힘 폴백 저장)은 호출측 책임 — 응답이 도착한 시점의
 * 시트 상태를 봐야 하기 때문이다.
 *
 * @param base 이어서 다듬기면 지금 고른 버전, null 이면 갤러리 원본을 기준으로.
 * @return (다듬은 128px 썸네일, 서버에 보낸 프롬프트) — 실패/취소면 null.
 */
private suspend fun refineItem(
    item: GalleryItem,
    refineTextValue: String,
    base: Bitmap?,
    onStart: () -> Unit,
    onFinish: () -> Unit,
    onToast: (String, Double) -> Unit,
): Pair<Bitmap, String>? {
    val context = com.seoyoung.withu.WithuApp.context
    val cost = GenerationQuota.cost("low")
    if (!GenerationQuota.canGenerate(cost)) {
        onToast(context.getString(R.string.gallery_no_candy_toast), 2.0)
        return null
    }
    val ref = base
        ?: withContext(Dispatchers.IO) { CharacterImageStore.loadGalleryImage(item.id) }
        ?: return null
    val trimmed = refineTextValue.trim()
    if (trimmed.isEmpty()) return null
    onStart()
    try {
        val refB64 = withContext(Dispatchers.Default) { ImageProcessing.toBase64Png(ref) }
        // 서버 프롬프트 — 영문 코드 상수 (iOS 원문 그대로, 00-PLAN §3-5)
        val prompt = "Use the reference image as the SAME character. Keep the EXACT same character — " +
            "identity, face and expression style, body proportions, art style, colors and shading, " +
            "line thickness, and every design detail. Change ONLY: $trimmed. " +
            "Transparent background — only the character, no shadows."
        val req = GenerateImageRequest(
            prompt = prompt,
            referenceImageBase64 = refB64,
            steps = 30,
            width = 1024,
            height = 1024,
            quality = "low",
            artStyle = null,
            style = "auto",
            kind = "refine",
            model = "gpt-image-2",
            userInput = trimmed,
            inputField = "다듬기",
        )
        // 갤러리 다듬기 — 원본 캐릭터(batchId)의 수정 체인에 이어붙인다.
        val resp = ApiClient.generateImage(req, sessionId = item.batchId, state = item.sourceState)
        val raw = withContext(Dispatchers.Default) { ImageProcessing.fromBase64(resp.imageBase64) }
        if (raw == null) {
            onToast(context.getString(R.string.gallery_no_image_toast), 1.6)
            return null
        }
        // gpt-image-2 마젠타 배경 → 크로마키 투명화 후 128px 썸네일 (iOS 동일)
        val small = withContext(Dispatchers.Default) {
            ImageProcessing.downsampled(ImageProcessing.chromaKeyRemoved(raw), 128)
        }
        // 로그인 제외 범위 — iOS AuthManager.applyEntitlement 대신 캔디만 끌어올리기 (max)
        resp.entitlement?.let { GenerationQuota.syncCreditsUp(it.credits) }
        GenerationQuota.record(cost)   // 성공했을 때만 차감
        return small to prompt
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        onToast(e.koreanized(), 2.5)
        return null
    } finally {
        onFinish()
    }
}

/** sourceState rawValue → 한국어 라벨. 매핑 실패 시 raw 그대로 (스펙 04 §3.8). */
internal fun stateKoreanLabel(raw: String): String =
    CharacterState.fromRaw(raw)?.koreanShortLabel ?: raw

/** 상대 시각 — iOS .relative(presentation: .named) 대응 (시스템 로케일 문구). */
internal fun relativeTime(millis: Long): String =
    DateUtils.getRelativeTimeSpanString(
        millis,
        System.currentTimeMillis(),
        DateUtils.MINUTE_IN_MILLIS,
    ).toString()
