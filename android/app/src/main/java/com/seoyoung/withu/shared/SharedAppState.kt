package com.seoyoung.withu.shared

import android.content.Context
import android.content.SharedPreferences
import com.seoyoung.withu.WithuApp
import kotlinx.serialization.json.Json

/**
 * 공유 상태 저장소 — iOS SharedAppState(App Group UserDefaults) 대응.
 * Android 는 위젯(Glance)이 같은 프로세스라 App Group 이 불필요 —
 * 단일 SharedPreferences 파일 "withu_shared" 로 대체. 키 문자열은 iOS 원문 유지.
 */
object SharedAppState {
    /** iOS groupID 의 흔적 — Android 에선 prefs 파일명으로 대체. */
    const val PREFS_NAME = "withu_shared"
    private const val MESSAGE_KEY = "withu.currentMessage.v1"

    private val json = Json { ignoreUnknownKeys = true }

    /** quota/설정이 공용으로 쓰는 공유 prefs 파일. */
    fun prefs(): SharedPreferences =
        WithuApp.context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** 스냅샷 저장. 위젯 갱신(updateAll)은 caller 책임 — iOS 와 동일 계약. */
    fun save(message: WatchMessage) {
        prefs().edit()
            .putString(MESSAGE_KEY, json.encodeToString(WatchMessage.serializer(), message))
            .apply()
    }

    fun loadMessage(): WatchMessage? {
        val raw = prefs().getString(MESSAGE_KEY, null) ?: return null
        return runCatching { json.decodeFromString<WatchMessage>(raw) }.getOrNull()
    }
}

/**
 * 앱 설정 플래그 — 00-PLAN §2-2 계약.
 * onboarded/seenGuide 는 표준 prefs (위젯이 안 읽음), 나머지는 공유 prefs.
 */
object AppPrefs {
    private const val STANDARD_PREFS_NAME = "withu_prefs"
    private const val ONBOARDED_KEY = "withu.onboarded.v1"
    private const val SEEN_GUIDE_KEY = "withu.seenGuide.v1"
    private const val SHOW_WEATHER_DECORATION_KEY = "withu.showWeatherDecoration.v1"
    private const val LAST_BACKGROUND_REFRESH_AT_KEY = "withu.lastBackgroundRefreshAt"

    private fun standard(): SharedPreferences =
        WithuApp.context.getSharedPreferences(STANDARD_PREFS_NAME, Context.MODE_PRIVATE)

    var onboarded: Boolean
        get() = standard().getBoolean(ONBOARDED_KEY, false)
        set(value) = standard().edit().putBoolean(ONBOARDED_KEY, value).apply()

    var seenGuide: Boolean
        get() = standard().getBoolean(SEEN_GUIDE_KEY, false)
        set(value) = standard().edit().putBoolean(SEEN_GUIDE_KEY, value).apply()

    /** 날씨 데코 표시 토글 — 기본 true. 위젯도 읽으므로 공유 prefs. */
    var showWeatherDecoration: Boolean
        get() = SharedAppState.prefs().getBoolean(SHOW_WEATHER_DECORATION_KEY, true)
        set(value) = SharedAppState.prefs().edit().putBoolean(SHOW_WEATHER_DECORATION_KEY, value).apply()

    /** 마지막 백그라운드 갱신 시각 (epoch millis). 없으면 null. */
    var lastBackgroundRefreshAt: Long?
        get() {
            val p = SharedAppState.prefs()
            return if (p.contains(LAST_BACKGROUND_REFRESH_AT_KEY)) {
                p.getLong(LAST_BACKGROUND_REFRESH_AT_KEY, 0L)
            } else null
        }
        set(value) {
            val e = SharedAppState.prefs().edit()
            if (value == null) e.remove(LAST_BACKGROUND_REFRESH_AT_KEY)
            else e.putLong(LAST_BACKGROUND_REFRESH_AT_KEY, value)
            e.apply()
        }
}
