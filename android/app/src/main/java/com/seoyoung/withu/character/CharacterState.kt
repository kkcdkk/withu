package com.seoyoung.withu.character

import androidx.compose.ui.graphics.Color

/**
 * 캐릭터 상태 — iOS CharacterState.swift 의 핵심 8종 포팅.
 * rawValue(name) 는 서버 프롬프트/저장 키와 호환되도록 iOS 와 동일하게 유지.
 * (운동×날씨 조합 12종·레거시 4종은 Android Phase 1 에선 미사용 — 필요 시 추가)
 */
enum class CharacterState(val raw: String) {
    IDLE("idle"),
    SLEEPING("sleeping"),
    WAKING_UP("wakingUp"),
    EATING("eating"),
    WALKING("walking"),
    RUNNING("running"),
    CYCLING("cycling"),
    ENERGETIC("energetic");

    val koreanShortLabel: String
        get() = when (this) {
            IDLE -> "기본"
            SLEEPING -> "수면"
            WAKING_UP -> "기상"
            EATING -> "식사"
            WALKING -> "산책"
            RUNNING -> "달리기"
            CYCLING -> "자전거"
            ENERGETIC -> "활기찬"
        }

    val caption: String
        get() = when (this) {
            IDLE -> "느긋한 하루"
            SLEEPING -> "쿨쿨… 자고 있어요"
            WAKING_UP -> "잠 깨는 중 🥱"
            EATING -> "맛있게 식사 중 🍽️"
            WALKING -> "산책 중 🚶"
            RUNNING -> "달리는 중 🏃"
            CYCLING -> "자전거 타는 중 🚴"
            ENERGETIC -> "에너지 넘치는 하루!"
        }

    val symbolEmoji: String
        get() = when (this) {
            IDLE -> "🙂"
            SLEEPING -> "💤"
            WAKING_UP -> "🥱"
            EATING -> "🍽️"
            WALKING -> "🚶"
            RUNNING -> "🏃"
            CYCLING -> "🚴"
            ENERGETIC -> "✨"
        }

    val tint: Color
        get() = when (this) {
            IDLE -> Color(0xFF8E8E93)        // gray
            SLEEPING -> Color(0xFF5856D6)    // indigo
            WAKING_UP -> Color(0xFFAF52DE)   // purple
            EATING -> Color(0xFFFF3B30)      // red
            WALKING -> Color(0xFF34C759)     // green
            RUNNING -> Color(0xFFFF9500)     // orange
            CYCLING -> Color(0xFF007AFF)     // blue
            ENERGETIC -> Color(0xFFFF2D55)   // pink
        }

    /** AI 생성 시작 프롬프트 — iOS generationHint 와 동일 (서버가 그림체 가드레일 추가). */
    val generationHint: String
        get() = when (this) {
            IDLE -> "standing peacefully, hands folded, looking calm with a small smile"
            SLEEPING -> "sleeping on a small pillow, eyes closed, with a 'zzz' bubble nearby"
            WAKING_UP -> "just woken up, holding a pillow, messy hair, mouth wide open in a big yawn, sleepy half-closed eyes"
            EATING -> "sitting at a small table, holding a fork with food on it down near the plate, food on plate, happy expression"
            WALKING -> "walking happily with one foot up, motion lines, friendly expression"
            RUNNING -> "running with arms swinging energetically, dynamic pose"
            CYCLING -> "riding a small bicycle, wearing a tiny helmet, friendly smile"
            ENERGETIC -> "jumping in the air with sparkles around, super happy"
        }

    companion object {
        fun fromRaw(raw: String): CharacterState? = entries.firstOrNull { it.raw == raw }
    }
}
