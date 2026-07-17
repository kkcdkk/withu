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
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.seoyoung.withu.R
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.shared.CharacterImageStore
import com.seoyoung.withu.shared.GalleryItem
import com.seoyoung.withu.ui.FrostedCard
import com.seoyoung.withu.ui.rememberBackgroundGradient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * '이 캐릭터'(batch 그룹) 그리드 + 기타(legacy) 폴더 — iOS GalleryGrid(items:) push 대응 (스펙 04 §1.1.2/1.3).
 * batchId == "" 규약 = legacy 폴더 (00-PLAN §2-12). 그 외 = loadGalleryByCharacter 의 해당 그룹.
 */
@Composable
fun BatchGroupScreen(batchId: String) {
    var refreshTick by remember { mutableIntStateOf(0) }
    val isLegacy = batchId.isEmpty()

    val items by produceState<List<GalleryItem>?>(initialValue = null, batchId, refreshTick) {
        value = withContext(Dispatchers.IO) {
            if (isLegacy) {
                CharacterImageStore.loadGalleryGrouped().legacy
            } else {
                CharacterImageStore.loadGalleryByCharacter()
                    .firstOrNull { it.batchId == batchId }?.items ?: emptyList()
            }
        }
    }

    val current = items
    if (current == null) {
        // 로딩 중 — 배경만
        Box(
            Modifier
                .fillMaxSize()
                .background(rememberBackgroundGradient(CharacterState.IDLE)),
        )
        return
    }

    val title = if (isLegacy) {
        stringResource(R.string.gallery_legacy_title)
    } else {
        stringResource(R.string.gallery_batch_group_title)
    }

    GalleryGrid(
        items = current,
        backgroundState = CharacterState.IDLE,
        title = title,
        onChange = { refreshTick++ },
        header = if (isLegacy) {
            { LegacyHeader(count = current.size) }
        } else {
            null
        },
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
                    fontWeight = FontWeight.Medium,
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
