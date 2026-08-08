package com.seoyoung.withu.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.seoyoung.withu.R

/**
 * iOS Design/VibeKit.swift 의 Font.galmuri / Font.pretendard 대응.
 * - DungGeunMo(둥근모꼴) = 픽셀 폰트, 1웨이트. 홈 텍스트·네비 타이틀·초록 버튼 글씨.
 * - Pretendard = 본문 기본. **Light/Bold 두 웨이트만** 있으므로 SemiBold/Medium 을 쓰면
 *   Compose 가 합성 웨이트로 흐리게 그린다 — 호출부는 Light 또는 Bold 만 쓸 것.
 */
val DungGeunMo = FontFamily(Font(R.font.dunggeunmo))

val Pretendard = FontFamily(
    Font(R.font.pretendard_light, FontWeight.Light),
    Font(R.font.pretendard_bold, FontWeight.Bold),
)

private fun TextStyle.pretendard(): TextStyle =
    copy(fontFamily = Pretendard, fontWeight = FontWeight.Light)

/**
 * iOS 는 루트에 .font(.pretendard(17)) 을 걸어 폰트 미지정 텍스트까지 Pretendard 로 만든다.
 * Compose 등가 = M3 Typography 15개 스타일에 **전부** fontFamily 를 넣는 것
 * (하나라도 빠지면 그 스타일을 쓰는 텍스트가 Roboto 로 남는다).
 */
val WithuTypography: Typography = Typography().let { d ->
    d.copy(
        displayLarge = d.displayLarge.pretendard(),
        displayMedium = d.displayMedium.pretendard(),
        displaySmall = d.displaySmall.pretendard(),
        headlineLarge = d.headlineLarge.pretendard(),
        headlineMedium = d.headlineMedium.pretendard(),
        headlineSmall = d.headlineSmall.pretendard(),
        titleLarge = d.titleLarge.pretendard(),
        titleMedium = d.titleMedium.pretendard(),
        titleSmall = d.titleSmall.pretendard(),
        bodyLarge = d.bodyLarge.pretendard().copy(fontSize = 17.sp), // iOS 본문 17
        bodyMedium = d.bodyMedium.pretendard(),
        bodySmall = d.bodySmall.pretendard(),
        labelLarge = d.labelLarge.pretendard(),
        labelMedium = d.labelMedium.pretendard(),
        labelSmall = d.labelSmall.pretendard().copy(fontSize = 11.sp), // iOS HelperFooter/footer 11
    )
}
