package com.seoyoung.withu.weather

/**
 * 날씨 조건 + 스냅샷 — 00-PLAN §2-8 계약, iOS WeatherCondition.swift 포팅.
 * (파일 소유는 F2 이지만 CharacterStateResolver 시그니처가 WeatherSnapshot 에 의존해
 *  F1 이 계약대로 먼저 생성 — F2 는 WeatherManager 를 별도 파일로 추가한다.)
 */
enum class WeatherCondition {
    SUNNY, CLOUDY, RAINY, SNOWY, FOGGY, THUNDER, UNKNOWN;

    val emoji: String
        get() = when (this) {
            SUNNY -> "☀️"
            CLOUDY -> "☁️"
            RAINY -> "🌧"
            SNOWY -> "❄️"
            FOGGY -> "🌫"
            THUNDER -> "⛈"
            UNKNOWN -> "❓"
        }

    val caption: String
        get() = when (this) {
            SUNNY -> "맑음"
            CLOUDY -> "흐림"
            RAINY -> "비"
            SNOWY -> "눈"
            FOGGY -> "안개"
            THUNDER -> "뇌우"
            UNKNOWN -> "?"   // iOS 도 비로컬라이즈 리터럴
        }

    companion object {
        /** Open-Meteo WMO weather_code → condition (스펙 10 §3.1 매핑 전량). */
        fun fromWmo(code: Int): WeatherCondition = when (code) {
            0, 1 -> SUNNY                 // clear / mainly clear
            2, 3 -> CLOUDY                // partly cloudy / overcast
            45, 48 -> FOGGY
            in 51..67 -> RAINY            // drizzle / rain
            in 71..77 -> SNOWY            // snow fall
            in 80..82 -> RAINY            // rain showers
            85, 86 -> SNOWY               // snow showers
            in 95..99 -> THUNDER
            else -> UNKNOWN
        }
    }
}

/** 1회 측정 스냅샷. sunrise/sunset 은 epoch millis (옵셔널 — 이전 캐시 호환). */
data class WeatherSnapshot(
    val condition: WeatherCondition,
    val temperatureC: Double,
    val timestamp: Long,
    val sunrise: Long? = null,
    val sunset: Long? = null,
) {
    /** 해변 캐릭터 판정 임계. */
    val isHot: Boolean get() = temperatureC >= 30
    val isCold: Boolean get() = temperatureC <= 0
}
