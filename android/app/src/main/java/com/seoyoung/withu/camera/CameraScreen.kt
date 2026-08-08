package com.seoyoung.withu.camera

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.view.PreviewView
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Cameraswitch
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.seoyoung.withu.R
import com.seoyoung.withu.character.CharacterImage
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.ui.theme.withuPink
import com.seoyoung.withu.ui.theme.withuPinkText
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

/**
 * 카메라 합성 화면 — iOS CameraView.swift 포팅 (스펙 12 Part A).
 * 레이어(아래→위): 카메라/앨범 배경 → 배치 캐릭터 오버레이 → 컨트롤 → 캡처 프리뷰 → 토스트.
 * 에뮬레이터 분기는 Android 불필요 (가상 카메라 제공 — 스펙 12 A-6) — 카메라 없으면 noCamera 문구.
 */
@Composable
fun CameraScreen() {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()

    val controller = remember { CameraController() }
    val previewView = remember {
        PreviewView(context).apply { scaleType = PreviewView.ScaleType.FILL_CENTER }
    }

    // "카메라는 항상 idle 하나로 시작" — iOS 초기값 (0.5, 0.6)
    val placed = remember {
        mutableStateListOf(
            PlacedCharacter(state = CharacterState.IDLE, position = Offset(0.5f, 0.6f)),
        )
    }
    var selectedId by remember { mutableStateOf<String?>(null) }
    val initialStatus = stringResource(R.string.camera_status_initializing)
    var statusText by remember { mutableStateOf(initialStatus) }
    var isCapturing by remember { mutableStateOf(false) }
    var previewCaptured by remember { mutableStateOf<Bitmap?>(null) }
    var showSavedToast by remember { mutableStateOf(false) }
    var isPermissionDenied by remember { mutableStateOf(false) }
    var backgroundImage by remember { mutableStateOf<Bitmap?>(null) }

    // 앨범 배경 픽커 (Photo Picker — 권한 불필요)
    val backgroundPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia(),
    ) { uri ->
        if (uri != null) {
            scope.launch {
                // 대형 사진 OOM 방지 — 화면 크기 2배 이하로 다운샘플 (스펙 12 A-6)
                val bmp = withContext(Dispatchers.IO) { decodeDownsampledBitmap(context, uri) }
                if (bmp != null) backgroundImage = bmp
            }
        }
    }

    // 카메라 권한 → 바인딩. bindTick 증가 = 재바인딩 트리거.
    var bindTick by remember { mutableIntStateOf(0) }
    val cameraPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            isPermissionDenied = false
            bindTick++
        } else {
            // iOS 처럼 거절 = 회복 화면 단일 처리 ("다시 묻지 않음" 구분 없음)
            isPermissionDenied = true
        }
    }
    LaunchedEffect(Unit) {
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) bindTick++ else cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
    }
    LaunchedEffect(bindTick) {
        if (bindTick == 0) return@LaunchedEffect
        try {
            controller.bind(context, lifecycleOwner, previewView)
            statusText = context.getString(R.string.camera_status_ready)
        } catch (e: CameraError) {
            statusText = e.userMessage(context)
        } catch (_: Exception) {
            statusText = context.getString(R.string.camera_status_error)
        }
    }
    DisposableEffect(Unit) {
        onDispose { controller.unbind() } // iOS onDisappear { camera.stop() } 대응
    }

    // API 28 전용 — MediaStore 쓰기 권한 (스펙 12 A-3 저장 권한)
    var pendingSave by remember { mutableStateOf<Bitmap?>(null) }
    val saveCurrent: (Bitmap) -> Unit = { image ->
        scope.launch {
            PhotoSaver.save(image).fold(
                onSuccess = {
                    previewCaptured = null
                    showSavedToast = true
                    delay(1600)
                    showSavedToast = false
                },
                onFailure = { e ->
                    statusText = context.getString(
                        R.string.camera_err_save_failed, e.localizedMessage ?: "",
                    )
                },
            )
        }
    }
    val writePermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        val image = pendingSave
        pendingSave = null
        if (image != null) {
            if (granted) saveCurrent(image)
            else statusText = context.getString(R.string.camera_err_photo_permission)
        }
    }
    val requestSave: (Bitmap) -> Unit = { image ->
        val needsPermission = PhotoSaver.needsLegacyWritePermission() &&
            ContextCompat.checkSelfPermission(
                context, Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ) != PackageManager.PERMISSION_GRANTED
        if (needsPermission) {
            pendingSave = image
            writePermissionLauncher.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        } else {
            saveCurrent(image)
        }
    }

    val shoot: () -> Unit = {
        if (!isCapturing) {
            scope.launch {
                isCapturing = true
                try {
                    val snapshot = placed.toList()
                    // 앨범 배경 모드 — 카메라 캡처 없이 그 사진 위에 캐릭터 합성 (즉시)
                    val photo = backgroundImage ?: controller.capture(context)
                    previewCaptured = withContext(Dispatchers.IO) {
                        PhotoCompositor.compose(photo, snapshot)
                    }
                } catch (e: CameraError) {
                    statusText = e.userMessage(context)
                } catch (_: Exception) {
                    statusText = context.getString(R.string.camera_err_capture)
                } finally {
                    isCapturing = false
                }
            }
        }
    }

    val addCharacter: (CharacterState) -> Unit = { state ->
        val new = PlacedCharacter(state = state, position = Offset(0.5f, 0.55f))
        placed.add(new)
        selectedId = new.id
    }

    // 분기 0 — 권한 거절 회복 화면 (앨범 배경을 골랐으면 카메라 없이도 진행 가능하므로 숨김)
    if (isPermissionDenied && backgroundImage == null) {
        PermissionDeniedView(
            onOpenSettings = {
                val intent = Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", context.packageName, null),
                )
                context.startActivity(intent)
            },
            onPickAlbum = {
                backgroundPicker.launch(
                    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                )
            },
        )
        return
    }

    // 분기 1 — 정상 화면
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        // 1) cameraLayer — 앨범 배경 or 라이브 프리뷰
        val bg = backgroundImage
        if (bg != null) {
            Image(
                bitmap = bg.asImageBitmap(),
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop, // scaledToFill
            )
        } else {
            AndroidView(factory = { previewView }, modifier = Modifier.fillMaxSize())
        }

        // 2) overlayLayer — 배치된 캐릭터 타일들
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val containerW = constraints.maxWidth.toFloat()
            val containerH = constraints.maxHeight.toFloat()
            placed.forEach { character ->
                key(character.id) {
                    CharacterTile(
                        character = character,
                        containerW = containerW,
                        containerH = containerH,
                        selected = selectedId == character.id,
                        onSelect = { selectedId = character.id },
                        onRemove = {
                            placed.removeAll { it.id == character.id }
                            if (selectedId == character.id) selectedId = null
                        },
                        onTransform = { pan, zoom, rotationDeg ->
                            // 조작 = 선택 (iOS onChanged 첫 줄과 동일)
                            selectedId = character.id
                            val i = placed.indexOfFirst { it.id == character.id }
                            if (i >= 0) {
                                val p = placed[i]
                                placed[i] = p.copy(
                                    position = Offset(
                                        (p.position.x + pan.x / containerW).coerceIn(0f, 1f),
                                        (p.position.y + pan.y / containerH).coerceIn(0f, 1f),
                                    ),
                                    size = (p.size * zoom).coerceIn(0.1f, 0.95f),
                                    rotation = p.rotation +
                                        Math.toRadians(rotationDeg.toDouble()).toFloat(),
                                )
                            }
                        },
                    )
                }
            }
        }

        // 3) controlsLayer
        Column(Modifier.fillMaxSize()) {
            Row(
                Modifier.fillMaxWidth().padding(top = 60.dp, end = 16.dp),
                horizontalArrangement = Arrangement.End,
            ) {
                Text(
                    text = statusText,
                    fontSize = 12.sp,
                    color = Color.White,
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.25f)) // ultraThinMaterial 근사
                        .padding(horizontal = 10.dp, vertical = 6.dp),
                )
            }
            Spacer(Modifier.weight(1f))
            CharacterPicker(onAdd = addCharacter)
            Spacer(Modifier.height(12.dp))
            Row(
                Modifier.fillMaxWidth()
                    .padding(horizontal = 30.dp)
                    .padding(bottom = 50.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // 좌: 앨범 배경 고르기 ↔ (배경 모드) 라이브 카메라 복귀
                if (backgroundImage != null) {
                    RoundControlButton(icon = Icons.Filled.PhotoCamera) {
                        backgroundImage = null
                    }
                } else {
                    RoundControlButton(icon = Icons.Filled.PhotoLibrary) {
                        backgroundPicker.launch(
                            PickVisualMediaRequest(
                                ActivityResultContracts.PickVisualMedia.ImageOnly,
                            ),
                        )
                    }
                }
                Spacer(Modifier.weight(1f))
                // 중앙: 셔터
                Box(
                    Modifier
                        .size(78.dp)
                        .border(4.dp, Color.White, CircleShape)
                        .clip(CircleShape)
                        .clickable(enabled = !isCapturing) { shoot() },
                    contentAlignment = Alignment.Center,
                ) {
                    Box(Modifier.size(64.dp).background(Color.White, CircleShape))
                    if (isCapturing) {
                        CircularProgressIndicator(
                            color = Color.Black,
                            strokeWidth = 3.dp,
                            modifier = Modifier.size(28.dp),
                        )
                    }
                }
                Spacer(Modifier.weight(1f))
                // 우: 전면/후면 전환 (앨범 배경 모드에선 자리만 유지 — 레이아웃 대칭)
                if (backgroundImage == null) {
                    RoundControlButton(
                        icon = Icons.Filled.Cameraswitch,
                        enabled = !isCapturing,
                    ) {
                        if (!controller.switchCamera(lifecycleOwner, previewView)) {
                            statusText = context.getString(R.string.camera_err_switch)
                        }
                    }
                } else {
                    Spacer(Modifier.size(50.dp))
                }
            }
        }

        // 4) 캡처 프리뷰 오버레이
        previewCaptured?.let { img ->
            CapturePreview(
                image = img,
                onCancel = { previewCaptured = null },
                onSave = { requestSave(img) },
            )
        }

        // 5) 저장 토스트
        AnimatedVisibility(
            visible = showSavedToast,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 140.dp),
        ) {
            Text(
                text = stringResource(R.string.camera_toast_saved),
                color = Color.White,
                modifier = Modifier
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.55f)) // ultraThinMaterial 근사
                    .padding(horizontal = 16.dp, vertical = 10.dp),
            )
        }
        // showDeleteHint 토스트는 iOS 에서도 죽은 코드 — 문구만 strings 에 보존 (스펙 12 A-1)
    }
}

// MARK: - 캐릭터 타일 (드래그/핀치/회전/탭/길게누름)

@Composable
private fun CharacterTile(
    character: PlacedCharacter,
    containerW: Float,
    containerH: Float,
    selected: Boolean,
    onSelect: () -> Unit,
    onRemove: () -> Unit,
    onTransform: (pan: Offset, zoom: Float, rotationDeg: Float) -> Unit,
) {
    val density = LocalDensity.current
    val rect = character.rect(containerW, containerH)
    val sizeDp = with(density) { rect.width().toDp() }
    Box(
        Modifier
            .offset { IntOffset(rect.left.roundToInt(), rect.top.roundToInt()) }
            .size(sizeDp)
            // 탭=선택 · 길게 눌러 삭제(시스템 기본 ≈500ms — iOS 0.4초 파리티 오차 허용)
            .pointerInput(character.id) {
                detectTapGestures(onTap = { onSelect() }, onLongPress = { onRemove() })
            }
            // 인스타 스티커 UX — 드래그+핀치+회전 동시. detectTransformGestures 는
            // delta(증분)를 주므로 iOS 의 시작 스냅샷 변수가 필요 없음 (클램프만 동일하게).
            .pointerInput(character.id, containerW, containerH) {
                detectTransformGestures { _, pan, zoom, rotation ->
                    onTransform(pan, zoom, rotation)
                }
            },
    ) {
        // 회전은 캐릭터 자기 중심 기준 — 제스처 입력은 회전 전 좌표계에서 받도록 안쪽만 회전
        Box(
            Modifier
                .fillMaxSize()
                .graphicsLayer {
                    rotationZ = Math.toDegrees(character.rotation.toDouble()).toFloat()
                }
                .then(
                    if (selected) {
                        Modifier.border(3.dp, Color.White, RoundedCornerShape(12.dp))
                    } else {
                        Modifier
                    },
                ),
        ) {
            CharacterImage(state = character.state, modifier = Modifier.fillMaxSize())
        }
    }
}

// MARK: - 캐릭터 픽커 (하단 가로 스크롤)

@Composable
private fun CharacterPicker(onAdd: (CharacterState) -> Unit) {
    Column {
        Text(
            text = stringResource(R.string.camera_picker_hint),
            fontSize = 11.sp,
            color = Color.White.copy(alpha = 0.7f),
            modifier = Modifier.padding(horizontal = 16.dp),
        )
        Spacer(Modifier.height(4.dp))
        Row(
            Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            CharacterState.userFacing.forEach { state ->
                Box(
                    Modifier
                        .size(56.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.25f)) // ultraThinMaterial 근사
                        .clickable { onAdd(state) },
                ) {
                    CharacterImage(
                        state = state,
                        modifier = Modifier.fillMaxSize().padding(6.dp),
                    )
                    Icon(
                        imageVector = Icons.Filled.AddCircle,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(2.dp)
                            .size(16.dp)
                            .background(Color.Black.copy(alpha = 0.4f), CircleShape),
                    )
                }
            }
        }
    }
}

// MARK: - 캡처 프리뷰 오버레이

@Composable
private fun CapturePreview(image: Bitmap, onCancel: () -> Unit, onSave: () -> Unit) {
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.9f))
            // 뒤 레이어(셔터/타일)로의 탭 통과 차단
            .pointerInput(Unit) { detectTapGestures { } },
    ) {
        Column(
            Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Image(
                bitmap = image.asImageBitmap(),
                contentDescription = null,
                modifier = Modifier.weight(1f).fillMaxWidth().padding(16.dp),
                contentScale = ContentScale.Fit,
            )
            Row(
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.padding(bottom = 40.dp),
            ) {
                OutlinedButton(onClick = onCancel) {
                    Text(stringResource(R.string.camera_preview_cancel))
                }
                Button(
                    onClick = onSave,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = withuPink(),
                        contentColor = Color.White,
                    ),
                ) {
                    Text(stringResource(R.string.camera_preview_save))
                }
            }
        }
    }
}

// MARK: - 권한 거절 회복 화면

@Composable
private fun PermissionDeniedView(onOpenSettings: () -> Unit, onPickAlbum: () -> Unit) {
    Column(
        Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        Box(
            Modifier
                .size(130.dp)
                .background(Color(0xFFFF9500).copy(alpha = 0.18f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            // iOS camera.fill.badge.ellipsis 대응 아이콘
            Icon(
                imageVector = Icons.Filled.PhotoCamera,
                contentDescription = null,
                tint = Color(0xFFFF9500),
                modifier = Modifier.size(56.dp),
            )
        }
        Spacer(Modifier.height(20.dp))
        Text(
            text = stringResource(R.string.camera_permission_title),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
        )
        Spacer(Modifier.height(8.dp))
        Text(
            text = stringResource(R.string.camera_permission_body),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.weight(1f))
        Button(
            onClick = onOpenSettings,
            colors = ButtonDefaults.buttonColors(
                containerColor = withuPink(),
                contentColor = Color.White,
            ),
            shape = RoundedCornerShape(14.dp),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp).height(50.dp),
        ) {
            Icon(Icons.Filled.Settings, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.size(8.dp))
            Text(
                text = stringResource(R.string.camera_permission_open_settings),
                fontWeight = FontWeight.Bold,
            )
        }
        Spacer(Modifier.height(12.dp))
        TextButton(onClick = onPickAlbum) {
            Text(
                text = stringResource(R.string.camera_permission_album_link),
                color = withuPinkText(),
                fontWeight = FontWeight.Bold,
            )
        }
        Spacer(Modifier.height(40.dp))
    }
}

// MARK: - 공용 소품/헬퍼

/** 50dp 원형 컨트롤 버튼 (ultraThinMaterial 근사). */
@Composable
private fun RoundControlButton(
    icon: ImageVector,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Box(
        Modifier
            .size(50.dp)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.25f))
            .clickable(enabled = enabled) { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = Color.White,
            modifier = Modifier.size(22.dp),
        )
    }
}

/** CameraError → 사용자 문구 (스펙 12 A-2 표). */
private fun CameraError.userMessage(context: Context): String = when (this) {
    is CameraError.NoCamera -> context.getString(R.string.camera_err_no_camera)
    is CameraError.ConfigurationFailed -> context.getString(R.string.camera_err_configuration)
    is CameraError.CaptureFailed -> context.getString(R.string.camera_err_capture)
}

/**
 * Photo Picker Uri → Bitmap. 화면 최대변의 2배 이하로 inSampleSize 다운샘플 (OOM 방지).
 * 합성 결과 크기는 이 배경 사진 크기 기준 — iOS 동일 (스펙 12 A-6).
 */
private fun decodeDownsampledBitmap(context: Context, uri: Uri): Bitmap? = try {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    context.contentResolver.openInputStream(uri)?.use {
        BitmapFactory.decodeStream(it, null, bounds)
    }
    val dm = context.resources.displayMetrics
    val maxTarget = maxOf(dm.widthPixels, dm.heightPixels) * 2
    val maxDim = maxOf(bounds.outWidth, bounds.outHeight)
    var sample = 1
    while (maxDim / (sample * 2) > maxTarget) sample *= 2
    val opts = BitmapFactory.Options().apply {
        inSampleSize = sample
        inPreferredConfig = Bitmap.Config.ARGB_8888
    }
    context.contentResolver.openInputStream(uri)?.use {
        BitmapFactory.decodeStream(it, null, opts)
    }
} catch (_: Exception) {
    null
}
