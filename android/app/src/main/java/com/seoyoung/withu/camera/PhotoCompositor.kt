package com.seoyoung.withu.camera

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import androidx.compose.ui.graphics.toArgb
import androidx.core.content.res.ResourcesCompat
import com.seoyoung.withu.WithuApp
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.shared.CharacterImageStore

/**
 * 촬영된 사진 위에 여러 캐릭터를 합성해서 최종 Bitmap 을 만드는 유틸 —
 * iOS PhotoCompositor.swift 포팅 (스펙 12 A-3).
 *
 * 캐릭터 이미지 3단 fallback (순서 변경 금지):
 *   1) CharacterImageStore.load — 사용자 적용 PNG
 *   2) 번들 drawable character_<raw소문자>
 *   3) tint 18% 원 배경 + 이모지 (iOS 는 SF Symbol — Android 엔 symbolName 대응이 없어
 *      CharacterImage 3단과 같은 symbolEmoji 로 근사, 크기 = rect 너비의 55%)
 *
 * ⚠️ CharacterImageStore.load 는 파일 I/O — caller 가 Dispatchers.IO 에서 호출할 것.
 */
object PhotoCompositor {

    fun compose(photo: Bitmap, placed: List<PlacedCharacter>): Bitmap {
        val out = Bitmap.createBitmap(photo.width, photo.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        canvas.drawBitmap(photo, 0f, 0f, paint)

        for (character in placed) {
            val rect = character.rect(photo.width.toFloat(), photo.height.toFloat())
            if (character.rotation != 0f) {
                // 캐릭터 자기 중심 기준 회전 — iOS 의 translate/rotate/translate 와 동일
                canvas.save()
                canvas.rotate(
                    Math.toDegrees(character.rotation.toDouble()).toFloat(),
                    rect.centerX(),
                    rect.centerY(),
                )
                drawCharacter(canvas, paint, character.state, rect)
                canvas.restore()
            } else {
                drawCharacter(canvas, paint, character.state, rect)
            }
        }
        return out
    }

    /** 한 캐릭터 합성. 사용자 이미지 → 번들 drawable → 이모지 fallback. */
    private fun drawCharacter(canvas: Canvas, paint: Paint, state: CharacterState, rect: RectF) {
        val userImage = CharacterImageStore.load(state)
        if (userImage != null) {
            drawAspectFit(canvas, paint, userImage, rect)
            return
        }
        val context = WithuApp.context
        val resId = context.resources.getIdentifier(
            state.imageAssetName, "drawable", context.packageName,
        )
        if (resId != 0) {
            val drawable = ResourcesCompat.getDrawable(context.resources, resId, context.theme)
            if (drawable != null) {
                val iw = drawable.intrinsicWidth.toFloat()
                val ih = drawable.intrinsicHeight.toFloat()
                val fit = if (iw > 0f && ih > 0f) aspectFitRect(iw, ih, rect) else rect
                drawable.setBounds(
                    fit.left.toInt(), fit.top.toInt(),
                    fit.right.toInt(), fit.bottom.toInt(),
                )
                drawable.draw(canvas)
                return
            }
        }
        drawEmojiFallback(canvas, state, rect)
    }

    /** rect 안 중앙 정렬 aspect-fit — iOS drawAspectFit 동일 규칙. */
    private fun aspectFitRect(imageWidth: Float, imageHeight: Float, rect: RectF): RectF {
        val scale = minOf(rect.width() / imageWidth, rect.height() / imageHeight)
        val w = imageWidth * scale
        val h = imageHeight * scale
        val left = rect.centerX() - w / 2f
        val top = rect.centerY() - h / 2f
        return RectF(left, top, left + w, top + h)
    }

    private fun drawAspectFit(canvas: Canvas, paint: Paint, image: Bitmap, rect: RectF) {
        if (image.width <= 0 || image.height <= 0) return
        val dst = aspectFitRect(image.width.toFloat(), image.height.toFloat(), rect)
        canvas.drawBitmap(image, null, dst, paint)
    }

    /** 최후 fallback — tint 18% 원 + 이모지 (rect 너비의 55%). 절대 깨지지 않음. */
    private fun drawEmojiFallback(canvas: Canvas, state: CharacterState, rect: RectF) {
        val circlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = state.tint.toArgb()
            alpha = (255 * 0.18f).toInt()
            style = Paint.Style.FILL
        }
        canvas.drawOval(rect, circlePaint)

        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = rect.width() * 0.55f
            textAlign = Paint.Align.CENTER
        }
        // 폰트 메트릭 기준 수직 중앙 정렬
        val fm = textPaint.fontMetrics
        val baseline = rect.centerY() - (fm.ascent + fm.descent) / 2f
        canvas.drawText(state.symbolEmoji, rect.centerX(), baseline, textPaint)
    }
}
