package com.seoyoung.withu.shared

/**
 * 배경/데코 레이어용 날씨 카테고리 — 4 날씨 + 야간 (iOS WeatherBackgroundCondition 포팅).
 * NIGHT 는 시간 기반 (날씨 무관) — 야간엔 어둠이 가장 강한 시각 신호라 다른 조건을 다 누른다.
 * raw 는 파일명 키 — rename 금지.
 */
enum class WeatherBackgroundCondition(val raw: String) {
    SUNNY("sunny"),
    CLOUDY("cloudy"),
    RAINY("rainy"),
    SNOWY("snowy"),
    NIGHT("night");

    /** 사용자 노출 라벨 (스펙 09 §2 원문). 위젯 접근성 때문에 enum 하드코딩. */
    val displayName: String
        get() = when (this) {
            SUNNY -> "맑음 ☀️"
            CLOUDY -> "흐림 ☁️"
            RAINY -> "비 🌧"
            SNOWY -> "눈 ❄️"
            NIGHT -> "밤하늘 🌙"
        }

    /** drawable/파일 없을 때 화면에 그대로 표시되는 fallback 이모지. */
    val fallbackEmoji: String
        get() = when (this) {
            SUNNY -> "☀️"
            CLOUDY -> "☁️"
            RAINY -> "🌧"
            SNOWY -> "❄️"
            NIGHT -> "🌙"
        }

    /** 배경 AI 생성 프롬프트 (영문 서버 지시문 — 번역 금지, iOS 원문 그대로). */
    val generationHint: String
        get() = when (this) {
            SUNNY ->
                "Bright sunny sky background, soft white clouds, warm sunlight, clean pastel landscape, illustration. NO character, NO person — empty scene only."
            CLOUDY ->
                "Soft overcast cloudy sky background, gray pastel atmosphere, calm empty landscape, illustration. NO character, NO person — empty scene only."
            RAINY ->
                "Rainy weather background scene, light rain falling, wet pavement, soft gray sky, pastel illustration, cinematic. NO character, NO person — empty scene only."
            SNOWY ->
                "Snowy winter background, gentle snowflakes falling, snow on ground, soft cold pastel colors, illustration. NO character, NO person — empty scene only."
            NIGHT ->
                "Calm night sky background, dark blue / deep purple, scattered stars, soft crescent moon, dreamy pastel illustration. NO character, NO person — empty scene only."
        }

    companion object {
        /**
         * 위젯/스냅샷의 emoji 로부터 매핑. WeatherCondition.emoji 와 일치해야 함 —
         * 천둥(⛈)은 비로. NIGHT 는 시간 판정이라 emoji 매핑 없음.
         */
        fun fromEmoji(emoji: String?): WeatherBackgroundCondition? = when (emoji) {
            "☀️" -> SUNNY
            "☁️" -> CLOUDY
            "🌧", "⛈" -> RAINY
            "❄️" -> SNOWY
            else -> null
        }
    }
}
