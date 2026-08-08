package com.seoyoung.withu.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// iOS OnboardingView.swift 의 브랜드 팔레트 포팅 (라이트/다크) — 스펙 06 hex
// 2026-07: 브랜드 색 전환 — 연핑크 → 그린(withuGreen 새싹 톤 기준). 이름은 iOS 와 동일하게 유지.
object WithuColors {
    val pinkLight = Color(0xFF8CCC94)        // withuPink light — 새싹 그린 (면적/버튼 배경용, greenLight 와 동일 톤)
    val pinkDark = Color(0xFF4D7A5C)         // withuPink dark — 딥그린
    val pinkSoftLight = Color(0xFFB8E3BD)    // withuPinkSoft — 캐릭터 원 배경, soft chip 등 더 옅은 톤
    val pinkSoftDark = Color(0xFF42664F)
    val pinkTextLight = Color(0xFF338047)    // withuPinkText — 글자·링크·배지용 진한 그린 (파스텔은 안 읽힘)
    val pinkTextDark = Color(0xFF9EDBA8)
    val greenLight = Color(0xFF8CCC94)       // withuGreen light — 새싹 (배경 그라데이션 기조)
    val greenDark = Color(0xFF4D7A5C)
    val ctaGreenLight = Color(0xFF57CC75)    // CTA — 선택 테두리/칩/ProgressView tint (iOS withuCTAGreen)
    val ctaGreenDark = Color(0xFF38A857)
    val pinkBackgroundLight = Color(0xFFF2FCF5)
    val pinkBackgroundDark = Color(0xFF141C17)
    // 홈 '함께할 캐릭터 생성하기' 버튼 전용 — 그린 전환 후에도 원래 연핑크 유지 (사용자 지정, iOS withuHeroPink)
    val heroPinkLight = Color(0xFFFFC7D9)
    val heroPinkDark = Color(0xFF8C526B)

    // iOS 시스템 색 근사 (스펙 06 §5 — 온보딩/StatusPill/tint 칩 공용)
    val systemMint = Color(0xFF00C7BE)
    val systemCyan = Color(0xFF32ADE6)
    val systemOrange = Color(0xFFFF9500)
    val systemIndigo = Color(0xFF5856D6)
    val systemGreen = Color(0xFF34C759)

    // 2026-07 레트로 픽셀 팔레트 (iOS OnboardingView.swift extension Color)
    val pixelOutlineLight = Color(0xFF5C4530)   // withuPixelOutline — 모든 테두리·아이콘·카드 상단바
    val pixelOutlineDark = Color(0xFF382B1F)
    val cardFillLight = Color(0xFFFCF7E8)       // withuCardFill — 카드 표면(크림)
    val cardFillDark = Color(0xFF2B2621)
    val warmBackgroundLight = Color(0xFFF5E8CC) // withuWarmBackground — 화면 배경 상단(베이지)
    val warmBackgroundDark = Color(0xFF1C1A17)
    val sageLight = Color(0xFF8CA880)           // withuSage — 초록 버튼 채움·토글 ON·보조 액센트
    val sageDark = Color(0xFF738C70)
}

// 브랜드 색 접근자 — 앱은 라이트 고정이라 전부 light 값을 돌려준다.
// (iOS withuApp.swift `.preferredColorScheme(.light)` 대응. dark 상수는 참고용으로 남겨 둠 —
//  시스템 다크에서 카드 헤더바/토글/입력칸 대비가 1.10:1 까지 떨어지는 회귀가 있었다.)
@Composable
fun withuPink(): Color = WithuColors.pinkLight

@Composable
fun withuPinkSoft(): Color = WithuColors.pinkSoftLight

@Composable
fun withuPinkText(): Color = WithuColors.pinkTextLight

@Composable
fun withuGreen(): Color = WithuColors.greenLight

@Composable
fun withuCTAGreen(): Color = WithuColors.ctaGreenLight

@Composable
fun withuPinkBackground(): Color = WithuColors.pinkBackgroundLight

@Composable
fun withuHeroPink(): Color = WithuColors.heroPinkLight

@Composable
fun withuPixelOutline(): Color = WithuColors.pixelOutlineLight

@Composable
fun withuCardFill(): Color = WithuColors.cardFillLight

@Composable
fun withuWarmBackground(): Color = WithuColors.warmBackgroundLight

@Composable
fun withuSage(): Color = WithuColors.sageLight

// M3 기본 컨테이너 색(#E7E0EC/#F3EDF7 계열 라벤더 회색)을 덮지 않으면 크림 화면 위에
// 보라빛 시트/다이얼로그/드롭다운이 뜬다 → surface* 계열을 전부 크림·베이지로 고정한다.
private val LightScheme = lightColorScheme(
    primary = WithuColors.sageLight,           // CTA 채움 = 세이지
    onPrimary = Color.White,                   // 명시 — 앞으로 붙는 M3 컴포넌트가 기본색을 물려받지 않게
    secondary = WithuColors.pinkTextLight,
    tertiary = WithuColors.greenLight,
    background = WithuColors.warmBackgroundLight,
    surface = WithuColors.cardFillLight,
    surfaceVariant = WithuColors.warmBackgroundLight,
    surfaceContainerLowest = WithuColors.cardFillLight,
    surfaceContainerLow = WithuColors.cardFillLight,
    surfaceContainer = WithuColors.cardFillLight,       // DropdownMenu
    surfaceContainerHigh = WithuColors.cardFillLight,   // AlertDialog
    surfaceContainerHighest = WithuColors.warmBackgroundLight,
    secondaryContainer = WithuColors.pinkSoftLight,     // SegmentedButton 선택 상태
    onSecondaryContainer = WithuColors.pinkTextLight,
    outline = WithuColors.pixelOutlineLight,
    outlineVariant = WithuColors.pixelOutlineLight,
)

private val DarkScheme = darkColorScheme(
    primary = WithuColors.sageDark,
    secondary = WithuColors.pinkTextDark,
    tertiary = WithuColors.greenDark,
    background = WithuColors.warmBackgroundDark,
    surface = WithuColors.cardFillDark,
    outline = WithuColors.pixelOutlineDark,
    outlineVariant = WithuColors.pixelOutlineDark,
)

/** 앱은 라이트 고정 (iOS `.preferredColorScheme(.light)`) — 시스템 다크 모드를 따라가지 않는다. */
@Composable
fun WithuTheme(
    darkTheme: Boolean = false,
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkScheme else LightScheme,
        typography = WithuTypography,
        content = content,
    )
}
