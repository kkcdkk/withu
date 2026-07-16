package com.seoyoung.withu.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.store.CharacterStore
import com.seoyoung.withu.ui.theme.WithuColors

/**
 * 홈 — iOS ContentView 의 최소 포팅: 캐릭터 원 + 캡션 + 만들기 버튼.
 * Phase 1 은 상태 자동 감지 없이 idle 고정 (Health Connect 는 Phase 2).
 */
@Composable
fun HomeScreen(onOpenGenerate: () -> Unit) {
    val ctx = LocalContext.current
    val state = CharacterState.IDLE
    // 화면 재진입 시 새로 로드 (생성 후 popBack 반영)
    val bitmap by remember { mutableStateOf(CharacterStore.load(ctx, state)) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(
                        WithuColors.greenLight.copy(alpha = 0.14f),
                        MaterialTheme.colorScheme.background,
                    )
                )
            )
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("with U", fontSize = 22.sp, fontWeight = FontWeight.SemiBold)

        Box(
            modifier = Modifier
                .padding(vertical = 28.dp)
                .size(220.dp)
                .background(WithuColors.pinkLight.copy(alpha = 0.35f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            val bmp = bitmap
            if (bmp != null) {
                Image(
                    bitmap = bmp.asImageBitmap(),
                    contentDescription = state.koreanShortLabel,
                    modifier = Modifier.size(160.dp),
                )
            } else {
                Text(state.symbolEmoji, fontSize = 84.sp)
            }
        }

        Text(state.caption, fontSize = 16.sp, color = MaterialTheme.colorScheme.onBackground)

        Button(
            onClick = onOpenGenerate,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 36.dp),
            shape = RoundedCornerShape(12.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = Color.White,
            ),
        ) {
            Text("함께할 캐릭터 생성하기", fontWeight = FontWeight.SemiBold)
        }
    }
}
