package com.seoyoung.withu.wear

/**
 * 상태 raw → 짧은 라벨 / 번들 fallback 드로어블 이름.
 * iOS CharacterState.shortLabel 의 축소 미러(워치는 표시만).
 * 날씨 접미(walkingSunny 등)는 base 상태로 접어 라벨/드로어블을 공유한다.
 */
object WearCharacter {

    fun shortLabel(raw: String?): String = when (baseOf(raw)) {
        "idle" -> "기본"
        "sleeping" -> "수면"
        "wakingUp" -> "기상"
        "eating" -> "식사"
        "walking" -> "산책"
        "running" -> "달리기"
        "cycling" -> "자전거"
        "energetic" -> "활기찬"
        else -> "기본"
    }

    /** 번들 fallback 드로어블 이름 (base 8종만 존재). 예: "character_walking". */
    fun fallbackDrawableName(raw: String?): String = "character_" + baseOf(raw).lowercase()

    private fun baseOf(raw: String?): String {
        val r = raw ?: "idle"
        return when {
            r.startsWith("walking") -> "walking"
            r.startsWith("running") -> "running"
            r.startsWith("cycling") -> "cycling"
            else -> r
        }
    }
}
