package com.seoyoung.withu.profile

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Nightlight
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.seoyoung.withu.R
import com.seoyoung.withu.character.CharacterProfile
import com.seoyoung.withu.character.CharacterProfileStore
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.character.CharacterStateResolver
import com.seoyoung.withu.health.HealthManager
import com.seoyoung.withu.health.SleepSignals
import com.seoyoung.withu.shared.CharacterImageStore
import com.seoyoung.withu.shared.SharedAppState
import com.seoyoung.withu.shared.StoreEvents
import com.seoyoung.withu.sync.SyncCoordinator
import com.seoyoung.withu.ui.FormSection
import com.seoyoung.withu.ui.FrostedCard
import com.seoyoung.withu.ui.KoreanStateChip
import com.seoyoung.withu.ui.PixelToggle
import com.seoyoung.withu.ui.WithuTopBarTitle
import com.seoyoung.withu.ui.pixelInputField
import com.seoyoung.withu.ui.rememberBackgroundGradient
import com.seoyoung.withu.ui.withuInputColors
import java.time.LocalDateTime
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 내 캐릭터 설정 — iOS CharacterProfileView.swift 포팅 (스펙 05).
 *
 * 자동 저장이 아니라 **명시적 '저장'** — 편집은 초안(profile/animationEnabled)에만 담기고,
 * 반영(저장 + 상태 재판정 + 위젯 갱신)은 save() 에서만 일어난다 (iOS CharacterProfileView:214-223).
 * 저장 안 한 채 나가려 하면 확인 팝업 — Android 는 시스템 뒤로가기도 있어 BackHandler 로도 가로챈다.
 * '자는 중' 판정은 resolver 의 수면 분기와 어긋나면 안 되므로 수면 창 포함 판정은
 * CharacterStateResolver.isNowInSleepWindow 를 공유한다 (스펙 05 §3-2 주의사항).
 */

/** 시간 피커가 편집 중인 필드 — iOS 의 DatePicker 바인딩 6개 대응. */
private enum class TimeField { SLEEP_START, SLEEP_END, LUNCH, DINNER, NIGHT_START, NIGHT_END }

/**
 * 저장 안 된 변경이 있는지 — 초안이 마지막 저장 스냅샷과 다르면 true (iOS `hasChanges`).
 * CharacterProfile 은 data class 라 `!=` 비교가 그대로 동작한다.
 */
internal fun profileHasChanges(
    draft: CharacterProfile,
    saved: CharacterProfile,
    animationEnabled: Boolean,
    savedAnimationEnabled: Boolean,
): Boolean = draft != saved || animationEnabled != savedAnimationEnabled

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(onOpenStateFolder: (CharacterState) -> Unit, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()

    // 프로필 — 초안(profile)과 마지막 저장 스냅샷(savedProfile)을 나눠 들고 hasChanges 를 판정.
    var profile by remember { mutableStateOf(CharacterProfile()) }
    var savedProfile by remember { mutableStateOf(CharacterProfile()) }
    var profileLoaded by remember { mutableStateOf(false) }
    // 히어로 = 지금 적용 중인 상태 — iOS heroState. 저장 후에 최신 반영해야 함
    // (예전 버그: produceState 가 키 없이 한 번만 읽어 시간 바꿔도 아바타가 안 바뀜).
    var heroState by remember { mutableStateOf(CharacterState.IDLE) }
    LaunchedEffect(Unit) {
        val loaded = withContext(Dispatchers.IO) { CharacterProfileStore.load() }
        profile = loaded
        savedProfile = loaded
        profileLoaded = true
        heroState = withContext(Dispatchers.IO) { SyncCoordinator.currentState() }
    }

    // 애니메이션 토글 — 프로필이 아닌 이미지 스토어에 저장 (위젯도 읽어야 해서 분리, iOS 파리티).
    // 이것도 초안 — 저장 전에는 스토어에 안 쓴다.
    var animationEnabled by remember { mutableStateOf(true) }
    var savedAnimationEnabled by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        val on = withContext(Dispatchers.IO) { CharacterImageStore.isAnimationEnabled() }
        animationEnabled = on
        savedAnimationEnabled = on
    }

    val hasChanges = profileLoaded &&
        profileHasChanges(profile, savedProfile, animationEnabled, savedAnimationEnabled)
    // 저장 안 한 채 나가려 할 때 확인 팝업
    var showDiscardConfirm by remember { mutableStateOf(false) }

    /** 초안을 실제로 반영 — 저장 + 상태 재판정 + 위젯 갱신 + 스냅샷 갱신 (iOS save()). */
    suspend fun save() {
        val p = profile
        val anim = animationEnabled
        withContext(Dispatchers.IO) {
            CharacterProfileStore.save(p)
            CharacterImageStore.setAnimationEnabled(anim)
        }
        // syncNow 가 저장된 프로필로 상태를 다시 resolve 하고 위젯 갱신까지 담당.
        SyncCoordinator.syncNow()
        heroState = withContext(Dispatchers.IO) { SyncCoordinator.currentState() }
        savedProfile = p
        savedAnimationEnabled = anim
    }

    // 시스템 뒤로가기도 가로챈다 — 변경이 있으면 pop 대신 확인 팝업 (iOS 커스텀 뒤로 버튼 대응).
    BackHandler(enabled = hasChanges) { showDiscardConfirm = true }

    // 상태별 '내 캐릭터 적용됨' 여부 — 이미지 변경 이벤트에 반응해 다시 읽는다.
    var appliedStates by remember { mutableStateOf<Set<CharacterState>>(emptySet()) }
    LaunchedEffect(Unit) {
        suspend fun reload() {
            appliedStates = withContext(Dispatchers.IO) {
                CharacterState.userFacing.filter { CharacterImageStore.hasImage(it) }.toSet()
            }
        }
        reload()
        StoreEvents.characterImageChanged.collect { reload() }
    }

    // 수면 신호 — iOS FocusModeManager/HealthKit 대응 (스펙 05 §5 근사표).
    LaunchedEffect(Unit) { HealthManager.fetchInBedSchedule() }
    val isInBedSchedule by HealthManager.isInBedSchedule.collectAsState()
    val hasSleepSchedule by HealthManager.hasSleepSchedule.collectAsState()
    // profile 을 key 로 — 기준 칩/토글을 바꾸는 순간 DND 신호를 다시 읽어 판정 갱신.
    val dndOn by produceState(false, profile) { value = SleepSignals.isDndOn() }
    val dndOffAt by produceState<LocalDateTime?>(null, profile) {
        value = withContext(Dispatchers.IO) { SleepSignals.lastDndOffAt() }
    }
    // iOS focusFilterLastPerformAt != nil 근사 — DND 신호를 한 번이라도 관측했는지.
    val hasObservedDnd = dndOn || dndOffAt != null

    // 이름 편집 알럿
    var showNameEdit by remember { mutableStateOf(false) }
    var nameDraft by remember { mutableStateOf("") }

    // '최근 수면 시간에 맞추기' 진행/결과
    var isAligningSleep by remember { mutableStateOf(false) }
    var sleepAlignMessage by remember { mutableStateOf<String?>(null) }

    // 기준 칩에서 '수면 모드 기준' 선택 시 안내 팝업
    var showSleepBasisTip by remember { mutableStateOf(false) }

    // 시간 피커 다이얼로그
    var editingField by remember { mutableStateOf<TimeField?>(null) }

    val alignFail = stringResource(R.string.profile_align_fail)
    val alignSuccessFormat = stringResource(R.string.profile_align_success)

    Box(
        Modifier
            .fillMaxSize()
            .background(rememberBackgroundGradient(heroState)),
    ) {
        Scaffold(
            containerColor = Color.Transparent,
            topBar = {
                TopAppBar(
                    title = { WithuTopBarTitle(stringResource(R.string.profile_nav_title)) },
                    navigationIcon = {
                        IconButton(onClick = {
                            if (hasChanges) showDiscardConfirm = true else onBack()
                        }) {
                            Icon(
                                Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = stringResource(R.string.common_close),
                            )
                        }
                    },
                    // 수정이 생기면 상단에 '저장' 버튼 등장 (iOS toolbar topBarTrailing).
                    actions = {
                        if (hasChanges) {
                            TextButton(onClick = { scope.launch { save() } }) {
                                Text(
                                    stringResource(R.string.common_save),
                                    fontWeight = FontWeight.Bold,
                                )
                            }
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
                )
            },
        ) { padding ->
            Column(
                Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp)
                    .padding(bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                // 1-1. 히어로 카드 — 탭하면 이름 편집 (유일한 이름 편집 진입점)
                HeroCard(
                    heroState = heroState,
                    name = profile.name,
                    onClick = {
                        nameDraft = profile.name
                        showNameEdit = true
                    },
                )

                // 1-2. 수면 시간
                FormSection(
                    header = stringResource(R.string.profile_sleep_header),
                    footer = sleepFooterText(profile, hasObservedDnd, hasSleepSchedule),
                ) {
                    SleepStatusRow(
                        profile = profile,
                        dndOn = dndOn,
                        isInBedSchedule = isInBedSchedule,
                        onSetManual = { manual ->
                            profile = profile.copy(manualSleepOnly = manual)
                            // iOS: false 로 set 될 때마다 안내 팝업 (기존값 무관)
                            if (!manual) showSleepBasisTip = true
                        },
                    )
                    // 토글 켜짐 = 자동 감지 = manualSleepOnly false (바인딩 반전 주의)
                    ToggleRow(
                        label = stringResource(R.string.profile_auto_detect),
                        checked = !profile.isManualSleepOnly,
                        onCheckedChange = { profile = profile.copy(manualSleepOnly = !it) },
                    )
                    // '수면 모드 기준'(자동 감지)에선 아래 시간이 판정 기준이 아니라 회색+비활성.
                    val sleepTimesDisabled = !profile.isManualSleepOnly
                    TimeRow(
                        label = stringResource(R.string.profile_sleep_start),
                        hour = profile.sleepStartHour, minute = profile.sleepStartMinute,
                        enabled = !sleepTimesDisabled,
                        onClick = { editingField = TimeField.SLEEP_START },
                    )
                    TimeRow(
                        label = stringResource(R.string.profile_sleep_end),
                        hour = profile.sleepEndHour, minute = profile.sleepEndMinute,
                        enabled = !sleepTimesDisabled,
                        onClick = { editingField = TimeField.SLEEP_END },
                    )
                    // 최근 수면 시간에 맞추기 — 워치류 수면 추적은 '설정 시간'이 사실상 판정 기준이라
                    // 그 설정 시간을 실제 수면 패턴에 맞춰주는 버튼 (iOS 원본 주석의 '왜').
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp))
                            .alpha(if (sleepTimesDisabled) 0.4f else 1f)
                            .clickable(enabled = !isAligningSleep && !sleepTimesDisabled) {
                                isAligningSleep = true
                                sleepAlignMessage = null
                                scope.launch {
                                    try {
                                        val w = HealthManager.averageSleepWindow()
                                        if (w == null) {
                                            sleepAlignMessage = alignFail
                                        } else {
                                            profile = profile.copy(
                                                sleepStartHour = w.startHour,
                                                sleepStartMinute = w.startMinute,
                                                sleepEndHour = w.endHour,
                                                sleepEndMinute = w.endMinute,
                                            )
                                            sleepAlignMessage = String.format(
                                                Locale.US, alignSuccessFormat,
                                                w.startHour, w.startMinute, w.endHour, w.endMinute,
                                            )
                                        }
                                    } finally {
                                        isAligningSleep = false
                                    }
                                }
                            }
                            .padding(vertical = 10.dp, horizontal = 2.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Icon(
                            Icons.Filled.NightsStay,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(18.dp),
                        )
                        Text(
                            stringResource(R.string.profile_align_button),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Spacer(Modifier.weight(1f))
                        if (isAligningSleep) {
                            CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
                        }
                    }
                    sleepAlignMessage?.let { msg ->
                        Text(
                            msg,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 2.dp, vertical = 2.dp),
                        )
                    }
                }

                // 1-3. 식사 시간
                FormSection(
                    header = stringResource(R.string.profile_meal_header),
                    footer = stringResource(R.string.profile_meal_footer),
                ) {
                    TimeRow(
                        label = stringResource(R.string.profile_lunch),
                        hour = profile.lunchHour, minute = profile.lunchMinute,
                        onClick = { editingField = TimeField.LUNCH },
                    )
                    TimeRow(
                        label = stringResource(R.string.profile_dinner),
                        hour = profile.dinnerHour, minute = profile.dinnerMinute,
                        onClick = { editingField = TimeField.DINNER },
                    )
                }

                // 1-4. 밤하늘 시간 — 저장은 hour/minute 이 아니라 자정 기준 '분' 단일 Int (혼동 금지)
                FormSection(
                    header = stringResource(R.string.profile_night_header),
                    footer = stringResource(R.string.profile_night_footer),
                ) {
                    TimeRow(
                        label = stringResource(R.string.profile_night_start),
                        hour = profile.effectiveNightFallbackStart / 60,
                        minute = profile.effectiveNightFallbackStart % 60,
                        onClick = { editingField = TimeField.NIGHT_START },
                    )
                    TimeRow(
                        label = stringResource(R.string.profile_night_end),
                        hour = profile.effectiveNightFallbackEnd / 60,
                        minute = profile.effectiveNightFallbackEnd % 60,
                        onClick = { editingField = TimeField.NIGHT_END },
                    )
                }

                // 1-5. 상태별 캐릭터 — 탭하면 그 상태의 갤러리 폴더 (이동은 콜백만, Phase I 배선)
                FormSection(
                    header = stringResource(R.string.profile_states_header),
                    footer = stringResource(R.string.profile_states_footer),
                ) {
                    CharacterState.userFacing.forEach { state ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .clickable { onOpenStateFolder(state) }
                                .padding(vertical = 6.dp, horizontal = 2.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            KoreanStateChip(state = state, size = 44.dp)
                            Column(Modifier.weight(1f)) {
                                Text(
                                    state.koreanShortLabel,
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.Bold,
                                )
                                Text(
                                    stringResource(
                                        if (state in appliedStates) R.string.profile_state_applied
                                        else R.string.profile_state_default,
                                    ),
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

                // 1-6. 움직임
                FormSection(
                    header = stringResource(R.string.profile_motion_header),
                    footer = stringResource(R.string.profile_motion_footer),
                ) {
                    ToggleRow(
                        label = stringResource(R.string.profile_motion_toggle),
                        checked = animationEnabled,
                        onCheckedChange = { animationEnabled = it },
                    )
                }

                // 1-7. 캐릭터 외형 한 줄 (고급) — 접힘 기본 (iOS DisclosureGroup)
                AdvancedPromptSection(
                    value = profile.aiPrompt,
                    onValueChange = { profile = profile.copy(aiPrompt = it) },
                )
            }
        }
    }

    // 저장 안 하고 나가려 할 때 확인 — iOS confirmationDialog 3버튼 근사.
    // (Compose AlertDialog 은 confirm/dismiss 2슬롯뿐이라 '저장 안 하고 나가기'는 본문 안 버튼으로.)
    if (showDiscardConfirm) {
        AlertDialog(
            onDismissRequest = { showDiscardConfirm = false },
            title = { Text(stringResource(R.string.profile_discard_title)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(stringResource(R.string.profile_discard_message))
                    TextButton(
                        onClick = {
                            showDiscardConfirm = false
                            onBack()
                        },
                        modifier = Modifier.align(Alignment.Start),
                    ) {
                        Text(
                            stringResource(R.string.profile_discard_exit),
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    showDiscardConfirm = false
                    scope.launch {
                        save()
                        onBack()
                    }
                }) { Text(stringResource(R.string.profile_discard_save_exit)) }
            },
            dismissButton = {
                TextButton(onClick = { showDiscardConfirm = false }) {
                    Text(stringResource(R.string.profile_discard_keep))
                }
            },
        )
    }

    // 이름 편집 알럿
    if (showNameEdit) {
        AlertDialog(
            onDismissRequest = { showNameEdit = false },
            title = { Text(stringResource(R.string.profile_name_alert_title)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(stringResource(R.string.profile_name_alert_message))
                    OutlinedTextField(
                        value = nameDraft,
                        onValueChange = { nameDraft = it },
                        placeholder = { Text(stringResource(R.string.profile_name_placeholder)) },
                        singleLine = true,
                        colors = withuInputColors(),
                        modifier = Modifier.fillMaxWidth().pixelInputField(),
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    profile = profile.copy(name = nameDraft.trim())
                    showNameEdit = false
                }) { Text(stringResource(R.string.common_save)) }
            },
            dismissButton = {
                TextButton(onClick = { showNameEdit = false }) {
                    Text(stringResource(R.string.common_cancel))
                }
            },
        )
    }

    // 수면 기준 안내 팝업 — '수면 모드 기준' 선택 시
    if (showSleepBasisTip) {
        AlertDialog(
            onDismissRequest = { showSleepBasisTip = false },
            title = { Text(stringResource(R.string.profile_basis_tip_title)) },
            text = { Text(stringResource(R.string.profile_basis_tip_message)) },
            confirmButton = {
                TextButton(onClick = { showSleepBasisTip = false }) {
                    Text(stringResource(R.string.common_confirm))
                }
            },
        )
    }

    // 시간 피커 다이얼로그 (시:분) — iOS 인라인 휠 대신 행 탭 → 다이얼로그 (스펙 05 §5)
    editingField?.let { field ->
        if (profileLoaded) {
            val (h, m) = fieldHourMinute(profile, field)
            TimePickerDialog(
                initialHour = h,
                initialMinute = m,
                onConfirm = { nh, nm ->
                    profile = profileWithField(profile, field, nh, nm)
                    editingField = null
                },
                onDismiss = { editingField = null },
            )
        }
    }
}

// MARK: - 히어로 카드

@Composable
private fun HeroCard(heroState: CharacterState, name: String, onClick: () -> Unit) {
    FrostedCard(
        cornerRadius = 18.dp,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            KoreanStateChip(state = heroState, size = 64.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        name.ifEmpty { stringResource(R.string.profile_default_name) },
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Icon(
                        Icons.Filled.Edit,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                        modifier = Modifier.size(14.dp),
                    )
                }
                Text(
                    heroState.caption,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// MARK: - 수면 상태 행 (자는 중/깨어 있음 + 기준 칩 메뉴)

@Composable
private fun SleepStatusRow(
    profile: CharacterProfile,
    dndOn: Boolean,
    isInBedSchedule: Boolean,
    onSetManual: (Boolean) -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }
    val sleeping = isSleepingNow(profile, dndOn, isInBedSchedule)
    val manual = profile.isManualSleepOnly

    // 기준 칩 라벨/아이콘 — 오로지 사용자가 고른 값(manualSleepOnly)으로만 결정한다 (iOS 파리티).
    // 살아있는 신호(DND/health)로 추론하지 않는다 — true='설정 시간 기준'(시계), false='수면 모드 기준'(달).
    val (basisLabelRes, basisIcon) = if (manual) {
        R.string.profile_basis_manual to Icons.Filled.Schedule
    } else {
        R.string.profile_basis_focus to Icons.Filled.Nightlight
    }

    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp, horizontal = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            stringResource(if (sleeping) R.string.profile_sleeping else R.string.profile_awake),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Bold,
        )
        Spacer(Modifier.weight(1f))
        Box {
            // 기준 칩 (Capsule) — 탭하면 기준 선택 메뉴
            Row(
                Modifier
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.12f))
                    .clickable { menuOpen = true }
                    .padding(horizontal = 10.dp, vertical = 5.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Icon(
                    basisIcon,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(12.dp),
                )
                Text(
                    stringResource(basisLabelRes),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Icon(
                    Icons.Filled.UnfoldMore,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(12.dp),
                )
            }
            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                // iOS Picker("수면 기준") 의 제목 근사 — 메뉴 헤더
                Text(
                    stringResource(R.string.profile_basis_menu_title),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
                )
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.profile_basis_focus)) },
                    leadingIcon = { Icon(Icons.Filled.Nightlight, contentDescription = null) },
                    trailingIcon = if (!manual) ({ CheckIcon() }) else null,
                    onClick = {
                        menuOpen = false
                        onSetManual(false)
                    },
                )
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.profile_basis_manual)) },
                    leadingIcon = { Icon(Icons.Filled.Schedule, contentDescription = null) },
                    trailingIcon = if (manual) ({ CheckIcon() }) else null,
                    onClick = {
                        menuOpen = false
                        onSetManual(true)
                    },
                )
            }
        }
    }
}

@Composable
private fun CheckIcon() {
    Icon(
        Icons.Filled.Check,
        contentDescription = null,
        tint = MaterialTheme.colorScheme.primary,
        modifier = Modifier.size(18.dp),
    )
}

// MARK: - '자는 중' 판정 — resolver 의 수면 분기와 동일해야 함 (스펙 05 §3-2)

/**
 * iOS isSleepingNow 포팅. Android 신호 근사 (스펙 05 §5):
 *  filterSleepingCorrected/isFocused ≈ DND on (+ 수면 창), lastFocusOffAt ≈ DND off 전환 시각.
 */
private fun isSleepingNow(
    profile: CharacterProfile,
    dndOn: Boolean,
    isInBedSchedule: Boolean,
): Boolean {
    val inWindow = CharacterStateResolver.isNowInSleepWindow(LocalDateTime.now(), profile)
    // '설정 시간 기준' — 시간창만 기준 (신호 무시)
    if (profile.isManualSleepOnly) return inWindow
    // '수면 모드 기준' — 실제 수면 신호만. (DND on && 수면 창) 또는 진행 중 수면 세션.
    //    DND(수면 모드)를 꺼두면 밤이어도 깨어 있음 — 시간창만으로는 안 잔다 (iOS 파리티).
    return (dndOn && inWindow) || isInBedSchedule
}

/** 수면 섹션 footer 3분기 (스펙 05 §3-5) — footer 2 조건: DND 신호 관측 이력도 수면 일정도 없음. */
@Composable
private fun sleepFooterText(
    profile: CharacterProfile,
    hasObservedDnd: Boolean,
    hasSleepSchedule: Boolean,
): String = when {
    profile.isManualSleepOnly -> stringResource(R.string.profile_sleep_footer_manual)
    !hasObservedDnd && !hasSleepSchedule -> stringResource(R.string.profile_sleep_footer_no_signal)
    else -> stringResource(R.string.profile_sleep_footer_default)
}

// MARK: - 시간 필드 매핑

private fun fieldHourMinute(p: CharacterProfile, f: TimeField): Pair<Int, Int> = when (f) {
    TimeField.SLEEP_START -> p.sleepStartHour to p.sleepStartMinute
    TimeField.SLEEP_END -> p.sleepEndHour to p.sleepEndMinute
    TimeField.LUNCH -> p.lunchHour to p.lunchMinute
    TimeField.DINNER -> p.dinnerHour to p.dinnerMinute
    // 밤하늘은 자정 기준 '분' 단일 Int 저장 — hour/minute 분리 필드와 혼동 금지 (스펙 05 §1-4)
    TimeField.NIGHT_START -> p.effectiveNightFallbackStart / 60 to p.effectiveNightFallbackStart % 60
    TimeField.NIGHT_END -> p.effectiveNightFallbackEnd / 60 to p.effectiveNightFallbackEnd % 60
}

private fun profileWithField(p: CharacterProfile, f: TimeField, h: Int, m: Int): CharacterProfile =
    when (f) {
        TimeField.SLEEP_START -> p.copy(sleepStartHour = h, sleepStartMinute = m)
        TimeField.SLEEP_END -> p.copy(sleepEndHour = h, sleepEndMinute = m)
        TimeField.LUNCH -> p.copy(lunchHour = h, lunchMinute = m)
        TimeField.DINNER -> p.copy(dinnerHour = h, dinnerMinute = m)
        TimeField.NIGHT_START -> p.copy(nightFallbackStartMinute = h * 60 + m)
        TimeField.NIGHT_END -> p.copy(nightFallbackEndMinute = h * 60 + m)
    }

// MARK: - 공용 행/다이얼로그

/** 라벨 + HH:mm 값 행 — 탭하면 시간 피커 (iOS DatePicker 행 대응). */
@Composable
private fun TimeRow(
    label: String,
    hour: Int,
    minute: Int,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .clickable(enabled = enabled, onClick = onClick)
            .alpha(if (enabled) 1f else 0.4f)
            .padding(vertical = 10.dp, horizontal = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Spacer(Modifier.weight(1f))
        Text(
            String.format(Locale.US, "%02d:%02d", hour, minute),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.1f))
                .padding(horizontal = 10.dp, vertical = 5.dp),
        )
    }
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            // iOS PixelToggleStyle 은 contentShape(Rectangle) + onTapGesture 로 행 전체가 탭 영역
            .toggleable(
                value = checked,
                onValueChange = onCheckedChange,
                role = Role.Switch,
            )
            .padding(vertical = 2.dp, horizontal = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        PixelToggle(checked = checked, onCheckedChange = null)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TimePickerDialog(
    initialHour: Int,
    initialMinute: Int,
    onConfirm: (Int, Int) -> Unit,
    onDismiss: () -> Unit,
) {
    val state = rememberTimePickerState(
        initialHour = initialHour,
        initialMinute = initialMinute,
        is24Hour = true,
    )
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = { onConfirm(state.hour, state.minute) }) {
                Text(stringResource(R.string.common_confirm))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel)) }
        },
        text = { TimePicker(state = state) },
    )
}

// MARK: - 캐릭터 외형 한 줄 (고급)

@Composable
private fun AdvancedPromptSection(value: String, onValueChange: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    FormSection {
        Row(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(10.dp))
                .clickable { expanded = !expanded }
                .padding(vertical = 8.dp, horizontal = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                stringResource(R.string.profile_advanced_label),
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f),
            )
            Icon(
                Icons.Filled.ExpandMore,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.rotate(if (expanded) 180f else 0f),
            )
        }
        AnimatedVisibility(visible = expanded) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = value,
                    onValueChange = onValueChange,
                    placeholder = { Text(stringResource(R.string.profile_advanced_placeholder)) },
                    minLines = 2,
                    maxLines = 5,
                    colors = withuInputColors(),
                    modifier = Modifier.fillMaxWidth().pixelInputField(),
                )
                Text(
                    stringResource(R.string.profile_advanced_hint),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
