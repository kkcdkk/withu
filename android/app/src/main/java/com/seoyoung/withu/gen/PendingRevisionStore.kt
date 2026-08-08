package com.seoyoung.withu.gen

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.seoyoung.withu.WithuApp
import com.seoyoung.withu.character.CharacterState
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

/**
 * 배치 다듬기 이력(버전 체인)을 '적용/취소' 전에 디스크에 보관 —
 * 배치 화면을 완전히 나갔다 들어와도 결정 안 한 이력을 복원한다 (캔디 쓴 결과 유실 방지).
 * iOS BatchCharacterGenView.swift:2269-2340 PendingRevisionStore 포팅.
 *
 * 파일 스키마는 iOS 와 바이트 동일 (App Group 컨테이너 ↔ Android filesDir):
 *   filesDir/pending_revisions/<state.raw>.v<i>.png   128 썸네일 (표시·저장용)
 *   filesDir/pending_revisions/<state.raw>.f<i>.png   1024 풀해상도 (다음 다듬기 참조용)
 *   filesDir/pending_revisions/<state.raw>.json       {"frame":Int,"selected":Int,"count":Int,"prompt":String}
 *
 * ⚠️ 파일 I/O 는 전부 동기 — caller 가 Dispatchers.IO 에서 호출할 것 (00-PLAN §0-3).
 */
internal object PendingRevisionStore {

    private const val FOLDER = "pending_revisions"

    @Serializable
    private data class Meta(val frame: Int, val selected: Int, val count: Int, val prompt: String)

    private val json = Json { ignoreUnknownKeys = true }

    private fun folder(): File = File(WithuApp.context.filesDir, FOLDER).apply { mkdirs() }

    /** 한 상태의 이력 통째로 다시 쓰기 — 인덱스가 어긋나지 않게 기존 파일을 지우고 처음부터. */
    fun save(state: CharacterState, chain: BatchRevision) {
        val dir = folder()
        remove(state)
        val key = state.raw
        chain.versions.forEachIndexed { i, bmp -> writePng(bmp, File(dir, pendingThumbName(key, i))) }
        chain.fullVersions.forEachIndexed { i, bmp -> writePng(bmp, File(dir, pendingFullName(key, i))) }
        runCatching {
            val meta = Meta(
                frame = chain.frame,
                selected = chain.selected.coerceIn(0, chain.versions.size - 1),
                count = chain.versions.size,
                prompt = chain.prompt,
            )
            File(dir, pendingMetaName(key)).writeText(json.encodeToString(Meta.serializer(), meta))
        }
    }

    /** 이 상태의 이력 파일 전부 삭제 — 접두사 "<raw>." 로 시작하는 것만 (iOS hasPrefix 동형). */
    fun remove(state: CharacterState) {
        val prefix = pendingFilePrefix(state.raw)
        folder().listFiles()?.forEach { f ->
            if (f.name.startsWith(prefix)) f.delete()
        }
    }

    /** 폴더 통째 삭제 — 새 배치 시작(= 새 캐릭터로 덮어쓸 때)에만 호출한다. */
    fun clearAll() {
        File(WithuApp.context.filesDir, FOLDER).deleteRecursively()
    }

    /** 복원 결과 — 뷰모델이 BatchRevision 으로 되살린다. */
    data class Restored(
        val state: CharacterState,
        val frame: Int,
        val versions: List<Bitmap>,
        val fullVersions: List<Bitmap>,
        val selected: Int,
        val prompt: String,
    )

    /** 저장된 이력 복원. 버전 파일이 하나라도 없으면 그 상태는 건너뛴다 (인덱스 어긋난 이력은 안 씀). */
    fun loadAll(): List<Restored> {
        val dir = folder()
        val files = dir.listFiles() ?: return emptyList()
        val out = mutableListOf<Restored>()
        for (f in files) {
            val key = pendingStateRawFromMetaName(f.name) ?: continue
            val state = CharacterState.fromRaw(key) ?: continue
            val meta = runCatching {
                json.decodeFromString(Meta.serializer(), f.readText())
            }.getOrNull() ?: continue
            // count <= 1 은 '원본만' 이라 이력으로서 의미가 없음 (iOS meta.count > 1 가드).
            if (meta.count <= 1) continue
            val versions = ArrayList<Bitmap>(meta.count)
            val fulls = ArrayList<Bitmap>(meta.count)
            var ok = true
            for (i in 0 until meta.count) {
                val v = decodePng(File(dir, pendingThumbName(key, i)))
                val full = decodePng(File(dir, pendingFullName(key, i)))
                if (v == null || full == null) {
                    ok = false
                    break
                }
                versions.add(v)
                fulls.add(full)
            }
            if (!ok) continue
            out += Restored(
                state = state,
                frame = meta.frame,
                versions = versions,
                fullVersions = fulls,
                selected = meta.selected.coerceIn(0, versions.size - 1),
                prompt = meta.prompt,
            )
        }
        return out
    }

    private fun writePng(image: Bitmap, file: File) {
        runCatching {
            file.outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
    }

    /** 투명 배경 유지 필수 — ARGB_8888 강제 디코드 (CharacterImageStore.decodePng 와 동일 규칙). */
    private fun decodePng(file: File): Bitmap? {
        if (!file.exists()) return null
        val opts = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
        return BitmapFactory.decodeFile(file.absolutePath, opts)
    }
}

// ----------------------------------------------------------------------------
// 파일명 규칙 — iOS 와 바이트 동일해야 하는 부분이라 순수 함수로 떼어 테스트한다.
// ----------------------------------------------------------------------------

/** 128 썸네일 파일명 — `<state.raw>.v<i>.png`. */
internal fun pendingThumbName(stateRaw: String, index: Int): String = "$stateRaw.v$index.png"

/** 1024 풀해상도 파일명 — `<state.raw>.f<i>.png`. */
internal fun pendingFullName(stateRaw: String, index: Int): String = "$stateRaw.f$index.png"

/** 메타 파일명 — `<state.raw>.json`. */
internal fun pendingMetaName(stateRaw: String): String = "$stateRaw.json"

/**
 * 한 상태의 파일 접두사 — 점(.)까지 포함해야 raw 가 서로 접두사인 상태끼리 섞이지 않는다
 * (예: "sleep" 삭제가 "sleeping" 파일을 지우면 안 됨).
 */
internal fun pendingFilePrefix(stateRaw: String): String = "$stateRaw."

/**
 * 메타 파일명 → state raw. `.json` 으로 끝나는 파일만 인정 (iOS `pathExtension == "json"` 동형).
 * `idle.v0.png` 같은 이미지 파일은 null.
 */
internal fun pendingStateRawFromMetaName(fileName: String): String? {
    if (!fileName.endsWith(".json")) return null
    return fileName.removeSuffix(".json").takeIf { it.isNotEmpty() }
}
