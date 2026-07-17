package com.seoyoung.withu.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.seoyoung.withu.character.CharacterImage
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.ui.theme.WithuColors
import com.seoyoung.withu.ui.theme.withuCTAGreen
import com.seoyoung.withu.ui.theme.withuGreen
import com.seoyoung.withu.ui.theme.withuPink
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * 공용 디자인 컴포넌트 — iOS VibeKit.swift 대응 (00-PLAN §2-10).
 * 규칙: frosted 카드 · state.tint 그라데이션 배경 · semibold 상한 · 평서형 한국어.
 * frosted = 배경 블러 대신 반투명 표면 + 얇은 보더로 근사 (Compose 블러 비용 큼).
 */

enum class StatusKind { OK, WARNING, OFF }

/** 모든 카드 표면의 단일 recipe. 솔리드 색·그림자 금지 — 반투명 표면 근사. */
@Composable
fun FrostedCard(
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 14.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(cornerRadius)
    Column(
        modifier = modifier
            .clip(shape)
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.72f))
            .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f), shape)
            .padding(14.dp),
        content = content,
    )
}

/** iOS Form 섹션 근사 — 헤더(caption) + 카드 + 푸터(caption2). */
@Composable
fun FormSection(
    header: String? = null,
    footer: String? = null,
    footerColor: Color? = null,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier = modifier.fillMaxWidth()) {
        if (header != null) {
            Text(
                text = header,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 4.dp, vertical = 6.dp),
            )
        }
        FrostedCard(modifier = Modifier.fillMaxWidth(), content = content)
        if (footer != null) {
            Text(
                text = footer,
                style = MaterialTheme.typography.labelSmall,
                color = footerColor ?: MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 4.dp, vertical = 6.dp),
            )
        }
    }
}

/** 카드 위 작은 그룹 라벨 + (선택) 우측 보조 요소 — iOS SectionHeader 대응. */
@Composable
fun SectionHeader(
    title: String,
    modifier: Modifier = Modifier,
    trailing: (@Composable RowScope.() -> Unit)? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.weight(1f))
        if (trailing != null) trailing()
    }
}

/** 액션 행 우측 보조 표시 — iOS ActionLinkTrailing 대응. */
sealed class ActionLinkTrailing {
    data object Chevron : ActionLinkTrailing()
    data object Checkmark : ActionLinkTrailing()
    data object None : ActionLinkTrailing()
    data class Text(val value: String) : ActionLinkTrailing()
}

/**
 * 메뉴 카드의 핵심 프리미티브 — 44dp tint 칩 + 제목/부제 + 우측 보조 (iOS ActionLinkRow).
 * onClick 이 null 이면 표시 전용.
 */
@Composable
fun ActionLinkRow(
    tint: Color,
    icon: ImageVector,
    title: String,
    subtitle: String? = null,
    trailing: ActionLinkTrailing = ActionLinkTrailing.Chevron,
    dimmed: Boolean = false,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
) {
    val shape = RoundedCornerShape(14.dp)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.72f))
            .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f), shape)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(14.dp)
            .alpha(if (dimmed) 0.55f else 1f),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            Modifier
                .size(44.dp)
                .background(tint.copy(alpha = 0.18f), RoundedCornerShape(12.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = tint)
        }
        Column(Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            if (subtitle != null) {
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        when (trailing) {
            ActionLinkTrailing.Chevron -> Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            )
            ActionLinkTrailing.Checkmark -> Icon(
                Icons.Filled.Check,
                contentDescription = null,
                tint = tint,
            )
            ActionLinkTrailing.None -> Unit
            is ActionLinkTrailing.Text -> Text(
                text = trailing.value,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
            )
        }
    }
}

/** 권한·연결 등 상태 한 줄 — ✅/⚠️/❌ 이모지 대체 (아이콘 + 의미색). */
@Composable
fun StatusPill(kind: StatusKind, text: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        val (icon, color) = when (kind) {
            StatusKind.OK -> Icons.Filled.CheckCircle to WithuColors.systemGreen
            StatusKind.WARNING -> Icons.Filled.Warning to WithuColors.systemOrange
            StatusKind.OFF -> Icons.Filled.Cancel to MaterialTheme.colorScheme.onSurfaceVariant
        }
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(14.dp))
        Text(
            text = text,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * CTA 공용 버튼 — 진한 그린 배경 + 흰 글자 (iOS WithuCTAButtonStyle 대응).
 * 누르는 동안 어두워지고 살짝 축소돼 '눌림'이 확실히 보인다. 비활성 opacity 0.45.
 */
@Composable
fun WithuCTAButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    loading: Boolean = false,
) {
    PressableFilledButton(
        text = text,
        onClick = onClick,
        background = withuCTAGreen(),
        cornerRadius = 12.dp,
        modifier = modifier,
        enabled = enabled,
        loading = loading,
    )
}

/** 온보딩/승인용 핑크 버튼 — CTA 그린이 아니라 withuPink + 흰 글자, 라운드 14 (스펙 06 §5). */
@Composable
fun WithuPinkButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    PressableFilledButton(
        text = text,
        onClick = onClick,
        background = withuPink(),
        cornerRadius = 14.dp,
        modifier = modifier,
        enabled = enabled,
        loading = false,
    )
}

@Composable
private fun PressableFilledButton(
    text: String,
    onClick: () -> Unit,
    background: Color,
    cornerRadius: Dp,
    modifier: Modifier,
    enabled: Boolean,
    loading: Boolean,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.97f else 1f, label = "ctaScale")
    val shape = RoundedCornerShape(cornerRadius)
    Box(
        modifier = modifier
            .graphicsLayer { scaleX = scale; scaleY = scale }
            .clip(shape)
            .background(background)
            .background(if (pressed) Color.Black.copy(alpha = 0.22f) else Color.Transparent)
            .clickable(
                interactionSource = interaction,
                indication = null,
                enabled = enabled && !loading,
                onClick = onClick,
            )
            .alpha(if (enabled) 1f else 0.45f)
            .padding(horizontal = 14.dp, vertical = 11.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (loading) {
            CircularProgressIndicator(
                modifier = Modifier.size(18.dp),
                strokeWidth = 2.dp,
                color = Color.White,
            )
        } else {
            Text(
                text = text,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
            )
        }
    }
}

/** 아이콘 새로고침 버튼 — 실행 중엔 미니 스피너. 최소 0.5초 스피너로 '눌렸다' 피드백. */
@Composable
fun RefreshIconButton(
    action: suspend () -> Unit,
    modifier: Modifier = Modifier,
) {
    var isRunning by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    if (isRunning) {
        CircularProgressIndicator(modifier = modifier.size(16.dp), strokeWidth = 2.dp)
    } else {
        IconButton(
            onClick = {
                scope.launch {
                    isRunning = true
                    val started = System.currentTimeMillis()
                    action()
                    val elapsed = System.currentTimeMillis() - started
                    if (elapsed < 500) delay(500 - elapsed)
                    isRunning = false
                }
            },
            modifier = modifier,
        ) {
            Icon(
                Icons.Filled.Refresh,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(16.dp),
            )
        }
    }
}

/** 행 새로고침 버튼 — 실행 중엔 우측 미니 스피너 + 재탭 방지. */
@Composable
fun RefreshRowButton(
    title: String,
    action: suspend () -> Unit,
    modifier: Modifier = Modifier,
) {
    var isRunning by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .clickable(enabled = !isRunning) {
                scope.launch {
                    isRunning = true
                    val started = System.currentTimeMillis()
                    action()
                    val elapsed = System.currentTimeMillis() - started
                    if (elapsed < 500) delay(500 - elapsed)
                    isRunning = false
                }
            }
            .padding(horizontal = 4.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            Icons.Filled.Refresh,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(18.dp),
        )
        Spacer(Modifier.width(10.dp))
        Text(text = title, style = MaterialTheme.typography.bodyMedium)
        Spacer(Modifier.weight(1f))
        if (isRunning) {
            CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
        }
    }
}

/** 카드·섹션 하단 친절 안내. 평서형 한 줄. */
@Composable
fun HelperFooter(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier.padding(horizontal = 4.dp),
    )
}

/** 오류/주의 배너 — .red 직접 사용 대체 (주황 삼각형 + 옅은 주황 배경). */
@Composable
fun WarningBanner(text: String, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(WithuColors.systemOrange.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(
            Icons.Filled.Warning,
            contentDescription = null,
            tint = WithuColors.systemOrange,
            modifier = Modifier.size(18.dp),
        )
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.weight(1f),
        )
    }
}

/** 하단 캡슐 토스트 — text 가 null 이면 숨김 (fade). */
@Composable
fun CapsuleToast(text: String?, modifier: Modifier = Modifier) {
    // 사라지는 애니메이션 동안 마지막 문구를 유지 (visible=false 인 순간 빈 캡슐 방지)
    var lastText by remember { mutableStateOf("") }
    if (text != null) lastText = text
    AnimatedVisibility(
        visible = text != null,
        enter = fadeIn(),
        exit = fadeOut(),
        modifier = modifier,
    ) {
        Box(
            Modifier
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.inverseSurface.copy(alpha = 0.92f))
                .padding(horizontal = 16.dp, vertical = 10.dp),
        ) {
            Text(
                text = lastText,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.inverseOnSurface,
            )
        }
    }
}

/** 🍬 보유 캔디 툴바 배지 — 탭하면 페이월. */
@Composable
fun CandyBadge(candy: Int, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(withuPink().copy(alpha = 0.18f))
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "🍬 $candy",
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

/** 현재 적용된 캐릭터를 보여주는 원형 칩 (설정 미리보기 등) — iOS KoreanStateChip. */
@Composable
fun KoreanStateChip(state: CharacterState, size: Dp = 44.dp, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(size)
            .background(state.tint.copy(alpha = 0.22f), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        // iOS: 컨테이너 크기의 12% 패딩
        CharacterImage(
            state = state,
            modifier = Modifier
                .size(size)
                .padding(size * 0.12f),
        )
    }
}

/**
 * 서브 화면 공통 배경 그라데이션 — 브랜드 그린 기조 + 상태 무드는 옅게 (iOS backgroundGradient).
 * top → bottom: withuGreen 0.14 → state.tint 0.04 → 시스템 배경.
 */
@Composable
fun rememberBackgroundGradient(state: CharacterState): Brush {
    val green = withuGreen()
    val background = MaterialTheme.colorScheme.background
    return remember(state, green, background) {
        Brush.verticalGradient(
            listOf(
                green.copy(alpha = 0.14f),
                state.tint.copy(alpha = 0.04f),
                background,
            ),
        )
    }
}
