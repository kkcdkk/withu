package com.seoyoung.withu.gen

import android.graphics.Bitmap
import java.util.ArrayDeque

/**
 * 마젠타 크로마키 — iOS ImageProcessing.chromaKeyRemoved() 포팅.
 * gpt-image-2 는 투명 미지원 → 서버가 순수 마젠타(#FF00FF) 단색 배경을 지시하고,
 * 여기서 가장자리에서 4-연결된 마젠타 영역만 투명으로 바꾼다.
 * - 가장자리 연결 BFS: 캐릭터 안(볼터치·핑크 옷)은 마젠타 판정이 아니면 안 지움.
 * - 마젠타가 거의 없으면(이미 투명) 원본 그대로 반환 — 안전한 no-op.
 */
object ChromaKey {

    fun removed(src: Bitmap): Bitmap {
        val w = src.width
        val h = src.height
        if (w == 0 || h == 0) return src
        val pixels = IntArray(w * h)
        src.getPixels(pixels, 0, w, 0, 0, w, h)

        // 마젠타 판정 — 압축/경계 블렌딩 여유를 두되 볼터치 핑크(G≈180)는 통과 못 하게.
        fun isMagenta(p: Int): Boolean {
            val c = pixels[p]
            val a = c ushr 24
            val r = (c shr 16) and 0xFF
            val g = (c shr 8) and 0xFF
            val b = c and 0xFF
            return a > 0 && r >= 160 && b >= 160 && g <= 120 && r - g >= 70 && b - g >= 70
        }

        // 가장자리에서 4-연결된 마젠타 = 진짜 배경 (BFS)
        val reached = BooleanArray(w * h)
        val queue = ArrayDeque<Int>()
        fun seed(p: Int) {
            if (!reached[p] && isMagenta(p)) { reached[p] = true; queue.add(p) }
        }
        for (x in 0 until w) { seed(x); seed((h - 1) * w + x) }
        for (y in 0 until h) { seed(y * w); seed(y * w + (w - 1)) }
        while (queue.isNotEmpty()) {
            val p = queue.poll()
            val x = p % w
            val y = p / w
            if (x > 0) seed(p - 1)
            if (x < w - 1) seed(p + 1)
            if (y > 0) seed(p - w)
            if (y < h - 1) seed(p + w)
        }

        var removedCount = 0
        for (p in 0 until w * h) {
            if (reached[p]) { pixels[p] = 0; removedCount++ }
        }
        // 마젠타 배경이 사실상 없으면 원본 유지 (오검출 방지)
        if (removedCount <= w * h / 100) return src

        // 경계 마젠타 번짐(halo) 중화 — 투명에 인접한 픽셀의 r/b 를 g 쪽으로 당김
        for (p in 0 until w * h) {
            val c = pixels[p]
            if (c ushr 24 == 0) continue
            val x = p % w
            val y = p / w
            val nearBG = (x > 0 && pixels[p - 1] ushr 24 == 0) ||
                (x < w - 1 && pixels[p + 1] ushr 24 == 0) ||
                (y > 0 && pixels[p - w] ushr 24 == 0) ||
                (y < h - 1 && pixels[p + w] ushr 24 == 0)
            if (!nearBG) continue
            val r = (c shr 16) and 0xFF
            val g = (c shr 8) and 0xFF
            val b = c and 0xFF
            if (r - g >= 40 && b - g >= 40) {
                val m = minOf(255, g + 30)
                pixels[p] = (c and 0xFF000000.toInt()) or
                    (minOf(r, m) shl 16) or (g shl 8) or minOf(b, m)
            }
        }

        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        out.setPixels(pixels, 0, w, 0, 0, w, h)
        return out
    }
}
