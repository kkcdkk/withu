package com.seoyoung.withu.camera

import android.content.ContentValues
import android.graphics.Bitmap
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.seoyoung.withu.WithuApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException

/**
 * 사진 앱(MediaStore) 저장 — iOS PHPhotoLibrary(addOnly) 대응 (00-PLAN §2-9).
 * F2 가 실제 구현으로 미리 생성 — S2/S3/S4/S6 공용 (카메라 전용이 아님).
 * API 29+ 는 scoped storage 라 권한 불필요, API 28 만 WRITE_EXTERNAL_STORAGE 필요 —
 * 권한 요청/거부 문구는 caller(각 화면) 소관.
 */
object PhotoSaver {

    /** API 28(P) 이하 — WRITE_EXTERNAL_STORAGE 런타임 권한이 필요한지. */
    fun needsLegacyWritePermission(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    /**
     * 비트맵을 사진 앱에 PNG 로 저장. 실패는 Result.failure — 사용자 문구는 caller 가 결정.
     * (API 28 에서 권한 없이 호출하면 insert/write 가 실패해 failure 로 떨어진다.)
     */
    suspend fun save(bitmap: Bitmap): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val resolver = WithuApp.context.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, "withu_${System.currentTimeMillis()}.png")
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(
                        MediaStore.Images.Media.RELATIVE_PATH,
                        Environment.DIRECTORY_PICTURES + "/withu",
                    )
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
            }
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("MediaStore insert failed")
            try {
                resolver.openOutputStream(uri)?.use { out ->
                    if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)) {
                        throw IOException("PNG compress failed")
                    }
                } ?: throw IOException("openOutputStream failed")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val done = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
                    resolver.update(uri, done, null, null)
                }
            } catch (e: Exception) {
                // 반쯤 쓰인 항목이 사진 앱에 남지 않게 정리 후 재던짐
                resolver.delete(uri, null, null)
                throw e
            }
        }
    }
}
