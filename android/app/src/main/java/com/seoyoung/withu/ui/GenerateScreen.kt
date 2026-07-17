package com.seoyoung.withu.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.gen.ChromaKey
import com.seoyoung.withu.net.ApiClient
import com.seoyoung.withu.net.GenerateImageRequest
import com.seoyoung.withu.store.CharacterStore
import kotlinx.coroutines.launch

/**
 * 캐릭터 만들기 — iOS CharacterGenView 의 최소 포팅.
 * 설명 입력 + 그림체 선택 → /generate (gpt-image-2) → 크로마키 투명화 → 저장.
 * Phase 1: 캔디/로그인 없음 (X-Withu-Token 경로), idle 상태 고정.
 */
@Composable
fun GenerateScreen(onDone: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()

    var prompt by remember { mutableStateOf("") }
    var artStyle by remember { mutableStateOf("casual") }
    var isGenerating by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<Bitmap?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text("캐릭터 만들기", fontSize = 20.sp, fontWeight = FontWeight.SemiBold)

        OutlinedTextField(
            value = prompt,
            onValueChange = { prompt = it },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("내 캐릭터 설명") },
            placeholder = { Text("예: 동그란 흰 곰, 분홍 볼터치") },
            minLines = 3,
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = artStyle == "casual",
                onClick = { artStyle = "casual" },
                label = { Text("부드러운") },
            )
            FilterChip(
                selected = artStyle == "pixel",
                onClick = { artStyle = "pixel" },
                label = { Text("픽셀") },
            )
        }

        Button(
            onClick = {
                isGenerating = true
                error = null
                scope.launch {
                    try {
                        val state = CharacterState.IDLE
                        val desc = prompt.trim()
                        val base = if (desc.isEmpty()) state.generationHint
                                   else "$desc, ${state.generationHint}"
                        val finalPrompt = "$base. Only the character on a transparent background — no background fill, no shadows, no extra elements."
                        // DTO 가 net/ApiModels.kt 로 분리됨 (F1) — 시그니처는 계약 §2-6
                        val resp = ApiClient.generateImage(
                            GenerateImageRequest(prompt = finalPrompt, artStyle = artStyle)
                        )
                        val bytes = Base64.decode(resp.imageBase64, Base64.DEFAULT)
                        val raw = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        val cut = ChromaKey.removed(raw)
                        // 128px 다운샘플 — iOS 와 동일 정책 (홈/위젯 표시 크기)
                        val small = Bitmap.createScaledBitmap(cut, 128, 128, true)
                        CharacterStore.save(ctx, small, state)
                        result = cut
                    } catch (e: Exception) {
                        error = e.message ?: "생성에 실패했어요. 다시 시도해 주세요."
                    } finally {
                        isGenerating = false
                    }
                }
            },
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            enabled = !isGenerating,
        ) {
            if (isGenerating) {
                CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                Text("  만드는 중… (20~30초)")
            } else {
                Text("이 모습으로 만들기", fontWeight = FontWeight.SemiBold)
            }
        }

        error?.let {
            Text(it, color = MaterialTheme.colorScheme.error, fontSize = 13.sp)
        }

        result?.let { bmp ->
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Image(
                    bitmap = bmp.asImageBitmap(),
                    contentDescription = "생성 결과",
                    modifier = Modifier.size(240.dp),
                )
                Button(onClick = onDone, shape = RoundedCornerShape(12.dp)) {
                    Text("홈에서 보기")
                }
            }
        }
    }
}
