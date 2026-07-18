package com.seoyoung.withu.wear.tile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.DimensionBuilders.expand
import androidx.wear.protolayout.DimensionBuilders.sp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.seoyoung.withu.wear.WearCharacter
import com.seoyoung.withu.wear.WearStore
import java.nio.ByteBuffer

/**
 * 캐릭터 Tile(=워치 위젯) — 애플워치 컴플리케이션 대응.
 * 폰이 push 해 WearStore 에 저장된 현재 상태 + 캐릭터 이미지를 그린다(재계산 없음).
 *
 * 이미지: 인라인 RGB_565(타일 인라인 이미지는 raw 픽셀만 지원). 투명 PNG 는
 * 타일 배경색 위에 합성해 알파를 없앤 뒤 넘긴다 → 캐릭터가 타일에 자연스럽게 얹힌다.
 */
class CharacterTileService : TileService() {

    override fun onTileRequest(
        requestParams: RequestBuilders.TileRequest,
    ): ListenableFuture<TileBuilders.Tile> {
        val snap = WearStore.loadSnapshot(this)
        val tile = TileBuilders.Tile.Builder()
            .setResourcesVersion(versionFor(snap))
            .setTileTimeline(TimelineBuilders.Timeline.fromLayoutElement(layout(snap)))
            .setFreshnessIntervalMillis(30 * 60 * 1000L)
            .build()
        return Futures.immediateFuture(tile)
    }

    override fun onTileResourcesRequest(
        requestParams: RequestBuilders.ResourcesRequest,
    ): ListenableFuture<ResourceBuilders.Resources> {
        val snap = WearStore.loadSnapshot(this)
        val builder = ResourceBuilders.Resources.Builder().setVersion(versionFor(snap))
        val bytes = if (snap.stateRaw != null) charImageRgb565(snap.stateRaw) else null
        if (bytes != null) {
            builder.addIdToImageMapping(
                RES_CHAR,
                ResourceBuilders.ImageResource.Builder()
                    .setInlineResource(
                        ResourceBuilders.InlineImageResource.Builder()
                            .setData(bytes)
                            .setWidthPx(IMG_PX)
                            .setHeightPx(IMG_PX)
                            .setFormat(ResourceBuilders.IMAGE_FORMAT_RGB_565)
                            .build(),
                    )
                    .build(),
            )
        }
        return Futures.immediateFuture(builder.build())
    }

    // --- 레이아웃 ---

    private fun layout(snap: WearStore.Snapshot): LayoutElementBuilders.LayoutElement {
        val bg = ModifiersBuilders.Modifiers.Builder()
            .setBackground(
                ModifiersBuilders.Background.Builder().setColor(argb(TILE_BG)).build(),
            )
            .build()

        if (snap.stateRaw == null) {
            return LayoutElementBuilders.Box.Builder()
                .setWidth(expand())
                .setHeight(expand())
                .setModifiers(bg)
                .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
                .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
                .addContent(text("폰에서 기다리는 중…", 14f, 0xFFBBBBBB.toInt()))
                .build()
        }

        val col = LayoutElementBuilders.Column.Builder()
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .addContent(
                LayoutElementBuilders.Image.Builder()
                    .setResourceId(RES_CHAR)
                    .setWidth(dp(72f))
                    .setHeight(dp(72f))
                    .build(),
            )
            .addContent(spacer(6f))
            .addContent(text(WearCharacter.shortLabel(snap.stateRaw), 16f, 0xFFFFFFFF.toInt()))

        val sub = subtitle(snap)
        if (sub.isNotBlank()) {
            col.addContent(spacer(2f))
            col.addContent(text(sub, 13f, 0xFFB0B0B0.toInt()))
        }

        return LayoutElementBuilders.Box.Builder()
            .setWidth(expand())
            .setHeight(expand())
            .setModifiers(bg)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .addContent(col.build())
            .build()
    }

    private fun subtitle(snap: WearStore.Snapshot): String {
        val parts = mutableListOf<String>()
        snap.steps?.let { parts.add("👟 ${it}보") }
        val weather = buildString {
            snap.weatherEmoji?.let { append(it) }
            snap.tempC?.let { if (isNotEmpty()) append(" "); append("$it°") }
        }
        if (weather.isNotBlank()) parts.add(weather)
        return parts.joinToString("   ")
    }

    private fun text(s: String, size: Float, color: Int): LayoutElementBuilders.Text =
        LayoutElementBuilders.Text.Builder()
            .setText(s)
            .setFontStyle(
                LayoutElementBuilders.FontStyle.Builder()
                    .setSize(sp(size))
                    .setColor(argb(color))
                    .build(),
            )
            .build()

    private fun spacer(h: Float): LayoutElementBuilders.Spacer =
        LayoutElementBuilders.Spacer.Builder().setHeight(dp(h)).build()

    // --- 이미지 (RGB_565 인라인) ---

    private fun charImageRgb565(stateRaw: String): ByteArray? {
        val src = WearStore.loadImage(this, stateRaw) ?: loadFallbackDrawable(stateRaw) ?: return null
        val scaled = Bitmap.createScaledBitmap(src, IMG_PX, IMG_PX, true)
        val out = Bitmap.createBitmap(IMG_PX, IMG_PX, Bitmap.Config.RGB_565)
        Canvas(out).apply {
            drawColor(TILE_BG)           // 투명 영역을 타일 배경색으로 → 알파 제거
            drawBitmap(scaled, 0f, 0f, null)
        }
        val buf = ByteBuffer.allocate(IMG_PX * IMG_PX * 2)
        out.copyPixelsToBuffer(buf)
        return buf.array()
    }

    private fun loadFallbackDrawable(stateRaw: String): Bitmap? {
        val name = WearCharacter.fallbackDrawableName(stateRaw)
        val id = resources.getIdentifier(name, "drawable", packageName)
        if (id == 0) return null
        return runCatching { BitmapFactory.decodeResource(resources, id) }.getOrNull()
    }

    private fun versionFor(snap: WearStore.Snapshot): String {
        val len = snap.stateRaw?.let { WearStore.loadImageBytes(this, it)?.size ?: 0 } ?: 0
        return "${snap.stateRaw}:${len}:${snap.updatedAt}"
    }

    companion object {
        private const val RES_CHAR = "char"
        private const val IMG_PX = 84            // 인라인 raw 픽셀 크기 (폰 push 다운샘플 100px 이하)
        private const val TILE_BG = 0xFF17171A.toInt()
    }
}
