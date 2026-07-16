# 08 — 상태 결정(CharacterStateResolver) + 캐릭터 표시(CharacterImageView/CharacterView)

진실의 원천 (Swift):
- `withu/Character/CharacterState.swift`
- `withu/Character/CharacterStateResolver.swift`
- `withu/Character/CharacterImageView.swift`
- `withu/Character/CharacterView.swift`
- (참조) `withu/Shared/CharacterProfile.swift` — resolver 가 읽는 프로필 기본값

이 문서는 UI 화면이 아니라 **공유 도메인 계층** 스펙이다: 상태 enum, 상태 자동 결정 순수 함수,
캐릭터 이미지 3단 fallback 뷰, 절차적 모션(2프레임 swap + 날씨 입자), 캡션 히어로 뷰.

---

## 1. 화면/모듈 구조

UI 계층이 아닌 순수 컴포넌트 4개. 위→아래 = 의존 방향.

1. **`CharacterState`** (enum, 24 case) — 모든 타깃(앱/위젯)이 공유하는 직렬화 가능한 상태 키.
2. **`CharacterStateResolver`** (순수 함수 object) — 시간/운동/수면신호/프로필 → `CharacterState`.
3. **`CharacterImageView`** (Composable) — 상태 하나를 이미지로 렌더. 3단 fallback + 옵션(다운샘플/외곽선/애니메이션).
   - 조건부: `animated=true` **그리고** frame1 파일 존재 **그리고** 상태별 애니메이션 미비활성 **그리고** 전역 토글 on → 0.7초 프레임 swap.
   - 부속: **`WeatherDecorationView`** — 날씨 조건별 코너 이모지/PNG 또는 떨어지는 입자(비/눈).
   - 부속(legacy): **`WeatherBackgroundView`** — AI 풀배경. SCOPE 제외(배경 생성 후속)이지만 표시 로직만 참고.
4. **`CharacterView`** (Composable) — 홈 히어로: tint 원(15% 투명) + 캐릭터 이미지 + 캡션 텍스트.

---

## 2. 사용자 문구 전량 (한국어 원문 그대로)

### 2.1 `koreanShortLabel` — 픽커/리스트용 짧은 라벨 (이모지 없음)

| state | 라벨 |
|---|---|
| idle | 기본 |
| sleeping | 수면 |
| wakingUp | 기상 |
| eating | 식사 |
| walking (+Sunny/Cloudy/Rainy/Snowy 조합 동일) | 산책 |
| running (+조합 동일) | 달리기 |
| cycling (+조합 동일) | 자전거 |
| energetic | 활기찬 |
| beach | 해변 |
| cloudy | 흐림 |
| rainyShelter | 우산 |
| snowPlay | 눈놀이 |

### 2.2 `caption` — 홈 히어로 아래 표시 문구

| state | caption |
|---|---|
| idle | 느긋한 하루 |
| sleeping | 쿨쿨… 자고 있어요 |
| wakingUp | 잠 깨는 중 🥱 |
| walking | 산책 중 🚶 |
| running | 달리는 중 🏃 |
| cycling | 자전거 타는 중 🚴 |
| energetic | 에너지 넘치는 하루! |
| eating | 맛있게 식사 중 🍽️ |
| beach | 해변에서 일광욕 🏖️ |
| cloudy | 구름 낀 하루 ☁️ |
| rainyShelter | 우산 쓰고 비 구경 ☔️ |
| snowPlay | 눈 속에서 신나게 ❄️ |
| walkingSunny | 햇살 받으며 산책 🚶☀️ |
| walkingCloudy | 흐린 날 산책 🚶☁️ |
| walkingRainy | 비 오는데 산책 🚶☔ |
| walkingSnowy | 눈길 산책 🚶❄️ |
| runningSunny | 햇살 아래 달리기 🏃☀️ |
| runningCloudy | 흐린 날 달리기 🏃☁️ |
| runningRainy | 비 맞으며 달리기 🏃☔ |
| runningSnowy | 눈 속 달리기 🏃❄️ |
| cyclingSunny | 햇살 자전거 🚴☀️ |
| cyclingCloudy | 흐린 날 자전거 🚴☁️ |
| cyclingRainy | 비 오는데 자전거 🚴☔ |
| cyclingSnowy | 눈 속 자전거 🚴❄️ |

### 2.3 `symbolEmoji` — 인라인 위젯/짧은 슬롯용

🙂(idle) 💤(sleeping) 🥱(wakingUp) 🚶(walking) 🏃(running) 🚴(cycling) ✨(energetic)
🍽️(eating) 🏖️(beach) ☁️(cloudy) ☔️(rainyShelter) ❄️(snowPlay)
조합: 🚶☀️ 🚶☁️ 🚶☔ 🚶❄️ / 🏃☀️ 🏃☁️ 🏃☔ 🏃❄️ / 🚴☀️ 🚴☁️ 🚴☔ 🚴❄️

### 2.4 날씨 입자 fallback 이모지 (WeatherDecorationView 내부)

- 비 입자: `💧`
- 눈 입자: `❄️`
- 해/달/구름 코너 이모지는 `WeatherBackgroundCondition.fallbackEmoji` (다른 스펙 소관 — 날씨 모듈).

### 2.5 프로필 기본값 문구 (CharacterProfile)

- 캐릭터 이름 기본값: `내 캐릭터`

이 모듈에는 버튼/에러/플레이스홀더 문구가 없다 (순수 표시/로직 계층). 위 문구는 전부
`strings.xml` 에 등록하되, **state rawValue → 리소스 키 매핑은 enum 안에 하드코딩** (iOS 와 동일하게
enum 프로퍼티로 노출)해야 위젯(Glance)에서도 Context 만으로 접근 가능.

---

## 3. 상태(state)와 로직

### 3.1 `CharacterState` — 24 case 전체 (rawValue = 직렬화/파일명 키, rename 금지)

핵심 12: `idle, sleeping, wakingUp, walking, running, cycling, energetic, eating, beach, cloudy, rainyShelter, snowPlay`
조합 12 (운동×날씨, **enum 에 존재하지만 resolver 는 반환하지 않음** — 날씨는 별도 배경/데코 layer):
`walkingSunny/Cloudy/Rainy/Snowy, runningSunny/Cloudy/Rainy/Snowy, cyclingSunny/Cloudy/Rainy/Snowy`

부가 프로퍼티 (전 case 필수 — Kotlin 에서도 `when` exhaustive 강제):

| 프로퍼티 | 역할 |
|---|---|
| `symbolName` | SF Symbol 이름 (최후 fallback 아이콘). Android 는 대응 아이콘으로 치환 (§5). |
| `userFacing` (static) | 픽커에 노출하는 8개: `idle, sleeping, wakingUp, eating, walking, running, cycling, energetic`. 레거시 4 + 조합 12 제외. 순서 유지. |
| `baseFallback` | 조합 → 운동 base (`walkingRainy → walking` 등). 조합 아니면 `nil`. 이미지 폴백 + 매핑용. |
| `koreanShortLabel` / `caption` / `symbolEmoji` | §2 문구. |
| `tint` | idle=gray, sleeping=indigo, wakingUp=purple, walking=green, running=orange, cycling=blue, energetic=pink, eating=red, beach=yellow, cloudy=gray, rainyShelter=teal, snowPlay=cyan, \*Sunny=yellow, \*Cloudy=gray, \*Rainy=blue, \*Snowy=cyan. |
| `imageAssetName` | `"character_\(rawValue)"` → Android 는 drawable `character_<rawValue>` (조합은 camelCase → 리소스 규칙상 소문자 언더스코어 변환 필요, §5 참고). |
| `generationHint` | AI 생성 시작 프롬프트 (영문, 24개 전부 — Swift 원문 그대로 복사할 것, 생성 스펙에서 사용). |
| `animationFrame2Hint` | 2프레임 생성 시 frame2 변화 힌트 (영문 24개 — "slightly different pose" 같은 모호한 표현은 OpenAI 가 거의 같은 그림을 만들어서 state 별로 구체적 변화를 정의해 둔 것. 원문 그대로 복사). |
| `usesGeneratedMotion` | frame2 를 **실제 생성**할지: `false` = idle, sleeping, beach, cloudy, rainyShelter (미세 모션은 절차적으로 충분 + 2프레임 재생성 시 이목구비 드리프트로 오히려 나빠짐). `true` = 나머지 전부 (다리 교차·하품·냠·페달은 scale/offset/rotation 으로 흉내 불가). |

### 3.2 `CharacterStateResolver.resolve(...)` — 우선순위 로직 전체

시그니처 (Swift 원문, Kotlin 포팅 시 파라미터명 유지):

```swift
static func resolve(
    now: Date = Date(),
    sleep: SleepSummary? = nil,           // 현재 정책에서 무시 — 시그니처는 호환용
    workouts: [WorkoutSummary],
    todaySteps: Double? = nil,            // 현재 정책에서 무시
    weather: WeatherSnapshot? = nil,
    inSleepSchedule: Bool = false,
    hasSleepSchedule: Bool = false,
    isFocusActive: Bool = false,
    isGenericFocusActive: Bool = false,
    focusWokeAt: Date? = nil,
    isLikelyInWorkout: Bool = false,
    recentStepsPerMinute: Double = 0,
    phoneWorkoutState: CharacterState? = nil,
    profile: CharacterProfile = CharacterProfile(),
    calendar: Calendar = .current
) -> CharacterState
```

상수:
- `recentWorkoutWindow = 60 * 60` (1시간)
- `energeticStepThreshold = 8000` (현재 미사용 — 선언만 존재)
- `sleepHours = {0..6, 22, 23}` (현재 미사용 — 선언만 존재; 수면은 profile 시간으로 판정)

**우선순위 (위에서 첫 match 반환):**

0. **HKWorkout 종료 후 1시간** — `workouts.first`(최신)의 종료시각(`start + duration`)이 `now` 기준 1시간 이내면 `mapWorkout(activity)` 반환.
   *왜 HR 추론보다 앞?* 운동 종료 후에도 HR 이 일시적으로 stream 되어 `isLikelyInWorkout` 이 stale true 인 상황 대응. 실제 운동 종료가 확정된 가장 신뢰성 있는 신호.
   *왜 base state 만?* 날씨는 background layer 가 별도 처리 — 조합 state 반환 안 함.
1. **진행 중 운동 (HR stream 추론)** — `isLikelyInWorkout == true` 면 분당 걸음수로 타입 추정:
   - `recentStepsPerMinute >= 130` → `.running` (달리기 cadence 보통 150+)
   - `>= 40` → `.walking` (걷기 90~120)
   - 그 외 (걸음 거의 없음 = 자전거 등) → `.energetic`
2. **(1.5) 폰 전용 보조 — CoreMotion 활동 분류** — `phoneWorkoutState != nil` 이고 `!isFocusActive && !inSleepSchedule` 이면 그 값 반환.
   *왜 수면 신호에 막히나?* 밤중에 폰 들고 서성이는 정도로 수면 상태를 덮지 않기 위해. (워치 HR 경로는 '명시적 운동 시작' 신호라 수면보다 우선 — 폰 모션은 부수 신호.)
   *지속 조건(10분간 걷기/달리기/자전거)은 caller(MotionActivityManager 상당) 가 검사* — resolver 는 결과만 받음. 일상 걸음 오탐 방지.
3. **수면** — 3단계 신호:
   1. `isFocusActive || inSleepSchedule` → `.sleeping` ("지금 자" 확정 신호: iOS Sleep Focus 또는 HealthKit inBed).
   2. `isGenericFocusActive` **그리고** 현재 시각이 profile 수면 창(`sleepStart..<sleepEnd`, 자정 넘김 처리) 안 → `.sleeping`. (예약 수면 모드가 잠긴 폰에서 필터 인텐트를 안 깨우는 케이스 보조.)
   3. 수면 창 fallback — 신호가 유실돼도 밤에는 잔다. 단 **`focusWokeAt` 이 이번 밤 창 시작 이후**면 "이번 밤에 수면 모드를 껐다" = 기상으로 존중 → sleeping 건너뛰고 아래로 진행.
   - `manualSleepOnly == true` 면 caller 가 Focus/inBed 신호를 전부 false/nil 로 넘김 → 시간만 적용.
4. **기상 직후** — `sleepEnd` 부터 60분 (`wakeEnd = (sleepEndMin + 60) % 1440`, 자정 넘김 안전) 안이면 `.wakingUp`.
5. **식사** — `lunchStart ..< lunchStart+30` 또는 `dinnerStart ..< dinnerStart+30` (분 단위, wrap 없음 — 시작+30이 1440 넘는 설정은 미고려) 이면 `.eating`.
6. **기본** — `.idle`. 날씨는 idle 상태에 영향 없음 (데코 layer 별도).

**헬퍼:**
- `isInRange(nowMin, start, end)` — `[start, end)`, `start > end` 면 자정 넘김 (`nowMin >= s || nowMin < e`). start/end 는 `% 1440` 정규화.
- `windowStartDate(now, startMin, calendar)` — 가장 최근에 지난 sleepStart 경계. 오늘의 sleepStart 가 미래면 어제로.
- `mapWorkout(type)` — running→`.running`, cycling→`.cycling`, walking/hiking→`.walking`, 그 외 전부→`.energetic`.

**엣지 케이스:**
- 수면 창이 자정을 넘는 게 기본값 (22:00→07:00). `isInRange` 의 wrap 분기가 핵심.
- `focusWokeAt` 은 "이번 밤 창"에만 유효 — 어제 껐던 기록이 오늘 밤에 영향 주지 않음.
- `workouts` 는 최신순 정렬을 전제 (`first` = 가장 최근). Android caller 도 동일 계약 유지.
- `sleep`, `todaySteps`, `hasSleepSchedule`, `weather` 파라미터는 **현재 정책에서 무시** — 시그니처 호환용으로만 존재. Kotlin 에서도 유지 (호출부 diff 최소화) 하되 미사용 주석 명시.

### 3.3 프로필 기본값 (resolver 입력)

`CharacterProfile` 기본: 수면 22:00 → 07:00, 점심 12:00, 저녁 18:00 (각 30분).
`manualSleepOnly: Bool?` — nil = false (옛 데이터 호환). `nightFallbackStartMinute`/`EndMinute` — nil → 20:00(1200) / 06:00(360) (날씨 배경용 — 이 모듈 밖).
저장: App Group UserDefaults 키 `withu.characterProfile.v1` (JSON). 저장 시 `characterProfileChanged` 알림 발송 → 메인 화면 즉시 갱신.

### 3.4 `CharacterImageView` — 3단 fallback + 애니메이션

파라미터: `state`, `symbolPaddingRatio = 0.2` (심볼 fallback 패딩, 컨테이너 폭 대비), `maxPixelSize: CGFloat? = nil` (위젯 메모리 절약 다운샘플), `outlineOnly = false` (알파 외곽선만 — 단색 컴플리케이션용), `animated = false`.

**3단 fallback (순서 절대 변경 금지):**
```
1) CharacterImageStore 사용자 PNG (App Group 파일)
   — 현재 state 에 없으면 baseFallback state (조합 → 운동 base) 파일도 시도
2) Asset Catalog "character_<rawValue>"
   — 없으면 baseFallback 의 asset 시도
   — 그것도 없으면 공통 placeholder "character_placeholder" (첫 생성 전 사용자 지정 사진)
3) SF Symbol (state.symbolName) — 최후 fallback, 절대 깨지지 않음
   — tint 색, scaledToFit, 컨테이너 폭 × symbolPaddingRatio 패딩
```

**프레임 로드 로직:**
- frame 0: `maxPixelSize` 있으면 `loadThumbnail(state, maxPixelSize)`, 없으면 `load(state)`.
- frame ≥ 1: `loadFrame(state, frame:)` — 없으면 frame 0 으로 fallback. frame1 은 작은 PNG 가정이라 별도 다운샘플 안 함 (주석의 '왜': loadThumbnail 만 다운샘플 가능, frame1 은 위험 없음으로 판단).

**애니메이션 (절차적 프레임 swap):**
- `shouldAnimate` = ① `animated: true` 호출 **AND** ② `CharacterImageStore.hasAnimationFrames(state)` (frame1 파일 존재) **AND** ③ `!isAnimationDisabled(state)` (상태별 끄기) **AND** ④ 전역 토글 `CharacterImageStore.animationEnabled` (기본 true).
- 동작: `TimelineView(.periodic(by: 0.7))` — **0.7초 주기**, `frame = floor(t / 0.7) % 2` 로 frame 0/1 교대. 크로스페이드 없음, 하드 swap.
- 애니메이션 토글이 CharacterProfile 이 아닌 CharacterImageStore 에 있는 '왜': 위젯 타깃도 읽어야 해서.

**outlineOnly 알고리즘 (`outlineImage(from:lineWidth:3)`):**
- RGBA 비트맵 순회. `alphaThreshold = 64`, `darkThreshold = 90`(luminance), 선폭 `w = 3`.
- alpha < 64 픽셀 → 투명.
- 불투명 픽셀 중: 주변 (2w+1)² 창에 투명 픽셀이 있거나 이미지 경계 밖 → edge. 또는 luminance `(r*299+g*587+b*114)/1000 < 90` → 어두운 디테일.
- edge/darkDetail → 흰색 불투명, 그 외 → 투명. 결과를 template 렌더링 (`widgetAccentable`).
- 대상: 워치 컴플리케이션 (단색 강제). **SCOPE 상 Wear OS 제외** → Android 이번 범위에서 미구현 (§6).

### 3.5 `WeatherDecorationView` — 캐릭터 옆 날씨 표현

- 파라미터: `condition: WeatherBackgroundCondition?`, `size = 44` (메인 44, 워치 18, 위젯 medium 18).
- condition nil → 아무것도 안 그림.
- **sunny / cloudy / night**: 우상단 코너 정적 요소. Asset Catalog `cond.decorationAssetName` PNG 있으면 그것, 없으면 `fallbackEmoji` 텍스트. 크기 = `size × 0.66` (캐릭터의 ~1/4.5), 상단·우측 패딩 `size × 0.08`.
- **rainy**: `FallingParticles(count: 7, particleSize: size × 0.35, fallPeriod: 1.0, drift: false)`, fallback `💧`.
- **snowy**: `FallingParticles(count: 7, particleSize: size × 0.38, fallPeriod: 2.6, drift: true)`, fallback `❄️`.

**FallingParticles 절차적 모션 (24fps 틱):**
- 입자 i (0..<count) 마다:
  - `startOffset = i / count` (staggered phase)
  - `phase = (t / fallPeriod + startOffset) mod 1.0`
  - `baseX = width × (i + 0.5) / count`
  - `jitter = sin(i × 7.31) × 12` (고정 수평 흐트림)
  - `driftX = drift ? sin(t × 1.2 + i × 1.7) × 10 : 0` (눈만 수평 sine 흔들림)
  - `y = -particleSize + phase × (height + 2×particleSize)` (위 밖 → 아래 밖)
  - opacity: phase < 0.08 → `phase/0.08` 페이드인, phase > 0.92 → `(1-phase)/0.08` 페이드아웃, 그 외 1.

### 3.6 `CharacterView` — 홈 히어로

- VStack(spacing 12):
  - ZStack: `Circle().fill(state.tint.opacity(0.15))` 200×200 + `CharacterImageView(state:)` 140×140.
  - `Text(state.caption)` — headline, primary 색, `.transition(.opacity)` + `.id(state)` — **상태 바뀌면 텍스트 fade 를 새로 트리거하기 위한 id 재발급**.
- `.frame(maxWidth: .infinity)`, 세로 패딩 16, `.animation(.snappy, value: state)` — 상태 변경 시 전체 스냅 애니메이션.
- 주의: 이 파일의 CharacterView 는 `animated` 를 안 넘김 (기본 false) — 홈에서 실제 애니메이션 호출부는 홈 스펙에서 확인 (CharacterImageView 호출 시 `animated: true` 전달 여부는 호출자 책임).

---

## 4. 데이터 의존성

| 의존 | 내용 |
|---|---|
| `CharacterImageStore` (파일) | App Group 컨테이너 `characters/<state.rawValue>.png` (활성 슬롯), frame1 = `<state.rawValue>_f1.png`. API: `load(state)`, `loadThumbnail(state, maxPixelSize)`, `loadFrame(state, frame:)`, `hasAnimationFrames(state)`, `isAnimationDisabled(state)`, `animationEnabled` (기본 true), `loadBackground(condition)` (legacy). |
| `CharacterProfileStore` (UserDefaults) | App Group suite, 키 `withu.characterProfile.v1`, JSON `CharacterProfile`. 저장 시 `withu.characterProfileChanged` Notification. |
| Asset Catalog | `character_<rawValue>` 번들 일러스트, `character_placeholder`, 날씨 데코 `cond.decorationAssetName`, `background_<condition>` (legacy). |
| HealthKit (입력만) | `WorkoutSummary(activity, start, duration)` 배열 (최신순), HR 기반 `isLikelyInWorkout` + `recentStepsPerMinute`, `inSleepSchedule`(inBed). resolver 는 순수 함수 — 수집은 caller. |
| Focus (iOS 전용) | `isFocusActive`(Sleep Focus 필터 인텐트) / `isGenericFocusActive`(INFocusStatusCenter) / `focusWokeAt`. |
| CoreMotion (iOS) | `phoneWorkoutState` — MotionActivityManager 가 10분 지속 걷기/달리기/자전거 판정 후 state 로 넘김. |
| 날씨 | `WeatherSnapshot` 파라미터는 현재 무시. 데코는 `WeatherBackgroundCondition` (날씨 모듈 스펙 소관). |

---

## 5. Android 구현 노트

- **`CharacterState`** → Kotlin `enum class CharacterState(val rawValue: String)` — rawValue 는 Swift camelCase 그대로 (`walkingSunny` 등). **파일명/직렬화 키이므로 rawValue 원문 유지** (`characters/walkingSunny.png`). 단 drawable 리소스명은 소문자만 허용 → `imageAssetName` 은 `"character_" + rawValue.lowercase()` 로 매핑하고 리소스도 그 이름으로 넣는다 (예: `character_walkingsunny`). iOS 와 파일 스키마(동형) 는 rawValue 기준, 리소스는 Android 규칙 — 이 두 이름을 혼동하지 말 것.
- **tint** → Compose `Color`. iOS 시스템 색 근사값 고정: gray `#8E8E93`, indigo `#5856D6`, purple `#AF52DE`, green `#34C759`, orange `#FF9500`, blue `#007AFF`, pink `#FF2D55`, red `#FF3B30`, yellow `#FFCC00`, teal `#30B0C7`, cyan `#32ADE6`.
- **symbolName (SF Symbol)** → Material Icons 근사 매핑 + 최후엔 `symbolEmoji` 텍스트 렌더도 허용 (핵심은 "절대 깨지지 않는 3단째"라는 계약). 제안: idle=`Icons.Outlined.SentimentSatisfied`, sleeping=`Bedtime`, wakingUp=`Bed`, walking=`DirectionsWalk`, running=`DirectionsRun`, cycling=`DirectionsBike`, energetic=`AutoAwesome`, eating=`Restaurant`, beach=`WbSunny`, cloudy=`Cloud`, rainyShelter=`BeachAccess`(우산 부재 시 `Umbrella`), snowPlay=`AcUnit`. 조합은 base 운동 아이콘.
- **Resolver** → `object CharacterStateResolver` 순수 함수. `Date` → `Instant`/`LocalDateTime`, `Calendar` → `java.time.ZoneId` 주입 (`now: LocalDateTime`, `clock: Clock` 파라미터로 테스트 가능성 유지). 분 단위 산술(`nowMin`, `isInRange`, `windowStartDate`)은 그대로 포팅. **유닛 테스트 필수**: 자정 넘김 수면 창, focusWokeAt 존중, 운동 1시간 윈도우, cadence 경계(130/40).
- **iOS 전용 신호 대체안:**
  - `HKWorkout` → **Health Connect** `ExerciseSessionRecord` (최근 세션 조회, `exerciseType` → mapWorkout: RUNNING→running, BIKING→cycling, WALKING/HIKING→walking, 기타→energetic).
  - `isLikelyInWorkout`/`recentStepsPerMinute` (워치 HR stream) → **Wear 제외이므로 이번 범위 입력 없음** — 파라미터는 유지하되 caller 가 항상 false/0 전달. 대신 우선순위 1.5 의 `phoneWorkoutState` 경로가 주력.
  - `phoneWorkoutState` (CoreMotion) → `ActivityRecognitionClient` (Transition API, `ACTIVITY_RECOGNITION` 권한). "10분 지속" 검사도 Android 쪽 MotionActivityManager 상당에서 구현.
  - `isFocusActive`/`isGenericFocusActive` (Focus) → 직접 대응 없음. 근사: `NotificationManager.getCurrentInterruptionFilter()` != ALL (방해금지) 를 `isGenericFocusActive` 로, **Sleep Focus 확정 신호는 없음** → `isFocusActive` 는 항상 false, Health Connect `SleepSessionRecord` 진행 중이면 `inSleepSchedule = true`. 결과적으로 수면 판정은 (inBed=SleepSession) → (방해금지+수면창) → (수면창 fallback) 3단이 그대로 살아남는다.
  - `focusWokeAt` → 방해금지 해제 시점 기록 (BroadcastReceiver `ACTION_INTERRUPTION_FILTER_CHANGED`) 또는 사용자가 앱을 연 시점으로 근사 — 구현 시 단순안(앱 foreground 진입 시각) 먼저.
- **CharacterImageView** → `@Composable fun CharacterImage(state, symbolPaddingRatio = 0.2f, maxPixelSize: Int? = null, animated: Boolean = false)`.
  - 3단 fallback 순서 유지. 파일 로드는 `CharacterImageStore` (App Group 대응 = 앱 내부 저장소, 위젯과 공유는 같은 프로세스 파일 접근으로 충분 — iOS App Group 개념 불필요).
  - `maxPixelSize` 다운샘플 → `BitmapFactory.Options.inSampleSize` 또는 Coil `size()`. Glance 위젯 Bitmap 메모리 한계 대응 목적 동일.
  - 프레임 swap → `LaunchedEffect` + `while(true) { delay(700) }` 로 frame 토글, 또는 `withFrameNanos` 기반. **0.7초 하드 swap, 트랜지션 없음**.
  - `outlineOnly` — Wear 제외라 이번 미구현. 알고리즘은 §3.4 에 보존 (후속 Wear 때 픽셀 순회 그대로 포팅 가능).
- **FallingParticles** → Compose `Canvas` + `rememberInfiniteTransition` 혹은 `withFrameMillis` 루프 (24fps 제한은 프레임 시각 기반 계산이라 자연 충족). 수식(§3.5) 그대로. 위젯(Glance)에서는 애니메이션 불가 → 정적 1프레임(phase 고정)만.
- **CharacterView** → `Box(200.dp, CircleShape, tint.copy(alpha=0.15f))` + 이미지 140.dp + `Text(caption, style = MaterialTheme.typography.titleMedium)`. 상태 변경 애니메이션: `AnimatedContent(targetState = state)` (fade) 가 `.id(state)` + `.transition(.opacity)` + `.animation(.snappy)` 조합의 대응.
- **Notification (`characterProfileChanged`)** → `SharedFlow`/`StateFlow` 로 대체 (`CharacterProfileStore.profileFlow`).
- 위젯 갱신: 이미지/상태 저장 후 iOS 의 `WidgetCenter.reloadAllTimelines()` 대응 = `GlanceAppWidget.updateAll(context)` — 저장소 쪽 스펙과 계약 공유.

---

## 6. 제외 항목 (SCOPE.md 기준)

- **`outlineOnly` / `outlineImage`** — watchOS 컴플리케이션 전용. Wear OS 제외이므로 이번 미구현.
- **`WeatherBackgroundView`** (AI 풀배경) — 배경 생성 자체가 후속. legacy 이며 iOS 에서도 entry 숨김.
- **레거시 4 state (beach/cloudy/rainyShelter/snowPlay) 와 조합 12 state 의 UI 노출** — enum 에는 전부 포함 (직렬화/이미지 키 호환 + generationHint 존재) 하되, resolver 미반환·픽커 미노출 동작 그대로.
- **워치 HR stream 입력 (`isLikelyInWorkout`, `recentStepsPerMinute`)** — Wear 제외로 이번엔 항상 기본값. 파라미터/로직은 포팅해 두고 (우선순위 0·1 코드 유지), 후속 Wear 연동 시 입력만 연결.
- **`SleepSummary` 파라미터 활용** — iOS 도 현재 무시. 동일하게 무시.
