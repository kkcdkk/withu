package com.seoyoung.withu.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// iOS OnboardingView.swift 의 브랜드 팔레트 포팅 (라이트/다크) — 스펙 06 hex
object WithuColors {
    val pinkLight = Color(0xFFFFC7D9)        // withuPink light — 파스텔 (면적/버튼 배경용)
    val pinkDark = Color(0xFF8C526B)         // withuPink dark — 채도 낮은 와인
    val pinkSoftLight = Color(0xFFFFD9EB)    // withuPinkSoft — 캐릭터 원 배경, soft chip 등 더 옅은 톤
    val pinkSoftDark = Color(0xFF73475C)
    val pinkTextLight = Color(0xFFC75278)    // withuPinkText — 글자·링크·배지용 진한 로즈 (파스텔은 안 읽힘)
    val pinkTextDark = Color(0xFFF29EB8)
    val greenLight = Color(0xFF8CCC94)       // withuGreen light — 새싹 (배경 그라데이션 기조)
    val greenDark = Color(0xFF4D7A5C)
    val ctaGreenLight = Color(0xFF33C759)    // CTA — 아이폰 메시지 초록 톤 (흰 글자 대비)
    val ctaGreenDark = Color(0xFF299E4A)
    val pinkBackgroundLight = Color(0xFFFFF2F7)
    val pinkBackgroundDark = Color(0xFF1F1419)

    // iOS 시스템 색 근사 (스펙 06 §5 — 온보딩/StatusPill/tint 칩 공용)
    val systemMint = Color(0xFF00C7BE)
    val systemCyan = Color(0xFF32ADE6)
    val systemOrange = Color(0xFFFF9500)
    val systemIndigo = Color(0xFF5856D6)
    val systemGreen = Color(0xFF34C759)
}

// 라이트/다크 대응 브랜드 색 접근자 — 화면 코드는 이걸 쓰면 다크 분기를 신경 쓸 필요 없음.
@Composable
fun withuPink(): Color =
    if (isSystemInDarkTheme()) WithuColors.pinkDark else WithuColors.pinkLight

@Composable
fun withuPinkSoft(): Color =
    if (isSystemInDarkTheme()) WithuColors.pinkSoftDark else WithuColors.pinkSoftLight

@Composable
fun withuPinkText(): Color =
    if (isSystemInDarkTheme()) WithuColors.pinkTextDark else WithuColors.pinkTextLight

@Composable
fun withuGreen(): Color =
    if (isSystemInDarkTheme()) WithuColors.greenDark else WithuColors.greenLight

@Composable
fun withuCTAGreen(): Color =
    if (isSystemInDarkTheme()) WithuColors.ctaGreenDark else WithuColors.ctaGreenLight

@Composable
fun withuPinkBackground(): Color =
    if (isSystemInDarkTheme()) WithuColors.pinkBackgroundDark else WithuColors.pinkBackgroundLight

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
