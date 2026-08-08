package com.seoyoung.withu.gallery

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.seoyoung.withu.R
import com.seoyoung.withu.character.CharacterImage
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.shared.CharacterImageStore
import com.seoyoung.withu.shared.GalleryCharacterGroup
import com.seoyoung.withu.shared.GalleryItem
import com.seoyoung.withu.shared.SharedAppState
import com.seoyoung.withu.ui.FrostedCard
import com.seoyoung.withu.ui.WithuTopBarTitle
import com.seoyoung.withu.ui.plainCard
import com.seoyoung.withu.ui.rememberBackgroundGradient
import com.seoyoung.withu.ui.theme.WithuColors
import com.seoyoung.withu.ui.theme.withuPink
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 캐릭터 갤러리 랜딩 — iOS CharacterGalleryView(landing) 포팅 (스펙 04 §1.1).
 * 상태별/캐릭터별 2탭. 상태별은 폴더 리스트, 캐릭터별은 batch 그룹 카드.
 * 화면 이동은 전부 콜백 (00-PLAN §2-12).
 */

private enum class GalleryMode { BY_STATE, BY_CHARACTER }

/** 랜딩이 한 번에 읽어오는 스냅샷 — IO 에서 조립 (00-PLAN §0-3). */
private data class LandingData(
    val counts: Map<CharacterState, Int>,
    val firstIds: Map<CharacterState, String>,   // 폴더 칩 프리뷰용 첫 항목 id
    val applied: Set<CharacterState>,
    val legacy: List<GalleryItem>,
    val characters: List<GalleryCharacterGroup>,
    val characterNames: Map<String, String>,     // batchId → 사용자가 지은 이름 (없으면 키 자체가 없음)
) {
    val totalCount: Int get() = counts.values.sum() + legacy.size
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GalleryLandingScreen(
    onOpenStateFolder: (CharacterState) -> Unit,
    onOpenBatchGroup: (String) -> Unit,
    onOpenLegacy: () -> Unit,
) {
    val lifecycleOwner = LocalLifecycleOwner.current

    var mode by remember { mutableStateOf(GalleryMode.BY_STATE) }
    // onAppear + 하위 화면 변경 콜백 대응 — 값 증가 시 재조회 (스펙 04 §3.1)
    var refreshTick by remember { mutableIntStateOf(0) }

    // landing 배경 = 현재 적용 중인 캐릭터 state 의 그라데이션
    val backgroundState = remember(refreshTick) {
        SharedAppState.loadMessage()?.characterState ?: CharacterState.IDLE
    }

    val data by produceState<LandingData?>(initialValue = null, refreshTick) {
        value = withContext(Dispatchers.IO) {
            val grouped = CharacterImageStore.loadGalleryGrouped()
            val counts = CharacterState.userFacing.associateWith { (grouped.byState[it]?.size ?: 0) }
            val firstIds = CharacterState.userFacing.mapNotNull { st ->
                grouped.byState[st]?.firstOrNull()?.let { st to it.id }
            }.toMap()
            val applied = CharacterState.userFacing.filter { CharacterImageStore.hasImage(it) }.toSet()
            val allGroups = CharacterImageStore.loadGalleryByCharacter()
            val names = allGroups.mapNotNull { g ->
                CharacterImageStore.characterName(g.batchId)?.let { g.batchId to it }
            }.toMap()
            LandingData(
                counts = counts,
                firstIds = firstIds,
                applied = applied,
                legacy = grouped.legacy,
                // 캐릭터별엔 '이름을 붙인 캐릭터' 또는 '상태 2개 이상(여러 모습 만들기)'만 노출 —
                // 이름 없는 단건이 목록을 어지럽히지 않게 (iOS refresh() 필터).
                characters = allGroups.filter { g ->
                    names.containsKey(g.batchId) || g.items.map { it.sourceState }.toSet().size > 1
                },
                characterNames = names,
            )
        }
    }

    // 하위 폴더/배치 화면에서 적용·삭제 후 복귀 시 stale 방지 — iOS onAppear{refresh()} 재현 (스펙 04 A-3).
    // RESUMED 될 때마다 refreshTick 을 올려 폴더 개수·총개수·'적용 중' 점·정렬·배경을 재조회.
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                refreshTick++
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
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
                    title = { WithuTopBarTitle(stringResource(R.string.gallery_title)) },
                    colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                        containerColor = Color.Transparent,
                    ),
                )
            },
        ) { padding ->
            val d = data
            LazyColumn(
                contentPadding = PaddingValues(
                    start = 20.dp, end = 20.dp, top = 8.dp, bottom = 40.dp,
                ),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            ) {
                item {
                    ModePicker(mode = mode, onSelect = { mode = it })
                }

                if (d != null && mode == GalleryMode.BY_STATE) {
                    item {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                stringResource(R.string.gallery_section_state_folders),
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Bold,
                            )
                            Spacer(Modifier.weight(1f))
                            Text(
                                stringResource(R.string.gallery_count, d.totalCount),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    items(sortedFolders(d), key = { it.raw }) { state ->
                        FolderRow(
                            state = state,
                            count = d.counts[state] ?: 0,
                            applied = d.applied.contains(state),
                            hasActiveImage = d.applied.contains(state),
                            firstGalleryId = d.firstIds[state],
                            onClick = { onOpenStateFolder(state) },
                        )
                    }
                    if (d.legacy.isNotEmpty()) {
                        item {
                            LegacyRow(count = d.legacy.size, onClick = onOpenLegacy)
                        }
                    }
                } else if (d != null) {
                    // mode == 캐릭터별 — 2열 썸네일 그리드.
                    // LazyColumn 안에 LazyVerticalGrid 를 중첩하면 높이가 무한대로 잡혀 크래시 —
                    // 2개씩 chunk 해서 Row 로 그린다 (홀수면 마지막 칸은 Spacer 로 자리만 채움).
                    if (d.characters.isEmpty()) {
                        item { ByCharacterEmpty() }
                    } else {
                        items(d.characters.chunked(2), key = { it.first().batchId }) { row ->
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                row.forEach { group ->
                                    CharacterTile(
                                        group = group,
                                        name = d.characterNames[group.batchId],
                                        onOpen = { onOpenBatchGroup(group.batchId) },
                                        modifier = Modifier.weight(1f),
                                    )
                                }
                                if (row.size == 1) Spacer(Modifier.weight(1f))
                            }
                        }
                    }
                }
            }
        }

        // 중앙 빈 상태 — 상태별이고 전체 0개일 때만 (스펙 04 §1.1.5)
        if (data?.totalCount == 0 && mode == GalleryMode.BY_STATE) {
            EmptyStateOverlay(Modifier.align(Alignment.Center))
        }
    }
}

// MARK: - 모드 피커 (상태별 / 캐릭터별)

@Composable
private fun ModePicker(mode: GalleryMode, onSelect: (GalleryMode) -> Unit) {
    val pink = withuPink()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.6f))
            .padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        @Composable
        fun seg(target: GalleryMode, label: String) {
            val selected = mode == target
            Text(
                text = label,
                textAlign = TextAlign.Center,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = if (selected) FontWeight.Bold else FontWeight.Light,
                color = if (selected) Color.White else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(8.dp))
                    .background(if (selected) pink else Color.Transparent)
                    .clickable { onSelect(target) }
                    .padding(vertical = 8.dp),
            )
        }
        seg(GalleryMode.BY_STATE, stringResource(R.string.gallery_mode_by_state))
        seg(GalleryMode.BY_CHARACTER, stringResource(R.string.gallery_mode_by_character))
    }
}

// MARK: - 상태 폴더 행 + 칩

@Composable
private fun FolderRow(
    state: CharacterState,
    count: Int,
    applied: Boolean,
    hasActiveImage: Boolean,
    firstGalleryId: String?,
    onClick: () -> Unit,
) {
    val subtitle = when {
        count == 0 -> stringResource(R.string.gallery_folder_empty_subtitle)
        applied -> stringResource(R.string.gallery_folder_applied_subtitle, count)
        else -> stringResource(R.string.gallery_count, count)
    }
    FrostedCard(
        modifier = Modifier
            .fillMaxWidth()
            .alpha(if (count == 0) 0.55f else 1f)
            .clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            GalleryStateChip(
                state = state,
                hasActiveImage = hasActiveImage,
                firstGalleryId = firstGalleryId,
                showAppliedDot = applied,
                size = 44,
            )
            Spacer(Modifier.size(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    state.koreanShortLabel,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    subtitle,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
            )
        }
    }
}

/**
 * 상태 칩 — iOS GalleryStateChip (스펙 04 §1.1 GalleryStateChip).
 * 적용본이 없고 갤러리 첫 항목이 있으면 그 사진, 아니면 CharacterImage 3단 fallback.
 */
@Composable
private fun GalleryStateChip(
    state: CharacterState,
    hasActiveImage: Boolean,
    firstGalleryId: String?,
    showAppliedDot: Boolean,
    size: Int,
) {
    Box(
        modifier = Modifier
            .size(size.dp)
            .clip(CircleShape)
            .background(state.tint.copy(alpha = 0.22f)),
        contentAlignment = Alignment.Center,
    ) {
        val previewId = if (!hasActiveImage) firstGalleryId else null
        if (previewId != null) {
            val bmp by produceState<Bitmap?>(initialValue = null, previewId) {
                value = withContext(Dispatchers.IO) { CharacterImageStore.loadGalleryImage(previewId) }
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
        // 적용 중이면 우상단 초록 점 (배경색 테두리)
        if (showAppliedDot) {
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .size(9.dp)
                    .background(WithuColors.systemGreen, CircleShape)
                    .border(1.5.dp, MaterialTheme.colorScheme.background, CircleShape),
            )
        }
    }
}

// MARK: - legacy 행

@Composable
private fun LegacyRow(count: Int, onClick: () -> Unit) {
    FrostedCard(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
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
                    stringResource(R.string.gallery_legacy_title),
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    stringResource(R.string.gallery_legacy_subtitle, count),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
            )
        }
    }
}

// MARK: - 캐릭터별 타일 (2열 그리드 한 칸)

/**
 * 캐릭터 타일 — 정사각 카드 + 대표 썸네일, 카드 아래 이름 1줄 (iOS characterTile).
 * '이 캐릭터로 모두 적용'은 랜딩이 아니라 탭해서 들어간 상세(BatchGroupScreen) 상단에 있다.
 */
@Composable
private fun CharacterTile(
    group: GalleryCharacterGroup,
    name: String?,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // 대표 썸네일 — idle 항목 우선, 없으면 첫 항목
    val repId = remember(group) {
        (group.items.firstOrNull { it.sourceState == CharacterState.IDLE.raw } ?: group.items.first()).id
    }
    val bmp by produceState<Bitmap?>(initialValue = null, repId) {
        value = withContext(Dispatchers.IO) { CharacterImageStore.loadGalleryImage(repId) }
    }
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .plainCard(cornerRadius = 16.dp)
                .clickable(onClick = onOpen),
            contentAlignment = Alignment.Center,
        ) {
            val b = bmp
            if (b != null) {
                Image(
                    bitmap = b.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(14.dp),
                )
            } else {
                Icon(
                    Icons.Filled.GridView,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(34.dp),
                )
            }
        }
        Spacer(Modifier.size(8.dp))
        Text(
            text = name ?: stringResource(R.string.gallery_unnamed_character),
            style = MaterialTheme.typography.bodyMedium,
            color = if (name == null) MaterialTheme.colorScheme.onSurfaceVariant
            else MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

// MARK: - 빈 상태

@Composable
private fun ByCharacterEmpty() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 60.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        CharacterImage(
            state = CharacterState.IDLE,
            modifier = Modifier.size(64.dp),
            maxPixelSize = 192,
        )
        Text(
            stringResource(R.string.gallery_by_character_empty),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun EmptyStateOverlay(modifier: Modifier) {
    Column(
        modifier = modifier.padding(horizontal = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // 빈 상태 아이콘 — 캐릭터별 탭·참고사진 피커와 같은 처리 (이모지 제거, iOS 커밋 75d00d1 방향)
        CharacterImage(state = CharacterState.IDLE, modifier = Modifier.size(64.dp))
        Text(
            stringResource(R.string.gallery_empty_title),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )
        Text(
            stringResource(R.string.gallery_empty_body),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

// MARK: - 로직

/**
 * 폴더 정렬 (스펙 04 §3.2) — rank: 적용 중 0 → 항목 있음 1 → 빈 폴더 2.
 * 같은 rank 안에서는 userFacing 선언 순서 유지 (stable).
 */
private fun sortedFolders(d: LandingData): List<CharacterState> {
    fun rank(state: CharacterState): Int = when {
        d.applied.contains(state) -> 0
        (d.counts[state] ?: 0) > 0 -> 1
        else -> 2
    }
    return CharacterState.userFacing.sortedWith(
        compareBy({ rank(it) }, { CharacterState.userFacing.indexOf(it) }),
    )
}

/**
 * '이 캐릭터로 모두 적용' (스펙 04 §3.3) — 각 item 의 sourceState 자리에 적용.
 * 매핑 실패 항목은 skip. 반환 = 실제 적용 성공 개수.
 * 호출 지점은 캐릭터 상세(BatchGroupScreen) 상단 헤더 — 같은 패키지에서 재사용한다.
 */
internal suspend fun applyCharacter(items: List<GalleryItem>): Int = withContext(Dispatchers.IO) {
    var applied = 0
    for (item in items) {
        val state = CharacterState.fromRaw(item.sourceState) ?: continue
        if (CharacterImageStore.applyGalleryItem(item.id, state)) {
            // 워치 전송 지점 — iOS: ConnectivityManager.sendCharacterImage. Wear OS 후속.
            applied++
        }
    }
    applied
}
