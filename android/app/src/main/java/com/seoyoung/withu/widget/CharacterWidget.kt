package com.seoyoung.withu.widget

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.compose.ui.graphics.Color
import androidx.glance.unit.ColorProvider
import com.seoyoung.withu.MainActivity
import com.seoyoung.withu.R
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.shared.CharacterImageStore
import com.seoyoung.withu.shared.SharedAppState
import com.seoyoung.withu.shared.WeatherBackgroundCondition
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Calendar
import kotlin.math.roundToInt

/**
 * 홈 위젯 (Glance) — iOS withuWidget.swift 의 홈화면(system*) 패밀리만 이식 (스펙 12 Part B).
 * 잠금화면 accessory 계열은 Android 대응 개념이 없어 제외.
 *
 * SizeMode.Responsive 로 small / medium / large 3개 브레이크포인트를 근사 —
 * iOS systemSmall / systemMedium / systemLarge 대응.
 * 배경은 투명(스티커 느낌) — 월페이퍼가 비침.
 */
class CharacterWidget : GlanceAppWidget() {

    // iOS 3개 홈 패밀리에 대응하는 근사 브레이크포인트.
    override val sizeMode: SizeMode = SizeMode.Responsive(
        setOf(SMALL, MEDIUM, LARGE),
    )

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        // 데이터/이미지 로드는 파일 I/O — provideContent 전에 IO 에서 끝냄 (스펙 00-PLAN §0-3).
        val entry = withContext(Dispatchers.IO) { CharacterEntry.current() }
        val visual = withContext(Dispatchers.IO) { resolveVisual(context, entry.state) }

        provideContent {
            GlanceTheme {
                WidgetContent(entry, visual)
            }
        }
    }

    companion object {
        private val SMALL = DpSize(110.dp, 110.dp)
        private val MEDIUM = DpSize(220.dp, 110.dp)
        private val LARGE = DpSize(220.dp, 220.dp)
    }
}

// MARK: - 표시 스냅샷 (iOS CharacterEntry 대응)

/** 위젯이 그릴 데이터 한 벌. 없으면 placeholder (idle · 4321보 · 38분 · 412kcal · 7.5h · ☀️18°). */
private data class CharacterEntry(
    val state: CharacterState,
    val todaySteps: Double?,
    val todayActiveMinutes: Double?,
    val todayActiveKcal: Double?,
    val lastSleepHours: Double?,
    val weatherEmoji: String?,
    val weatherTempC: Double?,
    val weatherSunrise: Long?,
    val weatherSunset: Long?,
    val timestamp: Long,
) {
    companion object {
        val placeholder = CharacterEntry(
            state = CharacterState.IDLE,
            todaySteps = 4321.0, todayActiveMinutes = 38.0, todayActiveKcal = 412.0,
            lastSleepHours = 7.5, weatherEmoji = "☀️", weatherTempC = 18.0,
            weatherSunrise = null, weatherSunset = null,
            timestamp = System.currentTimeMillis(),
        )

        fun current(): CharacterEntry {
            val msg = SharedAppState.loadMessage() ?: return placeholder
            return CharacterEntry(
                state = msg.characterState,
                todaySteps = msg.todaySteps,
                todayActiveMinutes = msg.todayActiveMinutes,
                todayActiveKcal = msg.todayActiveKcal,
                lastSleepHours = msg.lastSleepHours,
                weatherEmoji = msg.weatherEmoji,
                weatherTempC = msg.weatherTempC,
                weatherSunrise = msg.weatherSunrise,
                weatherSunset = msg.weatherSunset,
                timestamp = msg.timestamp,
            )
        }
    }
}

/** 캐릭터 이미지 3단 fallback 을 Glance 표현으로 축약 (사용자 PNG → 번들 drawable → 이모지). */
private sealed interface CharVisual {
    data class Bmp(val bitmap: Bitmap) : CharVisual
    data class Res(val resId: Int) : CharVisual
    data object EmojiOnly : CharVisual
}

/**
 * 3단 fallback 해석 — 위젯 메모리 한계 대비 512px 로 다운샘플 (스펙 12 B-2).
 * ① 사용자 적용 PNG → ② 번들 drawable character_<raw> → ③ 이모지.
 */
private fun resolveVisual(context: Context, state: CharacterState): CharVisual {
    val bmp = CharacterImageStore.loadThumbnail(state, 512)
    if (bmp != null) return CharVisual.Bmp(bmp)
    val resId = context.resources.getIdentifier(
        state.imageAssetName, "drawable", context.packageName,
    )
    if (resId != 0) return CharVisual.Res(resId)
    return CharVisual.EmojiOnly
}

// MARK: - 레이아웃 (small / medium / large)

@androidx.compose.runtime.Composable
private fun WidgetContent(entry: CharacterEntry, visual: CharVisual) {
    val size = LocalSize.current
    val context = LocalContext.current
    // 투명 배경 + 탭 시 앱 열기 (iOS Color.clear + widgetURL("withu://main") 대응)
    val root = GlanceModifier
        .fillMaxSize()
        .background(ColorProvider(Color.Transparent))
        .clickable(actionStartActivity(Intent(context, MainActivity::class.java)))

    when {
        size.height >= 200.dp -> LargeLayout(entry, visual, root)
        size.width >= 200.dp -> MediumLayout(entry, visual, root)
        else -> SmallLayout(entry, visual, root)
    }
}

@androidx.compose.runtime.Composable
private fun SmallLayout(entry: CharacterEntry, visual: CharVisual, modifier: GlanceModifier) {
    val context = LocalContext.current
    val weather = weatherLine(context, entry)
    val metric = smallMetricLine(context, entry)
    Column(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (weather != null) {
            Text(weather, style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Bold, color = onSurface()))
        }
        CharacterVisualBox(visual, entry, imageDp = 46.dp, decoSp = 12.sp, emojiSp = 28.sp)
        if (metric.isNotEmpty()) {
            Text(metric, style = TextStyle(fontSize = 9.sp, color = onSurfaceVariant()))
        }
    }
}

@androidx.compose.runtime.Composable
private fun MediumLayout(entry: CharacterEntry, visual: CharVisual, modifier: GlanceModifier) {
    val context = LocalContext.current
    val weather = weatherLine(context, entry)
    Row(
        modifier = modifier.padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CharacterVisualBox(visual, entry, imageDp = 64.dp, decoSp = 16.sp, emojiSp = 40.sp)
            Text(
                entry.state.caption,
                style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Bold, color = onSurface()),
            )
        }
        Spacer(GlanceModifier.width(12.dp))
        Column(verticalAlignment = Alignment.CenterVertically) {
            if (weather != null) {
                Text(weather, style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold, color = onSurface()))
            }
            FitnessRows(context, entry, fontSp = 12.sp)
        }
    }
}

@androidx.compose.runtime.Composable
private fun LargeLayout(entry: CharacterEntry, visual: CharVisual, modifier: GlanceModifier) {
    val context = LocalContext.current
    val weather = weatherLine(context, entry)
    Column(
        modifier = modifier.padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (weather != null) {
            Text(weather, style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Bold, color = onSurface()))
        }
        CharacterVisualBox(visual, entry, imageDp = 120.dp, decoSp = 28.sp, emojiSp = 72.sp)
        Text(
            entry.state.caption,
            style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold, color = onSurface()),
        )
        // iOS Divider 근사 — 얇은 가로선.
        Spacer(GlanceModifier.height(6.dp))
        Box(
            GlanceModifier.height(1.dp).fillMaxWidth().padding(horizontal = 40.dp)
                .background(onSurfaceVariant()),
        ) {}
        Spacer(GlanceModifier.height(6.dp))
        FitnessRows(context, entry, fontSp = 14.sp)
    }
}

/** 캐릭터 이미지 + 날씨 데코 오버레이 (iOS ZStack + WeatherDecorationView offset 대응). */
@androidx.compose.runtime.Composable
private fun CharacterVisualBox(
    visual: CharVisual,
    entry: CharacterEntry,
    imageDp: androidx.compose.ui.unit.Dp,
    decoSp: TextUnit,
    emojiSp: TextUnit,
) {
    Box(
        modifier = GlanceModifier.size(imageDp),
        contentAlignment = Alignment.Center,
    ) {
        when (visual) {
            is CharVisual.Bmp -> Image(
                provider = ImageProvider(visual.bitmap),
                contentDescription = null,
                modifier = GlanceModifier.size(imageDp),
                contentScale = ContentScale.Fit,
            )
            is CharVisual.Res -> Image(
                provider = ImageProvider(visual.resId),
                contentDescription = null,
                modifier = GlanceModifier.size(imageDp),
                contentScale = ContentScale.Fit,
            )
            CharVisual.EmojiOnly -> Text(
                entry.state.symbolEmoji,
                style = TextStyle(fontSize = emojiSp),
            )
        }
        // 데코는 상단 중앙에 작게 (iOS offset(y: -n) 근사).
        val deco = widgetDecoEmoji(entry)
        if (deco != null) {
            Box(
                modifier = GlanceModifier.fillMaxSize(),
                contentAlignment = Alignment.TopCenter,
            ) {
                Text(deco, style = TextStyle(fontSize = decoSp))
            }
        }
    }
}

/** 건강 metric 행들 — iOS fitnessRows 포팅. 걸음은 nil 만 생략(0도 표시), 나머지는 >0. */
@androidx.compose.runtime.Composable
private fun FitnessRows(context: Context, entry: CharacterEntry, fontSp: TextUnit) {
    Column {
        for (line in fitnessRowLines(context, entry)) {
            Text(line, style = TextStyle(fontSize = fontSp, color = onSurfaceVariant()))
        }
    }
}

// MARK: - 텍스트 helpers (iOS 동명 함수 포팅)

private fun fitnessRowLines(context: Context, entry: CharacterEntry): List<String> = buildList {
    entry.todaySteps?.let { add(context.getString(R.string.widget_steps, it.toInt())) }
    entry.todayActiveMinutes?.let { if (it > 0) add(context.getString(R.string.widget_active_minutes, it.toInt())) }
    entry.todayActiveKcal?.let { if (it > 0) add(context.getString(R.string.widget_kcal, it.toInt())) }
    entry.lastSleepHours?.let { if (it > 0) add(context.getString(R.string.widget_sleep, formatHours(context, it))) }
}

/** 맨 위 한 줄: 날씨 이모지 + 온도. 둘 다 없으면 null. */
private fun weatherLine(context: Context, entry: CharacterEntry): String? {
    val emoji = entry.weatherEmoji ?: ""
    val t = entry.weatherTempC
    if (t != null) {
        val head = if (emoji.isEmpty()) "" else "$emoji "
        return head + context.getString(R.string.widget_temp, t.roundToInt())
    }
    return if (emoji.isEmpty()) null else emoji
}

/** systemSmall 압축 한 줄 — 걸음(>0) · 수면(>0). 이모지는 코드 상수 (기호). */
private fun smallMetricLine(context: Context, entry: CharacterEntry): String {
    val parts = buildList {
        entry.todaySteps?.let { if (it > 0) add("👟" + it.toInt()) }
        entry.lastSleepHours?.let { if (it > 0) add("💤" + formatHours(context, it)) }
    }
    return parts.joinToString(" · ")
}

private fun formatHours(context: Context, h: Double): String {
    if (h < 1) return context.getString(R.string.widget_hours_minutes, (h * 60).toInt())
    val whole = h.toInt()
    val frac = ((h - whole) * 10).toInt()
    return if (frac == 0) {
        context.getString(R.string.widget_hours_whole, whole)
    } else {
        context.getString(R.string.widget_hours_frac, whole, frac)
    }
}

/**
 * 위젯 날씨 데코 이모지 — 1순위 일출/일몰 야간이면 🌙, 아니면 emoji → 조건 매핑.
 * iOS widgetWeatherCondition 포팅 (CharacterImageStore.isCurrentlyNight 분 단위 버전 사용).
 */
private fun widgetDecoEmoji(entry: CharacterEntry): String? {
    val nowMin = minuteOfDay(entry.timestamp)
    val sunriseMin = entry.weatherSunrise?.let { minuteOfDay(it) }
    val sunsetMin = entry.weatherSunset?.let { minuteOfDay(it) }
    val night = CharacterImageStore.isCurrentlyNight(nowMin, sunriseMin, sunsetMin)
    val condition = if (night) {
        WeatherBackgroundCondition.NIGHT
    } else {
        WeatherBackgroundCondition.fromEmoji(entry.weatherEmoji)
    }
    return condition?.fallbackEmoji
}

private fun minuteOfDay(millis: Long): Int {
    val cal = Calendar.getInstance().apply { timeInMillis = millis }
    return cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
}

// 위젯 텍스트 색 — 월페이퍼 위에서도 읽히도록 테마 적응색 사용.
@androidx.compose.runtime.Composable
private fun onSurface(): ColorProvider = GlanceTheme.colors.onSurface

@androidx.compose.runtime.Composable
private fun onSurfaceVariant(): ColorProvider = GlanceTheme.colors.onSurfaceVariant
