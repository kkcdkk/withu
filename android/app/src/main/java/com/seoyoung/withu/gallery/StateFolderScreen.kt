package com.seoyoung.withu.gallery

import android.graphics.Bitmap
import androidx.compose.foundation.Image
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.seoyoung.withu.R
import com.seoyoung.withu.character.CharacterImage
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.shared.CharacterImageStore
import com.seoyoung.withu.shared.GalleryItem
import com.seoyoung.withu.ui.FrostedCard
import com.seoyoung.withu.ui.WithuPinkButton
import com.seoyoung.withu.ui.rememberBackgroundGradient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 한 상태의 폴더 — iOS StateFolderView 포팅 (스펙 04 §1.2).
 * 항목 있으면 GalleryGrid, 없으면 miniHero + 빈 상태(생성 유도).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StateFolderScreen(
    state: CharacterState,
    onOpenSingleGen: () -> Unit,
) {
    var refreshTick by remember { mutableIntStateOf(0) }

    val items by produceState<List<GalleryItem>?>(initialValue = null, state, refreshTick) {
        value = withContext(Dispatchers.IO) {
            CharacterImageStore.loadGalleryGrouped().byState[state] ?: emptyList()
        }
    }

    val current = items
    if (current != null && current.isNotEmpty()) {
        // 항목 있음 — 재사용 그리드 (자체 Scaffold/topBar 보유)
        GalleryGrid(
            items = current,
            backgroundState = state,
            title = state.koreanShortLabel,
            onChange = { refreshTick++ },
            header = { StateMiniHero(state = state, count = current.size) },
        )
        return
    }

    // 로딩/빈 상태 — 자체 Scaffold
    Box(
        Modifier
            .fillMaxSize()
            .background(rememberBackgroundGradient(state)),
    ) {
        Scaffold(
            containerColor = Color.Transparent,
            topBar = {
                CenterAlignedTopAppBar(
                    title = { Text(state.koreanShortLabel, fontWeight = FontWeight.SemiBold) },
                    colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                        containerColor = Color.Transparent,
                    ),
                )
            },
        ) { padding ->
            if (current == null) return@Scaffold   // 로딩 중 — 빈 화면
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(horizontal = 20.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                StateMiniHero(state = state, count = 0)
                Spacer(Modifier.size(16.dp))
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(96.dp)
                            .clip(RoundedCornerShape(24.dp))
                            .background(state.tint.copy(alpha = 0.18f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        // 이모지 대신 번들 기본 일러스트 (iOS emptyState 동일) — 투명 PNG 라 tint 배경과 어울림
                        val context = LocalContext.current
                        val assetId = remember(state) {
                            fun idOf(name: String) =
                                context.resources.getIdentifier(name, "drawable", context.packageName)
                            var id = idOf(state.imageAssetName)
                            if (id == 0) id = idOf("character_placeholder")
                            id
                        }
                        Image(
                            painter = painterResource(assetId),
                            contentDescription = null,
                            contentScale = ContentScale.Fit,
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(12.dp),
                        )
                    }
                    Text(
                        stringResource(R.string.gallery_state_empty_title, state.koreanShortLabel),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        textAlign = TextAlign.Center,
                    )
                    Text(
                        stringResource(R.string.gallery_state_empty_body),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                    WithuPinkButton(
                        text = stringResource(R.string.gallery_state_empty_button),
                        onClick = onOpenSingleGen,
                    )
                }
            }
        }
    }
}

/** miniHero — 칩(56) + 캡션 + 개수 (스펙 04 §1.2 miniHero). */
@Composable
private fun StateMiniHero(state: CharacterState, count: Int) {
    val subtitle = if (count == 0) {
        stringResource(R.string.gallery_folder_empty_subtitle)
    } else {
        stringResource(R.string.gallery_count, count)
    }
    FrostedCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            HeroChip(state = state, size = 56)
            Spacer(Modifier.size(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    state.caption,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Medium,
                )
                Text(
                    subtitle,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/** 상태 칩 — 적용본이 없으면 갤러리 첫 항목, 아니면 CharacterImage 3단 fallback. */
@Composable
private fun HeroChip(state: CharacterState, size: Int) {
    Box(
        modifier = Modifier
            .size(size.dp)
            .clip(CircleShape)
            .background(state.tint.copy(alpha = 0.22f)),
        contentAlignment = Alignment.Center,
    ) {
        val previewId by produceState<String?>(initialValue = null, state) {
            value = withContext(Dispatchers.IO) {
                if (CharacterImageStore.hasImage(state)) {
                    null
                } else {
                    CharacterImageStore.loadGalleryGrouped().byState[state]?.firstOrNull()?.id
                }
            }
        }
        val pid = previewId
        if (pid != null) {
            val bmp by produceState<Bitmap?>(initialValue = null, pid) {
                value = withContext(Dispatchers.IO) { CharacterImageStore.loadGalleryImage(pid) }
            }
            val b = bmp
            if (b != null) {
                Image(
                    bitmap = b.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding((size * 0.15f).dp),
                )
            } else {
                CharacterImage(state = state, modifier = Modifier.fillMaxSize(), maxPixelSize = size * 3)
            }
        } else {
            CharacterImage(state = state, modifier = Modifier.fillMaxSize(), maxPixelSize = size * 3)
        }
    }
}
