package com.seoyoung.withu.character

import androidx.compose.ui.graphics.Color

/**
 * 캐릭터 상태 — iOS CharacterState.swift 의 24 case 전체 포팅 (스펙 08).
 * raw 는 Swift rawValue 원문 — 파일명(characters/<raw>.png)/직렬화 키라서 rename 절대 금지.
 * 라벨/캡션은 위젯(Glance)에서도 Context 없이 접근해야 하므로 enum 에 하드코딩 (iOS 파리티).
 */
enum class CharacterState(val raw: String) {
    // 핵심 8
    IDLE("idle"),
    SLEEPING("sleeping"),
    WAKING_UP("wakingUp"),
    EATING("eating"),
    WALKING("walking"),
    RUNNING("running"),
    CYCLING("cycling"),
    ENERGETIC("energetic"),
    // 레거시 4 — resolver 미반환·픽커 미노출이지만 직렬화/이미지 키 호환 위해 유지
    BEACH("beach"),
    CLOUDY("cloudy"),
    RAINY_SHELTER("rainyShelter"),
    SNOW_PLAY("snowPlay"),
    // 운동 × 날씨 조합 12 — 이미지 없으면 baseFallback 으로 폴백
    WALKING_SUNNY("walkingSunny"),
    WALKING_CLOUDY("walkingCloudy"),
    WALKING_RAINY("walkingRainy"),
    WALKING_SNOWY("walkingSnowy"),
    RUNNING_SUNNY("runningSunny"),
    RUNNING_CLOUDY("runningCloudy"),
    RUNNING_RAINY("runningRainy"),
    RUNNING_SNOWY("runningSnowy"),
    CYCLING_SUNNY("cyclingSunny"),
    CYCLING_CLOUDY("cyclingCloudy"),
    CYCLING_RAINY("cyclingRainy"),
    CYCLING_SNOWY("cyclingSnowy");

    /** 픽커/리스트용 짧은 한글 라벨. 이모지 없음. */
    val koreanShortLabel: String
        get() = when (this) {
            IDLE -> "기본"
            SLEEPING -> "수면"
            WAKING_UP -> "기상"
            EATING -> "식사"
            WALKING, WALKING_SUNNY, WALKING_CLOUDY, WALKING_RAINY, WALKING_SNOWY -> "산책"
            RUNNING, RUNNING_SUNNY, RUNNING_CLOUDY, RUNNING_RAINY, RUNNING_SNOWY -> "달리기"
            CYCLING, CYCLING_SUNNY, CYCLING_CLOUDY, CYCLING_RAINY, CYCLING_SNOWY -> "자전거"
            ENERGETIC -> "활기찬"
            BEACH -> "해변"
            CLOUDY -> "흐림"
            RAINY_SHELTER -> "우산"
            SNOW_PLAY -> "눈놀이"
        }

    /** 홈 히어로 아래 표시 문구. */
    val caption: String
        get() = when (this) {
            IDLE -> "느긋한 하루"
            SLEEPING -> "쿨쿨… 자고 있어요"
            WAKING_UP -> "잠 깨는 중"
            WALKING -> "산책 중"
            RUNNING -> "달리는 중"
            CYCLING -> "자전거 타는 중"
            ENERGETIC -> "에너지 넘치는 하루!"
            EATING -> "맛있게 식사 중"
            BEACH -> "해변에서 일광욕"
            CLOUDY -> "구름 낀 하루"
            RAINY_SHELTER -> "우산 쓰고 비 구경"
            SNOW_PLAY -> "눈 속에서 신나게"
            WALKING_SUNNY -> "햇살 받으며 산책"
            WALKING_CLOUDY -> "흐린 날 산책"
            WALKING_RAINY -> "비 오는데 산책"
            WALKING_SNOWY -> "눈길 산책"
            RUNNING_SUNNY -> "햇살 아래 달리기"
            RUNNING_CLOUDY -> "흐린 날 달리기"
            RUNNING_RAINY -> "비 맞으며 달리기"
            RUNNING_SNOWY -> "눈 속 달리기"
            CYCLING_SUNNY -> "햇살 자전거"
            CYCLING_CLOUDY -> "흐린 날 자전거"
            CYCLING_RAINY -> "비 오는데 자전거"
            CYCLING_SNOWY -> "눈 속 자전거"
        }

    /** 인라인 위젯/짧은 슬롯용 표시 이모지. 이미지 없을 때 최후 fallback 으로도 사용. */
    val symbolEmoji: String
        get() = when (this) {
            IDLE -> "🙂"
            SLEEPING -> "💤"
            WAKING_UP -> "🥱"
            WALKING -> "🚶"
            RUNNING -> "🏃"
            CYCLING -> "🚴"
            ENERGETIC -> "✨"
            EATING -> "🍽️"
            BEACH -> "🏖️"
            CLOUDY -> "☁️"
            RAINY_SHELTER -> "☔️"
            SNOW_PLAY -> "❄️"
            WALKING_SUNNY -> "🚶☀️"
            WALKING_CLOUDY -> "🚶☁️"
            WALKING_RAINY -> "🚶☔"
            WALKING_SNOWY -> "🚶❄️"
            RUNNING_SUNNY -> "🏃☀️"
            RUNNING_CLOUDY -> "🏃☁️"
            RUNNING_RAINY -> "🏃☔"
            RUNNING_SNOWY -> "🏃❄️"
            CYCLING_SUNNY -> "🚴☀️"
            CYCLING_CLOUDY -> "🚴☁️"
            CYCLING_RAINY -> "🚴☔"
            CYCLING_SNOWY -> "🚴❄️"
        }

    /** iOS 시스템 색 근사 hex (스펙 08 §5). */
    val tint: Color
        get() = when (this) {
            IDLE, CLOUDY -> Color(0xFF8E8E93)                                    // gray
            SLEEPING -> Color(0xFF5856D6)                                        // indigo
            WAKING_UP -> Color(0xFFAF52DE)                                       // purple
            WALKING -> Color(0xFF34C759)                                         // green
            RUNNING -> Color(0xFFFF9500)                                         // orange
            CYCLING -> Color(0xFF007AFF)                                         // blue
            ENERGETIC -> Color(0xFFFF2D55)                                       // pink
            EATING -> Color(0xFFFF3B30)                                          // red
            BEACH -> Color(0xFFFFCC00)                                           // yellow
            RAINY_SHELTER -> Color(0xFF30B0C7)                                   // teal
            SNOW_PLAY -> Color(0xFF32ADE6)                                       // cyan
            WALKING_SUNNY, RUNNING_SUNNY, CYCLING_SUNNY -> Color(0xFFFFCC00)     // yellow
            WALKING_CLOUDY, RUNNING_CLOUDY, CYCLING_CLOUDY -> Color(0xFF8E8E93)  // gray
            WALKING_RAINY, RUNNING_RAINY, CYCLING_RAINY -> Color(0xFF007AFF)     // blue
            WALKING_SNOWY, RUNNING_SNOWY, CYCLING_SNOWY -> Color(0xFF32ADE6)     // cyan
        }

    /**
     * AI 생성 시작 프롬프트 — iOS 원문 그대로 (서버가 그림체 가드레일 추가).
     * 서버 지시문(영문)이라 strings 리소스가 아닌 코드 상수 (00-PLAN §3-5).
     */
    val generationHint: String
        get() = when (this) {
            IDLE -> "standing peacefully, hands folded, looking calm with a small smile"
            SLEEPING -> "sleeping on a small pillow, eyes closed, with a 'zzz' bubble nearby"
            WAKING_UP -> "just woken up, holding a pillow, messy hair, mouth wide open in a big yawn, sleepy half-closed eyes"
            WALKING -> "walking happily with one foot up, motion lines, friendly expression"
            RUNNING -> "running with arms swinging energetically, dynamic pose"
            CYCLING -> "riding a small bicycle, wearing a tiny helmet, friendly smile"
            ENERGETIC -> "jumping in the air with sparkles around, super happy"
            EATING -> "sitting at a small table, holding a fork with food on it down near the plate, food on plate, happy expression"
            BEACH -> "lying on a beach towel with sunglasses, sun overhead"
            CLOUDY -> "standing calmly with small fluffy clouds floating above the head, soft cloudy sky background, peaceful expression"
            RAINY_SHELTER -> "holding an umbrella, wearing rain boots, raindrops around"
            SNOW_PLAY -> "standing in snow, making a snowball, wearing mittens and scarf"
            WALKING_SUNNY -> "walking happily under bright sunshine, sunny clear sky background, motion lines"
            WALKING_CLOUDY -> "walking calmly with soft cloudy sky background, motion lines"
            WALKING_RAINY -> "walking while holding an umbrella, light rain falling, wet pavement reflection"
            WALKING_SNOWY -> "walking in snow wearing a scarf and mittens, snowflakes around, snow on ground"
            RUNNING_SUNNY -> "running energetically under bright sunshine, sunny clear sky, motion blur"
            RUNNING_CLOUDY -> "running with arms swinging under cloudy sky, motion blur"
            RUNNING_RAINY -> "running in light rain, raindrops around, wet pavement"
            RUNNING_SNOWY -> "running through snow, scarf flowing, snowflakes falling"
            CYCLING_SUNNY -> "riding a small bicycle under bright sunshine, sunny clear sky, helmet on"
            CYCLING_CLOUDY -> "riding a bicycle under cloudy sky, helmet on, calm expression"
            CYCLING_RAINY -> "riding a bicycle in light rain wearing a raincoat or hood, raindrops around"
            CYCLING_SNOWY -> "riding a bicycle through light snow, bundled up with scarf and mittens"
        }

    /**
     * 연속 이미지(움직임) 생성 시 frame 2 변화 힌트 — iOS 원문 그대로.
     * "slightly different pose" 같은 모호한 표현은 거의 같은 그림이 나와서 state 별로 구체적 변화를 정의.
     */
    val animationFrame2Hint: String
        get() = when (this) {
            IDLE ->
                "eyes blinking (closed eyelids) instead of open, or head tilted to the opposite side. Keep everything else identical."
            SLEEPING ->
                "breathing in (slightly puffed chest / cheeks) instead of out, or 'z' bubble in a different position. Same closed eyes, same pillow."
            WAKING_UP ->
                "mouth fully closed with relaxed lips (NOT yawning), and both eyes closed (relaxed, resting). Same messy hair, same pillow, same pose and size."
            WALKING ->
                "a full stride swap: the clearly OPPOSITE leg forward — if frame 1's LEFT leg is forward, now the RIGHT leg is forward and the left leg is back, with arm swing mirrored to match. Same direction of walking, same outfit, same size and position."
            RUNNING ->
                "a full stride swap: arms and legs in the clearly OPPOSITE swing phase — if frame 1 had the right leg and left arm forward, frame 2 has the left leg and right arm forward. Same speed, same expression, same size and position."
            CYCLING ->
                "pedals rotated half a turn — opposite foot at the top. Same helmet, same direction, same bicycle."
            ENERGETIC ->
                "jumping at the higher peak with arms wider, or sparkles in a different position. Same big smile."
            EATING ->
                "the fork raised all the way up to the mouth, taking a bite — mouth open around the food, cheeks a little full. Same table, same food, same outfit, same size and position."
            BEACH ->
                "waving one hand, or sunglasses pushed slightly up — small but visible change. Same beach towel, same sun overhead."
            CLOUDY ->
                "small cloud floating to the other side above the head. Same calm expression, same background."
            RAINY_SHELTER ->
                "umbrella tilted to the opposite angle, or rain drops in different positions. Same boots and outfit."
            SNOW_PLAY ->
                "snowball mid-toss (in the air) instead of in hands, or scarf flowing the other direction. Same mittens, same snow ground."
            // 조합 — 운동 base 의 hint 와 동일한 변화 패턴 사용
            WALKING_SUNNY, WALKING_CLOUDY, WALKING_RAINY, WALKING_SNOWY ->
                "a full stride swap: the clearly OPPOSITE leg forward — if frame 1's LEFT leg is forward, now the RIGHT leg is forward and the left leg is back, arm swing mirrored. Same direction, same outfit, same weather conditions, same size and position."
            RUNNING_SUNNY, RUNNING_CLOUDY, RUNNING_RAINY, RUNNING_SNOWY ->
                "a full stride swap: arms and legs in the clearly OPPOSITE swing phase (left leg forward becomes right leg forward). Same speed, same expression, same weather conditions, same size and position."
            CYCLING_SUNNY, CYCLING_CLOUDY, CYCLING_RAINY, CYCLING_SNOWY ->
                "pedals rotated half a turn — opposite foot at the top. Same helmet, same direction, same bicycle, same weather conditions."
        }

    /**
     * frame2(움직임)를 실제로 새로 생성할지.
     * false = 미세 모션은 절차적으로 충분 + 2프레임 재생성 시 이목구비 드리프트로 오히려 나빠지는 상태들.
     */
    val usesGeneratedMotion: Boolean
        get() = when (this) {
            IDLE, SLEEPING, BEACH, CLOUDY, RAINY_SHELTER -> false
            else -> true
        }

    /** 조합 state 의 기본 운동 state (이미지 폴백 + 매핑용). 조합이 아니면 null. */
    val baseFallback: CharacterState?
        get() = when (this) {
            WALKING_SUNNY, WALKING_CLOUDY, WALKING_RAINY, WALKING_SNOWY -> WALKING
            RUNNING_SUNNY, RUNNING_CLOUDY, RUNNING_RAINY, RUNNING_SNOWY -> RUNNING
            CYCLING_SUNNY, CYCLING_CLOUDY, CYCLING_RAINY, CYCLING_SNOWY -> CYCLING
            else -> null
        }

    /**
     * 번들 일러스트 drawable 이름. Android 리소스는 소문자만 허용이라
     * rawValue 를 lowercase 로 변환 (예: walkingSunny → character_walkingsunny).
     * 파일 스키마(characters/<raw>.png)는 rawValue 원문 — 두 이름을 혼동하지 말 것 (스펙 08 §5).
     */
    val imageAssetName: String
        get() = "character_" + raw.lowercase()

    companion object {
        /**
         * 사용자 픽커에 노출하는 8개 — resolver 가 실제로 자동 반환하는 것.
         * 순서 고정 (갤러리 그룹핑 rank 에도 사용).
         */
        val userFacing: List<CharacterState> = listOf(
            IDLE, SLEEPING, WAKING_UP, EATING,
            WALKING, RUNNING, CYCLING, ENERGETIC,
        )

        fun fromRaw(raw: String): CharacterState? = entries.firstOrNull { it.raw == raw }
    }
}
