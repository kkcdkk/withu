package com.seoyoung.withu.home

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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.seoyoung.withu.R
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.health.HealthManager
import com.seoyoung.withu.shared.AppPrefs
import com.seoyoung.withu.sync.SyncCoordinator
import com.seoyoung.withu.ui.FormSection
import com.seoyoung.withu.ui.RefreshRowButton
import com.seoyoung.withu.ui.StatusKind
import com.seoyoung.withu.ui.StatusPill
import com.seoyoung.withu.ui.rememberBackgroundGradient
import kotlinx.coroutines.flow.StateFlow
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

@Composable
private fun stringRes(id: Int): String = stringResource(id)

@Composable
private fun stringRes(id: Int, vararg args: Any): String = stringResource(id, *args)

@Composable
private fun <T> StateFlow<T>.collectAsStateCompat(): State<T> = collectAsState()

/**
 * 진단 화면 — iOS AdvancedDiagnosticsView 대응 (스펙 01 §1.4).
 * 수면·집중 모드 섹션(Focus)·워치 행 SCOPE 제외. overrideState 는 SyncCoordinator 공유 홀더.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiagnosticsScreen() {
    val gradient = rememberBackgroundGradient(CharacterState.IDLE)

    val sleep by HealthManager.sleep.collectAsStateCompat()
    val isInBed by HealthManager.isInBedSchedule.collectAsStateCompat()
    val sleepCount48h by HealthManager.sleepSampleCount48h.collectAsStateCompat()
    val lastSleepStart by HealthManager.lastSleepSessionStart.collectAsStateCompat()
    val isLikelyInWorkout by HealthManager.isLikelyInWorkout.collectAsStateCompat()
    val hrCount by HealthManager.recentHRSampleCount.collectAsStateCompat()
    val hrAvg by HealthManager.recentHRAverage.collectAsStateCompat()
    val override by SyncCoordinator.overrideState.collectAsStateCompat()

    Scaffold(
        containerColor = Color.Transparent,
        topBar = {
            TopAppBar(
                title = { Text(stringRes(R.string.diag_title), fontWeight = FontWeight.SemiBold) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
            )
        },
        modifier = Modifier.background(gradient),
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            // 건강 앱 수면 정보
            FormSection(header = stringRes(R.string.diag_sleep_header)) {
                DiagValueRow(stringRes(R.string.diag_inbed_48h)) {
                    DiagSecondaryText(stringRes(R.string.diag_count_fmt, sleepCount48h))
                }
                DiagDivider()
                DiagValueRow(stringRes(R.string.diag_inbed_now)) {
                    StatusPill(
                        kind = if (isInBed) StatusKind.OK else StatusKind.OFF,
                        text = if (isInBed) stringRes(R.string.diag_pill_yes) else stringRes(R.string.diag_pill_no),
                    )
                }
                lastSleepStart?.let { start ->
                    DiagDivider()
                    DiagValueRow(stringRes(R.string.diag_last_inbed_start)) {
                        DiagSecondaryText(formatTimeShort(start))
                    }
                }
                DiagDivider()
                DiagValueRow(stringRes(R.string.diag_sleep_7d)) {
                    DiagSecondaryText(stringRes(R.string.diag_count_fmt, sleep?.sampleCount ?: 0))
                }
                sleep?.lastNight?.let { last ->
                    DiagDivider()
                    DiagValueRow(stringRes(R.string.diag_last_sleep_start)) {
                        DiagSecondaryText(formatDateTimeShort(last))
                    }
                }
                DiagDivider()
                RefreshRowButton(
                    title = stringRes(R.string.diag_sleep_refetch),
                    action = {
                        HealthManager.fetchSleep(days = 7)
                        HealthManager.fetchInBedSchedule()
                        SyncCoordinator.syncNow()
                    },
                )
            }

            // 운동 감지
            FormSection(header = stringRes(R.string.diag_motion_header)) {
                DiagValueRow(stringRes(R.string.diag_workout_likely)) {
                    StatusPill(
                        kind = if (isLikelyInWorkout) StatusKind.OK else StatusKind.OFF,
                        text = if (isLikelyInWorkout) stringRes(R.string.diag_pill_likely) else stringRes(R.string.diag_pill_no),
                    )
                }
                DiagDivider()
                DiagValueRow(stringRes(R.string.diag_hr_90s)) {
                    DiagSecondaryText(stringRes(R.string.diag_count_fmt, hrCount))
                }
                if (hrAvg > 0) {
                    DiagDivider()
                    DiagValueRow(stringRes(R.string.diag_hr_avg)) {
                        DiagSecondaryText(stringRes(R.string.diag_hr_bpm, hrAvg.toInt()))
                    }
                }
                DiagDivider()
                RefreshRowButton(
                    title = stringRes(R.string.diag_hr_recheck),
                    action = {
                        HealthManager.refreshWorkoutInference()
                        SyncCoordinator.syncNow()
                    },
                )
            }

            // 위젯 다시 맞추기 (워치 행 제외)
            FormSection(
                header = stringRes(R.string.diag_debug_header),
                footer = stringRes(R.string.diag_debug_footer),
            ) {
                DiagValueRow(stringRes(R.string.diag_last_bg)) {
                    val bgAt = remember { AppPrefs.lastBackgroundRefreshAt }
                    DiagSecondaryText(bgAt?.let { formatTimeShort(it) } ?: stringRes(R.string.diag_never))
                }
                DiagDivider()
                StatePickerRow(
                    selected = override,
                    onSelect = { SyncCoordinator.overrideState.value = it },
                )
                DiagDivider()
                RefreshRowButton(
                    title = stringRes(R.string.diag_widget_refresh),
                    action = { SyncCoordinator.syncNow() },
                )
            }
        }
    }
}

// MARK: - 상태 직접 고르기 (Picker)

@Composable
private fun StatePickerRow(selected: CharacterState?, onSelect: (CharacterState?) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val autoLabel = stringRes(R.string.diag_state_auto)
    Box {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { expanded = true }
                .padding(vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = stringRes(R.string.diag_state_picker),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(Modifier.weight(1f))
            Text(
                text = selected?.koreanShortLabel ?: autoLabel,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Icon(
                Icons.Filled.ArrowDropDown,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(
                text = { Text(autoLabel) },
                onClick = { onSelect(null); expanded = false },
            )
            CharacterState.entries.forEach { state ->
                DropdownMenuItem(
                    text = { Text(state.koreanShortLabel) },
                    onClick = { onSelect(state); expanded = false },
                )
            }
        }
    }
}

// MARK: - 행 프리미티브

@Composable
private fun DiagValueRow(title: String, trailing: @Composable () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text = title, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.weight(1f))
        trailing()
    }
}

@Composable
private fun DiagSecondaryText(text: String) {
    Text(text = text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun DiagDivider() {
    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f))
}

// MARK: - 시각 포맷 (파일-로컬)

private fun formatTimeShort(epochMillis: Long): String {
    val t = Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault()).toLocalTime()
    return t.format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT))
}

private fun formatDateTimeShort(epochMillis: Long): String {
    val dt = Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault()).toLocalDateTime()
    return dt.format(DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT))
}
