package com.seoyoung.withu.gen

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.seoyoung.withu.R
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.notify.NotificationHelper
import com.seoyoung.withu.camera.PhotoSaver
import com.seoyoung.withu.paywall.PaywallSheet
import com.seoyoung.withu.quota.GenerationQuota
import com.seoyoung.withu.ui.CandyBadge
import com.seoyoung.withu.ui.FormSection
import com.seoyoung.withu.ui.HelperFooter
import com.seoyoung.withu.ui.WarningBanner
import com.seoyoung.withu.ui.WithuCTAButton
import com.seoyoung.withu.ui.WithuPinkButton
import com.seoyoung.withu.ui.rememberBackgroundGradient
import com.seoyoung.withu.ui.theme.WithuColors
import com.seoyoung.withu.ui.theme.withuPink
import kotlinx.coroutines.delay

/**
 * 여러 모습 만들기 (배치 생성) — iOS BatchCharacterGenView.swift 포팅 (스펙 03).
 *
 * 화면은 표시·입력만 담당하고 모든 로직/상태는 BatchGenViewModel 에 있다.
 * 2단계 플로우: idle(앵커) 먼저 → 승인 → 나머지 일관 생성. 승인 대기 중이면
 * 리스트를 승인 섹션 하나로 교체한다 (iOS Form 분기와 동일).
 *
 * 네비게이션은 콜백(onClose)으로만. 사진 선택(전역/상태별/수정용)은 모두
 * 앨범 또는 '내 캐릭터' → 정사각 크롭을 거쳐 확정한다.
 */

/** 방금 고른 사진을 어디에 넣을지 — 앨범/갤러리 픽 결과의 라우팅 대상. */
private sealed interface PhotoTarget {
    data object Global : PhotoTarget
    data class ForState(val state: CharacterState) : PhotoTarget
    data object Revision : PhotoTarget
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BatchGenScreen(onClose: () -> Unit, vm: BatchGenViewModel = viewModel()) {
    val context = LocalContext.current

    // 배경 무드는 idle 기조 — 서브 화면 공통 그라데이션.
    val gradient = rememberBackgroundGradient(CharacterState.IDLE)

    // 사진 선택 → 크롭 파이프라인 상태.
    var pendingCrop by remember { mutableStateOf<Bitmap?>(null) }   // 크롭 대기 원본
    var cropTarget by remember { mutableStateOf<PhotoTarget?>(null) }
    var galleryTarget by remember { mutableStateOf<PhotoTarget?>(null) }   // '내 캐릭터' 피커 표시
    var albumTarget by remember { mutableStateOf<PhotoTarget?>(null) }     // 앨범 런처 발사 직전 대상

    // 앨범 사진 픽커 (권한 불필요) — 고른 Uri 를 다운샘플 Bitmap 으로 디코드 후 크롭 대기.
    val albumPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia(),
    ) { uri: Uri? ->
        val target = albumTarget
        albumTarget = null
        if (uri != null && target != null) {
            val bmp = decodeDownsampled(context, uri)
            if (bmp != null) {
                pendingCrop = bmp
                cropTarget = target
            } else if (target is PhotoTarget.Global) {
                vm.reportGlobalReferenceLoadFailed()
            }
        }
    }

    // 사진 앱 저장 권한(API 28 이하) 게이트 — 승인 후 실행할 저장 액션을 보관.
    var pendingSave by remember { mutableStateOf<(() -> Unit)?>(null) }
    val writePermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        val action = pendingSave
        pendingSave = null
        if (granted) action?.invoke() else vm.reportPhotosPermissionDenied()
    }
    val guardedSave: (() -> Unit) -> Unit = { action ->
        val needs = PhotoSaver.needsLegacyWritePermission() &&
            ContextCompat.checkSelfPermission(
                context, Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ) != PackageManager.PERMISSION_GRANTED
        if (needs) {
            pendingSave = action
            writePermissionLauncher.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        } else {
            action()
        }
    }

    // 알림 권한(API 33+) 요청 후 배치 시작 — 첫 시작 시 1회 시스템 다이얼로그 (iOS 파리티).
    val notifLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { vm.startBatch() }
    val launchStart: () -> Unit = {
        NotificationHelper.ensureChannels()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !NotificationHelper.hasPermission()) {
            NotificationHelper.markPermissionRequested()
            notifLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            vm.startBatch()
        }
    }

    // 진행 중 경과초 갱신용 0.5s 틱 (iOS TimelineView(0.5) 대응).
    var nowMs by remember { mutableStateOf(System.currentTimeMillis()) }
    LaunchedEffect(vm.isGenerating) {
        while (vm.isGenerating) {
            nowMs = System.currentTimeMillis()
            delay(500)
        }
    }

    Box(Modifier.fillMaxSize().background(gradient)) {
        Scaffold(
            containerColor = Color.Transparent,
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.batch_title)) },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
                    actions = {
                        CandyBadge(candy = vm.candy, onClick = { vm.showPaywall = true })
                        Spacer(Modifier.width(8.dp))
                    },
                )
            },
        ) { padding ->
            Column(
                Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp)
                    .padding(bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                if (vm.awaitingIdleApproval && vm.results[CharacterState.IDLE] != null) {
                    // 승인 단계 — '만들어진 모습'(결과)을 먼저 크게 보여주고,
                    // 그 아래에 '기준 모습 확인'(승인/수정 버튼)을 둔다 (사용자 요청 순서).
                    ResultsSection(vm = vm, onSaveAll = { guardedSave { vm.saveAllToPhotos() } })
                    IdleApprovalSection(vm)
                } else {
                    // (B~F) 일반 입력 — iOS 코드 순서: stateList → identity → reference → options → start.
                    StateListSection(
                        vm = vm,
                        nowMs = nowMs,
                        onPickAlbum = { target -> albumTarget = target; albumPicker.launch(imageOnly()) },
                        onPickGallery = { target -> galleryTarget = target },
                    )
                    IdentitySection(vm)
                    ReferenceSection(
                        vm = vm,
                        onPickAlbum = { albumTarget = PhotoTarget.Global; albumPicker.launch(imageOnly()) },
                        onPickGallery = { galleryTarget = PhotoTarget.Global },
                    )
                    OptionsSection(vm)
                    StartSection(vm = vm, onStart = launchStart)

                    // (G) 결과 — 입력 화면에서도 결과가 남아있으면 표시.
                    if (vm.results.isNotEmpty() || vm.errors.isNotEmpty()) {
                        ResultsSection(vm = vm, onSaveAll = { guardedSave { vm.saveAllToPhotos() } })
                    }
                }
            }
        }
    }

    // (H) 상세 시트
    vm.selectedResult?.let { state ->
        ResultDetailSheet(
            vm = vm,
            state = state,
            onPickAlbum = { albumTarget = PhotoTarget.Revision; albumPicker.launch(imageOnly()) },
            onSave = { frame -> guardedSave { vm.saveOneToPhotos(state, frame) } },
        )
    }

    // '내 캐릭터' 갤러리 참고 피커 (전역/상태별/수정용 공용) → 크롭 대기로.
    galleryTarget?.let { target ->
        GalleryReferencePicker(
            onPick = { bmp ->
                galleryTarget = null
                pendingCrop = bmp
                cropTarget = target
            },
            onClose = { galleryTarget = null },
        )
    }

    // 정사각 크롭 — 모든 사진 선택의 마지막 단계.
    pendingCrop?.let { source ->
        SquareCropView(
            source = source,
            onDone = { cropped ->
                when (val t = cropTarget) {
                    PhotoTarget.Global -> vm.referenceImage = cropped
                    is PhotoTarget.ForState -> vm.setStateReference(t.state, cropped)
                    PhotoTarget.Revision -> vm.revisionRefImage = cropped
                    null -> Unit
                }
                pendingCrop = null
                cropTarget = null
            },
            onCancel = {
                pendingCrop = null
                cropTarget = null
            },
        )
    }

    // 페이월 시트
    if (vm.showPaywall) {
        PaywallSheet(onClose = { vm.closePaywall() })
    }

    // 완료 알럿
    if (vm.showFinishedAlert) {
        // A-2c: 완료 알럿 '%d개 완성' — frame1 제외, frame0 결과 수만 (iOS results.count).
        val done = vm.results.size
        val failed = vm.errors.size
        AlertDialog(
            onDismissRequest = { vm.showFinishedAlert = false },
            title = { Text(stringResource(R.string.batch_done_title)) },
            text = { Text(stringResource(R.string.batch_done_body, done, failed)) },
            confirmButton = {
                TextButton(onClick = { vm.showFinishedAlert = false }) {
                    Text(stringResource(R.string.common_confirm))
                }
            },
        )
    }

    // 사진 저장 결과 알럿
    vm.saveResultMessage?.let { msg ->
        AlertDialog(
            onDismissRequest = { vm.dismissSaveResult() },
            title = { Text(stringResource(R.string.batch_save_alert_title)) },
            text = { Text(msg) },
            confirmButton = {
                TextButton(onClick = { vm.dismissSaveResult() }) {
                    Text(stringResource(R.string.common_confirm))
                }
            },
        )
    }
}

// ============================================================================
// (B) 상태 선택 섹션
// ============================================================================

@Composable
private fun StateListSection(
    vm: BatchGenViewModel,
    nowMs: Long,
    onPickAlbum: (PhotoTarget) -> Unit,
    onPickGallery: (PhotoTarget) -> Unit,
) {
    val cost = GenerationQuota.cost(vm.quality)
    FormSection(
        header = stringResource(R.string.batch_states_header, vm.selectedStates.size),
        footer = stringResource(R.string.batch_footer_count, vm.selectedStates.size) + "\n" +
            stringResource(R.string.batch_footer_cost, vm.needCandy),
    ) {
        CharacterState.userFacing.forEach { state ->
            StateRow(
                vm = vm,
                state = state,
                nowMs = nowMs,
                onPickAlbum = { onPickAlbum(PhotoTarget.ForState(state)) },
                onPickGallery = { onPickGallery(PhotoTarget.ForState(state)) },
            )
        }
        // 모두 켜기 / 모두 끄기 — Compose 는 Row 안 TextButton 이 각자 탭만 받아 iOS borderless 이슈 없음.
        Row(
            Modifier.fillMaxWidth().padding(top = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            TextButton(onClick = { vm.selectAll() }) {
                Text(stringResource(R.string.batch_all_on))
            }
            TextButton(onClick = { vm.deselectAll() }) {
                Text(
                    stringResource(R.string.batch_all_off),
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}

@Composable
private fun StateRow(
    vm: BatchGenViewModel,
    state: CharacterState,
    nowMs: Long,
    onPickAlbum: () -> Unit,
    onPickGallery: () -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val selected = state in vm.selectedStates

    Column(Modifier.fillMaxWidth().animateContentSize()) {
        // 라벨 행 — 체크 토글 + 라벨(해제 시 취소선) + 우측 결과 배지.
        Row(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(10.dp))
                .clickable { expanded = !expanded }
                .padding(vertical = 4.dp, horizontal = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Checkbox(checked = selected, onCheckedChange = { vm.setSelected(state, it) })
            Text(
                text = state.koreanShortLabel,
                style = MaterialTheme.typography.bodyMedium,
                textDecoration = if (selected) null else TextDecoration.LineThrough,
                color = if (selected) MaterialTheme.colorScheme.onSurface
                else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f).padding(start = 4.dp),
            )
            ResultBadge(vm = vm, state = state, nowMs = nowMs)
        }

        AnimatedVisibility(visible = expanded) {
            Column(
                Modifier.fillMaxWidth().padding(start = 8.dp, top = 4.dp, bottom = 8.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                // 1) 상태별 포즈 hint
                OutlinedTextField(
                    value = vm.stateHints[state] ?: state.generationHint,
                    onValueChange = { vm.stateHints[state] = it },
                    minLines = 2,
                    modifier = Modifier.fillMaxWidth(),
                )
                // 2) 상태별 참고 이미지 피커
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    RefThumb(bitmap = vm.stateReferenceImages[state], size = 36)
                    TextButton(onClick = onPickAlbum) {
                        Text(stringResource(R.string.batch_ref_album_small))
                    }
                    TextButton(onClick = onPickGallery) {
                        Text(stringResource(R.string.batch_ref_gallery_small))
                    }
                }
                if (vm.stateReferenceImages[state] != null) {
                    TextButton(onClick = { vm.removeStateReference(state) }) {
                        Text(
                            stringResource(R.string.batch_ref_remove_state),
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                }
                // 3) 움직임 토글 — usesGeneratedMotion 상태만.
                if (state.usesGeneratedMotion) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            stringResource(R.string.batch_motion_toggle),
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.weight(1f),
                        )
                        Switch(
                            checked = state in vm.animatedStates,
                            onCheckedChange = { vm.setAnimated(state, it) },
                        )
                    }
                }
                // 4) 기본값으로 되돌리기
                TextButton(onClick = { vm.resetHint(state) }) {
                    Text(stringResource(R.string.batch_reset_hint))
                }
            }
        }
    }
}

/** 우측 결과 배지 — 진행중(스피너+경과초) / 성공(체크) / 실패(경고). */
@Composable
private fun ResultBadge(vm: BatchGenViewModel, state: CharacterState, nowMs: Long) {
    when {
        state in vm.inProgressStates -> {
            val started = vm.stateStartedAt[state] ?: nowMs
            val elapsed = ((nowMs - started) / 1000).toInt().coerceAtLeast(0)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
                Text(
                    stringResource(R.string.batch_elapsed, elapsed),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        vm.results[state] != null -> Icon(
            Icons.Filled.CheckCircle, contentDescription = null,
            tint = WithuColors.systemGreen, modifier = Modifier.size(18.dp),
        )
        vm.errors[state] != null -> Icon(
            Icons.Filled.Warning, contentDescription = null,
            tint = WithuColors.systemOrange, modifier = Modifier.size(18.dp),
        )
    }
}

// ============================================================================
// (C) 캐릭터 프롬프트 섹션
// ============================================================================

@Composable
private fun IdentitySection(vm: BatchGenViewModel) {
    FormSection(
        header = stringResource(R.string.batch_identity_header),
        footer = stringResource(R.string.batch_identity_footer),
    ) {
        OutlinedTextField(
            value = vm.baseIdentity,
            onValueChange = { vm.baseIdentity = it },
            minLines = 3,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

// ============================================================================
// (D) 참고 사진 섹션 (전역 fallback)
// ============================================================================

@Composable
private fun ReferenceSection(
    vm: BatchGenViewModel,
    onPickAlbum: () -> Unit,
    onPickGallery: () -> Unit,
) {
    FormSection(
        header = stringResource(R.string.batch_ref_header),
        footer = stringResource(R.string.batch_ref_footer),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            RefThumb(bitmap = vm.referenceImage, size = 64)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                TextButton(onClick = onPickAlbum) {
                    Text(stringResource(R.string.batch_pick_album))
                }
                TextButton(onClick = onPickGallery) {
                    Text(stringResource(R.string.batch_pick_gallery))
                }
            }
        }
        if (vm.referenceImage != null) {
            TextButton(onClick = { vm.referenceImage = null }) {
                Text(
                    stringResource(R.string.batch_ref_remove),
                    color = MaterialTheme.colorScheme.error,
                )
            }
            // '그대로 둘 것'
            Text(
                stringResource(R.string.batch_keep_label),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.padding(top = 6.dp, start = 2.dp),
            )
            OutlinedTextField(
                value = vm.referenceKeep,
                onValueChange = { vm.referenceKeep = it },
                placeholder = { Text(stringResource(R.string.batch_keep_placeholder)) },
                minLines = 1, maxLines = 4,
                modifier = Modifier.fillMaxWidth(),
            )
            HelperFooter(stringResource(R.string.batch_keep_hint))
            // '바꿀 것'
            Text(
                stringResource(R.string.batch_change_label),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.padding(top = 6.dp, start = 2.dp),
            )
            OutlinedTextField(
                value = vm.referenceChange,
                onValueChange = { vm.referenceChange = it },
                placeholder = { Text(stringResource(R.string.batch_change_placeholder)) },
                minLines = 1, maxLines = 4,
                modifier = Modifier.fillMaxWidth(),
            )
            HelperFooter(stringResource(R.string.batch_change_hint))
        }
    }
}

// ============================================================================
// (E) 스타일 섹션
// ============================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun OptionsSection(vm: BatchGenViewModel) {
    // 선택 상태 중 움직임 가능한 게 있을 때만 '모두 움직이는' 토글/칩 노출.
    val animatable = vm.selectedStates.filter { it.usesGeneratedMotion }
    val allAnimatedOn = animatable.isNotEmpty() && animatable.all { it in vm.animatedStates }

    FormSection(
        header = stringResource(R.string.batch_style_header),
        footer = stringResource(R.string.batch_style_footer),
    ) {
        Text(
            stringResource(R.string.batch_style_picker_label),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 2.dp),
        )
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            SegmentedButton(
                selected = vm.artStyle == "casual",
                onClick = { vm.artStyle = "casual" },
                shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2),
            ) { Text(stringResource(R.string.batch_style_soft)) }
            SegmentedButton(
                selected = vm.artStyle == "pixel",
                onClick = { vm.artStyle = "pixel" },
                shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2),
            ) { Text(stringResource(R.string.batch_style_pixel)) }
        }

        if (animatable.isNotEmpty()) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 8.dp)) {
                Text(
                    stringResource(R.string.batch_all_motion),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f),
                )
                Switch(checked = allAnimatedOn, onCheckedChange = { vm.setAllAnimated(it) })
            }
            // 상태별 움직임 칩 (가로 스크롤) — 행 안 토글과 같은 값 공유.
            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(top = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                animatable.forEach { state ->
                    val on = state in vm.animatedStates
                    Row(
                        Modifier
                            .clip(CircleShape)
                            .background(
                                if (on) withuPink().copy(alpha = 0.18f)
                                else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.10f),
                            )
                            .border(
                                1.dp,
                                if (on) withuPink() else Color.Transparent,
                                CircleShape,
                            )
                            .clickable { vm.setAnimated(state, !on) }
                            .padding(horizontal = 12.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(state.symbolEmoji, style = MaterialTheme.typography.labelMedium)
                        Text(
                            state.koreanShortLabel,
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Medium,
                        )
                    }
                }
            }
        }
    }
}

// ============================================================================
// (F) 시작 섹션
// ============================================================================

@Composable
private fun StartSection(vm: BatchGenViewModel, onStart: () -> Unit) {
    val need = vm.needCandy
    val notEnough = vm.remainingGenerations < need
    // A-2d: 진행 카운터 '만드는 중… %d/%d' — frame1 제외 (iOS results.count + errors.count).
    val done = vm.results.size + vm.errors.size

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (vm.isGenerating) {
            ProgressCTAButton(
                text = stringResource(R.string.batch_generating, done, vm.requiredCount),
            )
            HelperFooter(stringResource(R.string.batch_bg_note, done, vm.requiredCount))
            WithuPinkButton(
                text = stringResource(R.string.batch_stop),
                onClick = { vm.stopBatch() },
                modifier = Modifier.fillMaxWidth(),
            )
        } else {
            val disabled = vm.selectedStates.isEmpty() ||
                vm.baseIdentity.isBlank() || notEnough
            WithuCTAButton(
                text = stringResource(R.string.batch_start),
                onClick = onStart,
                enabled = !disabled,
                modifier = Modifier.fillMaxWidth(),
            )
            if (notEnough) {
                WarningBanner(
                    stringResource(
                        R.string.batch_not_enough, vm.remainingGenerations, vm.selectedStates.size, need,
                    ),
                )
                WithuPinkButton(
                    text = stringResource(R.string.batch_paywall_cta),
                    onClick = { vm.showPaywall = true },
                    modifier = Modifier.fillMaxWidth(),
                )
            } else {
                HelperFooter(stringResource(R.string.batch_balance, vm.remainingGenerations, need))
            }
        }
    }
}

// ============================================================================
// (A) 기준 모습 승인 섹션
// ============================================================================

@Composable
private fun IdleApprovalSection(vm: BatchGenViewModel) {
    FormSection(
        header = stringResource(R.string.batch_approval_header),
        footer = stringResource(R.string.batch_approval_footer),
    ) {
        // 기준 모습(만들어진 결과) 이미지는 바로 위 '만들어진 모습' 섹션이 크게 보여주므로
        // 여기선 확인 버튼만 둔다 (중복 제거 + 결과 아래에 확인 컨트롤 배치).
        // CTA — 이 모습으로 나머지 만들기 (초록, 주요 진행 액션)
        WithuCTAButton(
            text = stringResource(R.string.batch_approve),
            onClick = { vm.approveIdleAndContinue() },
            modifier = Modifier.fillMaxWidth(),
        )
        // B-8: iOS 순서(버튼→필드) — 수정해서 생성하기 버튼/스피너가 입력 필드 위에 온다.
        // 수정해서 생성하기 — 생성 중엔 스피너, 수정사항 비면 비활성.
        if (vm.isGenerating) {
            Row(
                Modifier.fillMaxWidth().padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                Text(stringResource(R.string.batch_revising), style = MaterialTheme.typography.bodyMedium)
            }
        } else {
            TextButton(
                onClick = { vm.reviseIdle() },
                enabled = vm.idleRevisionText.isNotBlank(),
            ) { Text(stringResource(R.string.batch_revise)) }
        }
        // 수정사항 입력
        OutlinedTextField(
            value = vm.idleRevisionText,
            onValueChange = { vm.idleRevisionText = it },
            placeholder = { Text(stringResource(R.string.batch_revision_placeholder)) },
            minLines = 1, maxLines = 3,
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
        )
        // 프롬프트 수정해서 다시 — 결과/앵커 비우고 입력 화면 복귀.
        TextButton(onClick = { vm.backToPromptEdit() }) {
            Text(stringResource(R.string.batch_back_to_prompt))
        }
        vm.errors[CharacterState.IDLE]?.let { err ->
            WarningBanner(err, modifier = Modifier.padding(top = 8.dp))
        }
    }
}

// ============================================================================
// (G) 결과 섹션
// ============================================================================

@Composable
private fun ResultsSection(vm: BatchGenViewModel, onSaveAll: () -> Unit) {
    // 표시 대상 — 선언 순서 유지, 결과 또는 에러가 있는 상태만.
    val shown = CharacterState.entries.filter { vm.results[it] != null || vm.errors[it] != null }

    FormSection(header = stringResource(R.string.batch_results_header)) {
        // 수동 2열 그리드 — LazyVGrid 중첩 금지(iOS 동일 이유).
        shown.chunked(2).forEach { row ->
            Row(
                Modifier.fillMaxWidth().padding(vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                row.forEach { state ->
                    Box(Modifier.weight(1f)) {
                        if (vm.results[state] != null) {
                            ResultCard(vm, state)
                        } else {
                            ErrorCard(vm, state)
                        }
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }

        if (vm.results.isNotEmpty()) {
            Column(Modifier.fillMaxWidth().padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                WithuCTAButton(
                    text = stringResource(R.string.batch_apply_all, vm.results.size),
                    onClick = { vm.applyAll() },
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(
                        onClick = { vm.applyTransparentToAll() },
                        enabled = !vm.isProcessingTransparentBulk,
                        modifier = Modifier.weight(1f),
                    ) {
                        Text(
                            stringResource(
                                if (vm.isProcessingTransparentBulk) R.string.batch_bg_removing
                                else R.string.batch_bg_remove_all,
                            ),
                        )
                    }
                    TextButton(
                        onClick = { vm.restoreOriginalToAll() },
                        enabled = !vm.isProcessingTransparentBulk,
                        modifier = Modifier.weight(1f),
                    ) {
                        Text(
                            stringResource(R.string.batch_bg_restore_all),
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                }
                val photoCount = CharacterState.entries.sumOf { s ->
                    (if (vm.results[s] != null) 1 else 0) + (if (vm.resultsFrame1[s] != null) 1 else 0)
                }
                TextButton(
                    onClick = onSaveAll,
                    enabled = !vm.isSavingPhotos,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        stringResource(
                            if (vm.isSavingPhotos) R.string.batch_saving
                            else R.string.batch_save_all,
                            photoCount,
                        ),
                    )
                }
            }
        }
    }
}

@Composable
private fun ResultCard(vm: BatchGenViewModel, state: CharacterState) {
    val applied = state in vm.appliedStates
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box {
            vm.displayedImage(state, 0)?.let { bmp ->
                Image(
                    bitmap = bmp.asImageBitmap(),
                    contentDescription = state.koreanShortLabel,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(120.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .clickable { vm.openDetail(state) },
                )
            }
            // frame1 미니 썸네일 (우하단)
            vm.displayedImage(state, 1)?.let { f1 ->
                Image(
                    bitmap = f1.asImageBitmap(),
                    contentDescription = null,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(4.dp)
                        .size(40.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .border(2.dp, Color.White, RoundedCornerShape(8.dp)),
                )
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                state.koreanShortLabel,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.weight(1f),
            )
            if (applied) {
                Icon(
                    Icons.Filled.Check, contentDescription = null,
                    tint = WithuColors.systemGreen, modifier = Modifier.size(14.dp),
                )
            }
        }
        if (applied) {
            TextButton(onClick = {}, enabled = false, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.batch_applied))
            }
        } else {
            WithuPinkButton(
                text = stringResource(R.string.batch_apply),
                onClick = { vm.applyOne(state) },
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun ErrorCard(vm: BatchGenViewModel, state: CharacterState) {
    val enabled = !vm.isGenerating
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(120.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(WithuColors.systemOrange.copy(alpha = 0.12f))
                .clickable(enabled = enabled) { vm.retryOne(state) },
            contentAlignment = Alignment.Center,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Icon(
                    Icons.Filled.Refresh, contentDescription = null,
                    tint = WithuColors.systemOrange, modifier = Modifier.size(24.dp),
                )
                Text(
                    stringResource(R.string.batch_retry_card),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurface,
                )
            }
        }
        Text(
            state.koreanShortLabel,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Medium,
        )
        vm.errors[state]?.let { msg ->
            Text(
                msg,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ============================================================================
// (H) 상세 시트
// ============================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ResultDetailSheet(
    vm: BatchGenViewModel,
    state: CharacterState,
    onPickAlbum: () -> Unit,
    onSave: (Int) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val hasFrame1 = vm.resultsFrame1[state] != null
    val pageCount = if (hasFrame1) 2 else 1
    val pagerState = rememberPagerState(pageCount = { pageCount })

    // 페이저 페이지 ↔ vm.detailFrame 동기화 (reviseOne/저장이 참조).
    LaunchedEffect(pagerState) {
        snapshotFlow { pagerState.currentPage }.collect { vm.detailFrame = it }
    }

    ModalBottomSheet(
        onDismissRequest = { vm.closeDetail() },
        sheetState = sheetState,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    stringResource(R.string.batch_detail_title),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = { vm.closeDetail() }) {
                    Text(stringResource(R.string.common_close))
                }
            }

            // 1) 프레임 페이저
            HorizontalPager(
                state = pagerState,
                modifier = Modifier.fillMaxWidth().height(320.dp),
            ) { page ->
                vm.displayedImage(state, page)?.let { bmp ->
                    Image(
                        bitmap = bmp.asImageBitmap(),
                        contentDescription = null,
                        modifier = Modifier.fillMaxSize().padding(8.dp),
                    )
                }
            }

            // 2) 캡션
            Text(
                text = if (hasFrame1) {
                    stringResource(
                        if (vm.detailFrame == 1) R.string.batch_frame_caption_f1
                        else R.string.batch_frame_caption_base,
                        state.koreanShortLabel,
                    )
                } else {
                    state.koreanShortLabel
                },
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // 3) 배경 세그먼트 — 선택 즉시 적용까지 일어남 (표시만 X).
            val transparent = vm.displayTransparent(state)
            Text(
                stringResource(R.string.batch_bg_picker),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                SegmentedButton(
                    selected = !transparent,
                    onClick = { vm.applyTransparentOne(state, false) },
                    shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2),
                ) { Text(stringResource(R.string.batch_bg_white)) }
                SegmentedButton(
                    selected = transparent,
                    onClick = { vm.applyTransparentOne(state, true) },
                    shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2),
                ) { Text(stringResource(R.string.batch_bg_transparent)) }
            }

            // 4) frame1 있을 때만: 프레임 바꾸기 + 움직임 토글
            if (hasFrame1) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = { vm.swapDetailFrames(state) }) {
                        Text(stringResource(R.string.batch_swap_frames))
                    }
                    Spacer(Modifier.weight(1f))
                    // B-9: iOS Toggle(...).labelsHidden() — 라벨 없는 스위치.
                    Switch(
                        checked = vm.isMotionOn(state),
                        onCheckedChange = { vm.setMotionOn(state, it) },
                    )
                }
            }

            // 5) 수정 입력
            Text(
                stringResource(
                    if (vm.detailFrame == 1) R.string.batch_revise_q_f1 else R.string.batch_revise_q,
                ),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Medium,
            )
            OutlinedTextField(
                value = vm.revisionText,
                onValueChange = { vm.revisionText = it },
                placeholder = { Text(stringResource(R.string.batch_revise_placeholder)) },
                minLines = 2, maxLines = 4,
                modifier = Modifier.fillMaxWidth(),
            )
            // 수정용 참고사진
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                RefThumb(bitmap = vm.revisionRefImage, size = 36)
                TextButton(onClick = onPickAlbum) {
                    Text(
                        stringResource(
                            if (vm.revisionRefImage == null) R.string.batch_ref_add
                            else R.string.batch_ref_change,
                        ),
                    )
                }
                if (vm.revisionRefImage != null) {
                    TextButton(onClick = { vm.revisionRefImage = null }) {
                        Text(
                            stringResource(R.string.batch_ref_remove_small),
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                }
            }

            // 6) 저장 / 바꾸기
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(
                    onClick = { onSave(vm.detailFrame) },
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(R.string.common_save)) }
                WithuCTAButton(
                    text = stringResource(R.string.batch_revise_cta),
                    onClick = { vm.reviseOne(state, vm.detailFrame, vm.revisionText) },
                    enabled = vm.revisionText.isNotBlank(),
                    loading = vm.isRevising,
                    modifier = Modifier.weight(1f),
                )
            }

            // 7) 수정 에러 — 조용한 실패 금지.
            vm.revisionError?.let { err ->
                Text(
                    err,
                    style = MaterialTheme.typography.labelSmall,
                    color = WithuColors.systemOrange,
                )
            }
        }
    }
}

// ============================================================================
// 공용 헬퍼
// ============================================================================

/** 참고사진 썸네일 — 없으면 사진 아이콘 placeholder. */
@Composable
private fun RefThumb(bitmap: Bitmap?, size: Int) {
    val shape = RoundedCornerShape(8.dp)
    Box(
        Modifier
            .size(size.dp)
            .clip(shape)
            .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.10f))
            .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f), shape),
        contentAlignment = Alignment.Center,
    ) {
        if (bitmap != null) {
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            Icon(
                Icons.Filled.Photo,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                modifier = Modifier.size((size * 0.5f).dp),
            )
        }
    }
}

/** 생성 중 CTA — UiKit 버튼은 스피너+텍스트 동시 표기가 안 돼 자체 구성 (초록 배경). */
@Composable
private fun ProgressCTAButton(text: String) {
    Box(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(com.seoyoung.withu.ui.theme.withuCTAGreen())
            .padding(horizontal = 14.dp, vertical = 11.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp, color = Color.White)
            Text(
                text,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
            )
        }
    }
}

private fun imageOnly(): PickVisualMediaRequest =
    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)

/** Photo Picker Uri → 다운샘플 Bitmap (OOM 방지). */
private fun decodeDownsampled(context: Context, uri: Uri): Bitmap? = try {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    context.contentResolver.openInputStream(uri)?.use {
        BitmapFactory.decodeStream(it, null, bounds)
    }
    val dm = context.resources.displayMetrics
    val maxTarget = maxOf(dm.widthPixels, dm.heightPixels) * 2
    val maxDim = maxOf(bounds.outWidth, bounds.outHeight)
    var sample = 1
    while (maxDim / (sample * 2) > maxTarget) sample *= 2
    val opts = BitmapFactory.Options().apply {
        inSampleSize = sample
        inPreferredConfig = Bitmap.Config.ARGB_8888
    }
    context.contentResolver.openInputStream(uri)?.use {
        BitmapFactory.decodeStream(it, null, opts)
    }
} catch (_: Exception) {
    null
}
