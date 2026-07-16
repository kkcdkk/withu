package com.seoyoung.withu.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// iOS OnboardingView.swift 의 브랜드 팔레트 포팅 (라이트/다크)
object WithuColors {
    val pinkLight = Color(0xFFFFC7D9)        // withuPink light — 파스텔
    val pinkDark = Color(0xFF8C526B)         // withuPink dark — 채도 낮은 와인
    val pinkTextLight = Color(0xFFC75278)    // withuPinkText light — 진한 로즈
    val pinkTextDark = Color(0xFFF29EB8)
    val greenLight = Color(0xFF8CCC94)       // withuGreen light — 새싹
    val greenDark = Color(0xFF4D7A5C)
    val ctaGreenLight = Color(0xFF33C759)    // CTA — 아이폰 메시지 초록 톤
    val ctaGreenDark = Color(0xFF299E4A)
    val pinkBackgroundLight = Color(0xFFFFF2F7)
    val pinkBackgroundDark = Color(0xFF1F1419)
}

private val LightScheme = lightColorScheme(
    primary = WithuColors.ctaGreenLight,
    secondary = WithuColors.pinkTextLight,
    tertiary = WithuColors.greenLight,
    background = Color(0xFFF7F7F8),
    surface = Color.White,
)

private val DarkScheme = darkColorScheme(
    primary = WithuColors.ctaGreenDark,
    secondary = WithuColors.pinkTextDark,
    tertiary = WithuColors.greenDark,
    background = Color(0xFF000000),
    surface = Color(0xFF1C1C1E),
)

@Composable
fun WithuTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkScheme else LightScheme,
        content = content,
    )
}
