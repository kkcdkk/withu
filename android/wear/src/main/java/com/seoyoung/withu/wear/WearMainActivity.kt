package com.seoyoung.withu.wear

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text

/**
 * 워치 앱 본체 — 폰이 push 한 현재 캐릭터/상태를 전체화면으로 표시.
 * iOS 워치 ContentView 대응(표시만, 재계산 없음). 실제 글랜스는 Tile 이 담당.
 */
class WearMainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { WearApp() }
    }
}

@Composable
private fun WearApp() {
    val context = LocalContext.current
    var snap by remember { mutableStateOf(WearStore.loadSnapshot(context)) }
    var bmp by remember { mutableStateOf<Bitmap?>(null) }
    val lifecycleOwner = LocalLifecycleOwner.current

    // 화면 재진입/데이터 도착 반영 — resume 마다 최신 스냅샷·이미지 다시 로드.
    DisposableEffect(lifecycleOwner) {
        val obs = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                snap = WearStore.loadSnapshot(context)
                bmp = snap.stateRaw?.let { characterBitmap(context, it) }
            }
        }
        lifecycleOwner.lifecycle.addObserver(obs)
        onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
    }

    MaterialTheme {
        Box(
            modifier = Modifier.fillMaxSize().background(Color.Black),
            contentAlignment = Alignment.Center,
        ) {
            if (snap.stateRaw == null) {
                Text(
                    text = "폰에서 데이터를\n기다리는 중…",
                    textAlign = TextAlign.Center,
                    color = Color(0xFFBBBBBB),
                    style = MaterialTheme.typography.caption1,
                )
            } else {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    bmp?.let {
                        Image(
                            bitmap = it.asImageBitmap(),
                            contentDescription = WearCharacter.shortLabel(snap.stateRaw),
                            modifier = Modifier.size(96.dp),
                        )
                    }
                    Text(
                        text = WearCharacter.shortLabel(snap.stateRaw),
                        color = Color.White,
                        style = MaterialTheme.typography.title3,
                        modifier = Modifier.padding(top = 6.dp),
                    )
                    subtitle(snap)?.let {
                        Text(
                            text = it,
                            color = Color(0xFFB0B0B0),
                            style = MaterialTheme.typography.caption2,
                            modifier = Modifier.padding(top = 2.dp),
                        )
                    }
                }
            }
        }
    }
}

private fun subtitle(snap: WearStore.Snapshot): String? {
    val parts = mutableListOf<String>()
    snap.steps?.let { parts.add("👟 ${it}보") }
    val weather = buildString {
        snap.weatherEmoji?.let { append(it) }
        snap.tempC?.let { if (isNotEmpty()) append(" "); append("$it°") }
    }
    if (weather.isNotBlank()) parts.add(weather)
    return parts.joinToString("   ").ifBlank { null }
}

private fun characterBitmap(context: android.content.Context, stateRaw: String): Bitmap? {
    WearStore.loadImage(context, stateRaw)?.let { return it }
    val name = WearCharacter.fallbackDrawableName(stateRaw)
    val id = context.resources.getIdentifier(name, "drawable", context.packageName)
    if (id == 0) return null
    return runCatching { BitmapFactory.decodeResource(context.resources, id) }.getOrNull()
}
