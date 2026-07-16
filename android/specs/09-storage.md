# 09 — 이미지/상태 저장소 (CharacterImageStore / SharedAppState / WatchMessage)

원본(진실의 원천):
- `withu/Shared/CharacterImageStore.swift`
- `withu/Shared/SharedAppState.swift`
- `withu/Shared/WatchMessage.swift`

이 문서는 화면이 아니라 **데이터 계층 스펙**이다. 홈/갤러리/생성/위젯 스펙들이 전부 이 스키마 위에 선다.
SCOPE.md 규칙: **이미지 저장 스키마는 iOS CharacterImageStore 와 동형** (characters/<state>.png, gallery/<uuid>.png + metadata.json). Wear OS 는 제외.

---

## 1. 모듈 구조 (iOS 기준, 위→아래)

iOS 에서 이 세 파일은 4개 타깃(앱/워치/위젯/컴플리케이션)이 공유하는 App Group 컨테이너를 감싼다.

```
App Group 컨테이너 (group.com.seoyoung.withu)
├── characters/                 ← 활성 슬롯 (홈/위젯/워치가 읽는 "현재 적용본")
│   ├── <state>.png             ← frame 0 (기본 이미지)
│   └── <state>_f1.png          ← frame 1 (움직이는 캐릭터 2번째 프레임, 있을 때만)
├── gallery/                    ← 전체 이력 (재선택 가능)
│   ├── <uuid>.png              ← frame 0
│   ├── <uuid>_f1.png           ← frame 1 (hasFrame1 인 항목만)
│   └── metadata.json           ← [GalleryItem] JSON 배열
├── backgrounds/<cond>.png      ← 날씨 배경 (조건별 최대 4장) — SCOPE 상 AI 배경 생성은 후속
└── decorations/<cond>.png      ← 날씨 데코 아이콘 (조건별 최대 5장, 캐릭터 옆 작은 아이콘)

App Group UserDefaults (같은 suite)
├── withu.currentMessage.v1            ← WatchMessage JSON (SharedAppState)
├── withu.activeSourceMap.v1           ← [state.rawValue: galleryId] 활성 슬롯 출처 매핑
├── withu.animationEnabled.v1          ← Bool, 기본 true (전역 애니메이션 토글)
└── withu.animationDisabledStates.v1   ← [String] (상태별 움직임 끄기, rawValue 집합)
```

조건부 존재:
- `<state>_f1.png` — 움직이는(2프레임) 캐릭터를 적용했을 때만 존재. frame0 을 새로 저장하면 **옛 f1 은 반드시 삭제**된다(아래 §3).
- `backgrounds/`, `decorations/` — 사용자가 저장했을 때만 파일 존재. 없으면 emoji fallback.

---

## 2. 사용자 문구 전량

이 계층은 데이터 계층이라 UI 문구가 적다. 코드에 포함된 사용자 노출 문자열은 다음이 전부:

`WeatherBackgroundCondition.displayName` (localized):
| case | 문구 |
|---|---|
| sunny | `맑음 ☀️` |
| cloudy | `흐림 ☁️` |
| rainy | `비 🌧` |
| snowy | `눈 ❄️` |
| night | `밤하늘 🌙` |

fallback emoji (Asset/파일 없을 때 화면에 그대로 표시됨): `☀️` `☁️` `🌧` `❄️` `🌙`

디버그 전용 (`alphaInfoDescription`, 워치 디버그 화면 — Android 파리티 불필요하나 원문 기록):
- `❌ alpha 없음 (RGB only)` / `✅ alpha 있음 (RGBA)` / `alpha only` / `?`
- 형식: `%dx%d · %s` (원문 `"\(cg.width)x\(cg.height) · \(hasAlpha)"`)

`generationHint` (서버 프롬프트용 영문 — 번역 금지, 원문 그대로 사용):
- sunny: `Bright sunny sky background, soft white clouds, warm sunlight, clean pastel landscape, illustration. NO character, NO person — empty scene only.`
- cloudy: `Soft overcast cloudy sky background, gray pastel atmosphere, calm empty landscape, illustration. NO character, NO person — empty scene only.`
- rainy: `Rainy weather background scene, light rain falling, wet pavement, soft gray sky, pastel illustration, cinematic. NO character, NO person — empty scene only.`
- snowy: `Snowy winter background, gentle snowflakes falling, snow on ground, soft cold pastel colors, illustration. NO character, NO person — empty scene only.`
- night: `Calm night sky background, dark blue / deep purple, scattered stars, soft crescent moon, dreamy pastel illustration. NO character, NO person — empty scene only.`

(배경 AI 생성 자체는 SCOPE 제외지만, enum 은 데코/야간 판정에 쓰이므로 포팅한다.)

---

## 3. 스키마 + 로직

### 3-1. GalleryItem (metadata.json 의 원소)

```swift
struct GalleryItem: Identifiable, Codable, Equatable {
    let id: String              // UUID().uuidString
    let sourceState: String     // 처음 만들 때의 CharacterState.rawValue
    let createdAt: Date
    var hasFrame1: Bool?        // 연속 이미지(frame 1) 동봉 여부. 옛 메타엔 키 없음 → nil = false
    var batchId: String?        // '한번에 만들기' 세션 id. 단건/옛 항목 nil
    var prompt: String?         // 생성 당시 서버로 보낸 프롬프트. 옛 항목 nil
}
```

직렬화 주의 (iOS 파일과의 개념 호환 목적, Android 는 자체 파일이므로 형식만 동형이면 됨):
- iOS 는 기본 `JSONEncoder` — `createdAt` 이 **Double (secondsSinceReferenceDate, 2001-01-01 기준)** 로 직렬화된다. Android 에서 새로 쓰는 파일이므로 **epoch millis Long** 으로 저장해도 무방 — 단, 필드명은 동일하게 `id/sourceState/createdAt/hasFrame1/batchId/prompt` 유지하고 옵셔널 3개는 **없을 수 있음(null 허용)** 으로 파싱.
- `hasFrame1` 이 Optional 인 이유: 옛 메타에 키가 없어 nil → false fallback. Android 도 nullable Boolean.

### 3-2. WeatherBackgroundCondition

`sunny, cloudy, rainy, snowy, night` (rawValue = 파일명). `.night` 는 **시간 기반** (날씨 무관) — 야간엔 어둠이 가장 강한 시각 신호라 다른 조건을 다 누른다.

emoji → 조건 매핑 (`from(emoji:)`): `☀️`→sunny, `☁️`→cloudy, `🌧` 또는 `⛈`→rainy(천둥은 비로), `❄️`→snowy, 그 외 nil. night 는 emoji 매핑 없음(시간 판정).

### 3-3. 야간 판정 `isCurrentlyNight`

```swift
static func isCurrentlyNight(at date: Date = Date(), sunrise: Date? = nil, sunset: Date? = nil,
                             fallbackStartMinute: Int = 20 * 60, fallbackEndMinute: Int = 6 * 60,
                             calendar: Calendar = .current) -> Bool
```
- sunrise/sunset 둘 다 있으면: `nowM < riseM || nowM >= setM` — **분(minute-of-day)만 비교**. 이유: 저장된 일출/일몰의 절대 날짜가 오늘이 아닐 수 있어(스테일 데이터) 시-분만 비교하면 안전.
- 없으면 fallback 20:00~06:00. 자정 넘김 처리: `s < e ? (nowM >= s && nowM < e) : (nowM >= s || nowM < e)`.
- 순수 함수(now/calendar 주입) — 단위 테스트 대상.

### 3-4. 활성 슬롯 API

| API | 동작 |
|---|---|
| `load(_ state)` | `characters/<state>.png` 로드 (= loadFrame frame 0) |
| `loadFrame(_ state, frame:)` | frame>0 이면 `<state>_f<n>.png`. 없으면 nil — **caller 가 frame0 fallback** |
| `loadThumbnail(_ state, maxPixelSize:)` | 위젯 메모리 절약용 다운샘플. RGBA 유지 필수(투명 배경) |
| `hasImage(for:)` / `hasAnimationFrames(for:)` | 파일 존재 확인 (f1 존재 = 애니 캐릭터) |
| `saveActiveSlotOnly(_ image, for:, frame:)` | **활성 파일만** 덮어쓰기 — 갤러리/매핑 불변. 용도: 결과 화면에서 transparent 토글 등 "갤러리 원본 유지, 표시만 교체" |
| `clearActive(_ state)` | 활성 슬롯 삭제 → 번들 일러스트/심볼 fallback 으로 복귀 |
| `swapActiveFrames(for:)` | f0↔f1 파일 맞바꿈(tmp 경유 move). 둘 다 있어야 성공 |
| `wipeAll()` | 계정 삭제 시: 4개 폴더 + activeSourceMap + 캐시 전부 제거 |

**frame0 저장 시 옛 f1 무효화 규칙 (핵심 엣지 케이스)**: `save`/`saveActiveSlotOnly` 에서 frame 0 을 쓰면 기존 `<state>_f1.png` 를 **즉시 삭제**한다. 애니 캐릭터면 직후 frame1 이 다시 저장된다. 안 지우면 "frame1 없는 새 캐릭터가 옛 캐릭터의 frame1 과 섞여 움직이는" 버그.

### 3-5. 생성/갤러리 저장 API

```swift
@discardableResult
static func save(_ image: UIImage, for state: CharacterState, frame: Int = 0,
                 applyToActiveSlot: Bool = true, batchId: String? = nil,
                 prompt: String? = nil) -> GalleryItem?
```
- frame 0: 갤러리에 **새 항목 생성** (`gallery/<uuid>.png` + 메타 append) → 그 id 를 activeSourceMap[state] 로 기록.
- frame 1: 새 항목 안 만들고 **같은 state 의 가장 최근 갤러리 항목**에 `<id>_f1.png` 붙이고 `hasFrame1=true` (frame0 없이 frame1 만 오는 케이스는 정상 흐름에 없음 → nil 반환).
- `applyToActiveSlot: false`: 갤러리에만 저장, 활성 슬롯 불변 — **배치 생성**의 "만들어만 두고 나중에 버튼으로 적용" 흐름.
- 반환 GalleryItem 은 재선택용 id.

### 3-6. 갤러리 조회/조작 API

| API | 동작 |
|---|---|
| `loadGalleryMetadata()` | metadata.json 전체 → **createdAt 내림차순 정렬** 반환 |
| `loadGalleryGrouped()` | (byState: [CharacterState:[GalleryItem]], legacy: [GalleryItem]) — userFacing 상태별 버킷 + 옛/비노출 상태는 legacy("기타") 버킷. 메모리 그룹핑만, 디스크 포맷 불변 |
| `loadGalleryByCharacter()` | batchId 로 묶은 `[(batchId, createdAt, items)]`. batchId nil 항목 제외. 그룹 createdAt = 항목 max, 최신 그룹 먼저. 그룹 안은 `CharacterState.userFacing` 순서로 정렬(rank 없으면 맨 뒤) |
| `loadGalleryImage(id:)` / `loadGalleryFrame1(id:)` | 파일 로드, 없으면 nil |
| `replaceGalleryImage(_ id, with:, frame:)` | 갤러리 파일 교체(배경 빼기 등 후처리 반영). 메타 불변 |
| `swapGalleryFrames(_ id)` | 갤러리 항목 f0↔f1 맞바꿈 |
| `applyGalleryItem(_ id, to state)` | 갤러리 → 활성 슬롯 복사. **f1 규칙**: 갤러리에 f1 있으면 같이 복사, 없으면 active 의 기존 f1 삭제(다른 캐릭터 잔재 방지). activeSourceMap 갱신 + 변경 알림 |
| `deleteGalleryItem(_ id)` | f0 + f1 + 메타 항목 삭제 + **activeSourceMap 에서 이 id 를 가리키던 모든 state 제거**. (활성 슬롯 PNG 자체는 안 지움 — 이미 적용된 그림은 계속 보임, 출처 링크만 끊김) |

### 3-7. 활성 출처 매핑 (activeSourceMap)

`[state.rawValue: galleryId]` — "어떤 state 슬롯이 어떤 갤러리 항목을 쓰는 중인지".
- 갱신: `save(frame:0)`, `applyGalleryItem`. 정리: `deleteGalleryItem`, `wipeAll`.
- 조회: `currentGalleryItemId(for:)` (갤러리 상세 "적용 중" 뱃지), `statesUsingGalleryItem(_:)` (역검색 — 삭제 확인 다이얼로그 등에서 "이 항목이 어디 적용 중인지").

### 3-8. 애니메이션 토글

- 전역 `animationEnabled` (기본 **true**): f1 이 있어도 재생할지. 홈 CharacterImageView 가 읽음.
- 상태별 `isAnimationDisabled(for:)`: 전역과 **별개** — 이 state 만 정적. **f1 파일은 남겨두고 재생만 막음** (다시 켜면 즉시 복원).
- 값 변경 시 캐시 evict + 변경 알림 broadcast.

### 3-9. 변경 알림 + 캐시

- `Notification.Name.characterImageChanged` (object = state 또는 nil broadcast), `.weatherBackgroundChanged` — 홈/뷰 재로드 트리거. 위젯은 별도로 `WidgetCenter.reloadAllTimelines()`.
- 디코드 캐시(NSCache, 24개/24MB): **쓰기 드묾·읽기 hot** → 쓰기 때 전체 비움(단순/안전). 캐시 키에 **파일 버전(수정시각ms+크기)** 포함 — 다른 프로세스(위젯)가 evict 없이도 새 파일을 자동 인지.
- 파일 쓰기는 전부 atomic write.

### 3-10. SharedAppState / WatchMessage

```swift
enum SharedAppState {
    static let groupID = "group.com.seoyoung.withu"
    static func save(_ message: WatchMessage)      // 키 "withu.currentMessage.v1", JSON
    static func loadMessage() -> WatchMessage?
}
```
- 위젯 timeline reload 는 **caller 책임** (save 가 안 함).

```swift
struct WatchMessage: Codable, Equatable, Sendable {
    let state: CharacterState
    let todaySteps: Double?
    let lastSleepHours: Double?
    let todayActiveMinutes: Double?   // 오늘 활동(운동) 분
    let todayActiveKcal: Double?      // 오늘 활성 칼로리
    let weatherEmoji: String?         // 예: ☀️
    let weatherTempC: Double?         // 섭씨
    var weatherSunrise: Date? = nil   // 위치 local time
    var weatherSunset: Date? = nil
    let timestamp: Date
    static let payloadKey = "withu.watchMessage.v1"
}
```
- 모든 신규 필드는 옵셔널 — 옛 메시지 디코드 호환. Android 도 전 필드 nullable(필수는 state/timestamp)로 파싱.
- 이 스냅샷이 홈 히어로 상태·위젯·(iOS에선 워치) 표시의 단일 소스. Android 에선 Watch 전송은 없지만 **"현재 적용 스냅샷" 저장소 역할은 동일**하게 유지 — 홈/위젯(Glance)이 같은 데이터를 읽는다. 이름도 파리티를 위해 `WatchMessage` 유지 권장.

---

## 4. 데이터 의존성

- `CharacterState` (rawValue 가 파일명/JSON 키 — **rename 절대 금지**), `CharacterState.userFacing` (그룹핑 순서).
- App Group UserDefaults 키: `withu.currentMessage.v1`, `withu.activeSourceMap.v1`, `withu.animationEnabled.v1`, `withu.animationDisabledStates.v1`.
- 파일: §1 트리 전체. metadata.json 은 갤러리 폴더 안.
- 소비자: 홈(hero/frame swap), 갤러리 화면(08), 단건/배치 생성(02/03), 위젯(Glance), 계정 삭제(wipeAll), 날씨 데코 뷰.

---

## 5. Android 구현 노트

### 5-1. App Group 대체 = 앱 내부 저장소 + 공유 싱글턴

Android 는 위젯(Glance)이 **같은 프로세스/같은 앱**이므로 App Group 이 불필요. 대응:
- 파일: `context.filesDir` 아래 동일 트리 — `filesDir/characters/`, `filesDir/gallery/`, `filesDir/backgrounds/`, `filesDir/decorations/`. 외부 저장소/MediaStore 금지(내부 전용; "사진 앱에 저장" 기능은 갤러리 스펙에서 MediaStore 로 별도 export).
- UserDefaults: `SharedPreferences`(또는 DataStore Preferences) 단일 파일 `withu_shared`. **키 문자열은 iOS 원문 그대로** 유지 (`withu.currentMessage.v1` 등) — 스펙 대조 쉬움.
- `groupID` 상수는 의미 없어지므로 생략 가능하나, prefs 파일명 상수로 흔적 유지.

### 5-2. 구현 형태

- `object CharacterImageStore` (Kotlin object) + `Context` 주입(파라미터 or appContext 홀더). 함수 시그니처는 iOS 와 1:1 대응, `UIImage` → `Bitmap`.
- PNG 저장: `bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)` — **ARGB_8888 유지** (투명 배경 필수). Atomic write 대응: `AtomicFile` 또는 tmp 파일 write 후 `renameTo`.
- 스왑(swapActiveFrames/swapGalleryFrames): tmp 경유 `File.renameTo` 3회 — iOS 와 동일 패턴.
- metadata.json: `kotlinx.serialization` — `GalleryItem` data class, `hasFrame1/batchId/prompt` nullable + 기본 null (`ignoreUnknownKeys=true`).
- 다운샘플(loadThumbnail): `BitmapFactory.Options.inSampleSize`(2의 거듭제곱 근사) + 필요 시 `Bitmap.createScaledBitmap` 정밀 축소. `inPreferredConfig = ARGB_8888`. Glance 위젯도 큰 비트맵 전달 시 `TransactionTooLargeException` — maxPixelSize 개념 그대로 유지.
- 디코드 캐시: `LruCache<String, Bitmap>`(약 24MB, byteCount 비용). 캐시 키 = `"$state#$frame#$sizeTag#${lastModified}_${length}"` — iOS 의 파일 버전 키 그대로. 쓰기 시 `evictAll()`.
- 변경 알림: NotificationCenter 대체 = 싱글턴 `MutableSharedFlow<CharacterState?>` (null = broadcast) 두 개(`characterImageChanged`, `weatherBackgroundChanged`). Compose 는 `collectAsState`/`LaunchedEffect` 로 구독. 위젯 갱신은 저장 후 caller 가 `WithuWidget().updateAll(context)` (WidgetCenter.reloadAllTimelines 대응) — **save 가 아니라 caller 책임**인 점 동일 유지.
- `SharedAppState`: prefs 에 JSON 문자열 저장/로드. `WatchMessage` 는 kotlinx.serialization data class — `state` 는 rawValue 문자열로 (역)직렬화, `Date` 필드는 epoch millis Long(nullable).
- `isCurrentlyNight`: 순수 함수로 포팅 (`java.time.LocalTime`/Calendar 주입) + 단위 테스트 (자정 넘김/일출일몰/스테일 날짜 케이스).

### 5-3. 주의점

- **파일명 = state rawValue** — CharacterState enum 포팅 시 rawValue 문자열을 iOS 와 완전히 동일하게(01 스펙 참조). 바꾸면 스키마 동형 깨짐.
- frame0 저장 → **옛 f1 삭제** 규칙을 save/saveActiveSlotOnly 양쪽 다 구현할 것 (누락 시 "옛 f1 과 섞여 움직이는" 버그 그대로 재현됨).
- `applyGalleryItem` 의 "갤러리에 f1 없으면 active f1 삭제" 분기 누락 주의.
- `deleteGalleryItem` 은 활성 PNG 를 지우지 않는다 — 매핑만 끊는다. 그대로 유지.
- `loadFrame(frame:1)` 이 nil 이면 caller 가 frame0 fallback — 저장소가 fallback 하지 않는다.
- 위젯(Glance) 프로세스 분리는 없지만, 파일 버전 캐시 키는 그대로 두면 앱 내 다중 진입점(위젯 Worker 등)에서도 안전.
- 스레딩: 파일 I/O 는 `Dispatchers.IO` — Compose 에서 직접 호출 금지(iOS 는 동기 호출이지만 Android 는 StrictMode/ANR).

### 5-4. Android 신규 파일 제안

```
app/src/main/java/com/seoyoung/withu/shared/
├── CharacterImageStore.kt     (활성 슬롯 + 갤러리 + 배경/데코 + 매핑 + 애니 토글 + LruCache)
├── GalleryItem.kt             (@Serializable data class)
├── SharedAppState.kt          (prefs 래퍼 + WatchMessage 저장/로드)
├── WatchMessage.kt            (@Serializable data class)
├── WeatherBackgroundCondition.kt (enum + displayName/emoji/generationHint/from(emoji))
└── StoreEvents.kt             (characterImageChanged / weatherBackgroundChanged SharedFlow)
app/src/test/java/com/seoyoung/withu/shared/
├── IsCurrentlyNightTest.kt
└── GalleryMetadataTest.kt     (nullable 필드 하위호환·그룹핑·정렬)
```

---

## 6. 제외 항목 (SCOPE.md 기준)

- **Wear OS 전송 전체** — ConnectivityManager/transferFile/updateApplicationContext 대응 없음. WatchMessage 는 로컬 스냅샷 저장소로만 사용.
- **날씨 배경 AI 생성** — `saveBackground`/`loadBackground`(backgrounds/) 는 이번에 미구현 (폴더 예약만; wipeAll 은 폴더 지움). 단 **데코(decorations/)는 포함** — "날씨 데코"가 SCOPE 포함 항목.
- `alphaInfoDescription` — 워치 디버그 전용, 포팅 불필요.
- 계정 삭제(wipeAll 호출처) 자체는 로그인 범위 — Google 로그인이 후속이므로 wipeAll 함수만 구현해 두고 호출 화면은 후속.
