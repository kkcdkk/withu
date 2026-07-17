package com.seoyoung.withu.character

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.seoyoung.withu.shared.WeatherBackgroundCondition
import kotlinx.coroutines.delay
import kotlin.math.sin

/**
 * 캐릭터 옆 작은 날씨 표현 — iOS WeatherDecorationView 포팅 (스펙 08 §3.5).
 *   - 해/달/구름: 우상단 정적 요소 (drawable weather_<raw> 있으면 그것, 없으면 이모지)
 *   - 비/눈: 영역 전체에 떨어지는 입자 (절차적 모션 — 수식은 스펙 08 §3.5 그대로)
 * size 기본 44 (메인). 위젯(Glance)에선 애니메이션 불가 → 이 컴포저블 미사용.
 */
@Composable
fun WeatherDecoration(
    condition: WeatherBackgroundCondition?,
    size: Dp = 44.dp,
    modifier: Modifier = Modifier,
) {
    if (condition == null) return
    val context = LocalContext.current
    val assetId = remember(condition) {
        context.resources.getIdentifier("weather_${condition.raw}", "drawable", context.packageName)
    }
    when (condition) {
        WeatherBackgroundCondition.SUNNY,
        WeatherBackgroundCondition.CLOUDY,
        WeatherBackgroundCondition.NIGHT -> CornerElement(
            assetId = assetId,
            fallback = condition.fallbackEmoji,
            size = size,
            modifier = modifier,
        )
        WeatherBackgroundCondition.RAINY -> FallingParticles(
            assetId = assetId,
            fallbackSymbol = "💧",
            count = 7,
            particleSize = size * 0.35f,
            fallPeriod = 1.0,
            drift = false,
            modifier = modifier,
        )
        WeatherBackgroundCondition.SNOWY -> FallingParticles(
            assetId = assetId,
            fallbackSymbol = "❄️",
            count = 7,
            particleSize = size * 0.38f,
            fallPeriod = 2.6,
            drift = true,   // 눈만 수평 sine 흔들림
            modifier = modifier,
        )
    }
}

/** 해/달/구름 우상단 정적 — 캐릭터 대비 작게 (size × 0.66, 패딩 size × 0.08). */
@Composable
private fun CornerElement(assetId: Int, fallback: String, size: Dp, modifier: Modifier) {
    val elementSize = size * 0.66f
    Box(modifier.fillMaxSize()) {
        Box(
            Modifier
                .align(Alignment.TopEnd)
                .padding(top = size * 0.08f, end = size * 0.08f)
                .size(elementSize),
            contentAlignment = Alignment.Center,
        ) {
            if (assetId != 0) {
                Image(painterResource(assetId), contentDescription = null, Modifier.fillMaxSize())
            } else {
                EmojiText(fallback, elementSize)
            }
        }
    }
}

/**
 * 영역 전체에 떨어지는 입자 — 비/눈. 24fps 틱, 수식은 iOS 원문 그대로:
 *   startOffset = i/count, phase = (t/fallPeriod + startOffset) mod 1
 *   baseX = width × (i+0.5)/count, jitter = sin(i×7.31)×12
 *   driftX = drift ? sin(t×1.2 + i×1.7)×10 : 0
 *   y = -particleSize + phase × (height + 2×particleSize)
 *   opacity: phase<0.08 페이드인 / phase>0.92 페이드아웃 / 그 외 1
 */
@Composable
private fun FallingParticles(
    assetId: Int,
    fallbackSymbol: String,
    count: Int,
    particleSize: Dp,
    fallPeriod: Double,
    drift: Boolean,
    modifier: Modifier,
) {
    var t by remember { mutableDoubleStateOf(0.0) }
    LaunchedEffect(Unit) {
        var start = -1L
        while (true) {
            withFrameNanos { now ->
                if (start < 0) start = now
                t = (now - start) / 1e9
            }
            delay(1000L / 24)   // 24fps 제한 — iOS TimelineView(minimumInterval 1/24) 대응
        }
    }
    BoxWithConstraints(modifier.fillMaxSize()) {
        val w = maxWidth
        val h = maxHeight
        for (i in 0 until count) {
            val startOffset = i.toDouble() / count
            val phase = ((t / fallPeriod + startOffset) % 1.0).toFloat()
            val baseX = w * ((i + 0.5f) / count)
            val jitter = (sin(i * 7.31) * 12).dp
            val driftX = if (drift) (sin(t * 1.2 + i * 1.7) * 10).dp else 0.dp
            val y = particleSize * -1f + (h + particleSize * 2f) * phase
            val opacity = when {
                phase < 0.08f -> phase / 0.08f
                phase > 0.92f -> (1f - phase) / 0.08f
                else -> 1f
            }
            Box(
                Modifier
                    // position(x, y) = 중심 좌표 — 좌상단 기준 offset 으로 변환
                    .offset(x = baseX + jitter + driftX - particleSize / 2, y = y - particleSize / 2)
                    .size(particleSize)
                    .graphicsLayer { alpha = opacity },
                contentAlignment = Alignment.Center,
            ) {
                if (assetId != 0) {
                    Image(painterResource(assetId), contentDescription = null, Modifier.fillMaxSize())
                } else {
                    EmojiText(fallbackSymbol, particleSize)
                }
            }
        }
    }
}

/** 이모지를 지정 크기(dp→sp)로 렌더 — 폰트 스케일 무시하고 시각 크기 고정. */
@Composable
private fun EmojiText(text: String, size: Dp) {
    val fontSize = with(LocalDensity.current) { size.toSp() }
    Text(text = text, fontSize = fontSize, maxLines = 1, softWrap = false)
}
