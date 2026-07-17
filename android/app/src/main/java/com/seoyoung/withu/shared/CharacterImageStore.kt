package com.seoyoung.withu.shared

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import com.seoyoung.withu.WithuApp
import com.seoyoung.withu.character.CharacterState
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import java.io.File
import java.util.UUID

/**
 * 캐릭터 이미지 영구 저장소 — iOS CharacterImageStore.swift 포팅 (스펙 09).
 * 파일 스키마는 iOS 와 동형 (rawValue 기준):
 *   filesDir/characters/<raw>.png (+ <raw>_f1.png)  ← 활성 슬롯 (홈/위젯이 읽는 "현재 적용본")
 *   filesDir/gallery/<uuid>.png (+ <uuid>_f1.png) + metadata.json  ← 전체 이력
 *   filesDir/backgrounds|decorations/  ← 예약 폴더 (배경 AI 는 후속 — wipeAll 만 지움)
 *
 * ⚠️ 파일 I/O 는 전부 동기 — caller 가 Dispatchers.IO 에서 호출할 것 (00-PLAN §0-3).
 * 위젯 갱신(updateAll)은 caller 책임 — 이 객체는 StoreEvents 만 emit 한다.
 */
object CharacterImageStore {

    private const val ACTIVE_FOLDER = "characters"
    private const val GALLERY_FOLDER = "gallery"
    private const val METADATA_NAME = "metadata.json"
    private const val BACKGROUNDS_FOLDER = "backgrounds"
    private const val DECORATIONS_FOLDER = "decorations"
    private const val ANIMATION_ENABLED_KEY = "withu.animationEnabled.v1"
    private const val ANIMATION_DISABLED_STATES_KEY = "withu.animationDisabledStates.v1"
    private const val ACTIVE_SOURCE_MAP_KEY = "withu.activeSourceMap.v1"

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = false; explicitNulls = false }

    // MARK: - 디코드 캐시
    // 활성 슬롯 PNG 를 매 표시마다 재디코드하던 것을 캐시 (0.7초 frame swap·스크롤 렉 제거).
    // 쓰기 드묾·읽기 hot → 쓰기 때 전체 비움(단순/안전). 상한 24MB — 위젯 메모리 보호.
    private val imageCache = object : LruCache<String, Bitmap>(24 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
    }

    private fun evictImageCache() = imageCache.evictAll()

    /**
     * 활성 파일의 내용 버전(수정시각ms+크기) — 파일이 바뀌면 캐시 키도 바뀌어
     * 앱 내 다중 진입점(위젯 Worker 등)이 evict 없이도 새 파일을 자동 인지.
     */
    private fun fileVersion(file: File): String =
        if (file.exists()) "${file.lastModified()}_${file.length()}" else "0"

    // MARK: - 폴더/파일 경로

    private fun ensureFolder(name: String): File =
        File(WithuApp.context.filesDir, name).apply { mkdirs() }

    private fun activeFile(state: CharacterState, frame: Int = 0): File {
        val folder = ensureFolder(ACTIVE_FOLDER)
        return if (frame > 0) File(folder, "${state.raw}_f$frame.png")
        else File(folder, "${state.raw}.png")
    }

    private fun galleryFile(id: String): File = File(ensureFolder(GALLERY_FOLDER), "$id.png")
    private fun galleryFrame1File(id: String): File = File(ensureFolder(GALLERY_FOLDER), "${id}_f1.png")
    private fun metadataFile(): File = File(ensureFolder(GALLERY_FOLDER), METADATA_NAME)

    /** atomic write 대응 — tmp 에 쓴 뒤 rename (iOS .atomic 옵션과 같은 의도). */
    private fun writeAtomic(file: File, block: (File) -> Unit): Boolean {
        val tmp = File(file.parentFile, file.name + ".tmp")
        return try {
            block(tmp)
            if (file.exists()) file.delete()
            tmp.renameTo(file)
        } catch (_: Exception) {
            tmp.delete()
            false
        }
    }

    private fun writePngAtomic(bitmap: Bitmap, file: File): Boolean = writeAtomic(file) { tmp ->
        tmp.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    /** ARGB_8888 강제 디코드 — 투명 배경 유지 필수. */
    private fun decodePng(file: File): Bitmap? {
        if (!file.exists()) return null
        val opts = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
        return BitmapFactory.decodeFile(file.absolutePath, opts)
    }

    // MARK: - 활성 슬롯

    /** 활성 슬롯 로드 (= loadFrame frame 0). */
    fun load(state: CharacterState): Bitmap? = loadFrame(state, 0)

    /** frame 별 로드. frame > 0 인데 없으면 null — caller 가 frame 0 fallback (저장소는 폴백 안 함). */
    fun loadFrame(state: CharacterState, frame: Int): Bitmap? {
        val file = activeFile(state, frame)
        val key = "${state.raw}#$frame#full#${fileVersion(file)}"
        imageCache.get(key)?.let { return it }
        val bmp = decodePng(file) ?: return null
        imageCache.put(key, bmp)
        return bmp
    }

    /**
     * 위젯 메모리 절약용 다운샘플 로드. inSampleSize(2^n 근사) 후 정밀 축소 —
     * ARGB 유지 (Glance 에 큰 비트맵 넘기면 TransactionTooLargeException).
     */
    fun loadThumbnail(state: CharacterState, maxPixelSize: Int): Bitmap? {
        val file = activeFile(state, 0)
        val key = "${state.raw}#0#t$maxPixelSize#${fileVersion(file)}"
        imageCache.get(key)?.let { return it }
        if (!file.exists()) return null

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        val maxDim = maxOf(bounds.outWidth, bounds.outHeight)
        if (maxDim <= 0) return null

        var sample = 1
        while (maxDim / (sample * 2) >= maxPixelSize) sample *= 2
        val opts = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        var bmp = BitmapFactory.decodeFile(file.absolutePath, opts) ?: return null
        val decodedMax = maxOf(bmp.width, bmp.height)
        if (decodedMax > maxPixelSize) {
            val scale = maxPixelSize.toFloat() / decodedMax
            bmp = Bitmap.createScaledBitmap(
                bmp,
                (bmp.width * scale).toInt().coerceAtLeast(1),
                (bmp.height * scale).toInt().coerceAtLeast(1),
                true,
            )
        }
        imageCache.put(key, bmp)
        return bmp
    }

    fun hasImage(state: CharacterState): Boolean = activeFile(state, 0).exists()

    /** 애니메이션 frame 존재 여부 (f1 존재 = 애니 캐릭터). */
    fun hasAnimationFrames(state: CharacterState): Boolean = activeFile(state, 1).exists()

    /**
     * 활성 슬롯 파일만 덮어쓰기 — 갤러리/매핑 불변.
     * 결과 화면 transparent 토글처럼 "갤러리 원본 유지, 표시만 교체" 용도.
     * frame0 저장 시 옛 f1 은 반드시 삭제 — 안 지우면 "frame1 없는 새 캐릭터가
     * 옛 캐릭터의 frame1 과 섞여 움직이는" 버그가 재현된다 (스펙 09 §3-4 핵심 규칙).
     */
    fun saveActiveSlotOnly(image: Bitmap, state: CharacterState, frame: Int = 0): Boolean {
        val ok = writePngAtomic(image, activeFile(state, frame))
        if (!ok) return false
        if (frame == 0) activeFile(state, 1).delete()
        evictImageCache()
        StoreEvents.characterImageChanged.tryEmit(state)
        return true
    }

    /** 활성 슬롯 삭제 → 번들 일러스트/이모지 fallback 으로 복귀. */
    fun clearActive(state: CharacterState) {
        activeFile(state, 0).delete()
        evictImageCache()
    }

    /** 활성 슬롯 f0 ↔ f1 맞바꿈 (tmp 경유 move — iOS 동일 패턴). 둘 다 있어야 성공. */
    fun swapActiveFrames(state: CharacterState): Boolean {
        val f0 = activeFile(state, 0)
        val f1 = activeFile(state, 1)
        if (!f0.exists() || !f1.exists()) return false
        val tmp = File(f0.parentFile, "swap_tmp.png")
        tmp.delete()
        if (!f0.renameTo(tmp)) return false
        if (!f1.renameTo(f0)) { tmp.renameTo(f0); return false }
        if (!tmp.renameTo(f1)) return false
        evictImageCache()
        StoreEvents.characterImageChanged.tryEmit(state)
        return true
    }

    /** 계정/데이터 초기화 — 4개 폴더 + 활성 매핑 + 캐시 전부 제거. */
    fun wipeAll() {
        for (name in listOf(ACTIVE_FOLDER, GALLERY_FOLDER, BACKGROUNDS_FOLDER, DECORATIONS_FOLDER)) {
            File(WithuApp.context.filesDir, name).deleteRecursively()
        }
        SharedAppState.prefs().edit().remove(ACTIVE_SOURCE_MAP_KEY).apply()
        evictImageCache()
        StoreEvents.characterImageChanged.tryEmit(null)
        StoreEvents.weatherBackgroundChanged.tryEmit(Unit)
    }

    // MARK: - 생성/갤러리 저장

    /**
     * state 의 활성 슬롯 + 갤러리에 동시 저장 (생성 흐름에서 호출).
     * - frame 0: 새 갤러리 항목 생성 → 그 id 를 activeSourceMap 에 기록.
     * - frame 1: 새 항목 안 만들고 같은 state 의 가장 최근 항목에 f1 붙이고 hasFrame1=true.
     *   (frame0 없이 frame1 만 오는 케이스는 정상 흐름에 없음 → null 반환)
     * - applyToActiveSlot=false: 갤러리에만 저장 — 배치의 "만들어만 두고 나중에 적용" 흐름.
     */
    fun save(
        image: Bitmap,
        state: CharacterState,
        frame: Int = 0,
        applyToActiveSlot: Boolean = true,
        batchId: String? = null,
        prompt: String? = null,
    ): GalleryItem? {
        // 1) 활성 슬롯 (위젯이 보는 곳)
        if (applyToActiveSlot) {
            writePngAtomic(image, activeFile(state, frame))
            // frame0(새 기본 이미지) 저장 시 옛 f1(움직임)은 무효 → 제거.
            // 애니메이션 캐릭터면 이 직후 frame1 이 다시 저장된다.
            if (frame == 0) activeFile(state, 1).delete()
            evictImageCache()
            StoreEvents.characterImageChanged.tryEmit(state)
        }
        // 2) 갤러리 — frame 별 분기
        return if (frame == 0) {
            val item = addToGalleryInternal(image, state, batchId, prompt)
            if (item != null) setActiveSource(state, item.id)
            item
        } else {
            attachFrame1ToLatestGalleryItem(image, state)
        }
    }

    private fun addToGalleryInternal(
        image: Bitmap,
        sourceState: CharacterState,
        batchId: String?,
        prompt: String?,
    ): GalleryItem? {
        val id = UUID.randomUUID().toString()
        if (!writePngAtomic(image, galleryFile(id))) return null
        val item = GalleryItem(
            id = id,
            sourceState = sourceState.raw,
            createdAt = System.currentTimeMillis(),
            batchId = batchId,
            prompt = prompt,
        )
        saveGalleryMetadata(loadGalleryMetadata() + item)
        return item
    }

    /** frame 1 을 같은 state 의 가장 최근 갤러리 항목에 추가. 없으면 null. */
    private fun attachFrame1ToLatestGalleryItem(image: Bitmap, sourceState: CharacterState): GalleryItem? {
        val all = loadGalleryMetadata().toMutableList()   // createdAt desc 정렬됨
        val idx = all.indexOfFirst { it.sourceState == sourceState.raw }
        if (idx < 0) return null
        val item = all[idx]
        if (!writePngAtomic(image, galleryFrame1File(item.id))) return null
        all[idx] = item.copy(hasFrame1 = true)
        saveGalleryMetadata(all)
        return all[idx]
    }

    // MARK: - 갤러리 조회/조작

    /** 갤러리 메타 전체 — createdAt 내림차순. */
    fun loadGalleryMetadata(): List<GalleryItem> {
        val file = metadataFile()
        if (!file.exists()) return emptyList()
        val items = runCatching {
            json.decodeFromString(ListSerializer(GalleryItem.serializer()), file.readText())
        }.getOrDefault(emptyList())
        return items.sortedByDescending { it.createdAt }
    }

    private fun saveGalleryMetadata(items: List<GalleryItem>) {
        writeAtomic(metadataFile()) { tmp ->
            tmp.writeText(json.encodeToString(ListSerializer(GalleryItem.serializer()), items))
        }
    }

    /**
     * 상태별 그룹핑 — userFacing 상태별 버킷 + 옛/비노출 상태는 legacy("기타") 버킷.
     * 디스크 포맷 불변, 메모리 그룹핑만.
     */
    fun loadGalleryGrouped(): GalleryGrouped {
        val all = loadGalleryMetadata()   // 이미 createdAt desc
        val facing = CharacterState.userFacing.toSet()
        val byState = mutableMapOf<CharacterState, MutableList<GalleryItem>>()
        val legacy = mutableListOf<GalleryItem>()
        for (item in all) {
            val st = CharacterState.fromRaw(item.sourceState)
            if (st != null && st in facing) byState.getOrPut(st) { mutableListOf() }.add(item)
            else legacy.add(item)
        }
        return GalleryGrouped(byState, legacy)
    }

    /**
     * '캐릭터별' 그룹 — batchId 로 묶음. batchId 없는 항목(단건·옛)은 제외.
     * 최신 그룹 먼저 (그룹 createdAt = 항목 max), 그룹 안은 userFacing 순서 (rank 없으면 맨 뒤).
     */
    fun loadGalleryByCharacter(): List<GalleryCharacterGroup> {
        val all = loadGalleryMetadata()
        val groups = mutableMapOf<String, MutableList<GalleryItem>>()
        for (item in all) {
            val bid = item.batchId ?: continue
            groups.getOrPut(bid) { mutableListOf() }.add(item)
        }
        val order = CharacterState.userFacing
        fun rank(raw: String): Int =
            CharacterState.fromRaw(raw)?.let { order.indexOf(it).takeIf { i -> i >= 0 } } ?: order.size
        return groups.map { (bid, items) ->
            GalleryCharacterGroup(
                batchId = bid,
                createdAt = items.maxOf { it.createdAt },
                items = items.sortedBy { rank(it.sourceState) },
            )
        }.sortedByDescending { it.createdAt }
    }

    fun loadGalleryImage(id: String): Bitmap? = decodePng(galleryFile(id))

    fun loadGalleryFrame1(id: String): Bitmap? = decodePng(galleryFrame1File(id))

    /** 갤러리 파일 교체 (배경 빼기 등 후처리 반영). 메타 불변. */
    fun replaceGalleryImage(id: String, image: Bitmap, frame: Int = 0): Boolean {
        val file = if (frame == 1) galleryFrame1File(id) else galleryFile(id)
        return writePngAtomic(image, file)
    }

    /** 갤러리 항목 f0 ↔ f1 맞바꿈. 둘 다 있어야 성공. */
    fun swapGalleryFrames(id: String): Boolean {
        val f0 = galleryFile(id)
        val f1 = galleryFrame1File(id)
        if (!f0.exists() || !f1.exists()) return false
        val tmp = File(f0.parentFile, "${id}_swap_tmp.png")
        tmp.delete()
        if (!f0.renameTo(tmp)) return false
        if (!f1.renameTo(f0)) { tmp.renameTo(f0); return false }
        if (!tmp.renameTo(f1)) return false
        return true
    }

    /**
     * 갤러리 항목을 지정 state 의 활성 슬롯으로 적용.
     * f1 규칙: 갤러리에 있으면 같이 복사, 없으면 active 의 기존 f1 삭제 (다른 캐릭터 잔재 방지).
     */
    fun applyGalleryItem(id: String, state: CharacterState): Boolean {
        val src = galleryFile(id)
        if (!src.exists()) return false
        val ok = writeAtomic(activeFile(state, 0)) { tmp -> src.copyTo(tmp, overwrite = true) }
        if (!ok) return false
        val srcF1 = galleryFrame1File(id)
        if (srcF1.exists()) {
            writeAtomic(activeFile(state, 1)) { tmp -> srcF1.copyTo(tmp, overwrite = true) }
        } else {
            activeFile(state, 1).delete()
        }
        setActiveSource(state, id)
        evictImageCache()
        StoreEvents.characterImageChanged.tryEmit(state)
        return true
    }

    /**
     * 갤러리 항목 삭제 — f0 + f1 + 메타 + 활성 source 매핑 정리.
     * 활성 슬롯 PNG 자체는 안 지움 (이미 적용된 그림은 계속 보임, 출처 링크만 끊김).
     */
    fun deleteGalleryItem(id: String) {
        galleryFile(id).delete()
        galleryFrame1File(id).delete()
        saveGalleryMetadata(loadGalleryMetadata().filterNot { it.id == id })
        val map = loadActiveSourceMap().toMutableMap()
        val staleKeys = map.filterValues { it == id }.keys
        if (staleKeys.isNotEmpty()) {
            staleKeys.forEach { map.remove(it) }
            saveActiveSourceMap(map)
        }
    }

    // MARK: - 활성 출처 매핑 ([state.raw: galleryId])

    private val sourceMapSerializer = MapSerializer(String.serializer(), String.serializer())

    private fun loadActiveSourceMap(): Map<String, String> {
        val raw = SharedAppState.prefs().getString(ACTIVE_SOURCE_MAP_KEY, null) ?: return emptyMap()
        return runCatching { json.decodeFromString(sourceMapSerializer, raw) }.getOrDefault(emptyMap())
    }

    private fun saveActiveSourceMap(map: Map<String, String>) {
        SharedAppState.prefs().edit()
            .putString(ACTIVE_SOURCE_MAP_KEY, json.encodeToString(sourceMapSerializer, map))
            .apply()
    }

    private fun setActiveSource(state: CharacterState, galleryId: String?) {
        val map = loadActiveSourceMap().toMutableMap()
        if (galleryId != null) map[state.raw] = galleryId else map.remove(state.raw)
        saveActiveSourceMap(map)
    }

    /** 특정 state 슬롯에 현재 적용된 갤러리 id (갤러리 상세 "적용 중" 뱃지). */
    fun currentGalleryItemId(state: CharacterState): String? = loadActiveSourceMap()[state.raw]

    /** 한 갤러리 항목이 어떤 state 슬롯들에 적용 중인지 (삭제 확인 다이얼로그 역검색). */
    fun statesUsingGalleryItem(id: String): List<CharacterState> =
        loadActiveSourceMap().mapNotNull { (k, v) ->
            if (v == id) CharacterState.fromRaw(k) else null
        }

    // MARK: - 애니메이션 토글 (프로필과 별도 저장 — 위젯도 읽음)

    /** 전역 애니메이션 토글 — f1 이 있어도 재생할지. 기본 true. */
    fun isAnimationEnabled(): Boolean =
        SharedAppState.prefs().getBoolean(ANIMATION_ENABLED_KEY, true)

    fun setAnimationEnabled(enabled: Boolean) {
        SharedAppState.prefs().edit().putBoolean(ANIMATION_ENABLED_KEY, enabled).apply()
        // 모든 state 갱신 트리거 — null 로 broadcast.
        StoreEvents.characterImageChanged.tryEmit(null)
    }

    /** 상태별 움직임 끄기 — 전역과 별개. f1 파일은 남겨두고 재생만 막음. */
    fun isAnimationDisabled(state: CharacterState): Boolean =
        SharedAppState.prefs().getStringSet(ANIMATION_DISABLED_STATES_KEY, emptySet())
            ?.contains(state.raw) == true

    fun setAnimationDisabled(disabled: Boolean, state: CharacterState) {
        val set = SharedAppState.prefs().getStringSet(ANIMATION_DISABLED_STATES_KEY, emptySet())
            .orEmpty().toMutableSet()
        if (disabled) set.add(state.raw) else set.remove(state.raw)
        SharedAppState.prefs().edit().putStringSet(ANIMATION_DISABLED_STATES_KEY, set).apply()
        evictImageCache()
        StoreEvents.characterImageChanged.tryEmit(state)
    }

    // MARK: - 야간 판정 (순수 함수 — 단위 테스트 대상)

    /**
     * 시간 기반 야간 판정.
     * 1) sunrise/sunset 둘 다 있으면 그 시각 기준 — **분(minute-of-day)만 비교**.
     *    저장된 일출/일몰의 절대 날짜가 오늘이 아닐 수 있어(스테일) 시-분만 보면 안전.
     * 2) 없으면 fallback 20:00~06:00 (자정 넘김 wrap 처리).
     */
    fun isCurrentlyNight(
        nowMinuteOfDay: Int,
        sunriseMinuteOfDay: Int? = null,
        sunsetMinuteOfDay: Int? = null,
        fallbackStartMinute: Int = 20 * 60,
        fallbackEndMinute: Int = 6 * 60,
    ): Boolean {
        if (sunriseMinuteOfDay != null && sunsetMinuteOfDay != null) {
            return nowMinuteOfDay < sunriseMinuteOfDay || nowMinuteOfDay >= sunsetMinuteOfDay
        }
        val s = fallbackStartMinute % (24 * 60)
        val e = fallbackEndMinute % (24 * 60)
        return if (s < e) nowMinuteOfDay in s until e
        else nowMinuteOfDay >= s || nowMinuteOfDay < e
    }
}
