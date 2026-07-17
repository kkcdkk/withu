package com.seoyoung.withu.store

import android.content.Context
import android.graphics.Bitmap
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.shared.CharacterImageStore
import java.io.File

/**
 * (Deprecated) 구 화면(ui/HomeScreen, ui/GenerateScreen) 컴파일 유지용 위임 셔틀 —
 * 실제 저장은 shared/CharacterImageStore. Phase I 에서 구 화면과 함께 삭제 예정 (00-PLAN §1-1).
 */
@Deprecated("shared/CharacterImageStore 를 사용할 것 — Phase I 에서 삭제")
object CharacterStore {

    /** 활성 슬롯 + 갤러리에 저장 (신규 스토어 위임). */
    fun save(ctx: Context, bitmap: Bitmap, state: CharacterState) {
        CharacterImageStore.save(bitmap, state)
    }

    fun load(ctx: Context, state: CharacterState): Bitmap? =
        CharacterImageStore.load(state)

    fun hasImage(ctx: Context, state: CharacterState): Boolean =
        CharacterImageStore.hasImage(state)

    /** 구 화면 전용 — gallery 폴더의 PNG 파일 목록 (metadata.json 제외). */
    fun galleryFiles(ctx: Context): List<File> {
        val dir = File(ctx.filesDir, "gallery")
        return dir.listFiles()
            ?.filter { it.extension == "png" }
            ?.sortedByDescending { it.lastModified() }
            ?: emptyList()
    }
}
