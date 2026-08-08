# 00 — 구현 마스터플랜 (Android 파리티)

> 대상: SCOPE.md + 스펙 01~12 전체. 이 문서는 **병렬 구현 에이전트들의 단일 계약서**다.
> 여기 적힌 시그니처와 파일 소유권을 벗어나는 공유 API 추가/변경은 금지 — 필요하면 자기 파일 안 private 로 해결한다.

---

## 0. 전역 규칙 (모든 에이전트 공통)

1. **패키지**: `com.seoyoung.withu` 하위. Kotlin + Compose M3, minSdk 28, JDK 17.
2. **Context**: 공유 싱글턴은 `WithuApp.context` (Application 홀더) 를 내부에서 사용 — **공유 API 에 Context 파라미터 없음**.
3. **파일 I/O 는 `Dispatchers.IO`**. Compose 에서 저장소 직접 호출 금지 (suspend 또는 `remember` + `LaunchedEffect`).
4. **문구는 iOS 원문 그대로** (오타 `이용헤요` 포함). 서버 프롬프트 영문(`generationHint` 등)은 strings 리소스가 아니라 **코드 상수**.
5. **키/파일명 파리티**: SharedPreferences 키(`withu.*.v1`), 파일 스키마(`characters/<raw>.png`, `gallery/<uuid>.png`+`metadata.json`), `CharacterState.raw` 문자열은 iOS 와 완전 동일. rename 절대 금지.
6. 캔디 모델: **로컬이 권위** (서버 차감 없음, `syncCreditsUp` 은 max 끌어올리기만). DEBUG = 무제한 9999 / record no-op.
7. 워치(Wear OS)·로그인·Play 실결제·날씨 배경 AI = 제외. 호출 지점은 만들지 않거나 no-op + 주석.
8. 빌드 검증: `./build.sh :app:assembleDebug` (android/ 디렉터리).

---

## 1. 모듈 지도

### 1-1. 기존 뼈대 파일 처분

| 기존 파일 | 처분 | 담당 |
|---|---|---|
| `character/CharacterState.kt` | **교체(확장)** — 8 case → 24 case, 프로퍼티 추가 (§2-1). 기존 UPPER_CASE 상수·`raw`·`fromRaw` 유지 | F1 |
| `net/ApiClient.kt` | **교체(확장)** — preflight/redeem/referral/에러 분류/entitlement 추가 (§2-6). DTO 는 `ApiModels.kt` 로 분리 | F1 |
| `gen/ChromaKey.kt` | **유지** — `ImageProcessing.chromaKeyRemoved` 가 위임 호출 | F1 |
| `store/CharacterStore.kt` | **Deprecated 위임 셔틀로 축소** — 내부를 `shared/CharacterImageStore` 위임으로 바꿔 구 화면 컴파일 유지. Phase I 에서 삭제 | F1 (축소) → I (삭제) |
| `ui/HomeScreen.kt` | **유지 후 Phase I 삭제** — S1 이 `home/HomeScreen.kt` 를 새로 만든다. Phase S 에선 안 건드림 | I (삭제) |
| `ui/GenerateScreen.kt` | **유지 후 Phase I 삭제** — S2 가 `gen/SingleGenScreen.kt` 를 새로 만든다 | I (삭제) |
| `ui/theme/Theme.kt` | **확장** — `withuPinkSoft`, 시스템 색 근사(mint/cyan/orange/indigo/green) 상수 추가. 기존 정의 유지 | F1 |
| `MainActivity.kt` | **교체** — 전체 nav graph + 온보딩 게이트 + 딥링크. Phase S 는 안 건드림 | I |
| `app/build.gradle.kts` | **확장** — 의존성 추가 (§4 Phase F) | F1 |
| `AndroidManifest.xml` | **확장** — F1: Application/권한, I: 위젯 receiver/딥링크 | F1 + I |

### 1-2. 신규 파일 전체 (패키지별 책임)

```
com.seoyoung.withu/
├── WithuApp.kt                        [F1] Application — appContext 홀더, 채널 생성, BackgroundGenQueue.resumeIfNeeded()
├── character/
│   ├── CharacterState.kt              [F1·교체] 24 case enum + 라벨/캡션/tint/힌트/모션 플래그 (스펙 08)
│   ├── CharacterStateResolver.kt      [F1] 순수 함수 상태 결정 (스펙 08 §3.2)
│   ├── CharacterProfile.kt            [F1] @Serializable 프로필 + CharacterProfileStore (키 withu.characterProfile.v1)
│   ├── CharacterImage.kt              [F1] 3단 fallback Composable + 0.7s 프레임 swap (스펙 08 §3.4)
│   ├── CharacterHero.kt               [F1] tint 원 + 이미지 + 캡션 (CharacterView 대응)
│   └── WeatherDecoration.kt           [F1] 코너 데코 + FallingParticles (스펙 08 §3.5)
├── shared/
│   ├── CharacterImageStore.kt         [F1] 활성 슬롯/갤러리/매핑/애니 토글/LruCache/야간 판정 (스펙 09)
│   ├── GalleryItem.kt                 [F1] @Serializable (id/sourceState/createdAt/hasFrame1?/batchId?/prompt?)
│   ├── SharedAppState.kt              [F1] prefs "withu_shared" 래퍼 + WatchMessage 저장/로드 + AppPrefs 키
│   ├── WatchMessage.kt                [F1] @Serializable 스냅샷 (스펙 09 §3-10)
│   ├── WeatherBackgroundCondition.kt  [F1] enum + displayName/fallbackEmoji/from(emoji)/generationHint
│   └── StoreEvents.kt                 [F1] characterImageChanged/weatherBackgroundChanged/profileChanged SharedFlow
├── net/
│   ├── ApiClient.kt                   [F1·교체] /generate·/health·/redeem·/referral (스펙 11)
│   ├── ApiModels.kt                   [F1] GenerateImageRequest/Response, Entitlement, Redeem/Referral DTO
│   └── ApiError.kt                    [F1] sealed 에러 + koreanized() (스펙 11 §2.2 문구 전량)
├── quota/GenerationQuota.kt           [F1] 캔디 로컬 쿼터 (스펙 07 §3.2)
├── gen/
│   ├── ChromaKey.kt                   [기존 유지]
│   ├── ImageProcessing.kt             [F1] 크로마키/흰합성/참조정규화/색매칭/배경제거/다운샘플/b64
│   ├── SquareCropView.kt              [F2] 정사각 크롭 풀스크린 (02/03/04 공용)
│   ├── GalleryReferencePicker.kt      [F2] 내 캐릭터에서 참고사진 선택 시트 (02/03 공용)
│   ├── SingleGenScreen.kt             [S2] 단건 생성 화면 (스펙 02)
│   ├── SingleGenViewModel.kt          [S2] generate/refine/send/버전이력
│   ├── SingleGenModels.kt             [S2] GenerationMode/PendingAction/ResultVersion
│   ├── BatchGenScreen.kt              [S3] 배치 화면 (스펙 03)
│   └── BatchGenViewModel.kt           [S3] syncFromManager/승인/재시도/바꾸기
├── bggen/
│   ├── BgGenModels.kt                 [F2] BgGenJob/BgGenSpec/BgGenPhase/BgGenState
│   ├── BackgroundGenQueue.kt          [F2] jobs.json 영속 큐 + StateFlow (스펙 11 §4)
│   └── GenBatchWorker.kt              [F2] CoroutineWorker "bggen" + setForeground(dataSync)
├── weather/
│   ├── WeatherCondition.kt            [F2] enum + WMO 매핑 + WeatherSnapshot
│   └── WeatherManager.kt              [F2] FusedLocation(coarse, 2자리 반올림) + Open-Meteo + 30분 캐시
├── health/
│   ├── HealthModels.kt                [F2] SleepSummary/WorkoutSummary/WorkoutActivity/SleepWindow
│   ├── HealthManager.kt               [F2] Health Connect 조회 6종 + 추론 + averageSleepWindow
│   └── SleepSignals.kt                [F2] DND 읽기 근사 (isGenericFocusActive/focusWokeAt 입력용)
├── sync/SyncCoordinator.kt            [F2] resolve → SharedAppState.save → 위젯 updateAll + overrideState 홀더
├── notify/NotificationHelper.kt       [F2] 채널/배치완료/취침리마인더/걸음목표/운동종료 알림
├── paywall/PaywallScreen.kt           [F2] 페이월 (스펙 07 — 정적 팩 + '준비 중' + CANDY20)
├── ui/
│   ├── UiKit.kt                       [F1] FrostedCard/FormSection/StatusPill/CTA/WarningBanner/CapsuleToast/CandyBadge/backgroundGradient
│   └── theme/Theme.kt                 [F1·확장]
├── home/
│   ├── HomeScreen.kt                  [S1] 홈 (스펙 01)
│   ├── SettingsSheet.kt               [S1] 설정 (전체화면 다이얼로그)
│   ├── DiagnosticsScreen.kt           [S1] 캐릭터 상태 살펴보기
│   └── WidgetGuideSheet.kt            [S1] 홈 화면에 withu 두기
├── gallery/
│   ├── GalleryLandingScreen.kt        [S4] 상태별/캐릭터별 랜딩 (스펙 04)
│   ├── StateFolderScreen.kt           [S4] 상태 폴더
│   ├── GalleryGrid.kt                 [S4] 재사용 그리드 + 다중선택 + 상세시트
│   └── BatchGroupScreen.kt            [S4] '이 캐릭터' 그리드 + 기타(legacy) 폴더
├── profile/ProfileScreen.kt           [S5] 내 캐릭터 설정 (스펙 05)
├── onboarding/
│   ├── OnboardingScreen.kt            [S5] 멀티스텝 온보딩 (스펙 06, focus 스텝 생략)
│   └── HelpGuideSheet.kt              [S5] 사용법 안내
├── camera/
│   ├── CameraScreen.kt                [S6] 카메라 합성 (스펙 12 Part A)
│   ├── CameraController.kt            [S6] CameraX bind/셔터/전환
│   ├── PlacedCharacter.kt             [S6] 정규화 배치 모델
│   ├── PhotoCompositor.kt             [S6] Canvas 합성
│   └── PhotoSaver.kt                  [S6] MediaStore 저장 (갤러리 화면도 사용 → §2-9 계약)
└── widget/
    ├── CharacterWidget.kt             [S6] Glance 3 브레이크포인트 (스펙 12 Part B)
    └── CharacterWidgetReceiver.kt     [S6] receiver
res/
├── values/strings.xml                 [F1] 공통 키 (common_*/err_*)
├── values/strings_paywall.xml         [F2]
├── values/strings_{home,gen,batch,gallery,profile,onboarding,camera,widget}.xml  [각 S 소유자]
├── values-en/…                        [소유자 동일 — ko 파일과 1:1]
└── xml/character_widget_info.xml      [S6]
test/
├── character/CharacterStateResolverTest.kt  [F1] 자정 넘김/focusWokeAt/운동 1시간/cadence 경계
├── quota/GenerationQuotaTest.kt              [F1] 자정 리셋/syncCreditsUp delta/음수 방지
└── shared/IsCurrentlyNightTest.kt            [F1] 일출일몰/스테일 날짜/fallback wrap
```

주의: **PhotoSaver 는 S6 소유지만 S2/S3/S4 도 사용** → 계약(§2-9)만 보고 호출. 병렬 트리에서 미해결 참조가 되지 않도록 **F2 가 빈 구현(스텁 아님, 실제 MediaStore 구현)으로 미리 생성**한다. → PhotoSaver 는 [F2] 로 이동, S6 은 카메라 전용 파일만.

---

## 2. 인터페이스 계약 (컴파일 기준 — 변경 금지)

> Phase F 완료 시점에 아래 전부가 실제 코드로 존재하고 컴파일된다. Phase S 에이전트는 이 시그니처만 호출한다.

### 2-1. CharacterState (`character/CharacterState.kt`)

```kotlin
enum class CharacterState(val raw: String) {
    // 기존 8 + 레거시 4 + 조합 12 (raw 는 Swift rawValue 원문)
    IDLE("idle"), SLEEPING("sleeping"), WAKING_UP("wakingUp"), EATING("eating"),
    WALKING("walking"), RUNNING("running"), CYCLING("cycling"), ENERGETIC("energetic"),
    BEACH("beach"), CLOUDY("cloudy"), RAINY_SHELTER("rainyShelter"), SNOW_PLAY("snowPlay"),
    WALKING_SUNNY("walkingSunny"), WALKING_CLOUDY("walkingCloudy"), WALKING_RAINY("walkingRainy"), WALKING_SNOWY("walkingSnowy"),
    RUNNING_SUNNY("runningSunny"), RUNNING_CLOUDY("runningCloudy"), RUNNING_RAINY("runningRainy"), RUNNING_SNOWY("runningSnowy"),
    CYCLING_SUNNY("cyclingSunny"), CYCLING_CLOUDY("cyclingCloudy"), CYCLING_RAINY("cyclingRainy"), CYCLING_SNOWY("cyclingSnowy");

    val koreanShortLabel: String        // 스펙 08 §2.1
    val caption: String                 // 스펙 08 §2.2
    val symbolEmoji: String             // 스펙 08 §2.3
    val tint: Color                     // 스펙 08 §3.1 근사 hex
    val generationHint: String          // 영문 24개 — iOS 원문 복사
    val animationFrame2Hint: String     // 영문 24개 — iOS 원문 복사
    val usesGeneratedMotion: Boolean    // false = IDLE, SLEEPING, BEACH, CLOUDY, RAINY_SHELTER
    val baseFallback: CharacterState?   // 조합 → 운동 base, 아니면 null
    val imageAssetName: String          // "character_" + raw.lowercase() (drawable 규칙)

    companion object {
        val userFacing: List<CharacterState>   // [IDLE, SLEEPING, WAKING_UP, EATING, WALKING, RUNNING, CYCLING, ENERGETIC] 순서 고정
        fun fromRaw(raw: String): CharacterState?
    }
}
```

### 2-2. 저장소 (`shared/`)

```kotlin
@Serializable
data class GalleryItem(
    val id: String,
    val sourceState: String,
    val createdAt: Long,                 // epoch millis
    val hasFrame1: Boolean? = null,
    val batchId: String? = null,
    val prompt: String? = null,
)
data class GalleryGrouped(val byState: Map<CharacterState, List<GalleryItem>>, val legacy: List<GalleryItem>)
data class GalleryCharacterGroup(val batchId: String, val createdAt: Long, val items: List<GalleryItem>)

object CharacterImageStore {
    // 활성 슬롯 (frame0 저장 시 옛 _f1 반드시 삭제)
    fun load(state: CharacterState): Bitmap?
    fun loadFrame(state: CharacterState, frame: Int): Bitmap?          // 없으면 null — fallback 은 caller
    fun loadThumbnail(state: CharacterState, maxPixelSize: Int): Bitmap?
    fun hasImage(state: CharacterState): Boolean
    fun hasAnimationFrames(state: CharacterState): Boolean
    fun saveActiveSlotOnly(image: Bitmap, state: CharacterState, frame: Int = 0): Boolean
    fun clearActive(state: CharacterState)
    fun swapActiveFrames(state: CharacterState): Boolean
    fun wipeAll()
    // 갤러리
    fun save(image: Bitmap, state: CharacterState, frame: Int = 0,
             applyToActiveSlot: Boolean = true, batchId: String? = null, prompt: String? = null): GalleryItem?
    fun loadGalleryMetadata(): List<GalleryItem>                        // createdAt 내림차순
    fun loadGalleryGrouped(): GalleryGrouped
    fun loadGalleryByCharacter(): List<GalleryCharacterGroup>
    fun loadGalleryImage(id: String): Bitmap?
    fun loadGalleryFrame1(id: String): Bitmap?
    fun replaceGalleryImage(id: String, image: Bitmap, frame: Int = 0): Boolean
    fun swapGalleryFrames(id: String): Boolean
    fun applyGalleryItem(id: String, state: CharacterState): Boolean    // f1 없으면 active f1 삭제
    fun deleteGalleryItem(id: String)                                   // 활성 PNG 는 안 지움 (매핑만 해제)
    fun currentGalleryItemId(state: CharacterState): String?
    fun statesUsingGalleryItem(id: String): List<CharacterState>
    // 애니메이션 토글 (프로필과 별도 저장 — 위젯도 읽음)
    fun isAnimationEnabled(): Boolean                                   // 기본 true, 키 withu.animationEnabled.v1
    fun setAnimationEnabled(enabled: Boolean)
    fun isAnimationDisabled(state: CharacterState): Boolean             // 키 withu.animationDisabledStates.v1
    fun setAnimationDisabled(disabled: Boolean, state: CharacterState)
    // 야간 판정 (순수 함수 — 분 단위만 비교)
    fun isCurrentlyNight(nowMinuteOfDay: Int, sunriseMinuteOfDay: Int? = null, sunsetMinuteOfDay: Int? = null,
                         fallbackStartMinute: Int = 20 * 60, fallbackEndMinute: Int = 6 * 60): Boolean
}

object SharedAppState {
    fun save(message: WatchMessage)                                     // 위젯 갱신은 caller 책임
    fun loadMessage(): WatchMessage?
    fun prefs(): SharedPreferences                                      // "withu_shared" — quota/설정 공용 파일
}

@Serializable
data class WatchMessage(
    val state: String,                       // CharacterState.raw
    val todaySteps: Double? = null,
    val lastSleepHours: Double? = null,
    val todayActiveMinutes: Double? = null,
    val todayActiveKcal: Double? = null,
    val weatherEmoji: String? = null,
    val weatherTempC: Double? = null,
    val weatherSunrise: Long? = null,        // epoch millis
    val weatherSunset: Long? = null,
    val timestamp: Long,
) { val characterState: CharacterState get() = CharacterState.fromRaw(state) ?: CharacterState.IDLE }

enum class WeatherBackgroundCondition(val raw: String) {
    SUNNY("sunny"), CLOUDY("cloudy"), RAINY("rainy"), SNOWY("snowy"), NIGHT("night");
    val displayName: String; val fallbackEmoji: String; val generationHint: String
    companion object { fun fromEmoji(emoji: String?): WeatherBackgroundCondition? }
}

object StoreEvents {   // NotificationCenter 대체
    val characterImageChanged: MutableSharedFlow<CharacterState?>       // null = broadcast
    val weatherBackgroundChanged: MutableSharedFlow<Unit>
    val characterProfileChanged: MutableSharedFlow<Unit>
}

object AppPrefs {      // SharedAppState.kt 안에 정의
    var onboarded: Boolean                   // withu.onboarded.v1 (표준 prefs)
    var seenGuide: Boolean                   // withu.seenGuide.v1
    var showWeatherDecoration: Boolean       // withu.showWeatherDecoration.v1 (공유 prefs, 기본 true)
    var lastBackgroundRefreshAt: Long?       // withu.lastBackgroundRefreshAt (공유 prefs)
}
```

### 2-3. 프로필 (`character/CharacterProfile.kt`)

```kotlin
@Serializable
data class CharacterProfile(
    val name: String = "내 캐릭터",
    val description: String = "",
    val aiPrompt: String = "",
    val sleepStartHour: Int = 22, val sleepStartMinute: Int = 0,
    val sleepEndHour: Int = 7,   val sleepEndMinute: Int = 0,
    val lunchHour: Int = 12,     val lunchMinute: Int = 0,
    val dinnerHour: Int = 18,    val dinnerMinute: Int = 0,
    val manualSleepOnly: Boolean? = null,          // nil = false (구버전 호환)
    val nightFallbackStartMinute: Int? = null,     // nil = 1200 (20:00)
    val nightFallbackEndMinute: Int? = null,       // nil = 360 (06:00)
) {
    val isManualSleepOnly: Boolean get() = manualSleepOnly ?: false
    val effectiveNightFallbackStart: Int get() = nightFallbackStartMinute ?: 1200
    val effectiveNightFallbackEnd: Int get() = nightFallbackEndMinute ?: 360
}

object CharacterProfileStore {
    fun load(): CharacterProfile
    fun save(profile: CharacterProfile)            // 저장 후 StoreEvents.characterProfileChanged emit
    val profileFlow: StateFlow<CharacterProfile>   // load 초기값, save 시 갱신
}
```

### 2-4. 상태 결정 (`character/CharacterStateResolver.kt`)

```kotlin
object CharacterStateResolver {
    fun resolve(
        now: LocalDateTime = LocalDateTime.now(),
        sleep: SleepSummary? = null,               // 현재 정책 미사용 (시그니처 호환)
        workouts: List<WorkoutSummary> = emptyList(),   // 최신순 전제
        todaySteps: Double? = null,                // 미사용
        weather: WeatherSnapshot? = null,          // 미사용
        inSleepSchedule: Boolean = false,
        hasSleepSchedule: Boolean = false,
        isFocusActive: Boolean = false,            // Android: 항상 false
        isGenericFocusActive: Boolean = false,     // Android: DND on 근사
        focusWokeAt: LocalDateTime? = null,
        isLikelyInWorkout: Boolean = false,        // Android: 항상 false (Wear 제외)
        recentStepsPerMinute: Double = 0.0,
        phoneWorkoutState: CharacterState? = null,
        profile: CharacterProfile = CharacterProfile(),
    ): CharacterState

    // 프로필 화면 '자는 중' 판정과 resolver 수면 분기가 공유하는 함수 (스펙 05 §3-2 주의사항)
    fun isNowInSleepWindow(now: LocalDateTime, profile: CharacterProfile): Boolean
}
```

### 2-5. 캐릭터 표시 (`character/CharacterImage.kt`, `CharacterHero.kt`, `WeatherDecoration.kt`)

```kotlin
@Composable
fun CharacterImage(
    state: CharacterState,
    modifier: Modifier = Modifier,
    symbolPaddingRatio: Float = 0.2f,
    maxPixelSize: Int? = null,
    animated: Boolean = false,
    refreshKey: Int = 0,          // 홈 imageRefreshKey — 값 변경 시 강제 재로드
)

@Composable
fun CharacterHero(state: CharacterState, modifier: Modifier = Modifier,
                  animated: Boolean = true, refreshKey: Int = 0,
                  decoration: WeatherBackgroundCondition? = null)   // 240dp 원 + 200dp 이미지 + 캡션 + 데코 오버레이

@Composable
fun WeatherDecoration(condition: WeatherBackgroundCondition?, size: Dp = 44.dp, modifier: Modifier = Modifier)
```

### 2-6. 네트워킹 (`net/`)

```kotlin
// ApiModels.kt — 전부 @Serializable, 서버는 snake_case (@SerialName 명시)
data class GenerateImageRequest(
    val prompt: String,
    @SerialName("reference_image_base64") val referenceImageBase64: String? = null,
    val steps: Int = 30, val width: Int = 1024, val height: Int = 1024,
    val quality: String? = "low",
    @SerialName("art_style") val artStyle: String? = null,     // "casual" | "pixel"
    val style: String? = "auto",
    val kind: String? = null,                                  // "refine" 등
    val model: String? = "gpt-image-2",
)
data class GenerateImageResponse(
    @SerialName("image_base64") val imageBase64: String,
    val seed: Int = 0,
    @SerialName("revised_prompt") val revisedPrompt: String? = null,
    val entitlement: Entitlement? = null,
    @SerialName("free_consumed") val freeConsumed: Boolean? = null,
)
data class Entitlement(
    @SerialName("free_batch_remaining") val freeBatchRemaining: Int = 0,
    @SerialName("free_single_remaining") val freeSingleRemaining: Int = 0,
    val credits: Int = 0,
    @SerialName("sub_active") val subActive: Boolean = false,
    @SerialName("sub_expires_at") val subExpiresAt: Long? = null,
    @SerialName("referral_code") val referralCode: String? = null,
)

// ApiError.kt
sealed class ApiError(message: String) : Exception(message) {
    class InvalidResponse : ApiError
    class Server(val status: Int, val detail: String) : ApiError
    class Decoding(val reason: String) : ApiError
    class Transport(override val cause: Throwable) : ApiError
    class PaymentRequired(val balance: Entitlement?) : ApiError
}
fun Throwable.koreanized(): String     // 스펙 11 §2.2 문구 표 전량 — 사용자 노출은 반드시 이것

// ApiClient.kt
object ApiClient {
    suspend fun generateImage(req: GenerateImageRequest,
                              kind: String = "single",          // X-Withu-Kind
                              batchId: String? = null,          // X-Withu-Batch
                              idempotencyKey: String = UUID.randomUUID().toString()): GenerateImageResponse
        // throws ApiError (402 → PaymentRequired)
    suspend fun preflightPing()                                  // /health, 5초 클라이언트. 실패 시 ApiError throw
    suspend fun health(): Boolean
    suspend fun redeem(code: String): Entitlement                // POST /redeem (로그인 없어 401 가능 — 에러 그대로)
    suspend fun applyReferral(code: String): Entitlement         // POST /referral/apply
}
```

### 2-7. 캔디 쿼터 (`quota/GenerationQuota.kt`)

```kotlin
object GenerationQuota {
    const val freeDailyLimit: Int = 0
    const val testCandyCode: String = "CANDY20"
    const val testCandyAmount: Int = 20
    val allowsTestCandyCode: Boolean          // = BuildConfig.DEBUG
    fun usedToday(): Int
    fun credits(): Int
    fun remainingToday(): Int                 // DEBUG = 9999
    fun canGenerate(n: Int = 1): Boolean
    fun record(n: Int = 1)                    // DEBUG no-op. 성공 시에만 호출할 것
    fun cost(forQuality: String): Int         // high 6 / medium 3 / 기본 1
    fun addCredits(n: Int)
    fun syncCreditsUp(serverCredits: Int)     // delta > 0 만 가산. 절대값 덮어쓰기 금지
    fun resetServerBaseline()
    fun displayedCandy(): Int                 // = credits()
}
```

### 2-8. 날씨 / 건강 / 동기화 (`weather/`, `health/`, `sync/`)

```kotlin
enum class WeatherCondition { SUNNY, CLOUDY, RAINY, SNOWY, FOGGY, THUNDER, UNKNOWN;
    val emoji: String; val caption: String
    companion object { fun fromWmo(code: Int): WeatherCondition }
}
data class WeatherSnapshot(
    val condition: WeatherCondition, val temperatureC: Double, val timestamp: Long,
    val sunrise: Long? = null, val sunset: Long? = null,      // epoch millis
) { val isHot: Boolean get() = temperatureC >= 30; val isCold: Boolean get() = temperatureC <= 0 }

object WeatherManager {
    val snapshot: StateFlow<WeatherSnapshot?>
    val isFetching: StateFlow<Boolean>
    val lastError: StateFlow<String?>
    suspend fun refresh(force: Boolean = false)               // 30분 메모리 캐시. 권한 없으면 lastError 세팅
    fun hasLocationPermission(): Boolean
}

data class SleepSummary(val totalAsleepSeconds: Double, val sampleCount: Int, val lastNight: Long?)
enum class WorkoutActivity { RUNNING, CYCLING, WALKING, HIKING, SWIMMING, YOGA, STRENGTH, OTHER;
    val displayName: String }   // 달리기 🏃 등 스펙 10 §2
data class WorkoutSummary(val activity: WorkoutActivity, val start: Long,
                          val durationSeconds: Double, val kcal: Double? = null, val meters: Double? = null)
data class SleepWindow(val startHour: Int, val startMinute: Int, val endHour: Int, val endMinute: Int)

object HealthManager {
    val isAuthorized: StateFlow<Boolean>
    val sleep: StateFlow<SleepSummary?>
    val recentWorkouts: StateFlow<List<WorkoutSummary>>       // 최신순
    val todaySteps: StateFlow<Double?>
    val todayActiveMinutes: StateFlow<Double?>
    val todayActiveKcal: StateFlow<Double?>
    val isInBedSchedule: StateFlow<Boolean>
    val hasSleepSchedule: StateFlow<Boolean>
    val recentHRSampleCount: StateFlow<Int>
    val recentHRAverage: StateFlow<Double>
    val isLikelyInWorkout: StateFlow<Boolean>
    val recentStepsPerMinute: StateFlow<Double>
    val sleepSampleCount48h: StateFlow<Int>                   // 진단 (iOS inBedSampleCount24h 근사)
    val lastSleepSessionStart: StateFlow<Long?>               // 진단
    fun isAvailable(): Boolean                                 // Health Connect SDK status
    fun requiredPermissions(): Set<String>                     // 권한 계약 상수 (온보딩/설정 공용)
    suspend fun refreshAuthorizationStatus()                   // getGrantedPermissions 로 isAuthorized 갱신
    suspend fun fetchSleep(days: Int = 7)
    suspend fun fetchWorkouts(days: Int = 7, limit: Int = 20)
    suspend fun fetchTodaySteps()                              // no data → 0
    suspend fun fetchTodayActiveMinutes()
    suspend fun fetchTodayActiveKcal()
    suspend fun fetchInBedSchedule()                           // 실패는 전부 false (throw 안 함)
    suspend fun refreshWorkoutInference()                      // HR 90초 + 걸음 cadence(3분/10분 max)
    suspend fun averageSleepWindow(days: Int = 7): SleepWindow?  // 밤 2개 미만이면 null
    suspend fun loadAll()                                      // 홈 진입 일괄 (개별 실패 무시)
}

object SleepSignals {   // iOS Focus 근사 (DND)
    fun isDndOn(): Boolean
    fun lastDndOffAt(): LocalDateTime?
}

object SyncCoordinator {
    val overrideState: MutableStateFlow<CharacterState?>       // 진단 Picker ↔ 홈 공유 (비영속)
    fun currentState(): CharacterState                         // override ?: resolve(현재 신호 전부)
    suspend fun syncNow()                                      // currentState → WatchMessage 저장 → 위젯 updateAll
}
```

### 2-9. 배치 큐 / 알림 / 이미지 처리 / 사진 저장

```kotlin
// bggen/BgGenModels.kt
enum class BgGenPhase { ANCHOR, REST, RETRY }
enum class BgGenStatus { QUEUED, RUNNING, DONE, FAILED }
@Serializable
data class BgGenJob(
    val id: String, val stateRaw: String, val frame: Int,
    val quality: String, val artStyle: String, val batchId: String,
    val wantsFrame1: Boolean = false, val frame1Prompt: String? = null,
    val status: String = "queued",                 // BgGenStatus rawValue
    val errorMessage: String? = null, val startedAt: Long? = null,
    val paymentRequired: Boolean? = null, val attempts: Int? = null,
    val matchIdleColor: Boolean? = null, val prompt: String? = null,
)
data class BgGenSpec(
    val state: CharacterState, val frame: Int = 0, val prompt: String,
    val referenceImageBase64: String? = null,
    val wantsFrame1: Boolean = false, val frame1Prompt: String? = null,
    val matchIdleColor: Boolean = false,
)
data class BgGenState(val jobs: List<BgGenJob>, val phase: BgGenPhase,
                      val images: Map<String, Bitmap>,        // "raw#frame" → 128px (메모리 전용)
                      val tick: Long) {
    val isActive: Boolean; val doneCount: Int; val failedCount: Int
}

// bggen/BackgroundGenQueue.kt
object BackgroundGenQueue {
    val state: StateFlow<BgGenState>
    fun start(specs: List<BgGenSpec>, quality: String, artStyle: String, batchId: String, phase: BgGenPhase)
    fun retry(spec: BgGenSpec, quality: String, artStyle: String, batchId: String)
    fun cancelAll()
    fun resumeIfNeeded()                                       // WithuApp.onCreate 에서 호출
    fun loadFrame0FullRes(state: CharacterState): Bitmap?      // bggen/<raw>_f0.png (앵커 원본)
}

// notify/NotificationHelper.kt
object NotificationHelper {
    const val EXTRA_OPEN_BATCH = "withu.openBatch"             // 알림 탭 → 배치 화면 딥링크 extra
    fun ensureChannels()                                       // reminder / gen_done / gen_progress(FGS)
    fun hasPermission(): Boolean
    fun authorizationLabel(): String                           // "아직 요청 안 했어요"/"거부됨"/"허용됨"
    fun notifyBatchFinished(done: Int, failed: Int, phase: BgGenPhase)   // 스펙 11 §2.4 문구
    fun scheduleBedtimeReminder()                              // 매일 22:30
    fun cancelAllScheduled()
    fun scheduleStepGoalIfNeeded(steps: Double)
    fun scheduleWorkoutEndedIfNeeded(latest: WorkoutSummary?)
}

// gen/ImageProcessing.kt
object ImageProcessing {
    fun chromaKeyRemoved(src: Bitmap): Bitmap                  // ChromaKey.removed 위임
    fun flattenedOnWhite(src: Bitmap): Bitmap
    fun matchedToReference(image: Bitmap, reference: Bitmap): Bitmap   // 크기·위치 정규화
    fun colorMatched(image: Bitmap, reference: Bitmap): Bitmap
    fun bestEffortTransparent(src: Bitmap): Bitmap             // ML Kit 실패/미지원 시 src 그대로 반환 (동일 인스턴스)
    fun prepareForCharacter(src: Bitmap): Bitmap?              // import 용: 배경제거+정규화. 실패 null
    fun hasTransparentPixels(src: Bitmap): Boolean             // 32px 알파 스캔 (alpha<250)
    fun downsampled(src: Bitmap, maxPixelSize: Int): Bitmap
    fun toBase64Png(src: Bitmap): String
    fun fromBase64(b64: String): Bitmap?
}

// camera/PhotoSaver.kt  (F2 생성 — S2/S3/S4/S6 공용)
object PhotoSaver {
    suspend fun save(bitmap: Bitmap): Result<Unit>             // MediaStore. API 28 은 WRITE 권한 필요 — 실패 메시지는 caller 문구
    fun needsLegacyWritePermission(): Boolean                  // Build.VERSION < Q
}
```

### 2-10. UiKit (`ui/UiKit.kt`)

```kotlin
enum class StatusKind { OK, WARNING, OFF }

@Composable fun FrostedCard(modifier: Modifier = Modifier, cornerRadius: Dp = 14.dp,
                            content: @Composable ColumnScope.() -> Unit)
@Composable fun FormSection(header: String? = null, footer: String? = null,
                            footerColor: Color? = null, modifier: Modifier = Modifier,
                            content: @Composable ColumnScope.() -> Unit)   // iOS Form 섹션 근사
@Composable fun StatusPill(kind: StatusKind, text: String)
@Composable fun WithuCTAButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier,
                               enabled: Boolean = true, loading: Boolean = false)   // 초록 CTA
@Composable fun WithuPinkButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier,
                                enabled: Boolean = true)       // 온보딩/승인용 핑크
@Composable fun WarningBanner(text: String, modifier: Modifier = Modifier)
@Composable fun CapsuleToast(text: String?, modifier: Modifier = Modifier)  // 하단 캡슐. text null 이면 숨김
@Composable fun CandyBadge(candy: Int, onClick: () -> Unit)    // 🍬 %d 툴바 배지
@Composable fun rememberBackgroundGradient(state: CharacterState): Brush   // withuGreen 0.14 → tint 0.04 → background
```

### 2-11. Phase F 공용 화면 컴포넌트 (`gen/`, `paywall/`)

```kotlin
@Composable fun SquareCropView(source: Bitmap, onDone: (Bitmap) -> Unit, onCancel: () -> Unit)
    // 풀스크린. 결과 1024×1024. px 좌표계 통일 (iOS normalizeSquare 버그 교훈)
@Composable fun GalleryReferencePicker(onPick: (Bitmap) -> Unit, onClose: () -> Unit)
@Composable fun PaywallSheet(onClose: () -> Unit)
    // 전체화면 다이얼로그로 표시. 닫힐 때 호출측이 remainingGenerations 갱신
```

### 2-12. Phase S 화면 진입점 (Phase I nav 배선 계약)

```kotlin
// S1 home/
@Composable fun HomeScreen(
    onOpenSingleGen: () -> Unit, onOpenBatchGen: () -> Unit, onOpenCamera: () -> Unit,
    onOpenGallery: () -> Unit, onOpenProfile: () -> Unit, onOpenDiagnostics: () -> Unit,
    onShowHelp: () -> Unit,                     // 설정 '사용법 보기' + 첫 실행 자동 표시
    onReonboard: () -> Unit,                    // '처음 안내 다시 보기' → onboarded=false 는 호출측(I)이 처리
    openBatchFromNotification: Boolean = false, // 알림 탭 cold start
)
@Composable fun DiagnosticsScreen()             // overrideState 는 SyncCoordinator.overrideState 공유

// S2 gen/
@Composable fun SingleGenScreen(onOpenBatch: () -> Unit)

// S3 gen/
@Composable fun BatchGenScreen()

// S4 gallery/
@Composable fun GalleryLandingScreen(onOpenStateFolder: (CharacterState) -> Unit,
                                     onOpenBatchGroup: (String) -> Unit, onOpenLegacy: () -> Unit)
@Composable fun StateFolderScreen(state: CharacterState, onOpenSingleGen: () -> Unit)
@Composable fun BatchGroupScreen(batchId: String)      // legacy 는 batchId = "" 규약 또는 별도 LegacyFolderScreen()

// S5 profile/ + onboarding/
@Composable fun ProfileScreen(onOpenStateFolder: (CharacterState) -> Unit)
@Composable fun OnboardingScreen(onComplete: () -> Unit)
@Composable fun HelpGuideSheet(onDone: () -> Unit)

// S6 camera/ + widget/
@Composable fun CameraScreen()
class CharacterWidget : GlanceAppWidget
class CharacterWidgetReceiver : GlanceAppWidgetReceiver
```

**화면 간 규칙**: 다른 S 에이전트의 컴포저블을 **직접 호출 금지** — 이동은 전부 콜백. 직접 호출 허용 대상은 Phase F 산출물(§2-5, §2-10, §2-11)뿐.

---

## 3. strings 전략

1. **기본 로케일 = 한국어**: `res/values/strings*.xml` 에 iOS 원문 그대로 (오타 포함, `\n` 이스케이프 주의). `res/values-en/` 은 iOS Localizable 카탈로그의 en 값 — en 값을 모르는 키는 **생략** (기본 ko 로 fallback).
2. **파일 분할 = 소유권 경계**: 공통 `strings.xml`(F1), 이후 화면별 `strings_home.xml`, `strings_gen.xml`, `strings_batch.xml`, `strings_gallery.xml`, `strings_profile.xml`, `strings_onboarding.xml`, `strings_paywall.xml`(F2), `strings_camera.xml`, `strings_widget.xml`. **자기 파일 외 strings 파일 수정 금지** → 병렬 충돌 0.
3. **키 네이밍**: `<화면접두>_<의미>` snake_case — `home_`, `settings_`, `diag_`, `widget_guide_`, `gen_`, `batch_`, `gallery_`, `profile_`, `onboarding_`, `help_`, `paywall_`, `camera_`, `widget_`. 공통은 `common_` (닫기/확인/취소/저장/삭제/선택), 네트워크 에러는 `err_` (F1 소유 — ApiError.koreanized 가 사용).
4. **보간은 positional 필수**: `%1$d`, `%1$s` (`%d` 단독 금지 — 다인자 문구 존재).
5. **리소스에 넣지 않는 것**: `generationHint`/`animationFrame2Hint`/프롬프트 템플릿(영문 서버 지시문) → 코드 상수. `CharacterState` 라벨/캡션은 위젯(Glance)에서 Context 로 접근해야 하므로 **enum 하드코딩 유지** (iOS 파리티, 스펙 08 §2 주석).
6. 중복 원문이라도 화면별 키를 따로 만든다 (예: `닫기` 는 `common_close` 하나만 예외로 공유) — 화면 간 파일 의존 최소화.

---

## 4. 구현 순서

### Phase F — 기반 (순차 2 에이전트: F1 → F2)

**F1 (도메인·저장소·UI 토대)** — 산출물: WithuApp, CharacterState(교체), Resolver, Profile, CharacterImage/Hero/WeatherDecoration, shared/* 전부, net/* 전부, quota, ImageProcessing, UiKit, Theme 확장, CharacterStore 위임 축소, build.gradle 의존성 추가, Manifest(Application+권한), 공통 strings, 유닛테스트 3종.

의존성 추가 (F1 이 libs.versions.toml + build.gradle.kts 확정):
- `androidx.glance:glance-appwidget`, `androidx.work:work-runtime-ktx`, `androidx.health.connect:connect-client`, CameraX 4종(core/camera2/lifecycle/view), `com.google.android.gms:play-services-location`, `androidx.exifinterface`, ML Kit subject segmentation(옵션 — 실패 시 fallback 계약이 있으므로 리스크 시 제거 가능).

검증: `./build.sh :app:assembleDebug` + 유닛테스트 통과. **기존 ui/HomeScreen·GenerateScreen 이 계속 컴파일되는지 확인** (CharacterStore 위임 유지).

**F2 (매니저·큐·공용 화면)** — 산출물: weather/*, health/*, SleepSignals, sync/SyncCoordinator, bggen/*, notify/NotificationHelper, PhotoSaver, SquareCropView, GalleryReferencePicker, PaywallSheet, strings_paywall.

검증: 빌드 통과. 이 시점에 §2 계약 전부가 실코드로 존재.

### Phase S — 화면 병렬 (6 에이전트, 파일 소유권 표)

| 에이전트 | 스펙 | 생성 파일 (이것만 — 다른 파일 수정 금지) |
|---|---|---|
| **S1 홈** | 01 | `home/HomeScreen.kt`, `home/SettingsSheet.kt`, `home/DiagnosticsScreen.kt`, `home/WidgetGuideSheet.kt`, `values{,-en}/strings_home.xml` |
| **S2 단건 생성** | 02 | `gen/SingleGenScreen.kt`, `gen/SingleGenViewModel.kt`, `gen/SingleGenModels.kt`, `values{,-en}/strings_gen.xml` |
| **S3 배치 생성** | 03 | `gen/BatchGenScreen.kt`, `gen/BatchGenViewModel.kt`, `values{,-en}/strings_batch.xml` |
| **S4 갤러리** | 04 | `gallery/GalleryLandingScreen.kt`, `gallery/StateFolderScreen.kt`, `gallery/GalleryGrid.kt`, `gallery/BatchGroupScreen.kt`, `values{,-en}/strings_gallery.xml` |
| **S5 프로필+온보딩** | 05, 06 | `profile/ProfileScreen.kt`, `onboarding/OnboardingScreen.kt`, `onboarding/HelpGuideSheet.kt`, `values{,-en}/strings_profile.xml`, `values{,-en}/strings_onboarding.xml` |
| **S6 카메라+위젯** | 12 | `camera/CameraScreen.kt`, `camera/CameraController.kt`, `camera/PlacedCharacter.kt`, `camera/PhotoCompositor.kt`, `values{,-en}/strings_camera.xml`, `widget/CharacterWidget.kt`, `widget/CharacterWidgetReceiver.kt`, `xml/character_widget_info.xml`, `values{,-en}/strings_widget.xml` |

병렬 안전 규칙:
- **기존 파일(MainActivity, ui/HomeScreen, ui/GenerateScreen, Manifest, build.gradle) 수정 금지.** 새 화면은 어디서도 참조되지 않은 채 컴파일만 되면 된다.
- 각 에이전트는 자기 트리에서 `./build.sh :app:assembleDebug` 통과 후 종료.
- 공유 API 가 부족하면 **자기 파일 안 private 헬퍼**로 해결하고 PLAN 위반 사항을 보고 (Phase I 에서 승격 검토).

### Phase I — 통합 (1 에이전트)

1. `MainActivity.kt` 교체: NavHost routes — `home`, `gen/single`, `gen/batch`, `gallery`, `gallery/state/{raw}`, `gallery/batch/{batchId}`, `gallery/legacy`, `profile`, `camera`, `diagnostics`, `help`(dialog). 온보딩 게이트: `!AppPrefs.onboarded` → `OnboardingScreen(onComplete = { onboarded = true })`; `onboarded && !seenGuide` → HelpGuide 자동 표시.
2. 알림 탭 딥링크: `EXTRA_OPEN_BATCH` intent extra → `gen/batch` 진입 (`openBatchFromNotification` 소비).
3. Manifest 마무리: 위젯 receiver + widget_info, FGS(dataSync) 선언, Health Connect 권한 rationale intent-filter, 딥링크.
4. 구 파일 삭제: `ui/HomeScreen.kt`, `ui/GenerateScreen.kt`, `store/CharacterStore.kt`.
5. WorkManager 주기 백그라운드 갱신(15분) 등록 → 성공 시 `AppPrefs.lastBackgroundRefreshAt` 기록 + `SyncCoordinator.syncNow()`.

### Phase V — 빌드·검증 (1 에이전트)

1. `./build.sh :app:assembleDebug` 클린 빌드 + 유닛테스트.
2. 문구 대조: strings 파일 vs 스펙 §2 표 샘플링 (특히 오타 원문 유지, positional 포맷).
3. 계약 위반 스캔: Phase S 보고서의 private 헬퍼 승격 여부, 미사용 import, Manifest 권한 누락.
4. 스모크 시나리오 (에뮬레이터): 온보딩 → 홈 → 단건 생성(모의/실서버) → 적용 → 위젯 갱신 → 갤러리 → 프로필 저장.

---

## 5. 위험 목록 (병렬에서 어긋나기 쉬운 지점)

| # | 위험 | 방지책 |
|---|---|---|
| 1 | **계약 드리프트** — 화면 에이전트가 없는 공유 API 를 상상해서 호출 (예: `CharacterImageStore.saveAll`) | 이 문서 §2 가 유일한 계약. 부족하면 private 헬퍼 + 보고. Phase F 완료 커밋을 base 로 브랜치 |
| 2 | **strings 충돌/오염** — 같은 파일 수정, 키 중복, "오타 교정" | 파일=소유권 1:1, 접두 규칙, "원문 유지(이용헤요 포함)" 명시. Phase V 에서 대조 |
| 3 | **CharacterState 확장 여파** — 8→24 case 로 기존 `when` exhaustive 깨짐 | F1 이 교체와 동시에 구 화면(HomeScreen/GenerateScreen/CharacterStore) 컴파일 확인. Phase S 는 `userFacing` 만 순회 |
| 4 | **frame0 저장 시 옛 _f1 미삭제** — "옛 프레임과 섞여 움직이는" 버그 재현 | 계약에 명시(§2-2). F1 유닛테스트에 케이스 추가 |
| 5 | **캔디 이중 차감/미차감** — record 호출 시점 분산 (단건=뷰, 배치=큐 process, 다듬기=성공 시) | 각 스펙의 차감 시점 표를 화면 에이전트 지시에 복사. `record` 는 성공 판정(인스턴스 `!==` 비교) 후에만 |
| 6 | **의존성/버전 지옥** — Glance·Health Connect·ML Kit 버전이 compose BOM 과 충돌 | F1 단독으로 전 의존성 확정 + 빌드 통과 후 Phase S 시작. ML Kit 는 계약상 fallback 있어 제거 가능 |
| 7 | **네비게이션 컴파일 의존** — 화면끼리 컴포저블 직접 호출 | "이동=콜백, 직접 호출=Phase F 산출물만" 규칙 (§2-12). Phase I 가 유일한 배선 지점 |
| 8 | **suspend/스레딩 불일치** — 저장소 동기 API 를 메인스레드에서 호출 (ANR) | 계약에 IO 규칙 명시. 화면은 ViewModel/LaunchedEffect 에서 `withContext(IO)` |
| 9 | **overrideState/설정 공유 상태 이원화** — 홈과 진단이 각자 상태를 들면 즉시 반영 안 됨 | `SyncCoordinator.overrideState` 단일 홀더 (§2-8) |
| 10 | **Worker ↔ 뷰 상태 불일치** — 배치 재시작 후 images 맵이 빈 것을 뷰가 모름 | 계약: images 는 메모리 전용, 뷰는 반드시 `CharacterImageStore.loadFrame` fallback (스펙 03 §syncFromManager) |
| 11 | **DEBUG 쿼터 무제한** — 페이월/차감 흐름이 디버그 빌드에서 검증 불가 | Phase V 에서 release 빌드(`assembleRelease` minify off) 스모크 1회 |

---

## 6. 산출 요약

- 신규/교체 파일 추정: **Kotlin ~55개 + 리소스(strings ko/en, widget xml) ~22개 + 테스트 3개 ≈ 80개**
- 에이전트: **F 2 (순차) → S 6 (병렬) → I 1 → V 1 = 총 10회 실행**
- 최대 리스크: **#1 계약 드리프트** — Phase F 산출물이 이 문서와 1글자라도 다르면 병렬 화면 6개가 전부 컴파일 실패로 수렴하므로, F 종료 시 §2 시그니처 대조를 필수 게이트로 둘 것.
