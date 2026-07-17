package com.seoyoung.withu.camera

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import androidx.camera.core.CameraInfoUnavailableException
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.lifecycle.awaitInstance
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * 카메라 에러 — iOS CameraError 대응 (스펙 12 A-2 문구 표).
 * 사용자 문구 매핑은 화면(CameraScreen)이 strings 리소스로 담당.
 * NotAuthorized 는 화면이 권한 런처로 직접 판정하므로 여기엔 없음.
 */
sealed class CameraError : Exception() {
    class NoCamera : CameraError()
    class ConfigurationFailed : CameraError()
    class CaptureFailed : CameraError()
}

/**
 * CameraX 래퍼 — iOS CameraSession.swift 대응 (스펙 12 A-6).
 * iOS 는 AVCaptureSession 싱글턴 + 멱등 configure 였지만, CameraX 는
 * ProcessCameraProvider 가 lifecycle 바인딩/해제를 관리해 주므로
 * 화면 단위 인스턴스 + bindToLifecycle 로 대체 (재진입 시 unbindAll 후 재바인딩).
 */
class CameraController {

    private var provider: ProcessCameraProvider? = null
    private var imageCapture: ImageCapture? = null

    /** 초기 카메라 = 후면 (iOS 초기 후면 광각과 동일). */
    var lensFacing: Int = CameraSelector.LENS_FACING_BACK
        private set

    /**
     * 권한 승인 후 호출 — 프리뷰 + 캡처 유스케이스 바인딩.
     * @throws CameraError.NoCamera / CameraError.ConfigurationFailed
     */
    suspend fun bind(context: Context, lifecycleOwner: LifecycleOwner, previewView: PreviewView) {
        val provider = awaitProvider(context)
        this.provider = provider
        bindUseCases(provider, lifecycleOwner, previewView)
    }

    /**
     * 전면↔후면 전환 — CameraX 는 selector 를 바꿔 재바인딩.
     * @return 성공 여부. 실패 시 lensFacing 원복 (화면이 '카메라 전환 실패' 문구 표시).
     */
    fun switchCamera(lifecycleOwner: LifecycleOwner, previewView: PreviewView): Boolean {
        val provider = provider ?: return false
        val old = lensFacing
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK) {
            CameraSelector.LENS_FACING_FRONT
        } else {
            CameraSelector.LENS_FACING_BACK
        }
        return try {
            bindUseCases(provider, lifecycleOwner, previewView)
            true
        } catch (_: CameraError) {
            lensFacing = old
            // 원래 카메라로 되돌리기 시도 — 실패해도 화면은 에러 문구만 표시
            runCatching { bindUseCases(provider, lifecycleOwner, previewView) }
            false
        }
    }

    /** 화면 이탈 시 해제 — iOS onDisappear { camera.stop() } 대응. */
    fun unbind() {
        runCatching { provider?.unbindAll() }
        imageCapture = null
    }

    /**
     * 셔터 — in-memory 캡처 후 EXIF 회전(rotationDegrees)을 반영한 업라이트 Bitmap 반환.
     * '왜': 회전 미반영 시 합성 캐릭터 좌표가 90° 틀어짐 (스펙 12 A-6 회전 주의).
     * @throws CameraError.CaptureFailed
     */
    suspend fun capture(context: Context): Bitmap {
        val capture = imageCapture ?: throw CameraError.ConfigurationFailed()
        return suspendCancellableCoroutine { cont ->
            capture.takePicture(
                ContextCompat.getMainExecutor(context),
                object : ImageCapture.OnImageCapturedCallback() {
                    override fun onCaptureSuccess(image: ImageProxy) {
                        val result = runCatching { image.toUprightBitmap() }
                        image.close()
                        result.fold(
                            onSuccess = { cont.resume(it) },
                            onFailure = { cont.resumeWithException(CameraError.CaptureFailed()) },
                        )
                    }

                    override fun onError(exception: ImageCaptureException) {
                        cont.resumeWithException(CameraError.CaptureFailed())
                    }
                },
            )
        }
    }

    private fun bindUseCases(
        provider: ProcessCameraProvider,
        lifecycleOwner: LifecycleOwner,
        previewView: PreviewView,
    ) {
        val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()
        val hasCamera = try {
            provider.hasCamera(selector)
        } catch (_: CameraInfoUnavailableException) {
            false
        }
        if (!hasCamera) throw CameraError.NoCamera()

        val preview = Preview.Builder().build().also {
            it.surfaceProvider = previewView.surfaceProvider
        }
        val capture = ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
            .build()
        try {
            provider.unbindAll()
            provider.bindToLifecycle(lifecycleOwner, selector, preview, capture)
            imageCapture = capture
        } catch (_: Exception) {
            throw CameraError.ConfigurationFailed()
        }
    }

    // CameraX 1.4+ 의 suspend awaitInstance() 사용 — guava ListenableFuture 타입을
    // 전혀 노출하지 않아 클래스패스 스텁(빈 listenablefuture jar) 문제를 피함 (스펙 12 A-6).
    private suspend fun awaitProvider(context: Context): ProcessCameraProvider =
        try {
            ProcessCameraProvider.awaitInstance(context)
        } catch (_: Exception) {
            throw CameraError.ConfigurationFailed()
        }
}

/**
 * ImageProxy(JPEG) → 회전 반영 Bitmap.
 * 전면 카메라 미러링 안 함 — iOS AVCapturePhotoOutput 도 전면 캡처가 비미러 (파리티).
 */
private fun ImageProxy.toUprightBitmap(): Bitmap {
    val bitmap = toBitmap()
    val degrees = imageInfo.rotationDegrees
    if (degrees == 0) return bitmap
    val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
    return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
}
