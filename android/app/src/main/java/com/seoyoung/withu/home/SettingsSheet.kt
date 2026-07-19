package com.seoyoung.withu.home

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.health.connect.client.PermissionController
import com.seoyoung.withu.R
import com.seoyoung.withu.health.HealthManager
import com.seoyoung.withu.notify.NotificationHelper
import com.seoyoung.withu.paywall.PaywallSheet
import com.seoyoung.withu.quota.GenerationQuota
import com.seoyoung.withu.sync.SyncCoordinator
import com.seoyoung.withu.ui.FormSection
import com.seoyoung.withu.ui.StatusKind
import com.seoyoung.withu.ui.StatusPill
import com.seoyoung.withu.ui.rememberBackgroundGradient
import com.seoyoung.withu.character.CharacterState
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

private const val PRIVACY_URL = "https://kkcdkk.github.io/withu/PRIVACY_POLICY.html"
private const val TERMS_URL = "https://kkcdkk.github.io/withu/TERMS_OF_SERVICE.html"

@Composable
private fun stringRes(id: Int): String = stringResource(id)

@Composable
private fun stringRes(id: Int, vararg args: Any): String = stringResource(id, *args)

@Composable
private fun <T> StateFlow<T>.collectAsStateCompat(): State<T> = collectAsState()

/**
 * 설정 시트 — iOS SettingsView 대응 (스펙 01 §1.2).
 * Form 이 길어 바텀시트 대신 전체화면 다이얼로그 (스펙 05 권장).
 * 워치·계정 섹션 SCOPE 제외. 건강 푸터(단축어 안내)도 Android 제외.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsSheet(
    onClose: () -> Unit,
    onOpenProfile: () -> Unit,
    onOpenDiagnostics: () -> Unit,
    onShowHelp: () -> Unit,
    onReonboard: () -> Unit,
) {
    Dialog(
        onDismissRequest = onClose,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        SettingsContent(
            onClose = onClose,
            onOpenProfile = onOpenProfile,
            onOpenDiagnostics = onOpenDiagnostics,
            onShowHelp = onShowHelp,
            onReonboard = onReonboard,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsContent(
    onClose: () -> Unit,
    onOpenProfile: () -> Unit,
    onOpenDiagnostics: () -> Unit,
    onShowHelp: () -> Unit,
    onReonboard: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val isHealthAuthorized by HealthManager.isAuthorized.collectAsStateCompat()
    var candy by remember { mutableIntStateOf(GenerationQuota.displayedCandy()) }
    var healthMessage by remember { mutableStateOf("") }
    var healthLoading by remember { mutableStateOf(false) }
    // 알림 라벨/권한은 동기 조회라 요청 후 재계산 트리거가 필요
    var notifTick by remember { mutableIntStateOf(0) }
    var showPaywall by remember { mutableStateOf(false) }
    var showWidgetGuide by remember { mutableStateOf(false) }
    var showReonboardConfirm by remember { mutableStateOf(false) }
    var showBedtimePicker by remember { mutableStateOf(false) }

    // 갤럭시 워치 연동 상태 (비동기 조회)
    var watchState by remember { mutableStateOf<com.seoyoung.withu.watch.WatchStatus.State?>(null) }
    var watchSyncing by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { watchState = com.seoyoung.withu.watch.WatchStatus.query() }

    // 건강 권한 시트 (Health Connect)
    val healthPermissionLauncher = rememberLauncherForActivityResult(
        contract = PermissionController.createRequestPermissionResultContract(),
    ) { scope.launch { HealthManager.refreshAuthorizationStatus() } }

    // 알림 권한 (API 33+)
    val notifPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission(),
    ) {
        NotificationHelper.markPermissionRequested()
        notifTick++
    }

    val gradient = rememberBackgroundGradient(CharacterState.IDLE)
    val notifLabel = remember(notifTick) { NotificationHelper.authorizationLabel() }
    val notifGranted = remember(notifTick) { NotificationHelper.hasPermission() }
    val notifAsked = remember(notifTick) { NotificationHelper.permissionRequested() }

    Scaffold(
        containerColor = Color.Transparent,
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text(stringRes(R.string.settings_title), fontWeight = FontWeight.SemiBold) },
                actions = {
                    TextButton(onClick = onClose) { Text(stringRes(R.string.common_close)) }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
            )
        },
        modifier = Modifier
            .fillMaxSize()
            // 불투명 베이스를 먼저 깔고 그 위에 반투명 그라데이션 — Dialog 는 창 배경이 투명해서
            // 이게 없으면 뒤의 홈 화면이 비쳐 타이틀이 겹쳐 보인다("w설정U"). iOS .sheet 는 불투명.
            .background(MaterialTheme.colorScheme.background)
            .background(gradient),
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            // 1. 더 만들기
            FormSection(
                header = stringRes(R.string.settings_more_header),
                footer = stringRes(R.string.settings_candy_footer, candy),
            ) {
                SettingsButtonRow(title = stringRes(R.string.settings_candy_charge)) { showPaywall = true }
            }

            // 2. 건강 데이터 (푸터 없음 — 단축어 안내 Android 제외)
            FormSection(header = stringRes(R.string.settings_health_header)) {
                SettingsValueRow(title = stringRes(R.string.settings_permission)) {
                    StatusPill(
                        kind = if (isHealthAuthorized) StatusKind.OK else StatusKind.OFF,
                        text = if (isHealthAuthorized) stringRes(R.string.settings_health_granted)
                        else stringRes(R.string.settings_health_denied),
                    )
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f))
                // iOS 는 HealthKit 재요청이 무반응이라 설정 앱으로 안내 — Android(Health Connect)는
                // 권한 변경 화면을 launcher 로 바로 띄울 수 있어 그 화면을 연다 (문구는 iOS 원문 유지).
                SettingsButtonRow(title = stringRes(R.string.settings_health_reask)) {
                    if (HealthManager.isAvailable()) {
                        healthPermissionLauncher.launch(HealthManager.requiredPermissions())
                    } else {
                        openAppSettingsFromSettings(context)
                    }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f))
                SettingsButtonRow(
                    title = stringRes(R.string.settings_health_refresh),
                    enabled = !healthLoading,
                ) {
                    scope.launch {
                        healthLoading = true
                        healthMessage = reloadHealth(context)
                        healthLoading = false
                    }
                }
                if (healthMessage.isNotEmpty()) {
                    Text(
                        text = healthMessage,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 4.dp, vertical = 6.dp),
                    )
                }
            }

            // 3. 알림
            FormSection(header = stringRes(R.string.settings_notify_header)) {
                SettingsValueRow(title = stringRes(R.string.settings_notify_status)) {
                    Text(
                        text = notifLabel,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (!notifGranted) {
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f))
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !notifAsked) {
                        SettingsButtonRow(title = stringRes(R.string.settings_notify_request)) {
                            notifPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                        }
                    } else {
                        // 이미 거절된 뒤에는 시스템 다이얼로그가 무반응 — 설정 앱 알림 화면으로 안내 (iOS 파리티)
                        SettingsButtonRow(title = stringRes(R.string.settings_notify_open_settings)) {
                            openNotificationSettings(context)
                        }
                    }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f))
                // 행 탭 → 시간 피커 다이얼로그 → 확인 시 예약 (iOS DatePicker+확인 행 대응)
                SettingsButtonRow(title = stringRes(R.string.settings_notify_bedtime)) {
                    showBedtimePicker = true
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f))
                SettingsButtonRow(
                    title = stringRes(R.string.settings_notify_cancel_all),
                    destructive = true,
                ) { NotificationHelper.cancelAllScheduled() }
            }

            // 3.5 갤럭시 워치 연동 (iOS '애플 워치' 섹션 대응)
            FormSection(
                header = stringRes(R.string.settings_watch_header),
                footer = stringRes(R.string.settings_watch_footer),
            ) {
                val ws = watchState
                SettingsValueRow(title = stringRes(R.string.settings_watch_paired)) {
                    StatusPill(
                        kind = if (ws?.paired == true) StatusKind.OK else StatusKind.OFF,
                        text = if (ws?.paired == true) stringRes(R.string.settings_watch_on)
                        else stringRes(R.string.settings_watch_off),
                    )
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f))
                SettingsValueRow(title = stringRes(R.string.settings_watch_app)) {
                    StatusPill(
                        kind = if (ws?.appInstalled == true) StatusKind.OK else StatusKind.OFF,
                        text = if (ws?.appInstalled == true) stringRes(R.string.settings_watch_installed)
                        else stringRes(R.string.settings_watch_not_installed),
                    )
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f))
                SettingsValueRow(title = stringRes(R.string.settings_watch_reachable)) {
                    StatusPill(
                        kind = if (ws?.reachable == true) StatusKind.OK else StatusKind.OFF,
                        text = if (ws?.reachable == true) stringRes(R.string.settings_watch_on)
                        else stringRes(R.string.settings_watch_waiting),
                    )
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f))
                SettingsValueRow(title = stringRes(R.string.settings_watch_last_sync)) {
                    Text(
                        text = ws?.lastSyncAt?.takeIf { it > 0 }?.let {
                            java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT)
                                .format(java.util.Date(it))
                        } ?: stringRes(R.string.settings_watch_sync_never),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f))
                SettingsButtonRow(
                    title = stringRes(R.string.settings_watch_sync_now),
                    enabled = !watchSyncing,
                ) {
                    scope.launch {
                        watchSyncing = true
                        com.seoyoung.withu.watch.WearSyncManager.push(force = true)
                        watchState = com.seoyoung.withu.watch.WatchStatus.query()
                        watchSyncing = false
                    }
                }
            }

            // 4. 캐릭터 (프로필 진입 + 진단 링크) — iOS 와 동일하게 진단 row 위에 프로필 row
            FormSection(footer = stringRes(R.string.settings_diagnostics_footer)) {
                SettingsButtonRow(title = stringRes(R.string.home_btn_profile_title)) { onOpenProfile() }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f))
                SettingsButtonRow(title = stringRes(R.string.settings_diagnostics)) { onOpenDiagnostics() }
            }

            // 5. 도움말
            FormSection(header = stringRes(R.string.settings_help_header)) {
                SettingsButtonRow(title = stringRes(R.string.settings_help_guide)) { onShowHelp() }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f))
                SettingsButtonRow(title = stringRes(R.string.settings_widget_guide)) { showWidgetGuide = true }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f))
                SettingsButtonRow(title = stringRes(R.string.settings_reonboard)) { showReonboardConfirm = true }
            }

            // 6. 법적 정보
            FormSection(header = stringRes(R.string.settings_legal_header)) {
                SettingsButtonRow(title = stringRes(R.string.settings_privacy)) { openUrl(context, PRIVACY_URL) }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f))
                SettingsButtonRow(title = stringRes(R.string.settings_terms)) { openUrl(context, TERMS_URL) }
            }
        }
    }

    if (showPaywall) {
        PaywallSheet(onClose = {
            showPaywall = false
            candy = GenerationQuota.displayedCandy()
        })
    }
    if (showWidgetGuide) {
        WidgetGuideSheet(onClose = { showWidgetGuide = false })
    }
    if (showBedtimePicker) {
        val stored = NotificationHelper.bedtimeReminderMinutes()
        BedtimePickerDialog(
            initialHour = stored / 60,
            initialMinute = stored % 60,
            onConfirm = { h, m ->
                NotificationHelper.scheduleBedtimeReminder(hour = h, minute = m)
                showBedtimePicker = false
            },
            onDismiss = { showBedtimePicker = false },
        )
    }
    if (showReonboardConfirm) {
        AlertDialog(
            onDismissRequest = { showReonboardConfirm = false },
            title = { Text(stringRes(R.string.settings_reonboard)) },
            text = { Text(stringRes(R.string.settings_reonboard_body)) },
            confirmButton = {
                TextButton(onClick = {
                    showReonboardConfirm = false
                    onReonboard()
                }) { Text(stringRes(R.string.settings_reonboard_confirm)) }
            },
            dismissButton = {
                TextButton(onClick = { showReonboardConfirm = false }) {
                    Text(stringRes(R.string.common_cancel))
                }
            },
        )
    }
}

// MARK: - 취침 리마인더 시간 피커 (ProfileScreen 의 TimePickerDialog 패턴)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BedtimePickerDialog(
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

// MARK: - 행 프리미티브

@Composable
private fun SettingsButtonRow(
    title: String,
    enabled: Boolean = true,
    destructive: Boolean = false,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.bodyMedium,
            color = when {
                !enabled -> MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                destructive -> MaterialTheme.colorScheme.error
                else -> MaterialTheme.colorScheme.onSurface
            },
        )
        if (!enabled) {
            Spacer(Modifier.weight(1f))
            CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
        }
    }
}

@Composable
private fun SettingsValueRow(title: String, trailing: @Composable () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Spacer(Modifier.weight(1f))
        trailing()
    }
}

// MARK: - 로직 헬퍼

/** 5종 재조회 — 실패 항목명 수집 → "최신화 완료" 또는 "실패: …". iOS reloadHealth 이식. */
private suspend fun reloadHealth(context: Context): String {
    val errors = mutableListOf<String>()
    runCatching { HealthManager.fetchSleep(days = 7) }.onFailure { errors.add(context.getString(R.string.settings_health_item_sleep)) }
    runCatching { HealthManager.fetchWorkouts(days = 7) }.onFailure { errors.add(context.getString(R.string.settings_health_item_workout)) }
    runCatching { HealthManager.fetchTodaySteps() }.onFailure { errors.add(context.getString(R.string.settings_health_item_steps)) }
    runCatching { HealthManager.fetchTodayActiveMinutes() }.onFailure { errors.add(context.getString(R.string.settings_health_item_minutes)) }
    runCatching { HealthManager.fetchTodayActiveKcal() }.onFailure { errors.add(context.getString(R.string.settings_health_item_kcal)) }
    runCatching { HealthManager.fetchInBedSchedule() }
    SyncCoordinator.syncNow()
    return if (errors.isEmpty()) {
        context.getString(R.string.settings_health_done)
    } else {
        context.getString(R.string.settings_health_failed, errors.joinToString(", "))
    }
}

private fun openUrl(context: Context, url: String) {
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    runCatching { context.startActivity(intent) }
}

private fun openAppSettingsFromSettings(context: Context) {
    val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
        data = Uri.fromParts("package", context.packageName, null)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    runCatching { context.startActivity(intent) }
}

/** 앱 알림 설정 화면 — 거절된 권한은 재요청이 무반응이라 여기로 안내 (iOS '설정 앱에서 변경' 대응). */
private fun openNotificationSettings(context: Context) {
    val intent = Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
        putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    runCatching { context.startActivity(intent) }
        .onFailure { openAppSettingsFromSettings(context) }
}
