package com.seoyoung.withu.gen

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import com.seoyoung.withu.R
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.paywall.PaywallSheet
import com.seoyoung.withu.ui.CandyBadge
import com.seoyoung.withu.ui.FormSection
import com.seoyoung.withu.ui.WarningBanner
import com.seoyoung.withu.ui.WithuCTAButton
import com.seoyoung.withu.ui.rememberBackgroundGradient
import com.seoyoung.withu.ui.theme.WithuColors
import com.seoyoung.withu.ui.theme.withuPinkText
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 단건 생성 화면 — iOS CharacterGenView.swift 포팅 (스펙 02).
 * 위→아래 섹션: 배치 진입 · 생성 옵션(모드) · 상태 · (AI) 프롬프트/참고사진/스타일/만들기/결과/다듬기/이력
 * · (import) 사진 고르기/미리보기. 네비게이션은 콜백(onOpenBatch)만.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SingleGenScreen(onOpenBatch: () -> Unit) {
    val vm: SingleGenViewModel = viewModel()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // 화면 진입 시 잔량 갱신 (iOS onAppear — 무료 배지가 옛 캐시로 뜨는 것 방지)
    LaunchedEffect(Unit) { vm.refreshQuota() }

    // 폼 스크롤 시 키보드 해제 (iOS .scrollDismissesKeyboard(.interactively) 대응)
    val scrollState = rememberScrollState()
    val focusManager = LocalFocusManager.current
    LaunchedEffect(scrollState.isScrollInProgress) {
        if (scrollState.isScrollInProgress) focusManager.clearFocus()
    }

    // 적용/저장 성공·실패 햅틱 (iOS UINotificationFeedbackGenerator .success/.error)
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(vm.hapticSignal) {
        when (vm.hapticSignal) {
            HapticSignal.SUCCESS -> haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            HapticSignal.ERROR -> {
                // 실패는 두 번 울려 성공과 구분 (Compose 1.7 은 success/error 타입이 없음)
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                delay(120)
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            }
            null -> Unit
        }
        if (vm.hapticSignal != null) vm.consumeHaptic()
    }

    // 앨범 참고사진 픽커 (Photo Picker — 권한 불필요)
    val referencePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia(),
    ) { uri ->
        if (uri != null) scope.launch {
            val bmp = withContext(Dispatchers.IO) { decodeDownsampledBitmap(context, uri) }
            if (bmp != null) vm.pickedAlbumReference(bmp) else vm.onPhotoLoadFailed()
        }
    }
    // import 모드 사진 픽커
    val importPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia(),
    ) { uri ->
        if (uri != null) scope.launch {
            val bmp = withContext(Dispatchers.IO) { decodeDownsampledBitmap(context, uri) }
            if (bmp != null) vm.pickedImportPhoto(bmp) else vm.onPhotoLoadFailed()
        }
    }

    val gradient = rememberBackgroundGradient(vm.targetState)

    Box(Modifier.fillMaxSize()) {
        Scaffold(
            containerColor = Color.Transparent,
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.gen_title)) },
                    actions = {
                        CandyBadge(candy = vm.displayedCandy) { vm.showPaywall = true }
                        Spacer(Modifier.width(8.dp))
                    },
                )
            },
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .background(gradient)
                    .padding(padding)
                    .verticalScroll(scrollState)
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                BatchSection(onOpenBatch)
                ModeSection(vm)
                StateSection(vm)

                if (vm.mode == GenerationMode.AI_GENERATE) {
                    PromptSection(vm)
                    ReferenceSection(vm, onPickAlbum = {
                        referencePicker.launch(
                            PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                        )
                    })
                    OptionsSection(vm)
                    GenerateButtonSection(vm)
                    ResultSection(vm)
                    RefinementSection(vm)
                    VersionHistorySection(vm)
                } else {
                    ImportSection(vm, onPick = {
                        importPicker.launch(
                            PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                        )
                    })
                    ImportResultSection(vm)
                }
                Spacer(Modifier.size(24.dp))
            }
        }

        // 정사각 크롭 풀스크린 (사진 선택 직후 강제 크롭)
        vm.cropTarget?.let { req ->
            SquareCropView(
                source = req.source,
                onDone = { cropped -> req.onDone(cropped); vm.cropTarget = null },
                onCancel = { vm.cropTarget = null },
            )
        }
    }

    // 내 캐릭터에서 참고사진 선택 시트
    if (vm.showGalleryRefPicker) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { vm.showGalleryRefPicker = false },
            sheetState = sheetState,
        ) {
            GalleryReferencePicker(
                onPick = { bmp -> vm.pickedGalleryReference(bmp); vm.showGalleryRefPicker = false },
                onClose = { vm.showGalleryRefPicker = false },
            )
        }
    }

    // 페이월 (전체화면 다이얼로그 — 닫히면 잔량 갱신)
    if (vm.showPaywall) {
        Dialog(
            onDismissRequest = { vm.onPaywallClosed() },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            PaywallSheet(onClose = { vm.onPaywallClosed() })
        }
    }

    // 캔디 안내 팝업 — 만들기/다듬기는 확인 후에만 실행
    CandyDialog(vm)

    // 적용/저장 알림
    if (vm.showAppliedAlert) {
        AlertDialog(
            onDismissRequest = { vm.showAppliedAlert = false },
            title = { Text(stringResource(R.string.gen_alert_applied_title)) },
            text = {
                Text(stringResource(R.string.gen_alert_applied_body, vm.targetState.koreanShortLabel))
            },
            confirmButton = {
                TextButton(onClick = { vm.showAppliedAlert = false }) {
                    Text(stringResource(R.string.common_confirm))
                }
            },
        )
    }
    if (vm.showSavedAlert) {
        AlertDialog(
            onDismissRequest = { vm.showSavedAlert = false },
            title = { Text(stringResource(R.string.gen_alert_saved_title)) },
            text = { Text(stringResource(R.string.gen_alert_saved_body)) },
            confirmButton = {
                TextButton(onClick = { vm.showSavedAlert = false }) {
                    Text(stringResource(R.string.common_confirm))
                }
            },
        )
    }
}

// MARK: - 공통 섹션

/** 배치 생성 진입 — 처음 시작하는 사용자가 가장 먼저 보게. */
@Composable
private fun BatchSection(onOpenBatch: () -> Unit) {
    FormSection {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onOpenBatch)
                .padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    text = stringResource(R.string.gen_batch_title),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = stringResource(R.string.gen_batch_subtitle),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            )
        }
    }
}

/** 생성 옵션 — AI 생성 / 내 이미지 (라디오형, 체크마크 표시). */
@Composable
private fun ModeSection(vm: SingleGenViewModel) {
    // AI 생성 모드는 footer 설명 없음 (iOS 와 동일 — 사용자 요청으로 삭제)
    val footer = if (vm.mode == GenerationMode.AI_GENERATE) {
        null
    } else {
        stringResource(R.string.gen_mode_footer_import)
    }
    val disabled = vm.isGenerating || vm.isProcessing
    FormSection(header = stringResource(R.string.gen_mode_header), footer = footer) {
        ModeRow(stringResource(R.string.gen_mode_ai), vm.mode == GenerationMode.AI_GENERATE, disabled) {
            vm.selectMode(GenerationMode.AI_GENERATE)
        }
        ModeRow(stringResource(R.string.gen_mode_import), vm.mode == GenerationMode.IMPORT_PHOTO, disabled) {
            vm.selectMode(GenerationMode.IMPORT_PHOTO)
        }
    }
}

@Composable
private fun ModeRow(label: String, selected: Boolean, disabled: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = !disabled, onClick = onClick)
            .padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        if (selected) {
            Icon(Icons.Filled.Check, contentDescription = null, tint = withuPinkText())
        }
    }
}

/** 상태 선택 (메뉴 — userFacing 목록, 라벨 = koreanShortLabel). */
@Composable
private fun StateSection(vm: SingleGenViewModel) {
    var expanded by remember { mutableStateOf(false) }
    val disabled = vm.isGenerating || vm.isProcessing
    FormSection(header = stringResource(R.string.gen_state_header)) {
        Box {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(enabled = !disabled) { expanded = true }
                    .padding(vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = vm.targetState.koreanShortLabel,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f),
                )
                Icon(
                    Icons.Filled.KeyboardArrowDown,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                CharacterState.userFacing.forEach { s ->
                    DropdownMenuItem(
                        text = { Text(s.koreanShortLabel) },
                        onClick = { vm.selectTargetState(s); expanded = false },
                    )
                }
            }
        }
    }
}

// MARK: - AI 생성 섹션

/** 캐릭터 프롬프트 — 자유 설명 + 항목별 입력 도우미. */
@Composable
private fun PromptSection(vm: SingleGenViewModel) {
    FormSection(header = stringResource(R.string.gen_prompt_header)) {
        Text(
            text = stringResource(R.string.gen_prompt_caption),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.size(8.dp))
        OutlinedTextField(
            value = vm.prompt,
            onValueChange = { vm.prompt = it },
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 100.dp),
            placeholder = { Text(stringResource(R.string.gen_prompt_placeholder)) },
            enabled = !vm.isGenerating,
        )
        Spacer(Modifier.size(8.dp))
        ExpandableRow(title = stringResource(R.string.gen_helper_disclosure)) {
            HelperFieldRow(
                label = stringResource(R.string.gen_helper_subject_label),
                value = vm.subjectField,
                placeholder = stringResource(R.string.gen_helper_subject_placeholder),
                enabled = !vm.isGenerating,
                onChange = vm::updateSubjectField,
            )
            HelperFieldRow(
                label = stringResource(R.string.gen_helper_looks_label),
                value = vm.looksField,
                placeholder = stringResource(R.string.gen_helper_looks_placeholder),
                enabled = !vm.isGenerating,
                onChange = vm::updateLooksField,
            )
            HelperFieldRow(
                label = stringResource(R.string.gen_helper_color_label),
                value = vm.colorField,
                placeholder = stringResource(R.string.gen_helper_color_placeholder),
                enabled = !vm.isGenerating,
                onChange = vm::updateColorField,
            )
            Text(
                text = stringResource(R.string.gen_helper_caption),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun HelperFieldRow(
    label: String,
    value: String,
    placeholder: String,
    enabled: Boolean,
    onChange: (String) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(72.dp),
        )
        OutlinedTextField(
            value = value,
            onValueChange = onChange,
            modifier = Modifier.weight(1f),
            placeholder = { Text(placeholder, style = MaterialTheme.typography.bodySmall) },
            singleLine = true,
            enabled = enabled,
        )
    }
}

/** 참고 사진 (Optional) — 앨범/내 캐릭터 선택 + keep/change 입력. */
@Composable
private fun ReferenceSection(vm: SingleGenViewModel, onPickAlbum: () -> Unit) {
    val hasRef = vm.referenceImage != null
    val footer = if (hasRef) {
        stringResource(R.string.gen_ref_footer_has)
    } else {
        stringResource(R.string.gen_ref_footer_none)
    }
    FormSection(header = stringResource(R.string.gen_ref_header), footer = footer) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            val ref = vm.referenceImage
            Box(
                Modifier
                    .size(64.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.15f)),
                contentAlignment = Alignment.Center,
            ) {
                if (ref != null) {
                    Image(
                        bitmap = ref.asImageBitmap(),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    Icon(
                        Icons.Filled.Photo,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Spacer(Modifier.width(12.dp))
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedButton(
                    onClick = onPickAlbum,
                    enabled = !vm.isGenerating,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(stringResource(R.string.gen_ref_pick_album)) }
                OutlinedButton(
                    onClick = { vm.showGalleryRefPicker = true },
                    enabled = !vm.isGenerating,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(stringResource(R.string.gen_ref_pick_gallery)) }
            }
        }
        if (hasRef) {
            Spacer(Modifier.size(8.dp))
            TextButton(
                onClick = { vm.removeReference() },
                enabled = !vm.isGenerating,
            ) {
                Text(stringResource(R.string.gen_ref_remove), color = MaterialTheme.colorScheme.error)
            }
            ReferenceHintField(
                label = stringResource(R.string.gen_ref_keep_label),
                value = vm.referenceKeep,
                placeholder = stringResource(R.string.gen_ref_keep_placeholder),
                examples = stringResource(R.string.gen_ref_keep_examples),
                enabled = !vm.isGenerating,
                onChange = { vm.referenceKeep = it },
            )
            ReferenceHintField(
                label = stringResource(R.string.gen_ref_change_label),
                value = vm.referenceChange,
                placeholder = stringResource(R.string.gen_ref_change_placeholder),
                examples = stringResource(R.string.gen_ref_change_examples),
                enabled = !vm.isGenerating,
                onChange = { vm.referenceChange = it },
            )
        }
    }
}

@Composable
private fun ReferenceHintField(
    label: String,
    value: String,
    placeholder: String,
    examples: String,
    enabled: Boolean,
    onChange: (String) -> Unit,
) {
    Column(Modifier.padding(top = 8.dp)) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        OutlinedTextField(
            value = value,
            onValueChange = onChange,
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text(placeholder, style = MaterialTheme.typography.bodySmall) },
            enabled = enabled,
        )
        Text(
            text = examples,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}

/** 스타일 — Soft(casual) / Pixel. */
@Composable
private fun OptionsSection(vm: SingleGenViewModel) {
    FormSection(header = stringResource(R.string.gen_style_header)) {
        SegmentedTwo(
            leftLabel = stringResource(R.string.gen_style_soft),
            rightLabel = stringResource(R.string.gen_style_pixel),
            leftSelected = vm.artStyle == "casual",
            enabled = !vm.isGenerating,
            onLeft = { vm.artStyle = "casual" },
            onRight = { vm.artStyle = "pixel" },
        )
    }
}

/** 만들기 버튼 섹션 — 진행 중 / 충전 / 일반(토글 + CTA)의 3분기. */
@Composable
private fun GenerateButtonSection(vm: SingleGenViewModel) {
    // 경과 초 (0.5초 틱)
    var elapsed by remember { mutableIntStateOf(0) }
    LaunchedEffect(vm.isGenerating, vm.generationStartedAt) {
        val started = vm.generationStartedAt
        if (vm.isGenerating && started != null) {
            while (isActive) {
                elapsed = ((System.currentTimeMillis() - started) / 1000).toInt()
                delay(500)
            }
        } else {
            elapsed = 0
        }
    }

    val unitCost = vm.unitCost
    val footerGenerating = stringResource(R.string.gen_footer_generating)
    val footerWaiting = stringResource(R.string.gen_footer_waiting)

    FormSection {
        if (vm.isGenerating) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(10.dp))
                Text(
                    text = if (vm.generationStartedAt != null) {
                        stringResource(R.string.gen_progress, elapsed)
                    } else {
                        stringResource(R.string.gen_progress_nostart)
                    },
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            Spacer(Modifier.size(10.dp))
            TextButton(onClick = { vm.cancelGeneration() }) {
                Text(stringResource(R.string.gen_cancel), color = MaterialTheme.colorScheme.error)
            }
        } else if (vm.remainingGenerations < unitCost && !vm.hasFreeCreation) {
            OutlinedButton(
                onClick = { vm.showPaywall = true },
                modifier = Modifier.fillMaxWidth(),
            ) { Text(stringResource(R.string.gen_recharge)) }
        } else {
            // 2프레임이 의미 있는 상태만 토글 노출
            if (vm.targetState.usesGeneratedMotion) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        stringResource(R.string.gen_animate_toggle),
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.weight(1f),
                    )
                    Switch(checked = vm.generateAnimated, onCheckedChange = { vm.generateAnimated = it })
                }
                Spacer(Modifier.size(4.dp))
            }
            // 참고 사진이 있으면 설명 없이도 생성 가능
            val ctaEnabled = vm.prompt.trim().isNotEmpty() || vm.referenceImage != null
            WithuCTAButton(
                text = stringResource(R.string.gen_cta),
                onClick = { vm.requestGenerate() },
                modifier = Modifier.fillMaxWidth(),
                enabled = ctaEnabled,
            )
        }

        Spacer(Modifier.size(8.dp))
        // footer — 2줄 (진행/대기 + 무료/부족/일반)
        Text(
            text = if (vm.isGenerating) footerGenerating else footerWaiting,
            style = MaterialTheme.typography.labelSmall,
            color = if (vm.isGenerating) WithuColors.systemOrange else MaterialTheme.colorScheme.onSurfaceVariant,
        )
        when {
            vm.hasFreeCreation -> Text(
                stringResource(R.string.gen_footer_free),
                style = MaterialTheme.typography.labelSmall,
                color = withuPinkText(),
            )
            vm.remainingGenerations < unitCost -> Text(
                stringResource(R.string.gen_footer_insufficient),
                style = MaterialTheme.typography.labelSmall,
                color = WithuColors.systemOrange,
            )
            else -> Text(
                stringResource(R.string.gen_footer_normal, vm.remainingGenerations, vm.newGenerationCost),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** 결과 섹션 — 프레임 스와이프/배경 토글/실제 프롬프트/적용·저장. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ResultSection(vm: SingleGenViewModel) {
    if (vm.resultImage == null) {
        vm.lastError?.let { WarningBanner(it) }
        return
    }
    FormSection(header = stringResource(R.string.gen_result_header)) {
        // 다듬은 버전 배지
        val current = vm.versions.getOrNull(vm.selectedVersion)
        if (current?.isRefined == true) {
            Text(
                text = stringResource(R.string.gen_result_refined_badge, vm.selectedVersion),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = withuPinkText(),
            )
            Spacer(Modifier.size(8.dp))
        }

        val f0 = vm.currentDisplay(0)
        val f1 = vm.currentDisplay(1)
        if (f0 != null && f1 != null) {
            val pagerState = rememberPagerState(initialPage = vm.singleDetailFrame) { 2 }
            LaunchedEffect(pagerState.currentPage) { vm.singleDetailFrame = pagerState.currentPage }
            LaunchedEffect(vm.singleDetailFrame) {
                if (pagerState.currentPage != vm.singleDetailFrame) {
                    pagerState.animateScrollToPage(vm.singleDetailFrame)
                }
            }
            HorizontalPager(
                state = pagerState,
                modifier = Modifier.fillMaxWidth().heightIn(min = 260.dp, max = 260.dp),
            ) { page ->
                val img = if (page == 0) f0 else f1
                Image(
                    bitmap = img.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)),
                )
            }
            // 점 인디케이터
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
                horizontalArrangement = Arrangement.Center,
            ) {
                repeat(2) { i ->
                    Box(
                        Modifier
                            .padding(horizontal = 3.dp)
                            .size(6.dp)
                            .clip(CircleShape)
                            .background(
                                if (i == pagerState.currentPage) {
                                    MaterialTheme.colorScheme.onSurface
                                } else {
                                    MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)
                                },
                            ),
                    )
                }
            }
            Text(
                text = if (vm.singleDetailFrame == 1) {
                    stringResource(R.string.gen_frame_second)
                } else {
                    stringResource(R.string.gen_frame_first)
                },
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        } else if (f0 != null) {
            // iOS: resizable().scaledToFit() — full width, 높이 캡 없음 (260 은 pager 전용).
            Image(
                bitmap = f0.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp)),
            )
        }

        Spacer(Modifier.size(12.dp))
        // 배경 토글
        SegmentedTwo(
            leftLabel = stringResource(R.string.gen_bg_white),
            rightLabel = stringResource(R.string.gen_bg_transparent),
            leftSelected = !vm.displayTransparent,
            enabled = true,
            onLeft = { vm.displayTransparent = false },
            onRight = { vm.displayTransparent = true },
        )

        // 실제 사용한 설명
        vm.revisedPrompt?.let { revised ->
            Spacer(Modifier.size(8.dp))
            ExpandableRow(title = stringResource(R.string.gen_revised_disclosure)) {
                Text(
                    text = revised,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        Spacer(Modifier.size(12.dp))
        WithuCTAButton(
            text = stringResource(R.string.gen_apply_cta, vm.targetState.koreanShortLabel),
            onClick = { vm.applyCurrentSelection() },
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.size(4.dp))
        TextButton(
            onClick = { vm.saveCurrentResultToPhotos() },
            modifier = Modifier.fillMaxWidth(),
        ) { Text(stringResource(R.string.gen_save_photos)) }
    }
    vm.lastError?.let {
        Spacer(Modifier.size(12.dp))
        WarningBanner(it)
    }
}

/** 이어서 다듬기. */
@Composable
private fun RefinementSection(vm: SingleGenViewModel) {
    if (vm.resultImage == null) return
    val motionFrame = vm.resultFrame2 != null && vm.singleDetailFrame == 1
    val header = if (motionFrame) {
        stringResource(R.string.gen_refine_header_motion)
    } else {
        stringResource(R.string.gen_refine_header)
    }
    FormSection(header = header, footer = stringResource(R.string.gen_refine_footer)) {
        OutlinedTextField(
            value = vm.refinementPrompt,
            onValueChange = { vm.refinementPrompt = it },
            modifier = Modifier.fillMaxWidth().heightIn(min = 80.dp),
            enabled = !vm.isGenerating,
        )
        Spacer(Modifier.size(8.dp))
        val enabled = !vm.isGenerating && vm.refinementPrompt.trim().isNotEmpty()
        if (vm.isGenerating) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(10.dp))
                Text(
                    stringResource(R.string.gen_refine_button_progress),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            OutlinedButton(
                onClick = { vm.requestRefine() },
                enabled = enabled,
                modifier = Modifier.fillMaxWidth(),
            ) { Text(stringResource(R.string.gen_refine_button)) }
        }
    }
}

/** 다듬기 이력 — 원본/다듬음 썸네일 가로 스크롤. */
@Composable
private fun VersionHistorySection(vm: SingleGenViewModel) {
    if (vm.resultImage == null || vm.versions.size <= 1) return
    FormSection(
        header = stringResource(R.string.gen_history_header),
        footer = stringResource(R.string.gen_history_footer),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            vm.versions.forEachIndexed { idx, v ->
                val selected = idx == vm.selectedVersion
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.clickable { vm.selectVersion(idx) },
                ) {
                    Image(
                        bitmap = v.small.asImageBitmap(),
                        contentDescription = null,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier
                            .size(72.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(MaterialTheme.colorScheme.background)
                            .border(
                                width = 2.5.dp,
                                color = if (selected) withuPinkText() else Color.Transparent,
                                shape = RoundedCornerShape(10.dp),
                            ),
                    )
                    Spacer(Modifier.size(4.dp))
                    Text(
                        text = if (v.isRefined) {
                            stringResource(R.string.gen_history_refined, idx)
                        } else {
                            stringResource(R.string.gen_history_original)
                        },
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                        color = if (selected) withuPinkText() else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

// MARK: - import 섹션

/** 사진 고르기. */
@Composable
private fun ImportSection(vm: SingleGenViewModel, onPick: () -> Unit) {
    FormSection(
        header = stringResource(R.string.gen_import_header),
        footer = stringResource(R.string.gen_import_footer),
    ) {
        OutlinedButton(
            onClick = onPick,
            enabled = !vm.isProcessing,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                if (vm.importedRawImage == null) {
                    stringResource(R.string.gen_import_pick)
                } else {
                    stringResource(R.string.gen_import_pick_change)
                },
            )
        }
        if (vm.isProcessing) {
            Spacer(Modifier.size(8.dp))
            ProcessingRow(stringResource(R.string.gen_import_processing))
        }
    }
}

/** 미리보기 — 배경 빼기 토글 + 적용/저장. */
@Composable
private fun ImportResultSection(vm: SingleGenViewModel) {
    val display = vm.displayedImport()
    if (display != null) {
        FormSection(header = stringResource(R.string.gen_import_result_header)) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    stringResource(R.string.gen_import_toggle_removebg),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f),
                )
                Switch(
                    checked = vm.removeBackground,
                    onCheckedChange = { vm.removeBackground = it },
                    enabled = !vm.isProcessing,
                )
            }
            Spacer(Modifier.size(8.dp))
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 300.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant),
                contentAlignment = Alignment.Center,
            ) {
                Image(
                    bitmap = display.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            if (vm.isProcessing) {
                Spacer(Modifier.size(8.dp))
                ProcessingRow(stringResource(R.string.gen_import_bg_processing))
            }
            Spacer(Modifier.size(12.dp))
            WithuCTAButton(
                text = stringResource(R.string.gen_apply_cta, vm.targetState.koreanShortLabel),
                onClick = { vm.applyImportSelection() },
                modifier = Modifier.fillMaxWidth(),
                enabled = !(vm.removeBackground && vm.isProcessing),
            )
            Spacer(Modifier.size(4.dp))
            TextButton(
                onClick = { vm.displayedImport()?.let { vm.saveToPhotos(it) } },
                modifier = Modifier.fillMaxWidth(),
            ) { Text(stringResource(R.string.gen_save_photos)) }
        }
    }
    vm.lastError?.let {
        Spacer(Modifier.size(12.dp))
        WarningBanner(it)
    }
}

// MARK: - 캔디 팝업

@Composable
private fun CandyDialog(vm: SingleGenViewModel) {
    val action = vm.pendingAction ?: return
    val isRefine = action is PendingAction.Refine
    val cost = if (isRefine) vm.unitCost else vm.newGenerationCost
    val free = vm.hasFreeCreation
    AlertDialog(
        onDismissRequest = { vm.dismissPendingAction() },
        title = {
            Text(
                if (free) {
                    stringResource(R.string.gen_candy_title_free)
                } else {
                    stringResource(R.string.gen_candy_title_normal)
                },
            )
        },
        text = {
            Text(
                when {
                    free -> stringResource(R.string.gen_candy_body_free)
                    isRefine -> stringResource(R.string.gen_candy_body_refine, cost)
                    else -> stringResource(R.string.gen_candy_body_new, cost)
                },
            )
        },
        confirmButton = {
            TextButton(onClick = { vm.confirmPendingAction() }) {
                Text(
                    if (isRefine) {
                        stringResource(R.string.gen_candy_confirm_refine)
                    } else {
                        stringResource(R.string.gen_candy_confirm_new)
                    },
                )
            }
        },
        dismissButton = {
            TextButton(onClick = { vm.dismissPendingAction() }) {
                Text(stringResource(R.string.common_cancel))
            }
        },
    )
}

// MARK: - 소형 재사용 컴포넌트 (자기 파일 private)

/** 접이식 그룹 — iOS DisclosureGroup 대응. */
@Composable
private fun ExpandableRow(title: String, content: @Composable ColumnScope.() -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { expanded = !expanded }
                .padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(title, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            Icon(
                Icons.Filled.KeyboardArrowDown,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        AnimatedVisibility(visible = expanded) {
            Column(content = content)
        }
    }
}

/** 2분할 세그먼트 컨트롤 — iOS segmented Picker 대응. */
@Composable
private fun SegmentedTwo(
    leftLabel: String,
    rightLabel: String,
    leftSelected: Boolean,
    enabled: Boolean,
    onLeft: () -> Unit,
    onRight: () -> Unit,
) {
    val shape = RoundedCornerShape(8.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.12f))
            .padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        SegmentCell(leftLabel, leftSelected, enabled, Modifier.weight(1f), onLeft)
        SegmentCell(rightLabel, !leftSelected, enabled, Modifier.weight(1f), onRight)
    }
}

@Composable
private fun SegmentCell(
    label: String,
    selected: Boolean,
    enabled: Boolean,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .background(
                if (selected) MaterialTheme.colorScheme.surface else Color.Transparent,
            )
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            color = if (selected) {
                MaterialTheme.colorScheme.onSurface
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
        )
    }
}

/** 처리 중 한 줄 — 스피너 + 안내. */
@Composable
private fun ProcessingRow(text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
        Spacer(Modifier.width(10.dp))
        Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

// MARK: - 사진 디코딩

/** Photo Picker Uri → Bitmap. 화면 최대변 2배 이하로 inSampleSize 다운샘플 (OOM 방지). */
private fun decodeDownsampledBitmap(context: Context, uri: Uri): Bitmap? = try {
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
