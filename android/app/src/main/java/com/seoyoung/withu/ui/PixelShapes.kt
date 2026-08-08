package com.seoyoung.withu.ui

import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp

/**
 * 모서리를 픽셀 계단(2단)으로 깎은 사각형 — iOS Design/VibeKit.swift PixelBorderShape 이식.
 * pixel = 한 계단 크기(카드/버튼 5, 토글 3). 모서리는 2계단(= 2*pixel).
 * Compose 의 border(width, color, shape) 가 shape 안쪽으로 그려주므로 iOS 의 inset 파라미터는 불필요.
 */
data class PixelBorderShape(val pixel: Dp = 5.dp) : Shape {
    override fun createOutline(
        size: Size,
        layoutDirection: LayoutDirection,
        density: Density,
    ): Outline {
        val px = with(density) { pixel.toPx() }
        // 계단이 변 길이를 넘지 않게 제한 (아주 작은 버튼 보호) — iOS VibeKit.swift 와 동일
        val p = minOf(px, minOf(size.width, size.height) / 4f)
        val c = p * 2f
        val minX = 0f
        val minY = 0f
        val maxX = size.width
        val maxY = size.height
        val path = Path().apply {
            moveTo(minX + c, minY)
            lineTo(maxX - c, minY) // 윗변
            lineTo(maxX - p, minY) // TR 2계단
            lineTo(maxX - p, minY + p)
            lineTo(maxX, minY + p)
            lineTo(maxX, minY + c)
            lineTo(maxX, maxY - c) // 오른변
            lineTo(maxX, maxY - p) // BR 2계단
            lineTo(maxX - p, maxY - p)
            lineTo(maxX - p, maxY)
            lineTo(maxX - c, maxY)
            lineTo(minX + c, maxY) // 아랫변
            lineTo(minX + p, maxY) // BL 2계단
            lineTo(minX + p, maxY - p)
            lineTo(minX, maxY - p)
            lineTo(minX, maxY - c)
            lineTo(minX, minY + c) // 왼변
            lineTo(minX, minY + p) // TL 2계단
            lineTo(minX + p, minY + p)
            lineTo(minX + p, minY)
            close()
        }
        return Outline.Generic(path)
    }
}
