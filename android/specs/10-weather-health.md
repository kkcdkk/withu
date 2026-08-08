# 10 — 날씨 + 건강 데이터 (WeatherManager / HealthKitManager)

원본(진실의 원천):
- `withu/Weather/WeatherManager.swift`
- `withu/Weather/WeatherCondition.swift` (WMO 매핑 · 이모지 · 스냅샷 모델)
- `withu/HealthKit/HealthKitManager.swift`

SCOPE.md 규칙: **날씨 = Open-Meteo + 위치(반올림 2자리)**, **상태 자동 결정 = Health Connect 걸음/수면/운동**. UI 화면이 아닌 데이터 계층 모듈 — 홈/프로필/리졸버 스펙(01, 05 등)이 이 모듈을 소비한다.

---

## 1. 화면/모듈 구조

이 스펙에는 자체 화면이 없다. 두 매니저(싱글턴)와 하나의 값 모델 계층으로 구성:

1. **`WeatherCondition`** — enum (`sunny / cloudy / rainy / snowy / foggy / thunder / unknown`). WMO 코드 매핑 + 이모지 + 캡션 + tint.
2. **`WeatherSnapshot`** — 1회 측정 값 (`condition`, `temperatureC`, `timestamp`, `sunrise?`, `sunset?`, `isHot`, `isCold`).
3. **`WeatherManager`** — 위치 → Open-Meteo → snapshot. 관찰 가능 상태: `snapshot`, `isFetching`, `lastError`, `authorizationStatus`.
4. **`HealthKitManager`(→ HealthConnectManager)** — 걸음/수면/운동/활동분/칼로리 조회 + 수면 일정 판정 + 평균 수면 창 계산.

노출 조건(소비처 기준):
- 홈 날씨 헤더: `snapshot != nil` 이면 `이모지 + %d°C`, fetch 중이면 스피너, `lastError` 는 홈 진단/에러 표시에 사용.
- 오늘 활동 카드: `todaySteps` / `todayActiveMinutes` / `todayActiveKcal` 이 nil 이면 각 항목 미표시(또는 "—").
- 리졸버 입력: `recentWorkouts`, `isInBedSchedule`, `hasSleepSchedule`, `isLikelyInWorkout`, `recentStepsPerMinute`.

---

## 2. 사용자 문구 전량 (한국어 원문 그대로)

### WeatherManager (에러)

| 위치 | 문구 |
|---|---|
| 위치 권한 거부 (`WeatherError.locationDenied`) | `위치 권한이 없어요. 설정에서 켜주세요.` |
| 위치 없음 (`WeatherError.noLocation`) | `현재 위치를 찾지 못했어요.` |
| 네트워크 실패 (`WeatherError.network`) | `날씨 통신 실패: %s` |
| 디코딩 실패 (`WeatherError.decoding`) | `날씨 응답 해석 실패: %s` |
| URL 생성 실패 | `URL 생성 실패` |
| 위치 조회 실패 (didFailWithError) | `위치 조회 실패: %s` |

### WeatherCondition 캡션

| condition | emoji | caption |
|---|---|---|
| sunny | ☀️ | `맑음` |
| cloudy | ☁️ | `흐림` |
| rainy | 🌧 | `비` |
| snowy | ❄️ | `눈` |
| foggy | 🌫 | `안개` |
| thunder | ⛈ | `뇌우` |
| unknown | ❓ | `?` (caption은 비로컬라이즈 리터럴) |

### HealthKitManager (에러)

| 위치 | 문구 |
|---|---|
| `HealthError.notAvailable` | `이 기기에서는 HealthKit을 쓸 수 없어요.` → Android 대체: `이 기기에서는 헬스 커넥트를 쓸 수 없어요.` (신규 문구 — Health Connect 미설치/미지원 시) |
| `HealthError.typeUnavailable` | `HealthKit 데이터 타입 사용 불가: %s` |
| `HealthError.query` | `쿼리 실패: %s` |

### 운동 종류 표시명 (`HKWorkoutActivityType.displayName`)

| 종류 | 문구 |
|---|---|
| running | `달리기 🏃` |
| cycling | `자전거 🚴` |
| walking | `걷기 🚶` |
| hiking | `등산 🥾` |
| swimming | `수영 🏊` |
| yoga | `요가 🧘` |
| traditionalStrengthTraining / functionalStrengthTraining | `근력 💪` |
| 그 외 전부 | `운동` |

---

## 3. 상태(state)와 로직

### 3.1 WeatherManager

상태:
```swift
private(set) var snapshot: WeatherSnapshot?
private(set) var isFetching: Bool
private(set) var lastError: String?
private(set) var authorizationStatus: CLAuthorizationStatus
```

**`refresh(force: Bool = false)` 흐름:**
1. `force == false` 이고 `snapshot.timestamp` 가 **30분(cacheTTL = 30 * 60초)** 이내면 아무것도 안 함 (메모리 캐시 — 디스크 저장 없음).
2. `isFetching = true`, `lastError = nil`.
3. 위치 권한 분기:
   - 미결정 → 권한 요청 (허용되면 콜백에서 위치 요청 이어감).
   - 허용 → 1회 위치 요청 (`requestLocation`, 정확도 `kCLLocationAccuracyKilometer` — km 급이면 충분).
   - 거부/제한 → `isFetching = false`, `lastError = "위치 권한이 없어요. 설정에서 켜주세요."`.
4. 위치 수신 → `fetchOpenMeteo(lat:lon:)`.
5. 위치 실패 → `isFetching = false`, `lastError = "위치 조회 실패: %s"`.

**Open-Meteo 호출 (파라미터 정확히):**
- 좌표는 **소수 2자리(~1km)로 반올림** — 주석의 '왜': *"날씨엔 충분하고, 정확한 위치가 기기 밖(타사 API)으로 나가지 않게 (App Privacy: '대략적 위치')"*. `(lat * 100).rounded() / 100`.
- URL:
  ```
  https://api.open-meteo.com/v1/forecast
    ?latitude=<lat>&longitude=<lon>
    &current=temperature_2m,weather_code
    &daily=sunrise,sunset&timezone=auto
  ```
- 응답 파싱: `current.temperature_2m`(Double), `current.weather_code`(Int), `daily.sunrise[0]` / `daily.sunset[0]`(String 배열, 옵셔널).
- **일출/일몰 포맷**: `"yyyy-MM-dd'T'HH:mm"` — 오프셋 없는 위치 로컬 시각. `timezone=auto` 로 요청했으므로 위치 로컬 TZ이고, **사용자 TZ와 같다고 가정하고 기기 로컬 TZ로 파싱** (주석: 대부분 케이스). 파싱 실패 시 nil (스냅샷의 sunrise/sunset은 옵셔널 — 이전 캐시 호환).
- 성공 → `snapshot` 교체, `lastError = nil`. 네트워크 오류 → `날씨 통신 실패: %s`, 디코딩 오류 → `날씨 응답 해석 실패: %s`. 어떤 경로든 종료 시 `isFetching = false` (defer).

**WMO weather_code → condition 매핑 (전량):**

| WMO 코드 | condition |
|---|---|
| 0, 1 | sunny (clear / mainly clear) |
| 2, 3 | cloudy (partly cloudy / overcast) |
| 45, 48 | foggy |
| 51–67 | rainy (drizzle / rain) |
| 71–77 | snowy (snow fall) |
| 80–82 | rainy (rain showers) |
| 85, 86 | snowy (snow showers) |
| 95–99 | thunder |
| 그 외 | unknown |

**WeatherSnapshot 파생값:** `isHot = temperatureC >= 30` (해변 캐릭터 판정), `isCold = temperatureC <= 0`.

엣지 케이스:
- 캐시는 메모리 전용 → 앱 프로세스 재시작 시 첫 refresh 는 항상 네트워크.
- 권한 요청 도중(시트 표시 중)에는 `isFetching = true` 로 남아 있다가 권한 콜백에서 진행/실패 확정.
- 거부 상태에서 refresh 를 다시 불러도 매번 같은 에러 문구 세팅 (앱 설정 유도).

### 3.2 HealthKitManager

읽기 권한 대상 6종: **workout, sleepAnalysis, stepCount, activeEnergyBurned, appleExerciseTime, heartRate.** 쓰기 없음.

관찰 가능 상태(전량):
```swift
private(set) var isAuthorized: Bool
private(set) var sleep: SleepSummary?                 // (totalAsleep 초, sampleCount, lastNight)
private(set) var recentWorkouts: [WorkoutSummary]     // (activity, start, duration, kcal?, meters?)
private(set) var todaySteps: Double?
private(set) var todayActiveMinutes: Double?          // appleExerciseTime
private(set) var todayActiveKcal: Double?             // activeEnergyBurned
private(set) var isInBedSchedule: Bool
private(set) var hasSleepSchedule: Bool
private(set) var inBedSampleCount24h: Int             // 진단용
private(set) var lastInBedSampleStart: Date?          // 진단용
private(set) var lastInBedSampleEnd: Date?            // 진단용
private(set) var recentHRSampleCount: Int             // 최근 90초
private(set) var recentHRAverage: Double
private(set) var isLikelyInWorkout: Bool
private(set) var recentStepsPerMinute: Double
```

**권한 모델의 '왜'**: Apple HealthKit은 어떤 항목이 허용됐는지 앱에 알려주지 않음 → `isAuthorized` 는 "권한 요청을 한 번이라도 했거나 마지막 fetch 가 에러 없이 통과" 로 추론. 각 fetch 성공 시마다 `isAuthorized = true` 재설정. (Health Connect 는 `getGrantedPermissions()` 로 정확히 알 수 있으므로 Android 는 추론 불필요 — §5 참고.)

**fetchSleep(days: 7)**: 지난 N일 sleepAnalysis 샘플 중 **asleep 계열만** (`asleepUnspecified/Core/Deep/REM` — inBed 제외) 합산. `SleepSummary(totalAsleep: 초 합계, sampleCount, lastNight: 가장 최근 샘플의 startDate)`.

**fetchTodaySteps()**: 오늘 자정(startOfDay)~현재 stepCount cumulativeSum. **"No data available" 에러는 진짜 에러가 아니라 0건 의미 → 0으로 처리** (주석 그대로).

**fetchTodayActiveMinutes() / fetchTodayActiveKcal()**: 같은 방식의 오늘 누적합. appleExerciseTime(분) / activeEnergyBurned(kcal). "no data → 0" 규칙 동일.

**fetchWorkouts(days: 7, limit: 20)**: 최근 N일 워크아웃, 시작시각 내림차순, 최대 20개. 각각 activity 종류·시작·지속시간·kcal·거리(m).

**fetchInBedSchedule() — 수면 일정/현재 수면 판정** (never throws, 실패는 전부 false):
- 조회 창: **현재 기준 ±24시간** (미래 24h 포함 — iOS 는 수면 일정의 wind-down~기상 구간을 `inBed` 샘플로 **미리** 기록하기 때문).
- `hasSleepSchedule = inBed 샘플이 1개라도 존재` — 주석의 '왜': *"워치 수면 추적은 inBed 없이 asleep(수면 단계)만 남기는 경우가 많음 — 그런 사용자는 예측 신호가 없어 '지금 덮는 샘플' + 프로필 시간이 기준."* 없으면 리졸버가 기본 22–07 시간대(또는 프로필 수면 창)로 fallback.
- `isInBedSchedule = '지금'을 시간상 덮는 샘플 존재 (inBed 또는 asleep 계열 모두 인정)` — 주석: *"워치가 밤중에 동기화한 실시간 수면 기록으로도 자는 상태를 잡는다."*
- 진단값 3개(24h 내 inBed 개수, 마지막 inBed 시작/종료)도 갱신.

**averageSleepWindow(days: 7) — '최근 수면 시간에 맞추기'** (프로필 화면의 기준 칩에서 사용):
- 지난 N일의 asleep 계열 + inBed 샘플을 **'밤' 단위로 그룹핑**: 키 = `startOfDay(샘플시작 - 12h)` — 자정 넘김 보정 (23시 취침과 01시 취침이 같은 밤).
- 밤마다 (최소 시작, 최대 종료) 구간으로 병합. **밤이 2개 미만이면 nil** (낮잠 오탐 방지).
- 취침 평균: 18:00 기준 상대 분으로 변환해 평균 (자정 wrap 보정: `(분 + 1440 - 18*60) % 1440` 평균 후 역변환). 기상 평균: 자정 기준 분 그대로 평균.
- 반환: `(startHour, startMinute, endHour, endMinute)?`.

**startObservingChanges() — 자동 감지 4종** (각각 중복 등록 방지 nil 체크):
1. **workout 변화** → `fetchWorkouts(days: 1)` + `isLikelyInWorkout = false` (주석: *"HKWorkout 이 commit 됐다 = 운동 종료. HR 추론은 stale 가능성 → 즉시 클리어. resolver 가 HKWorkout 우선이라 이론상 무관하지만 진단/일관성 위해 명시."*) + `SyncCoordinator.syncNow()` (SharedAppState 갱신 + 워치 push + 위젯 reload).
2. **step 변화** → 오늘 걸음/활동분/칼로리 3종 재조회 + syncNow.
3. **sleep 변화** → `fetchInBedSchedule()` + syncNow.
4. **heart rate 변화** → `refreshWorkoutInference()` + syncNow.

원본의 백그라운드 딜레이 정책 주석 7개 항목(entitlement 필요, frequency 강등, completionHandler 필수, ~30초 실행 한도, force-quit 시 안 깨어남, observer long-lived, 권한 필요)은 iOS 전용 제약 — Android 대응은 §5.

**refreshWorkoutInference() — 워치 운동 추론 (HR 빈도 기반):**
- 최근 **90초** HR 샘플 개수 + 평균 bpm 계산.
- 판정: `isLikelyInWorkout = (샘플 5개 이상 / 90초) AND (평균 >= 95 bpm)` — 주석의 '왜': *"평상시 ~1개, 운동중 워치 stream 모드 ~10-30개"* / *"avg >= 95 = 평상시 휴식(60-80)보다 명백히 높음."*
- `recentStepsPerMinute`: 걸음 누적합을 창 길이로 나눈 분당 걸음수를 **10분 창과 3분 창 두 번 재서 max** — 주석의 '왜': *"10분 창은 운동 시작 초반(대부분 정지였던 시간이 분모에 포함)에 과소평가 — 시작 직후엔 3분이, 안정 구간엔 10분이 잡음."* 진행 중 운동의 걷기/달리기 구분용 (HKWorkout 은 운동이 끝나야 생기므로).

---

## 4. 데이터 의존성

- **WeatherManager** → 소비처: 홈 날씨 헤더/데코, `CharacterStateResolver`(날씨 state), `SyncCoordinator` 가 `WatchMessage` 에 실어 보냄 (`weatherEmoji`, `weatherTempC`, `weatherSunrise`, `weatherSunset` — Android 파리티에선 Wear 제외지만 위젯용 SharedAppState 스냅샷 스키마는 동형 유지).
- **캐시**: 메모리 전용 30분 TTL. 디스크 키 없음.
- **HealthKitManager** → 소비처: 홈 '오늘 활동' 카드, `CharacterStateResolver`(운동/수면/기상 판정), 프로필의 '최근 수면 시간에 맞추기' 칩(`averageSleepWindow`), `SyncCoordinator.syncNow()` 경유로 SharedAppState/위젯.
- 저장 위치: 이 모듈 자체는 아무것도 영속하지 않음. 영속은 SyncCoordinator 가 쓰는 `SharedAppState`(App Group UserDefaults → Android: 공용 SharedPreferences/DataStore, 위젯 스펙과 키 동형) 담당.

---

## 5. Android 구현 노트

### 날씨 (`weather/` 패키지)

- **위치**: `FusedLocationProviderClient.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY)` — km 급 정확도 대응. 권한은 `ACCESS_COARSE_LOCATION` **하나만** 요청 (iOS가 좌표를 2자리로 반올림하는 취지와 동일 — coarse 면 충분하고 프라이버시 취지도 지킴). 반올림 로직은 그래도 유지 (coarse 도 2자리보다 정밀할 수 있음).
- **권한 상태 매핑**: `notDetermined` → 아직 안 물어봄(런타임 요청), `denied` → `shouldShowRequestPermissionRationale` 무관하게 에러 문구 세팅 + 설정 이동 유도. iOS의 `authorizationStatus` 프로퍼티는 Compose 쪽에서 `PermissionState` 로 대체.
- **HTTP**: 별도 SDK 없이 `HttpURLConnection` 또는 프로젝트 공용 HTTP 클라이언트 + `kotlinx.serialization`(필드명 `temperature_2m`, `weather_code` 스네이크 그대로 매핑). API 키 불필요 (Open-Meteo 무료).
- **일출/일몰 파싱**: `LocalDateTime.parse(s, DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm"))` 후 `atZone(ZoneId.systemDefault())` — iOS와 동일한 "위치 TZ ≒ 기기 TZ" 가정 유지.
- **상태 홀더**: `WeatherManager` 를 싱글턴 클래스 + `StateFlow<WeatherSnapshot?>` / `isFetching` / `lastError` 로. `@Observable` → StateFlow 가 1:1 대응.
- **캐시**: iOS와 동일하게 메모리 30분 TTL. 디스크 캐시 추가하지 말 것 (파리티).
- tint 색은 Compose Color 로: yellow/gray/blue/cyan/secondary(→ M3 onSurfaceVariant)/purple/gray.

### 건강 (`health/` 패키지) — HealthKit → Health Connect 대응표

| iOS (HealthKit) | Android (Health Connect) | 비고 |
|---|---|---|
| `stepCount` cumulativeSum (오늘) | `StepsRecord` — `aggregate(COUNT_TOTAL)` | 자정~현재 TimeRangeFilter |
| `appleExerciseTime` (오늘 활동 분) | `ExerciseSessionRecord` 지속시간 합산 (또는 미기록 시 0) | **완전 등가물 없음** — Apple 전용 지표. 오늘 운동 세션 duration 합을 분으로 환산해 근사. 세션 없으면 0 |
| `activeEnergyBurned` (오늘 kcal) | `ActiveCaloriesBurnedRecord` — `aggregate(ACTIVE_CALORIES_TOTAL)` | kcal 변환: `Energy.inKilocalories` |
| `HKWorkout` (최근 7일, 20개) | `ExerciseSessionRecord` — `readRecords`, 시작 내림차순 | kcal/거리는 세션 연관 aggregate 또는 `TotalCaloriesBurned`/`Distance` 레코드로 별도 조회. 없으면 nil |
| `HKWorkoutActivityType` | `ExerciseSessionRecord.exerciseType` (Int 상수) | 매핑: RUNNING→달리기, BIKING→자전거, WALKING→걷기, HIKING→등산, SWIMMING_*→수영, YOGA→요가, STRENGTH_TRAINING/WEIGHTLIFTING→근력, 그 외→`운동` |
| `sleepAnalysis` asleep 계열 | `SleepSessionRecord` + `stages` (STAGE_TYPE_SLEEPING/LIGHT/DEEP/REM) | stage 없으면 세션 전체를 asleep 으로 간주 |
| `sleepAnalysis` `inBed` (미래 일정 샘플) | **등가물 없음** | Health Connect 에는 "예정된 수면" 개념이 없음 → `hasSleepSchedule` 는 사실상 항상 false, 리졸버는 프로필 수면 창 fallback 을 탄다. `isInBedSchedule` 는 '지금을 덮는 SleepSessionRecord(또는 AWAKE 아닌 stage)' 존재로만 판정 |
| `heartRate` 90초 빈도 추론 | `HeartRateRecord` — 최근 90초 samples | 판정식 동일: 5+ samples && avg >= 95. 단, Wear OS 미보유 사용자는 HR 스트림 자체가 없어 항상 false — iOS 도 워치 없으면 동일 |
| `HKObserverQuery` + background delivery | **주기 폴링으로 대체**: `WorkManager` `PeriodicWorkRequest` (최소 15분) + 앱 포그라운드 진입 시(`ON_RESUME`) 즉시 재조회 | Health Connect 의 변경 알림 브로드캐스트는 범위 제한적 — 파리티 목적(위젯/상태 갱신)엔 15분 폴링 + 포그라운드 갱신이면 충분. iOS 도 quantity type 은 `.hourly` 강등이라 실질 지연 비슷함 |
| `enableBackgroundDelivery` entitlement | `PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND` (백그라운드 읽기 권한) | Worker 에서 읽으려면 이 권한도 요청 목록에 포함 |
| `requestAuthorization(toShare:[], read:)` | `PermissionController.createRequestPermissionResultContract()` | 읽기 권한 6종: Steps, ExerciseSession, ActiveCaloriesBurned, SleepSession, HeartRate, Distance(워크아웃 거리용) |
| `HKHealthStore.isHealthDataAvailable()` | `HealthConnectClient.getSdkStatus()` — `SDK_UNAVAILABLE`/`SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED` 처리 | minSdk 28 이면 Health Connect 앱 설치 필요 케이스 존재 → 에러 문구(§2 Android 대체) 표시 |
| `isAuthorized` 추론 | `permissionController.getGrantedPermissions()` 로 **정확히 판정** | 추론 불필요. 단 프로퍼티 이름/의미는 유지 |

- **SyncCoordinator.syncNow() 대응**: 공용 `SyncCoordinator` (SharedAppState 스냅샷 갱신 + Glance `updateAll()`)를 각 fetch 후 호출. Wear push 는 범위 제외.
- **시간 계산**: `Calendar.current.startOfDay` → `LocalDate.now().atStartOfDay(zone)`. averageSleepWindow 의 18:00 wrap 산식은 정수 분 연산이라 그대로 이식.
- **"no data → 0" 규칙**: Health Connect aggregate 는 데이터 없으면 null 반환 — `?: 0.0` 으로 동일 의미 보존.
- **주의**: Health Connect 조회는 전부 suspend — 매니저 메서드 시그니처를 iOS 처럼 suspend 로 유지하고 상태는 StateFlow 로 노출.

---

## 6. 제외 항목 (SCOPE.md 기준)

- **Wear OS 연동 전체** — `SyncCoordinator` 의 워치 push, WatchMessage 의 weather* 필드 전송. (SharedAppState 스냅샷 스키마 자체는 위젯용으로 동형 유지.)
- **배경 생성(날씨 배경 AI)** — 날씨 snapshot 을 입력으로 쓰는 AI 배경은 후속. 이 모듈은 snapshot 제공까지만.
- iOS 전용 진단 3종(`inBedSampleCount24h`, `lastInBedSampleStart/End`)은 inBed 등가물이 없으므로 '지금을 덮는 수면 세션' 기준 진단값으로 축소 구현 (홈 진단 화면 스펙에서 소비 시).
- HealthKit 백그라운드 딜리버리의 `.immediate` 실시간성 재현 — Android 는 15분 폴링 + 포그라운드 갱신으로 대체하고 그 이상 쫓지 않음.
