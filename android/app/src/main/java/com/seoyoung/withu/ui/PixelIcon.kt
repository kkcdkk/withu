package com.seoyoung.withu.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * 직접 그린 도트 아이콘 — 기성 이모지 대신. Canvas 로 antialiasing 없이 픽셀 사각형만 채운다.
 * iOS Design/VibeKit.swift 의 PixelIcon / PixelIconSet 이식 (그리드 문자열은 iOS 원본 그대로).
 */
@Composable
fun PixelIcon(
    grid: List<List<Boolean>>,
    tint: Color,
    modifier: Modifier = Modifier,
    size: Dp = 20.dp,
) {
    Canvas(modifier = modifier.size(size)) {
        val rows = grid.size
        val cols = grid.maxOfOrNull { it.size } ?: 0
        if (rows == 0 || cols == 0) return@Canvas
        val cell = minOf(this.size.width / cols, this.size.height / rows)
        val ox = (this.size.width - cell * cols) / 2f
        val oy = (this.size.height - cell * rows) / 2f
        grid.forEachIndexed { r, row ->
            row.forEachIndexed { c, filled ->
                if (filled) {
                    drawRect(
                        color = tint,
                        topLeft = Offset(ox + c * cell, oy + r * cell),
                        // 0.5 = 픽셀 사이 실틈 방지 (iOS VibeKit.swift 와 동일)
                        size = Size(cell + 0.5f, cell + 0.5f),
                    )
                }
            }
        }
    }
}

object PixelIconSet {
    /** "#" = 채움, 그 외("." 등) = 빈칸. 줄 길이는 같게. */
    private fun rows(s: String): List<List<Boolean>> =
        s.trimIndent().lines().map { line -> line.map { it == '#' } }

    /** 활동분 — 시계(테두리 + 바늘). */
    val clock = rows(
        """
        ...####...
        .##....##.
        #........#
        #...#....#
        #...#....#
        #...###..#
        #........#
        .##....##.
        ...####...
        """,
    )

    /** kcal — 불꽃. */
    val flame = rows(
        """
        ...##....
        ..###....
        ..##.....
        .##.#....
        ##..##...
        #....##..
        #....##..
        ##...#...
        .##.##...
        ..###....
        """,
    )

    /** 수면 — 초승달. */
    val moon = rows(
        """
        ..###....
        .#####...
        ####.....
        ###......
        ###......
        ###......
        ###......
        ####.....
        .#####...
        ..###....
        """,
    )
}
