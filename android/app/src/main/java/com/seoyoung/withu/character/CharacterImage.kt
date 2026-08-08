package com.seoyoung.withu.character

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.material3.Text
import com.seoyoung.withu.shared.CharacterImageStore
import com.seoyoung.withu.shared.StoreEvents
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * 캐릭터 이미지 — iOS CharacterImageView 포팅 (스펙 08 §3.4).
 * 3단 fallback (순서 절대 변경 금지):
 *   1) CharacterImageStore 사용자 PNG — 없으면 baseFallback state 파일도 시도
 *   2) 번들 drawable character_<raw소문자> — 없으면 base asset → character_placeholder
 *   3) 이모지 (state.symbolEmoji) — 최후 fallback, 절대 깨지지 않음
 *
 * 애니메이션: animated=true AND f1 존재 AND 상태별 미비활성 AND 전역 토글 on →
 * 0.7초 하드 swap (크로스페이드 없음).
 * outlineOnly(워치 컴플리케이션 전용)는 Wear 제외로 미구현 (스펙 08 §6).
 */
@Composable
fun CharacterImage(
    state: CharacterState,
    modifier: Modifier = Modifier,
    symbolPaddingRatio: Float = 0.2f,
    maxPixelSize: Int? = null,
    animated: Boolean = false,
    refreshKey: Int = 0,   // 홈 imageRefreshKey — 값 변경 시 강제 재로드
) {
    val context = LocalContext.current

    // 저장소 변경 알림 구독 — 해당 state(또는 broadcast/base) 변경 시 재로드
    var storeTick by remember(state) { mutableIntStateOf(0) }
    androidx.compose.runtime.LaunchedEffect(state) {
        StoreEvents.characterImageChanged.collect { changed ->
            if (changed == null || changed == state || changed == state.baseFallback) storeTick++
        }
    }

    // 파일 I/O 는 IO 디스패처에서 — Compose 에서 저장소 직접 호출 금지 (00-PLAN §0-3)
    val frames by produceState<CharacterFrames?>(
        initialValue = null,
        state, refreshKey, storeTick, animated, maxPixelSize,
    ) {
        value = withContext(Dispatchers.IO) { loadFrames(state, maxPixelSize, animated) }
    }

    // 0.7초 프레임 swap — f1 이 실제로 로드됐을 때만
    var frameIndex by remember { mutableIntStateOf(0) }
    val frame1 = frames?.frame1
    androidx.compose.runtime.LaunchedEffect(frame1) {
        frameIndex = 0
        if (frame1 != null) {
            while (true) {
                delay(700)
                frameIndex = (frameIndex + 1) % 2
            }
        }
    }

    val loaded = frames
    val bitmap: Bitmap? = when {
        loaded == null -> null
        frameIndex == 1 && loaded.frame1 != null -> loaded.frame1
        else -> loaded.frame0
    }

    when {
        loaded == null -> Box(modifier) {} // 로딩 중 자리 유지 (다음 프레임에 채워짐)
        bitmap != null -> Image(
            bitmap = bitmap.asImageBitmap(),
            contentDescription = state.koreanShortLabel,
            modifier = modifier,
            contentScale = ContentScale.Fit,
        )
        else -> {
            // 2단: 번들 drawable (현재 → base → placeholder)
            val assetId = remember(state) {
                fun idOf(name: String) =
                    context.resources.getIdentifier(name, "drawable", context.packageName)
                var id = idOf(state.imageAssetName)
                if (id == 0 && state.baseFallback != null) id = idOf(state.baseFallback!!.imageAssetName)
                if (id == 0) id = idOf("character_placeholder")
                id
            }
            if (assetId != 0) {
                Image(
                    painter = painterResource(assetId),
                    contentDescription = state.koreanShortLabel,
                    modifier = modifier,
                    contentScale = ContentScale.Fit,
                )
            } else {
                // 3단: 이모지 — 컨테이너 폭 × (1 - 2×paddingRatio) 크기로 렌더
                BoxWithConstraints(modifier, contentAlignment = Alignment.Center) {
                    val fontSize = with(LocalDensity.current) {
                        (maxWidth * (1f - 2f * symbolPaddingRatio)).toSp()
                    }
                    Text(
                        text = state.symbolEmoji,
                        fontSize = fontSize,
                        textAlign = TextAlign.Center,
                        maxLines = 1,
                        softWrap = false,
                    )
                }
            }
        }
    }
}

/** frame0/frame1 로드 결과. frame1 은 애니메이션 조건을 모두 통과했을 때만 non-null. */
private data class CharacterFrames(val frame0: Bitmap?, val frame1: Bitmap?)

/**
 * frame 로드 규칙 (iOS 동일):
 *  - frame0: maxPixelSize 있으면 loadThumbnail, 없으면 load. 없으면 baseFallback state 시도.
 *  - frame1: loadFrame(1) — 없으면 caller(뷰)가 frame0 을 계속 표시 (저장소는 폴백 안 함).
 *    frame1 은 작은 PNG 가정이라 별도 다운샘플 안 함 (iOS 주석 참고).
 */
private fun loadFrames(
    state: CharacterState,
    maxPixelSize: Int?,
    animated: Boolean,
): CharacterFrames {
    fun load0(s: CharacterState): Bitmap? =
        if (maxPixelSize != null) CharacterImageStore.loadThumbnail(s, maxPixelSize)
        else CharacterImageStore.load(s)

    var target = state
    var f0 = load0(state)
    if (f0 == null && state.baseFallback != null) {
        // 조합 state (예: walkingRainy) 이미지 없으면 base (walking) 시도
        target = state.baseFallback!!
        f0 = load0(target)
    }
    val shouldAnimate = animated &&
        f0 != null &&
        CharacterImageStore.hasAnimationFrames(target) &&
        !CharacterImageStore.isAnimationDisabled(target) &&
        CharacterImageStore.isAnimationEnabled()
    val f1 = if (shouldAnimate) CharacterImageStore.loadFrame(target, 1) else null
    return CharacterFrames(f0, f1)
}
