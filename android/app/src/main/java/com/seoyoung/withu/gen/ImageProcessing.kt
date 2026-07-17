package com.seoyoung.withu.gen

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.util.Base64
import android.graphics.BitmapFactory
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * 이미지 가공 유틸 — iOS ImageProcessing.swift 포팅 (00-PLAN §2-9 계약).
 * 전부 CPU 픽셀 연산 — caller 가 Dispatchers.IO/Default 에서 호출할 것.
 */
object ImageProcessing {

    /** gpt-image-2 마젠타 배경 제거 — 기존 ChromaKey 구현에 위임 (계약: 투명 결과엔 no-op). */
    fun chromaKeyRemoved(src: Bitmap): Bitmap = ChromaKey.removed(src)

    /**
     * 알파(투명)가 있으면 흰 배경에 합성해 평탄화.
     * frame0 은 생성(흰배경)인데 frame1 은 edit 라 모델이 가끔 알파를 만들어 배경이 어긋남 → 통일용.
     * 알파 없으면 원본 그대로 반환 (no-op).
     */
    fun flattenedOnWhite(src: Bitmap): Bitmap {
        if (!src.hasAlpha()) return src
        val out = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawColor(Color.WHITE)
        canvas.drawBitmap(src, 0f, 0f, null)
        return out
    }

    /**
     * 애니메이션 2번째 장면(image)을 reference(1번째)와 같은 크기·위치로 정규화.
     * alpha bbox 로 전경을 잘라 reference 전경 bbox 위치·크기에 aspect-fit 재배치 —
     * 크기/위치만 1번째에 맞추고 투명은 유지. 전경을 못 찾으면 원본 그대로.
     */
    fun matchedToReference(image: Bitmap, reference: Bitmap): Bitmap {
        val target = 1024
        val imgBox = alphaBoundingBox(image) ?: return image
        val refBox = alphaBoundingBox(reference) ?: return image
        if (image.width <= 0 || image.height <= 0 || reference.width <= 0 || reference.height <= 0) {
            return image
        }
        // 전경이 거의 안 잡히면(이상치) 원본 유지 — 조각 확대 방지.
        if (imgBox.width().toFloat() / image.width < 0.1f &&
            imgBox.height().toFloat() / image.height < 0.1f
        ) {
            return image
        }
        val refW = reference.width.toFloat()
        val refH = reference.height.toFloat()
        val dst = RectF(
            refBox.left / refW * target,
            refBox.top / refH * target,
            refBox.right / refW * target,
            refBox.bottom / refH * target,
        )
        val fit = min(dst.width() / imgBox.width(), dst.height() / imgBox.height())
        val dw = imgBox.width() * fit
        val dh = imgBox.height() * fit
        val drawRect = RectF(
            dst.centerX() - dw / 2,
            dst.centerY() - dh / 2,
            dst.centerX() + dw / 2,
            dst.centerY() + dh / 2,
        )
        val out = Bitmap.createBitmap(target, target, Bitmap.Config.ARGB_8888) // 투명 캔버스
        val canvas = Canvas(out)
        val paint = Paint(Paint.FILTER_BITMAP_FLAG)
        canvas.drawBitmap(image, imgBox, drawRect, paint)
        return out
    }

    /**
     * 프레임2의 색을 프레임0(reference)에 맞춰 스왑 시 미묘한 색 드리프트 제거 —
     * 전경(알파>200) 픽셀의 채널별 평균/표준편차를 맞추는 Reinhard 색 전이.
     * 의도된 국소 변화(입·다리)는 전체 통계를 거의 안 바꾸므로 보존. 알파 유지.
     * 128px 썸네일에 적용하는 전제(저비용). 통계가 불안정하면 원본 반환.
     */
    fun colorMatched(image: Bitmap, reference: Bitmap): Bitmap {
        val src = channelStats(image) ?: return image
        val ref = channelStats(reference) ?: return image
        // 표준편차가 너무 작으면(거의 단색) 나눗셈 불안정 → 스킵
        if (src.std.any { it < 0.5 }) return image

        val w = image.width
        val h = image.height
        val pixels = IntArray(w * h)
        image.getPixels(pixels, 0, w, 0, 0, w, h)

        // out = in * gain + off  (gain = rStd/sStd, off = rMean - gain*sMean)
        val gain = DoubleArray(3) { ref.std[it] / src.std[it] }
        val off = DoubleArray(3) { ref.mean[it] - gain[it] * src.mean[it] }

        for (p in 0 until w * h) {
            val c = pixels[p]
            val a = c ushr 24
            if (a <= 200) continue   // 전경만
            val r = (((c shr 16 and 0xFF) * gain[0] + off[0]).roundToInt()).coerceIn(0, 255)
            val g = (((c shr 8 and 0xFF) * gain[1] + off[1]).roundToInt()).coerceIn(0, 255)
            val b = (((c and 0xFF) * gain[2] + off[2]).roundToInt()).coerceIn(0, 255)
            pixels[p] = (a shl 24) or (r shl 16) or (g shl 8) or b
        }
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        out.setPixels(pixels, 0, w, 0, 0, w, h)
        return out
    }

    /**
     * 베스트-에포트 배경 제거 — iOS 는 Vision, Android 는 ML Kit 후보였으나
     * 의존성 리스크로 이번 범위 미탑재 (00-PLAN §4: 계약상 fallback 허용).
     * 계약: 실패/미지원 시 src 를 '동일 인스턴스'로 반환 — caller 가 === 비교로 무변화 감지.
     */
    fun bestEffortTransparent(src: Bitmap): Bitmap = src

    /**
     * 사진 첨부 흐름의 한 번 호출: (베스트에포트) 배경 제거 → 정사각 1024 정규화.
     * 실패하면 null — caller 가 에러 문구 처리.
     */
    fun prepareForCharacter(src: Bitmap): Bitmap? = runCatching {
        // 원본(수천 px)에 그대로 픽셀 연산을 돌리지 않도록 먼저 다운샘플.
        val downsized = downsampled(src, 1024)
        val cutout = bestEffortTransparent(downsized)
        normalizeSquare(cutout, 1024)
    }.getOrNull()

    /**
     * 투명 픽셀 존재 여부 — 32px 로 줄여 알파 스캔 (alpha<250 이면 투명 취급).
     * 결과 화면의 '배경 있는/없는' 판별용 저비용 검사.
     */
    fun hasTransparentPixels(src: Bitmap): Boolean {
        if (!src.hasAlpha()) return false
        val sample = if (max(src.width, src.height) > 32) downsampled(src, 32) else src
        val w = sample.width
        val h = sample.height
        val pixels = IntArray(w * h)
        sample.getPixels(pixels, 0, w, 0, 0, w, h)
        return pixels.any { (it ushr 24) < 250 }
    }

    /** 긴 변이 maxPixelSize 이하가 되도록 비율 유지 축소. 이미 작으면 원본 그대로. */
    fun downsampled(src: Bitmap, maxPixelSize: Int): Bitmap {
        val maxDim = max(src.width, src.height)
        if (maxDim <= maxPixelSize) return src
        val scale = maxPixelSize.toFloat() / maxDim
        return Bitmap.createScaledBitmap(
            src,
            (src.width * scale).toInt().coerceAtLeast(1),
            (src.height * scale).toInt().coerceAtLeast(1),
            true,
        )
    }

    /** PNG base64 인코딩 (참고사진 업로드용). */
    fun toBase64Png(src: Bitmap): String {
        val out = java.io.ByteArrayOutputStream()
        src.compress(Bitmap.CompressFormat.PNG, 100, out)
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }

    /** base64 → Bitmap. 실패 null. */
    fun fromBase64(b64: String): Bitmap? = runCatching {
        val bytes = Base64.decode(b64, Base64.DEFAULT)
        val opts = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
    }.getOrNull()

    // MARK: - 내부 헬퍼

    /**
     * 전체를 정사각(target) 안에 aspect-fit + 중앙 정렬. 투명 배경 유지(잘리지 않음).
     * 픽셀 좌표계만 사용 — iOS 의 포인트/픽셀 혼용 버그(normalizeSquare) 교훈.
     */
    private fun normalizeSquare(src: Bitmap, target: Int): Bitmap {
        val out = Bitmap.createBitmap(target, target, Bitmap.Config.ARGB_8888)
        val w = src.width
        val h = src.height
        if (w <= 0 || h <= 0) return out
        val s = min(target.toFloat() / w, target.toFloat() / h)
        val dw = w * s
        val dh = h * s
        val left = (target - dw) / 2
        val top = (target - dh) / 2
        Canvas(out).drawBitmap(
            src, null,
            RectF(left, top, left + dw, top + dh),
            Paint(Paint.FILTER_BITMAP_FLAG),
        )
        return out
    }

    /** 전경(알파 > threshold)이 차지하는 bounding box (픽셀). 전경 없으면 null. */
    private fun alphaBoundingBox(src: Bitmap, threshold: Int = 10): Rect? {
        val w = src.width
        val h = src.height
        if (w <= 0 || h <= 0) return null
        val pixels = IntArray(w * h)
        src.getPixels(pixels, 0, w, 0, 0, w, h)
        var minX = w; var minY = h; var maxX = -1; var maxY = -1
        for (y in 0 until h) {
            val row = y * w
            for (x in 0 until w) {
                if ((pixels[row + x] ushr 24) > threshold) {
                    if (x < minX) minX = x
                    if (x > maxX) maxX = x
                    if (y < minY) minY = y
                    if (y > maxY) maxY = y
                }
            }
        }
        if (maxX < minX || maxY < minY) return null
        return Rect(minX, minY, maxX + 1, maxY + 1)
    }

    private class ChannelStats(val mean: DoubleArray, val std: DoubleArray)

    /** 전경(알파>200) 픽셀의 RGB 채널별 평균/표준편차. 전경이 너무 적으면(≤100px) null. */
    private fun channelStats(src: Bitmap): ChannelStats? {
        val w = src.width
        val h = src.height
        if (w <= 0 || h <= 0) return null
        val pixels = IntArray(w * h)
        src.getPixels(pixels, 0, w, 0, 0, w, h)
        val sum = DoubleArray(3)
        val sumSq = DoubleArray(3)
        var n = 0
        for (p in 0 until w * h) {
            val c = pixels[p]
            if ((c ushr 24) <= 200) continue
            n++
            val r = (c shr 16 and 0xFF).toDouble()
            val g = (c shr 8 and 0xFF).toDouble()
            val b = (c and 0xFF).toDouble()
            sum[0] += r; sum[1] += g; sum[2] += b
            sumSq[0] += r * r; sumSq[1] += g * g; sumSq[2] += b * b
        }
        if (n <= 100) return null
        val nd = n.toDouble()
        val mean = DoubleArray(3) { sum[it] / nd }
        val std = DoubleArray(3) { sqrt(max(0.0, sumSq[it] / nd - mean[it] * mean[it])) }
        return ChannelStats(mean, std)
    }
}
