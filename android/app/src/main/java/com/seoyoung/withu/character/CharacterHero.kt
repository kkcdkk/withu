package com.seoyoung.withu.character

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.seoyoung.withu.shared.WeatherBackgroundCondition

/**
 * 홈 히어로 — iOS CharacterView 대응 (00-PLAN §2-5: 240dp 원 + 200dp 이미지 + 캡션 + 데코).
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
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(240.dp), contentAlignment = Alignment.Center) {
            // tint 원 (15% 투명) — 캐릭터 이미지의 무드 배경
            Box(
                Modifier
                    .matchParentSize()
                    .background(state.tint.copy(alpha = 0.15f), CircleShape),
            )
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
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onBackground,
            )
        }
    }
}
