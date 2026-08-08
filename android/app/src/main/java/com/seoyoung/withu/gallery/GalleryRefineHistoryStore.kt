package com.seoyoung.withu.gallery

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.seoyoung.withu.WithuApp
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

/**
 * 갤러리 항목별 '다듬기 이력'(버전 체인) 영속 — iOS GalleryRefineHistoryStore
 * (CharacterGalleryView.swift:1494-1537) 포팅.
 *
 * 갤러리 원본은 항목당 하나뿐이라 각 버전 이미지를 직접 PNG 로 보관한다.
 * 파일 스키마는 iOS 와 바이트 동일:
 *   filesDir/gallery_refine/<itemId>/0.png, 1.png, … + meta.json
 *   meta.json = {"selected":Int,"count":Int}
 * count > 1 (다듬은 게 하나라도 있음) 일 때만 의미가 있어 그때만 저장한다.
 *
 * ⚠️ 파일 I/O 는 전부 동기 — caller 가 Dispatchers.IO 에서 호출할 것 (00-PLAN §0-3).
 */
internal object GalleryRefineHistoryStore {

    /** 버전 상한 — [0] 원본은 항상 보존하고 가장 오래된 '다듬음'부터 밀어낸다. */
    const val MAX_VERSIONS = 8

    private const val FOLDER = "gallery_refine"
    private const val META_NAME = "meta.json"

    @Serializable
    private data class Meta(val selected: Int, val count: Int)

    private val json = Json { ignoreUnknownKeys = true }

    private fun dir(itemId: String): File = File(File(WithuApp.context.filesDir, FOLDER), itemId)

    /** 이력 통째로 다시 쓰기 — 인덱스가 어긋나지 않게 폴더를 비우고 처음부터 쓴다. */
    fun save(itemId: String, versions: List<Bitmap>, selected: Int) {
        if (versions.size <= 1) return
        val d = dir(itemId)
        d.deleteRecursively()
        if (!d.mkdirs()) return
        versions.forEachIndexed { i, bmp ->
            runCatching {
                File(d, "$i.png").outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
            }
        }
        runCatching {
            val meta = Meta(selected = selected.coerceIn(0, versions.size - 1), count = versions.size)
            File(d, META_NAME).writeText(json.encodeToString(Meta.serializer(), meta))
        }
    }

    fun clear(itemId: String) {
        dir(itemId).deleteRecursively()
    }

    fun exists(itemId: String): Boolean = File(dir(itemId), META_NAME).exists()

    /** 복원 — 버전 파일이 하나라도 없으면 null (인덱스 어긋난 이력은 쓰지 않는다). */
    fun load(itemId: String): Pair<List<Bitmap>, Int>? {
        val d = dir(itemId)
        val metaFile = File(d, META_NAME)
        if (!metaFile.exists()) return null
        val meta = runCatching {
            json.decodeFromString(Meta.serializer(), metaFile.readText())
        }.getOrNull() ?: return null
        if (meta.count <= 1) return null
        // 투명 배경 유지 필수 — ARGB_8888 강제 디코드 (CharacterImageStore.decodePng 와 동일)
        val opts = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
        val versions = ArrayList<Bitmap>(meta.count)
        for (i in 0 until meta.count) {
            val bmp = BitmapFactory.decodeFile(File(d, "$i.png").absolutePath, opts) ?: return null
            versions.add(bmp)
        }
        return versions to meta.selected.coerceIn(0, versions.size - 1)
    }
}

/**
 * 다듬기 버전 체인에 새 버전 추가 — 상한(8) 초과 시 [0](원본)은 보존하고
 * 가장 오래된 다듬기(index 1)를 밀어낸다 (iOS CharacterGalleryView.swift:1194).
 */
internal fun <T> appendRefineVersion(
    versions: List<T>,
    new: T,
    limit: Int = GalleryRefineHistoryStore.MAX_VERSIONS,
): List<T> {
    val next = versions + new
    return if (next.size > limit) listOf(next.first()) + next.drop(2) else next
}
