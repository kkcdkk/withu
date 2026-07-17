package com.seoyoung.withu.character

import com.seoyoung.withu.shared.SharedAppState
import com.seoyoung.withu.shared.StoreEvents
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * 사용자가 설정하는 캐릭터 프로필 — iOS CharacterProfile.swift 포팅.
 * resolver 가 수면/식사 시간 정보를 사용. JSON 으로 공유 prefs 에 저장.
 */
@Serializable
data class CharacterProfile(
    val name: String = "내 캐릭터",
    val description: String = "",
    /** AI 캐릭터 생성 시 baseIdentity 의 default — 비어있으면 hardcoded fallback 사용. */
    val aiPrompt: String = "",
    /** 수면 시작 시 (0-23). 기본 22 = 22:00 */
    val sleepStartHour: Int = 22,
    val sleepStartMinute: Int = 0,
    /** 기상 시 (0-23). 기본 7 = 07:00 */
    val sleepEndHour: Int = 7,
    val sleepEndMinute: Int = 0,
    /** 점심 시작. 30분 동안 식사 */
    val lunchHour: Int = 12,
    val lunchMinute: Int = 0,
    /** 저녁 시작. 30분 동안 식사 */
    val dinnerHour: Int = 18,
    val dinnerMinute: Int = 0,
    /**
     * true 면 수면 신호(DND/수면 세션)를 무시하고 sleepStart/End 시간만으로 sleeping 판정.
     * nullable 인 이유: 옛 저장 데이터엔 이 키가 없어 null → false fallback (구버전 호환).
     */
    val manualSleepOnly: Boolean? = null,
    /** 야간 fallback 시작 (분, midnight 기준). null → 20:00 (1200). */
    val nightFallbackStartMinute: Int? = null,
    /** 야간 fallback 종료 (분, midnight 기준). null → 06:00 (360). */
    val nightFallbackEndMinute: Int? = null,
    // 애니메이션 토글은 CharacterImageStore 로 분리 — 위젯도 읽어야 하기 때문 (iOS 파리티).
) {
    // 기본값 '설정 시간 기준'(true) — 설치 직후 별도 설정 없이도 밤에 확실히 자는 경험.
    // '수면 모드 기준'(false)은 opt-in. (iOS CharacterProfile.isManualSleepOnly 와 동일)
    val isManualSleepOnly: Boolean get() = manualSleepOnly ?: true
    val effectiveNightFallbackStart: Int get() = nightFallbackStartMinute ?: 1200
    val effectiveNightFallbackEnd: Int get() = nightFallbackEndMinute ?: 360
}

/**
 * 프로필 저장소 — 공유 prefs 키 `withu.characterProfile.v1` (iOS 키 원문 유지).
 * 저장 시 StoreEvents.characterProfileChanged emit → 홈 즉시 갱신.
 */
object CharacterProfileStore {
    private const val KEY = "withu.characterProfile.v1"
    private val json = Json { ignoreUnknownKeys = true }

    // load 초기값은 최초 접근 시 1회 — SharedPreferences 읽기는 가벼워 lazy 로 충분.
    private val _profileFlow: MutableStateFlow<CharacterProfile> by lazy { MutableStateFlow(load()) }

    val profileFlow: StateFlow<CharacterProfile> get() = _profileFlow

    fun load(): CharacterProfile {
        val raw = SharedAppState.prefs().getString(KEY, null) ?: return CharacterProfile()
        return runCatching { json.decodeFromString<CharacterProfile>(raw) }
            .getOrDefault(CharacterProfile())
    }

    fun save(profile: CharacterProfile) {
        SharedAppState.prefs().edit()
            .putString(KEY, json.encodeToString(CharacterProfile.serializer(), profile))
            .apply()
        _profileFlow.value = profile
        // 메인 화면 등에 알려서 즉시 갱신 (iOS NotificationCenter 대응)
        StoreEvents.characterProfileChanged.tryEmit(Unit)
    }
}
