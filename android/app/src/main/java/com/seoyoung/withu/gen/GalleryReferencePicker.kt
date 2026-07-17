package com.seoyoung.withu.gen

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.seoyoung.withu.R
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.shared.CharacterImageStore
import com.seoyoung.withu.shared.GalleryItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 내 캐릭터(갤러리)에서 참고사진 고르기 시트 — iOS GalleryReferencePicker.swift 포팅
 * (스펙 04 §1.4). 단건(02)/배치(03) 생성 화면 공용 — 호스팅(시트/다이얼로그)은 caller 소관.
 */
@Composable
fun GalleryReferencePicker(onPick: (Bitmap) -> Unit, onClose: () -> Unit) {
    // 메타 로드는 IO — 시트 열릴 때 1회 (iOS onAppear)
    val items by produceState<List<GalleryItem>?>(initialValue = null) {
        value = withContext(Dispatchers.IO) { CharacterImageStore.loadGalleryMetadata() }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // 상단 바: 타이틀 + 닫기
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 16.dp, end = 4.dp, top = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = stringResource(R.string.refpicker_title),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.weight(1f))
            TextButton(onClick = onClose) {
                Text(stringResource(R.string.common_close))
            }
        }

        val loaded = items
        when {
            loaded == null -> Unit   // 로딩 중 — 짧아서 스피너 생략 (iOS 동일)
            loaded.isEmpty() -> {
                // 빈 상태
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text(text = "🎨", fontSize = 44.sp)
                    Spacer(Modifier.size(12.dp))
                    Text(
                        text = stringResource(R.string.refpicker_empty_title),
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                        textAlign = TextAlign.Center,
                    )
                    Spacer(Modifier.size(6.dp))
                    Text(
                        text = stringResource(R.string.refpicker_empty_body),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
            }
            else -> {
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(96.dp),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    items(loaded, key = { it.id }) { item ->
                        PickerCell(item = item, onPick = onPick)
                    }
                }
            }
        }
    }
}

@Composable
private fun PickerCell(item: GalleryItem, onPick: (Bitmap) -> Unit) {
    // 원본 로드 (갤러리 PNG 는 최대 1024 — 셀 표시와 onPick 원본을 겸함)
    val bitmap by produceState<Bitmap?>(initialValue = null, key1 = item.id) {
        value = withContext(Dispatchers.IO) { CharacterImageStore.loadGalleryImage(item.id) }
    }
    // 이미지 로드 실패 셀은 아예 렌더하지 않음 (iOS 동일)
    val bmp = bitmap ?: return
    val label = CharacterState.fromRaw(item.sourceState)?.koreanShortLabel
        ?: stringResource(R.string.refpicker_label_fallback)
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Image(
            bitmap = bmp.asImageBitmap(),
            contentDescription = label,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .clip(RoundedCornerShape(12.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .clickable { onPick(bmp) },
        )
        Spacer(Modifier.size(4.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
