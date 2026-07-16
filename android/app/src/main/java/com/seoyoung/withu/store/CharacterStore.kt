package com.seoyoung.withu.store

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.seoyoung.withu.character.CharacterState
import java.io.File

/**
 * 캐릭터 PNG 저장소 — iOS CharacterImageStore 의 최소 포팅.
 * filesDir/characters/<state>.png = 활성 슬롯, filesDir/gallery/<uuid>.png = 이력.
 * (위젯 공유가 필요해지면 Glance 가 같은 filesDir 를 읽으므로 App Group 같은 개념 불필요)
 */
object CharacterStore {

    private fun charactersDir(ctx: Context): File =
        File(ctx.filesDir, "characters").apply { mkdirs() }

    private fun galleryDir(ctx: Context): File =
        File(ctx.filesDir, "gallery").apply { mkdirs() }

    /** 활성 슬롯 저장 (128px 다운샘플 후 호출 권장) + 갤러리에도 복사. */
    fun save(ctx: Context, bitmap: Bitmap, state: CharacterState) {
        val slot = File(charactersDir(ctx), "${state.raw}.png")
        slot.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        val galleryFile = File(galleryDir(ctx), "${System.currentTimeMillis()}_${state.raw}.png")
        slot.copyTo(galleryFile, overwrite = true)
    }

    fun load(ctx: Context, state: CharacterState): Bitmap? {
        val f = File(charactersDir(ctx), "${state.raw}.png")
        if (!f.exists()) return null
        return BitmapFactory.decodeFile(f.absolutePath)
    }

    fun hasImage(ctx: Context, state: CharacterState): Boolean =
        File(charactersDir(ctx), "${state.raw}.png").exists()

    fun galleryFiles(ctx: Context): List<File> =
        galleryDir(ctx).listFiles()?.sortedByDescending { it.name } ?: emptyList()
}
