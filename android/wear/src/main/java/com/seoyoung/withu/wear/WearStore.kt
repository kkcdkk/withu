package com.seoyoung.withu.wear

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File

/**
 * 워치 로컬 저장소 — 폰이 push 한 상태 스냅샷 + 상태별 캐릭터 PNG 를 보관.
 * iOS 워치의 SharedAppState(스냅샷) + CharacterImageStore(PNG) 를 워치 단독 파일로 합친 축소판.
 * 폰이 두뇌라 여기엔 계산 로직이 없다 — 받은 걸 그대로 읽어 Tile/화면이 표시만 한다.
 *
 * Data Layer 경로/키는 폰 WearSyncManager 와 바이트 동일해야 한다.
 */
object WearStore {

    const val PATH_STATE = "/withu/state"
    const val PATH_IMAGE_PREFIX = "/withu/image/"

    private const val PREFS = "withu_wear"
    private const val KEY_STATE = "state"
    private const val KEY_STEPS = "steps"
    private const val KEY_SLEEP = "sleepHours"
    private const val KEY_WEATHER_EMOJI = "weatherEmoji"
    private const val KEY_TEMP = "tempC"
    private const val KEY_UPDATED_AT = "updatedAt"

    // 워치가 손목 움직임으로 직접 감지한 활동(산책/달리기/자전거). 폰 없이도 바로 반영.
    private const val KEY_WATCH_ACT = "watchActivity"
    private const val KEY_WATCH_ACT_AT = "watchActivityAt"
    private const val WATCH_ACT_FRESH_MS = 10 * 60 * 1000L  // EXIT 놓쳐도 10분 뒤 자동 해제

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun imageDir(context: Context): File =
        File(context.filesDir, "characters").apply { mkdirs() }

    private fun imageFile(context: Context, stateRaw: String): File =
        File(imageDir(context), "$stateRaw.png")

    // --- 상태 스냅샷 ---

    fun saveState(
        context: Context,
        stateRaw: String,
        steps: Double?,
        sleepHours: Double?,
        weatherEmoji: String?,
        tempC: Double?,
        updatedAt: Long,
    ) {
        prefs(context).edit().apply {
            putString(KEY_STATE, stateRaw)
            if (steps != null) putFloat(KEY_STEPS, steps.toFloat()) else remove(KEY_STEPS)
            if (sleepHours != null) putFloat(KEY_SLEEP, sleepHours.toFloat()) else remove(KEY_SLEEP)
            if (weatherEmoji != null) putString(KEY_WEATHER_EMOJI, weatherEmoji) else remove(KEY_WEATHER_EMOJI)
            if (tempC != null) putFloat(KEY_TEMP, tempC.toFloat()) else remove(KEY_TEMP)
            putLong(KEY_UPDATED_AT, updatedAt)
        }.apply()
    }

    data class Snapshot(
        val stateRaw: String?,
        val steps: Int?,
        val weatherEmoji: String?,
        val tempC: Int?,
        val updatedAt: Long,
    )

    // --- 손목 활동 (워치 자체 감지) ---

    fun saveWatchActivity(context: Context, stateRaw: String?) {
        prefs(context).edit().apply {
            if (stateRaw == null) {
                remove(KEY_WATCH_ACT); remove(KEY_WATCH_ACT_AT)
            } else {
                putString(KEY_WATCH_ACT, stateRaw)
                putLong(KEY_WATCH_ACT_AT, System.currentTimeMillis())
            }
        }.apply()
    }

    /** 지금 저장된 손목 활동 raw (freshness 무시) — EXIT 매칭용. */
    fun currentWatchActivityRaw(context: Context): String? =
        prefs(context).getString(KEY_WATCH_ACT, null)

    /**
     * 표시에 쓸 상태 — 손목 활동이 최근(10분 내)이면 그걸 우선(폰 없이도 산책 반영),
     * 아니면 폰이 push 한 스냅샷 상태.
     */
    fun effectiveStateRaw(context: Context): String? {
        val p = prefs(context)
        val act = p.getString(KEY_WATCH_ACT, null)
        val at = p.getLong(KEY_WATCH_ACT_AT, 0L)
        if (act != null && System.currentTimeMillis() - at < WATCH_ACT_FRESH_MS) return act
        return p.getString(KEY_STATE, null)
    }

    fun loadSnapshot(context: Context): Snapshot {
        val p = prefs(context)
        return Snapshot(
            stateRaw = p.getString(KEY_STATE, null),
            steps = if (p.contains(KEY_STEPS)) p.getFloat(KEY_STEPS, 0f).toInt() else null,
            weatherEmoji = p.getString(KEY_WEATHER_EMOJI, null),
            tempC = if (p.contains(KEY_TEMP)) p.getFloat(KEY_TEMP, 0f).toInt() else null,
            updatedAt = p.getLong(KEY_UPDATED_AT, 0L),
        )
    }

    // --- 캐릭터 이미지 (상태별) ---

    fun saveImage(context: Context, stateRaw: String, png: ByteArray) {
        val f = imageFile(context, stateRaw)
        val tmp = File(f.parentFile, f.name + ".tmp")
        tmp.writeBytes(png)
        tmp.renameTo(f)
    }

    /** 상태의 사용자 적용 PNG. 없으면 null → 화면/Tile 이 번들 fallback 사용. */
    fun loadImage(context: Context, stateRaw: String): Bitmap? {
        val f = imageFile(context, stateRaw)
        if (!f.exists()) return null
        return runCatching { BitmapFactory.decodeFile(f.absolutePath) }.getOrNull()
    }

    fun loadImageBytes(context: Context, stateRaw: String): ByteArray? {
        val f = imageFile(context, stateRaw)
        return if (f.exists()) runCatching { f.readBytes() }.getOrNull() else null
    }
}
