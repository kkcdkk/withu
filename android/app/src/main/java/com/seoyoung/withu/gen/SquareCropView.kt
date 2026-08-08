package com.seoyoung.withu.gen

import android.graphics.Canvas
import android.graphics.Color as AndroidColor
import android.graphics.Matrix
import android.graphics.Paint
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.seoyoung.withu.R
import com.seoyoung.withu.ui.theme.withuPink
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import android.graphics.Bitmap
import kotlin.math.max
import kotlin.math.min

/**
 * 정사각 크롭 풀스크린 — iOS SquareCropView.swift 포팅 (스펙 04 §1.5).
 * 드래그(이동)와 핀치(확대) 동시 인식, 1배 미만 축소 금지.
 * 결과는 **수학적 크롭**으로 원본 Bitmap 좌표를 역산해 1024×1024 로 렌더 —
 * 픽셀 좌표계만 사용 (iOS normalizeSquare 포인트/픽셀 혼용 버그 교훈).
 */
@Composable
fun SquareCropView(source: Bitmap, onDone: (Bitmap) -> Unit, onCancel: () -> Unit) {
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    var isRendering by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        val density = LocalDensity.current
        // 크롭 윈도우 한 변 = min(화면 w, h) − 48dp (iOS 동일)
        val sideDp = min(maxWidth.value, maxHeight.value).dp - 48.dp
        val sidePx = with(density) { sideDp.toPx() }

        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // 상단 바: 취소 / 선택
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = stringResource(R.string.common_cancel),
                    color = Color.White,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.clickable(enabled = !isRendering) { onCancel() },
                )
                Spacer(Modifier.weight(1f))
                Text(
                    text = stringResource(R.string.common_select),
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(withuPink())
                        .clickable(enabled = !isRendering) {
                            isRendering = true
                            scope.launch {
                                val cropped = withContext(Dispatchers.Default) {
                                    runCatching {
                                        renderSquareCrop(source, sidePx, scale, offset)
                                    }.getOrNull()
                                }
                                // 렌더 실패 시 onCancel (iOS ImageRenderer nil 경로와 동일)
                                if (cropped != null) onDone(cropped) else onCancel()
                            }
                        }
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }

            Spacer(Modifier.weight(1f))

            // 중앙 크롭 윈도우 — scaledToFill + scaleEffect + offset (iOS 변환 순서 동일)
            Box(
                modifier = Modifier
                    .size(sideDp)
                    .clip(RoundedCornerShape(12.dp))
                    .border(2.dp, Color.White, RoundedCornerShape(12.dp))
                    .pointerInput(Unit) {
                        detectTransformGestures { _, pan, zoom, _ ->
                            // 1배 미만 축소 금지 (원본보다 작게 못 줄임 — iOS 동일)
                            scale = max(1f, scale * zoom)
                            offset += pan
                        }
                    },
            ) {
                Image(
                    bitmap = source.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,   // scaledToFill 대응
                    modifier = Modifier
                        .fillMaxSize()
                        .graphicsLayer {
                            scaleX = scale
                            scaleY = scale
                            translationX = offset.x
                            translationY = offset.y
                        },
                )
            }

            // 아래 안내
            Text(
                text = stringResource(R.string.crop_hint),
                color = Color.White.copy(alpha = 0.7f),
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.padding(top = 16.dp),
            )

            Spacer(Modifier.weight(1f))
        }
    }
}

/**
 * 화면 변환(fill 배율 × scale, offset)을 역산해 지금 보이는 정사각을 1024×1024 로 렌더.
 * 이미지 밖 영역은 화면과 동일하게 검정으로 채운다.
 */
private fun renderSquareCrop(source: Bitmap, sidePx: Float, scale: Float, offset: Offset): Bitmap {
    val target = 1024
    val w = source.width.toFloat()
    val h = source.height.toFloat()
    require(w > 0 && h > 0 && sidePx > 0)

    // ContentScale.Crop(=scaledToFill) 기본 배율 × 사용자 확대
    val fill = max(sidePx / w, sidePx / h)
    val t = fill * scale

    // 화면 좌표 → 원본 픽셀 좌표 역산: 윈도우 좌상단이 원본의 어느 지점인지
    val srcLeft = w / 2f + (-sidePx / 2f - offset.x) / t
    val srcTop = h / 2f + (-sidePx / 2f - offset.y) / t
    val k = target * t / sidePx   // 원본 px → 출력 px 배율

    val out = Bitmap.createBitmap(target, target, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(out)
    canvas.drawColor(AndroidColor.BLACK)
    val matrix = Matrix().apply {
        postTranslate(-srcLeft, -srcTop)
        postScale(k, k)
    }
    canvas.drawBitmap(source, matrix, Paint(Paint.FILTER_BITMAP_FLAG))
    return out
}
