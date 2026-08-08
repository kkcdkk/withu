package com.seoyoung.withu.character

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.seoyoung.withu.shared.WeatherBackgroundCondition
import com.seoyoung.withu.ui.theme.DungGeunMo

/**
 * 홈 히어로 — iOS CharacterView 대응 (240dp 영역 + 200dp 이미지 + 캡션 + 데코).
 * 2026-07 레트로 픽셀 개편: 캐릭터 뒤 tint 원 제거 (iOS ContentView.swift:338-360 에 원이 없음).
 * 상태 변경 시 캡션은 fade 로 교체 (iOS .transition(.opacity) + .id(state) 대응).
 */
@Composable
fun CharacterHero(
    state: CharacterState,
    modifier: Modifier = Modifier,
    animated: Boolean = true,
    refreshKey: Int = 0,
    decoration: WeatherBackgroundCondition? = null,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        // iOS ContentView.swift VStack(spacing: 14) — 캐릭터↔캡션 간격
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.size(240.dp), contentAlignment = Alignment.Center) {
            CharacterImage(
                state = state,
                modifier = Modifier.size(200.dp),
                animated = animated,
                refreshKey = refreshKey,
            )
            // 날씨 데코 오버레이 — 코너 이모지/떨어지는 입자
            WeatherDecoration(
                condition = decoration,
                size = 44.dp,
                modifier = Modifier.matchParentSize(),
            )
        }
        AnimatedContent(
            targetState = state,
            transitionSpec = { fadeIn() togetherWith fadeOut() },
            label = "heroCaption",
        ) { s ->
            Text(
                text = s.caption,
                // iOS ContentView.swift:353 — .galmuri(20)
                fontFamily = DungGeunMo,
                fontSize = 20.sp,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onBackground,
            )
        }
    }
}
