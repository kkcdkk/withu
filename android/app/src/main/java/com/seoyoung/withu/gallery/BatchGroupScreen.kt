package com.seoyoung.withu.gallery

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.seoyoung.withu.R
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.shared.CharacterImageStore
import com.seoyoung.withu.shared.GalleryItem
import com.seoyoung.withu.sync.SyncCoordinator
import com.seoyoung.withu.ui.CapsuleToast
import com.seoyoung.withu.ui.FrostedCard
import com.seoyoung.withu.ui.WithuCTAButton
import com.seoyoung.withu.ui.rememberBackgroundGradient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** 이 화면이 한 번에 읽어오는 스냅샷 — IO 에서 조립 (00-PLAN §0-3). */
private data class GroupData(val items: List<GalleryItem>, val name: String?)

/**
 * '이 캐릭터'(batch 그룹) 그리드 + 기타(legacy) 폴더 — iOS GalleryGrid(items:) push 대응 (스펙 04 §1.1.2/1.3).
 * batchId == "" 규약 = legacy 폴더 (00-PLAN §2-12). 그 외 = loadGalleryByCharacter 의 해당 그룹.
 *
 * '이 캐릭터로 모두 적용'은 랜딩이 아니라 여기(상세) 상단에 있다 — 확인 다이얼로그도 이 화면이 들고 있어야
 * 푸시된 상태에서 실제로 뜬다 (랜딩에 두면 안 뜸, iOS CharacterApplyHeader 주석 참고).
 */
@Composable
fun BatchGroupScreen(batchId: String) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    var refreshTick by remember { mutableIntStateOf(0) }
    val isLegacy = batchId.isEmpty()
    var showApplyAllConfirm by remember { mutableStateOf(false) }
    var toastText by remember { mutableStateOf<String?>(null) }
    var toastJob by remember { mutableStateOf<Job?>(null) }

    val data by produceState<GroupData?>(initialValue = null, batchId, refreshTick) {
        value = withContext(Dispatchers.IO) {
            if (isLegacy) {
                GroupData(CharacterImageStore.loadGalleryGrouped().legacy, null)
            } else {
                val items = CharacterImageStore.loadGalleryByCharacter()
                    .firstOrNull { it.batchId == batchId }?.items ?: emptyList()
                GroupData(items, CharacterImageStore.characterName(batchId))
            }
        }
    }

    val d = data
    if (d == null) {
        // 로딩 중 — 배경만
        Box(
            Modifier
                .fillMaxSize()
                .background(rememberBackgroundGradient(CharacterState.IDLE)),
        )
        return
    }
    val current = d.items

    // 제목 = 사용자가 지은 이름, 없으면 '이 캐릭터' (iOS navigationTitle(charName ?? "이 캐릭터"))
    val title = when {
        isLegacy -> stringResource(R.string.gallery_legacy_title)
        d.name != null -> d.name
        else -> stringResource(R.string.gallery_batch_group_title)
    }

    Box(Modifier.fillMaxSize()) {
        GalleryGrid(
            items = current,
            backgroundState = CharacterState.IDLE,
            title = title,
            onChange = { refreshTick++ },
            header = when {
                isLegacy -> {
                    { LegacyHeader(count = current.size) }
                }
                current.isNotEmpty() -> {
                    { CharacterApplyHeader(onClick = { showApplyAllConfirm = true }) }
                }
                else -> null
            },
        )
        CapsuleToast(
            text = toastText,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 40.dp),
        )
    }

    // '이 캐릭터로 모두 적용' 확인 — 여러 자리를 한 번에 덮으므로 반드시 확인 (스펙 04 §3.1)
    if (showApplyAllConfirm) {
        AlertDialog(
            onDismissRequest = { showApplyAllConfirm = false },
            title = { Text(stringResource(R.string.gallery_apply_all_confirm_title)) },
            text = { Text(stringResource(R.string.gallery_apply_all_confirm_body, current.size)) },
            confirmButton = {
                TextButton(onClick = {
                    showApplyAllConfirm = false
                    scope.launch {
                        val applied = applyCharacter(current)
                        SyncCoordinator.refreshWidgets()
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        refreshTick++
                        toastJob?.cancel()
                        toastText = context.getString(R.string.gallery_apply_all_toast, applied)
                        toastJob = scope.launch {
                            delay(1600)
                            toastText = null
                        }
                    }
                }) { Text(stringResource(R.string.gallery_apply_all_button)) }
            },
            dismissButton = {
                TextButton(onClick = { showApplyAllConfirm = false }) {
                    Text(stringResource(R.string.common_cancel))
                }
            },
        )
    }
}

/** 캐릭터 상세 상단 — '이 캐릭터로 모두 적용' CTA (iOS CharacterApplyHeader). */
@Composable
private fun CharacterApplyHeader(onClick: () -> Unit) {
    WithuCTAButton(
        text = stringResource(R.string.gallery_apply_all),
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
    )
}

/** legacy 폴더 내부 헤더 — tray 아이콘(56) + 예전에 만든 캐릭터 + %d개 (스펙 04 §1.1 legacy 헤더). */
@Composable
private fun LegacyHeader(count: Int) {
    FrostedCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(56.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.Inbox,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.size(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    stringResource(R.string.gallery_legacy_header),
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    stringResource(R.string.gallery_count, count),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
