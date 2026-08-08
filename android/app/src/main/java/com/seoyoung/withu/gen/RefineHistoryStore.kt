package com.seoyoung.withu.gen

import android.graphics.Bitmap
import com.seoyoung.withu.WithuApp
import com.seoyoung.withu.shared.CharacterImageStore
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

/**
 * '하나씩 만들기' 다듬기 이력을 디스크에 저장 — 화면을 나갔다 와도 이력·선택이 복원된다
 * (iOS CharacterGenView.swift 의 RefineHistoryStore 포팅).
 *
 * 이미지는 각 버전이 이미 갤러리에 자동 저장돼 있으므로 여기선 galleryId 체인만 보관한다.
 * (새 캐릭터를 만들면 generate() 가 이력을 갈아끼우며 이 저장본도 덮어쓴다.)
 *
 * ⚠️ 파일 I/O 는 동기 — caller 가 Dispatchers.IO 에서 호출할 것 (다른 스토어와 같은 규약).
 * ⚠️ 파일명 `single_refine_history.json` 은 iOS 와 바이트 동일 (rename 금지).
 */
internal object RefineHistoryStore {

    private const val FILE_NAME = "single_refine_history.json"

    @Serializable
    private data class SavedVersion(val galleryId: String, val isRefined: Boolean, val hasFrame2: Boolean)

    @Serializable
    private data class SavedChain(val stateRaw: String, val selected: Int, val versions: List<SavedVersion>)

    private val json = Json { ignoreUnknownKeys = true }

    private fun file(): File = File(WithuApp.context.filesDir, FILE_NAME)

    /**
     * versions: (galleryId, 다듬음 여부, 움직임 프레임 여부).
     * galleryId 가 하나라도 없으면 인덱스가 어긋나 복원이 깨지므로 저장본을 지우고 중단한다.
     */
    fun save(stateRaw: String, selected: Int, versions: List<Triple<String?, Boolean, Boolean>>) {
        val saved = versions.mapNotNull { (id, isRefined, hasFrame2) ->
            id?.let { SavedVersion(it, isRefined, hasFrame2) }
        }
        if (saved.isEmpty() || saved.size != versions.size) {
            file().delete()
            return
        }
        val sel = selected.coerceIn(0, saved.size - 1)
        runCatching {
            file().writeText(json.encodeToString(SavedChain.serializer(), SavedChain(stateRaw, sel, saved)))
        }
    }

    /** 저장된 체인의 메타만 (이미지 디코딩 없이) — 워커가 이력을 이어붙일 때 쓴다. */
    class ChainEntry(val galleryId: String, val isRefined: Boolean, val hasFrame2: Boolean)

    class ChainMeta(val stateRaw: String, val selected: Int, val versions: List<ChainEntry>)

    fun loadMeta(): ChainMeta? {
        val f = file()
        if (!f.exists()) return null
        val chain = runCatching {
            json.decodeFromString(SavedChain.serializer(), f.readText())
        }.getOrNull() ?: return null
        if (chain.versions.isEmpty()) return null
        return ChainMeta(
            chain.stateRaw,
            chain.selected.coerceIn(0, chain.versions.size - 1),
            chain.versions.map { ChainEntry(it.galleryId, it.isRefined, it.hasFrame2) },
        )
    }

    class RestoredVersion(
        val small: Bitmap,
        val frame2: Bitmap?,
        val galleryId: String,
        val isRefined: Boolean,
    )

    class Restored(val stateRaw: String, val selected: Int, val versions: List<RestoredVersion>)

    /** 저장된 체인 복원 — 갤러리에서 이미지를 다시 읽는다. 하나라도 사라졌으면 복원 취소(null). */
    fun load(): Restored? {
        val f = file()
        if (!f.exists()) return null
        val chain = runCatching {
            json.decodeFromString(SavedChain.serializer(), f.readText())
        }.getOrNull() ?: return null
        val out = mutableListOf<RestoredVersion>()
        for (v in chain.versions) {
            val small = CharacterImageStore.loadGalleryImage(v.galleryId) ?: return null
            val f2 = if (v.hasFrame2) CharacterImageStore.loadGalleryFrame1(v.galleryId) else null
            out.add(RestoredVersion(small, f2, v.galleryId, v.isRefined))
        }
        if (out.isEmpty()) return null
        return Restored(chain.stateRaw, chain.selected.coerceIn(0, out.size - 1), out)
    }
}
