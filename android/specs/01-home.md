# 01 — 홈 화면 + 설정 시트 + 위젯 안내 + 진단 화면

> 진실의 원천: `/Users/seoyoung/Desktop/withu/withu/ContentView.swift`
> 범위 규칙: `android/specs/SCOPE.md` (Wear OS 제외 — 워치 관련 UI는 이 문서에 "제외" 로 표기)

---

## 1. 화면/모듈 구조

### 1.1 홈 화면 (`ContentView` → `HomeScreen`)

세로 스크롤(ScrollView) 안에 VStack(spacing: 20), 좌우 패딩 20, 상단 8. 위에서 아래 순서:

| # | 섹션 | 조건부 노출 |
|---|---|---|
| 1 | 권한 배너 `permissionBanner` | 거절된 권한이 1개 이상일 때만 |
| 2 | 날씨 헤더 `weatherHeader` | 항상 |
| 3 | 캐릭터 히어로 `characterHero` | 항상 (날씨 데코는 `showWeather` 토글 시) |
| 4 | 오늘 활동 카드 `metricsCard` | 항상 (하단 활동 메시지는 비어있지 않을 때만) |
| 5 | 액션 버튼 4개 `actionButtons` | 항상 |
| 6 | 워치 상태 카드 `watchStatusCard` | **Android 제외** (Wear OS 후속) |
| 7 | 마지막 갱신 푸터 `lastUpdateFooter` | 항상 |

- 내비게이션 타이틀: **"with U"** (인라인). 상단 우측 툴바에 톱니(⚙︎, `gearshape.fill`) 버튼 → 설정 시트.
- 배경: 위→아래 LinearGradient `[withuGreen 0.14, characterState.tint 0.04, systemBackground]`. 기조는 브랜드 그린, 상태 무드는 중간에 옅게만.
- 풀스크린 게이트 2겹 (홈 위에 덮음):
  1. `!onboarded` → `OnboardingView` (별도 스펙)
  2. `onboarded && auth.state == .signedOut` → `LoginGateView` — **Android 제외** (Google 로그인 후속). Android 에선 로그인 게이트 없이 진행.
- 첫 실행 사용법 안내 시트: `onboarded && signedIn && !seenGuide` 이면 `HelpGuideView` 자동 표시 (Android 는 로그인 조건 제거 → `onboarded && !seenGuide`). 닫으면 `seenGuide = true` 영구 저장.
- 생성 완료 알림 탭 → 배치 화면(`BatchCharacterGenView`) push. cold start 시에도 진입 시 1회 플래그 확인 (iOS 주석: "종료 상태에서 알림을 탭해 켜진 경우 — onChange 등록 전에 delegate 가 먼저 플래그를 세웠을 수 있어 진입 시 한 번 직접 확인").

### 1.2 설정 시트 (`SettingsView`)

Form(리스트) 스타일, 타이틀 **"설정"** (인라인), 우측 상단 **"닫기"** 버튼. 섹션 순서:

1. **더 만들기** — 캔디 충전 버튼 → 페이월 시트. 푸터에 보유 캔디 수.
2. **애플 워치** `watchSection` — **Android 제외** (전체 섹션).
3. **건강 데이터** `healthSection` — 권한 pill, 다시 묻기, 새로고침, 결과 메시지, 단축어 안내 푸터(→ Android 문구 대체 필요, §5 참고).
4. **알림** `notificationsSection` — 권한 상태, 권한 요청(미허용일 때만), 취침 리마인더, 모두 취소.
5. **(무제목)** — "캐릭터 상태 살펴보기" NavigationLink → `AdvancedDiagnosticsView`. 푸터 설명.
6. **도움말** — 사용법 보기 / 홈 화면·시계 화면에 두기(위젯 안내 시트) / 처음 안내 다시 보기(확인 알럿).
7. **법적 정보** — 개인정보처리방침 / 이용약관 (외부 링크).
8. **계정** — 세션 토큰이 있을 때만 노출. 로그아웃 / 계정 삭제(확인 알럿 + 진행중 스피너 + 실패 알럿). **Android: 로그인 제외 범위이므로 이 섹션 전체 제외** (Google 로그인 도입 시 복원).

시트/알럿:
- `WidgetGuideView` 시트, `HelpGuideView` 시트, `PaywallView` 시트
- "처음 안내 다시 보기" 알럿 — 확인 시 `onboarded = false` 후 시트 닫기 → 온보딩 재진입
- 계정 삭제 확인/실패 알럿 (제외)

### 1.3 위젯 안내 시트 (`WidgetGuideView`)

타이틀 **"홈 화면에 withu 두기"** (인라인), 우측 상단 **"닫기"**. 스크롤 + 카드 3개(아이콘 + 제목 + 번호 매긴 단계 목록, frosted 카드):

1. 홈 화면 위젯 (icon: iphone, tint cyan)
2. 잠금 화면 위젯 (icon: lock.iphone, tint mint) — **Android 제외** (잠금 화면 위젯 개념 없음)
3. 시계 화면에 올리기 (icon: applewatch, tint brown) — **Android 제외** (Wear OS)

Android 는 홈 화면 위젯 1개 카드만, 단계 문구는 Android 절차로 대체 (§5).

### 1.4 진단 화면 (`AdvancedDiagnosticsView`)

설정 → "캐릭터 상태 살펴보기" push. 타이틀 **"캐릭터 상태 살펴보기"** (인라인). Form 섹션 순서:

1. **수면·집중 모드** `focusSection` — **Android 제외** (iOS Focus API 전용. Android 대체안은 §5 참고 — v1 제외)
2. **건강 앱 수면 정보** `healthSleepSection` — 잠자리/수면 기록 통계 + 다시 가져오기
3. **운동 감지** `motionSection` — 운동중 추정 pill, 최근 90초 심박(Health Connect 심박) 통계, 다시 확인
4. **위젯·워치 다시 맞추기** `debugSection` — 마지막 백그라운드 갱신, 상태 직접 고르기 Picker, 위젯 새로고침 버튼. 워치 관련 행(모든 그림 재동기화·보내는 중·마지막 전송)은 **Android 제외**.

---

## 2. 사용자 문구 전량 (한국어 원문, 보간은 %s/%d)

### 2.1 홈

| 위치 | 문구 |
|---|---|
| 내비 타이틀 | `with U` |
| 날씨 헤더 (로딩) | `날씨 가져오는 중…` |
| 날씨 헤더 (값) | `%s %s` (condition.emoji + condition.caption) · `%.0f°` |
| 날씨 토글 접근성 라벨 | `날씨 표시` (labelsHidden — 화면엔 스위치만) |
| 캐릭터 캡션 | `characterState.caption` (CharacterState 스펙에서 정의) |
| 활동 카드 제목 | `오늘 활동` |
| 지표 라벨 | `걸음` / `활동분` / `kcal` / `수면` |
| 지표 값 없음 | `-` |
| 수면 값 포맷 | `%.1fh` |
| 아침 메시지 (랜덤) | `좋은 아침! 오늘도 함께해요 ☀️` |
| | `새 하루 시작이에요 🌱` |
| | `기지개 펴고 시작해봐요 🧘` |
| | `물 한 잔 마시는 거 잊지 마세요 💧` |
| 활발한 날 | `오늘 알찬 하루였네요! 평소보다 많이 움직였어요` |
| 보통 | `오늘 %d보 걸었어요 🌿` |
| 잔잔한 날 (랜덤 1개) | `가벼운 산책 어때요 🌿` |
| 버튼1 | `함께할 캐릭터 생성하기` / `함께할 캐릭터를 만들어요` |
| 버튼2 | `함께 사진 찍기` / `캐릭터와 함께 사진 찍어요` |
| 버튼3 | `캐릭터 갤러리` / `만든 캐릭터를 모아봐요` |
| 버튼4 | `내 캐릭터 설정하기` / `이름 · 수면 · 식사 시간` |
| 푸터 (갱신 있음) | `마지막 갱신 %s` (시각, 시간만 short) |
| 푸터 (없음) | `백그라운드 갱신 대기 중` |

워치 카드 문구 (**제외** — 참고용): `Apple Watch` / `페어링` / `앱 설치` / `연결`

### 2.2 권한 배너

| 위치 | 문구 |
|---|---|
| 권한 이름 | `건강` / `위치` / `알림` |
| 제목 | `%s 권한이 꺼져 있어요` (이름들을 ` · ` 로 join) |
| 부제목 | `기능이 제한될 수 있어요. iOS 설정에서 켤 수 있어요.` → **Android: `기능이 제한될 수 있어요. 설정에서 켤 수 있어요.`** (iOS 명칭 제거 — 문구 변경 최소화, "iOS " 만 삭제) |

### 2.3 설정 시트

| 위치 | 문구 |
|---|---|
| 타이틀 | `설정` / 닫기 버튼 `닫기` |
| 더 만들기 헤더 | `더 만들기` |
| 캔디 충전 | `캔디 충전` |
| 캔디 푸터 | `캔디 %d개 갖고 있어요.` |
| 건강 헤더 | `건강 데이터` |
| 건강 권한 행 | `권한` · pill `허용됨` / `허용 안 됨` |
| 버튼 | `건강 권한 다시 묻기` |
| 버튼 | `오늘 데이터 새로고침` |
| 새로고침 결과 | `최신화 완료` / `실패: %s` (실패 항목: `수면`, `운동`, `걸음`, `활동`, `칼로리` — `, ` join) |
| 건강 푸터 (iOS) | `운동이나 수면을 시작하는 순간 바로 캐릭터를 바꾸고 싶다면, '단축어' 앱의 자동화에서 '운동' 또는 '수면 모드' 트리거에 'withu 앱 열기' 동작을 더해주세요.` → **Android 제외** (단축어 앱 없음; 푸터 생략) |
| 알림 헤더 | `알림` |
| 알림 권한 행 | `권한 상태` · 값 `아직 요청 안 했어요` / `거부됨` / `허용됨` / `—` |
| 버튼 | `알림 권한 요청` |
| 버튼 | `매일 22:30 취침 리마인더 설정` |
| 버튼 (destructive) | `등록된 알림 모두 취소` |
| 진단 링크 | `캐릭터 상태 살펴보기` |
| 진단 푸터 | `집중 모드, 건강 앱 수면 기록, 운동 감지, 백그라운드 갱신 같은 자세한 정보예요. 평소엔 보지 않아도 돼요.` |
| 도움말 헤더 | `도움말` |
| 버튼 | `사용법 보기` |
| 버튼 | `홈 화면·시계 화면에 두기` → **Android: `홈 화면에 두기`** (시계 제외) |
| 버튼 | `처음 안내 다시 보기` |
| 재온보딩 알럿 제목 | `처음 안내 다시 보기` |
| 알럿 본문 | `권한 안내 화면을 처음부터 다시 봐요. 거절한 권한도 다시 한 번 물어볼 수 있어요.` |
| 알럿 버튼 | `다시 보기` / `취소` |
| 법적 정보 헤더 | `법적 정보` |
| 링크 | `개인정보처리방침` (https://kkcdkk.github.io/withu/PRIVACY_POLICY.html) |
| 링크 | `이용약관` (https://kkcdkk.github.io/withu/TERMS_OF_SERVICE.html) |

계정 섹션 문구 (**제외** — 로그인 후속 시 사용): 헤더 `계정` · `로그아웃` · `계정 삭제` · `삭제 중…` · 푸터 `계정·서버 이용 기록과 이 기기에 만든 캐릭터·갤러리를 모두 삭제해요. 충전한 횟수·무료 혜택도 함께 사라지고 되돌릴 수 없어요.` · 알럿 `계정을 삭제할까요?` / `계정과 서버 이용 기록, 이 기기의 캐릭터·갤러리가 모두 삭제돼요. 충전한 횟수·무료 혜택도 사라지며 되돌릴 수 없어요.` / `삭제` / `취소` · 실패 알럿 `계정 삭제 실패` / `확인` / 기본 에러 `삭제에 실패했어요. 잠시 후 다시 시도해 주세요.`

애플 워치 섹션 문구 (**제외**): 헤더 `애플 워치` · `페어링` `앱 설치` `연결 상태` (`연결됨`/`안 됨`/`설치됨`/`대기 중`) · `마지막 전송` · `지금 바로 동기화` · 푸터 `운동(산책·달리기 등)은 워치 기준으로 알아채요.` / `워치가 없으면 아이폰의 움직임으로 운동을 알아채요. 아이폰을 몸에 지니고 있을 때만 감지돼요.` — Android 는 워치 없음 전제이므로 운동 감지 안내가 필요하면 두 번째 문구를 `아이폰` → `휴대폰` 으로 바꿔 건강 섹션 푸터로 이동 가능 (선택).

### 2.4 위젯 안내 시트

| 위치 | 문구 |
|---|---|
| 타이틀 | `홈 화면에 withu 두기` / `닫기` |
| 카드1 제목 | `홈 화면 위젯` |
| 카드1 단계 (iOS 원문) | `홈 화면 빈 곳을 길게 눌러주세요` / `왼쪽 위 더하기 버튼을 눌러주세요` / `검색창에 "withu" 라고 입력해주세요` / `원하는 크기를 골라 추가해주세요` |
| 카드1 단계 (**Android 대체안**) | `홈 화면 빈 곳을 길게 눌러주세요` / `'위젯'을 눌러주세요` / `목록에서 "withu"를 찾아주세요` / `원하는 크기를 골라 추가해주세요` |
| 단계 번호 | `%d.` |

카드2 `잠금 화면 위젯`, 카드3 `시계 화면에 올리기` 전체 — **Android 제외**.

### 2.5 진단 화면 (Android 포함분만)

| 위치 | 문구 |
|---|---|
| 타이틀 | `캐릭터 상태 살펴보기` |
| 수면 정보 헤더 | `건강 앱 수면 정보` |
| 행 | `최근 48시간 잠자리 기록` · `%d개` |
| 행 | `지금 잠자리 시간대` · pill `맞아요` / `아니에요` |
| 행 | `마지막 잠자리 시작` (시각) |
| 행 | `최근 7일 수면 기록` · `%d개` |
| 행 | `마지막 수면 시작` (날짜+시각) |
| 버튼 | `수면 기록 다시 가져오기` |
| 운동 감지 헤더 | `운동 감지` |
| 행 | `운동 중으로 보이나요` · pill `그런 것 같아요` / `아니에요` |
| 행 | `최근 90초 심박 기록` · `%d개` |
| 행 | `평균 심박수` · `분당 %d회` |
| 버튼 | `심박으로 다시 확인` |
| 디버그 헤더 | `위젯·워치 다시 맞추기` → **Android: `위젯 다시 맞추기`** |
| 행 | `마지막 백그라운드 갱신` · 값 없으면 `한 번도 없음` |
| Picker | `상태 직접 고르기` · 기본 옵션 `자동으로 맡기기 (추천)` + 상태별 `state.koreanShortLabel` |
| 버튼 | `위젯 지금 새로고침` |
| 푸터 (iOS) | `백그라운드 갱신은 폰이 앱을 잠깐 깨워 화면을 새로 맞춘 시각이에요. 30분에서 몇 시간 간격으로 폰이 알아서 정해요. 워치 동기화는 앱을 처음 켜거나 워치 앱을 새로 설치하면 한 번 자동으로 이뤄져요.` → **Android: 첫 두 문장만** (워치 문장 삭제) |

수면·집중 모드 섹션 문구 (**제외** — Focus API 없음): 헤더 `수면·집중 모드` · `권한` `현재 집중 모드` `수면 집중 모드 신호` (`받는 중`/`꺼짐`) · `마지막으로 받은 시각` (`아직 없어요`) · `마지막 확인` · `집중 모드 신호 기록 (최근 %d번)` (`수면 켜짐`/`수면 꺼짐`) · `집중 모드 권한 요청` · `지금 다시 확인` · `설정 앱 열기`

---

## 3. 상태(state)와 로직

### 3.1 홈 상태

| 상태 | 타입/초기값 | 저장 | 설명 |
|---|---|---|---|
| `overrideState` | `CharacterState?` = nil | 메모리 | 진단 Picker 로 수동 지정. nil 이면 resolver 자동 |
| `showSettings` | Bool | 메모리 | 설정 시트 |
| `openGenScreenFromNotification` | Bool | 메모리 | 알림 탭 → 배치 화면 push |
| `profile` | `CharacterProfile` | `CharacterProfileStore` 에서 로드; `characterProfileChanged` 브로드캐스트 수신 시 재로드 |
| `imageRefreshKey` | Int = 0 | 메모리 | `characterImageChanged` 수신 시 ++ → 캐릭터 이미지 강제 재로드 (Compose: key 로 recomposition) |
| `activityMessage` | String = "" | 메모리 | 진입/새로고침 시 `computeActivityMessage()` 로 갱신 |
| `onboarded` | Bool, key `withu.onboarded.v1` | 앱 UserDefaults(표준) | 온보딩 완료 |
| `seenGuide` | Bool, key `withu.seenGuide.v1` | 앱 UserDefaults | 사용법 1회 자동 표시 여부 |
| `showGuide` | Bool | 메모리 | 사용법 시트 |
| `showWeather` | Bool = true, key `withu.showWeatherDecoration.v1` | **App Group UserDefaults** (`group.com.seoyoung.withu`) | 캐릭터 옆 날씨 데코 표시. 위젯도 읽을 수 있게 공유 저장소 |

`characterState` (computed):
```swift
overrideState ?? CharacterStateResolver.resolve(sleep:, workouts:, todaySteps:, weather:,
    inSleepSchedule:, hasSleepSchedule:, isFocusActive:, isGenericFocusActive:, focusWokeAt:,
    isLikelyInWorkout:, recentStepsPerMinute:, phoneWorkoutState:, profile:)
```
- `profile.manualSleepOnly == true` 면 수면 자동 감지 신호(inSleepSchedule/hasSleepSchedule/Focus 계열)를 전부 false/nil 로 넘김 — "SyncCoordinator 와 동일 정책".
- iOS 주석의 '왜': Focus 는 어떤 집중 모드인지 구분 못 해 방해금지·업무에도 잠들던 버그 → 수면 전용 신호만 사용. **Android: Focus 계열 파라미터는 항상 false/nil** (resolver 시그니처는 유지해 포팅).

### 3.2 라이프사이클/이벤트 흐름

진입(.task 상당, LaunchedEffect):
1. 연결 활성화 (Android: 생략)
2. 알림 권한 상태 갱신 — **권한 요청은 온보딩에서만**; 여기선 status 갱신 + fetch 만
3. `weather.refresh()`
4. `loadAll()` — 수면 7일, 운동 7일, 오늘 걸음/활동분/kcal, 잠자리 스케줄을 순차 fetch (개별 실패 무시), 이후 위젯/워치 sync + `activityMessage` 재계산
5. `health.startObservingChanges()` (Android: Health Connect 는 push 옵저버 없음 → 폴링으로 대체, §5)
6. `maybeShowGuide()`
7. 알림 탭 cold start 플래그 확인 → 배치 화면 push

onChange 반응:
- `characterState` / `weather.snapshot` / `health.isInBedSchedule` 변경 → `sendStateToWatch` = `SyncCoordinator.syncNow(override:)` (Android: 위젯 갱신 + 공유 상태 저장)
- `health.todaySteps` 변경 → sync + `notifications.scheduleStepGoalIfNeeded(steps:)` (걸음 목표 알림)
- `health.recentWorkouts` 변경 → `notifications.scheduleWorkoutEndedIfNeeded(latest:)` (운동 종료 알림)
- foreground 진입(scenePhase .active) → focus 폴링(제외) + `SyncCoordinator.syncNow`
- 3초 타이머 (active 일 때만): Focus 폴링 — **Android 제외**
- 30초 타이머 (active 일 때만): 잠자리 스케줄 fetch + 운동 추론 갱신 + (워치 미페어링 시) 폰 CoreMotion 활동 분류 + syncNow. '왜': HKObserverQuery 가 미스해도 안전한 catchup; 3초는 store query 부담, 30초가 균형. **Android: 30초 폴링만 이식** (Health Connect 재조회 + 운동 추론 + syncNow)
- `characterProfileChanged` 브로드캐스트 → profile 재로드 + sync
- `characterImageChanged` 브로드캐스트 → `imageRefreshKey++`

엣지 케이스:
- 신규 사용자: 온보딩 직후 로그인 게이트(fullScreenCover)가 떠 있어 그 시점 sheet 표시가 무시됨 → 로그인 완료 시 `maybeShowGuide()` 재시도. Android 는 로그인 게이트가 없어 온보딩 완료 시점 1곳만 처리.
- 알림 탭이 onChange 등록 전에 도착할 수 있음 → 진입 시 플래그 직접 확인 후 소비(플래그 false 로 리셋).
- 같은 메시지 중복 sync 방지는 SyncCoordinator/ConnectivityManager 책임 (홈은 그냥 호출).

### 3.3 날씨 헤더

- `weather.snapshot` 있으면 `이모지 캡션 · 온도(%.0f°)`, 없으면 "날씨 가져오는 중…".
- 미니 스위치: `showWeather` (App Group 저장).
- `weather.isFetching` 이면 미니 스피너, 아니면 ↻ 버튼 → `weather.refresh(force: true)`.

### 3.4 캐릭터 히어로

- 240pt tint 원 (`characterState.tint` 22% 불투명) 위에 200pt `CharacterImageView(state:, animated: true)`.
- `.id("\(state.rawValue)-\(imageRefreshKey)")` — 상태 변경 또는 이미지 변경 시 뷰 강제 재생성.
- `showWeather` 이면 `WeatherDecorationView(condition:, size: 44)` 를 240pt 프레임에 오버레이 (터치 통과). 해/달/구름은 우상단 고정, 비/눈은 영역 전체 떨어짐.
- 캡션: `characterState.caption`, 상태 변경 시 opacity 트랜지션 + snappy 애니메이션.
- `weatherBackgroundCondition` 매핑: 야간 우선 — `CharacterImageStore.isCurrentlyNight(sunrise:, sunset:, fallbackStartMinute: profile.effectiveNightFallbackStart, fallbackEndMinute: profile.effectiveNightFallbackEnd)` 가 true 면 무조건 `.night`. 아니면 sunny→sunny, cloudy→cloudy, rainy·thunder→rainy, snowy→snowy, 그 외 nil(데코 없음).

### 3.5 오늘 활동 카드

- 헤더 행: "오늘 활동" + 새로고침 아이콘 버튼(`RefreshIconButton`, async `loadAll()`).
- 지표 4개 균등폭 + 사이 Divider(높이 32): 👟 걸음(Int) / 🏃 활동분(Int) / 🔥 kcal(Int) / 💤 수면(`%.1fh`, totalAsleep 초÷3600; 없거나 0이면 `-`).
- `computeActivityMessage()` 분기 (시간대 + 활동량):
  - `hour < 11 && kcal < 100` → 아침 메시지 4개 중 랜덤
  - `kcal >= 400 || minutes >= 60 || steps >= 10000` → 활발한 날
  - `kcal >= 150 || steps >= 4000` → `오늘 %d보 걸었어요 🌿`
  - 그 외 → 잔잔한 날 (`가벼운 산책 어때요 🌿`)
  - nil 값은 0 취급. 갱신 시점은 진입 + `loadAll()` 완료 시 (지표 onChange 마다가 아님 — 랜덤 문구가 계속 바뀌지 않도록).

### 3.6 액션 버튼 4개

공통 레이아웃: 44pt 라운드 아이콘 배지(tint 18%) + 제목/부제목 + chevron, frosted 카드. NavigationLink push:
1. 캐릭터 생성 (`CharacterGenView`) — icon `wand.and.stars`, tint withuPink
2. 함께 사진 찍기 (`CameraView`) — icon `camera.fill`, tint withuGreen
3. 갤러리 (`CharacterGalleryView`) — icon `photo.stack`, tint mint
4. 프로필 (`CharacterProfileView`) — icon `person.crop.circle.fill`, tint brown

### 3.7 마지막 갱신 푸터

App Group UserDefaults key **`withu.lastBackgroundRefreshAt`** (Date) 읽기. 있으면 "마지막 갱신 {시각}", 없으면 "백그라운드 갱신 대기 중". 10pt, tertiary. '왜': BG refresh(WorkManager 상당)가 정상 작동 중인지 한눈에.

### 3.8 권한 배너

`deniedPermissions` 계산:
- `!health.isAuthorized` → "건강"
- 위치 권한 denied/restricted → "위치"
- 알림 권한 denied → "알림"

비어있지 않으면 주황 배너 (⚠️ + 제목 + 부제목 + chevron, orange 12% 배경). 탭 → 시스템 설정 앱의 이 앱 설정 열기 (iOS `openSettingsURLString`).

### 3.9 설정 시트 로직

- 캔디 푸터: `GenerationQuota.displayedCandy()` — 로컬 권위 잔액 (DEBUG 는 9999).
- 건강 "다시 묻기": `health.requestAuthorization()` (Health Connect 권한 시트).
- "오늘 데이터 새로고침" `reloadHealth()`: 5종 fetch 각각 try, 실패 항목명 수집 → `최신화 완료` 또는 `실패: 수면, 걸음` 식 메시지. 진행 중엔 버튼 disabled.
- 알림: 권한 상태 라벨 3분기, 미허용 시 요청 버튼. `scheduleBedtimeReminder()` = 매일 22:30 반복 로컬 알림. `cancelAll()` = 등록 알림 전부 취소.
- "처음 안내 다시 보기" 확인 → `onboarded = false` + dismiss → 홈의 온보딩 게이트가 다시 뜸. 재온보딩에서 거절한 권한 재요청 가능하다는 안내가 알럿 본문.
- 법적 링크는 외부 브라우저.

### 3.10 진단 화면 로직

- `overrideState` Picker: nil = 자동. 선택 시 홈 characterState 가 즉시 override 로 바뀜 (binding 공유). **영속 아님** — 앱 재시작 시 자동 복귀.
- "위젯 지금 새로고침": sync + 위젯 전체 리로드 (iOS 는 kind 별 reload 도 추가 호출 — Android 는 Glance `updateAll`).
- 수면/운동 통계 행은 HealthKitManager 의 파생 상태 노출: `inBedSampleCount24h`(이름과 달리 48시간 창), `isInBedSchedule`, `lastInBedSampleStart`, `sleep.sampleCount`, `sleep.lastNight`, `isLikelyInWorkout`, `recentHRSampleCount`, `recentHRAverage`.
- `RefreshRowButton` = 실행 중 스피너 붙는 async 행 버튼.

---

## 4. 데이터 의존성

| 의존성 | iOS | 읽기/쓰기 | Android 대응 |
|---|---|---|---|
| 건강 데이터 | `HealthKitManager.shared` | 수면 7일 / 운동 7일 / 오늘 걸음·활동분·kcal / 잠자리 스케줄 / 심박 90초 | `HealthManager` (Health Connect) |
| 날씨 | `WeatherManager.shared` (`snapshot`, `isFetching`, `authorizationStatus`, `refresh(force:)`) | 메모리 + 캐시 | Open-Meteo + FusedLocation (SCOPE: 위치 반올림 2자리) |
| 알림 | `NotificationManager.shared` | 권한 상태, 취침/걸음목표/운동종료 알림, `wantsOpenGenerationScreen` 플래그 | `NotificationManager` (NotificationManagerCompat + AlarmManager/WorkManager) |
| 캐릭터 프로필 | `CharacterProfileStore.load()` + `.characterProfileChanged` 알림 | 로드 전용 (편집은 프로필 화면) | DataStore/SharedPreferences + Flow 브로드캐스트 |
| 캐릭터 이미지 | `CharacterImageStore` (`.characterImageChanged` 알림, `isCurrentlyNight`) | 읽기 | 동형 스키마 `characters/<state>.png`, `gallery/<uuid>.png` + `metadata.json` |
| 상태 결정 | `CharacterStateResolver.resolve(...)` 순수 함수 | — | Kotlin 포팅 (now/calendar 주입 유지) |
| 동기화 | `SyncCoordinator.syncNow(override:)` | 위젯+워치 갱신 트리거 | 위젯 갱신 + SharedAppState 저장만 (워치 제외) |
| 캔디 | `GenerationQuota.displayedCandy()` | App Group UserDefaults | SharedPreferences 포팅 (SCOPE: 로컬 권위) |
| 설정값 키 | `withu.onboarded.v1` / `withu.seenGuide.v1` (표준 UserDefaults) · `withu.showWeatherDecoration.v1` / `withu.lastBackgroundRefreshAt` (App Group `group.com.seoyoung.withu`) | R/W | 표준 → 앱 SharedPreferences, App Group → 위젯과 공유 가능한 SharedPreferences (같은 프로세스라 파일 하나로 충분; 키 이름 동일 유지) |
| 인증 | `AuthManager` / `KeychainStore` | 세션 토큰 | **제외** |
| 워치 | `ConnectivityManager.shared` | 페어링/설치/reachable/전송 상태 | **제외** |
| 집중 모드 | `FocusModeManager.shared` | 수면 Focus 필터 | **제외** |

---

## 5. Android 구현 노트

- **화면**: 단일 Activity + Compose Navigation. 홈 = `HomeScreen`, 설정은 iOS 시트 느낌 유지하려면 `ModalBottomSheet` 대신 **전체화면 다이얼로그/별도 route** 권장 (Form 이 길어서 바텀시트 부적합).
- **Form 스타일**: M3 에 Form 없음 — 섹션 헤더(라벨 텍스트) + Card 리스트 + 푸터 캡션으로 재현. `StatusPill` 은 AssistChip 또는 커스텀 Surface.
- **frosted material**: `.regularMaterial` 대응 없음 — 반투명 surfaceColor + 낮은 elevation 로 근사 (blur 는 성능상 생략).
- **HealthKit → Health Connect**: 걸음 `StepsRecord`, 활동분 `ExerciseSessionRecord` 합산(또는 `ActiveCaloriesBurnedRecord` 기반), kcal `ActiveCaloriesBurnedRecord`, 수면 `SleepSessionRecord`, 심박 `HeartRateRecord`. `startObservingChanges()` 같은 옵저버 없음 → 홈의 30초 폴링(수명주기 aware, `LaunchedEffect` + `while(isActive)`)이 유일한 갱신 경로. `isInBedSchedule` 은 Health Connect 에 '잠자리 스케줄' 개념이 없어 최근 SleepSession(진행 중 판단) + 프로필 sleep window 로 근사.
- **잠자리/수면 신호**: iOS 의 Focus 필터·HKCategory inBed 조합 대신 (1) 프로필 sleep window (2) Health Connect SleepSession 만 사용. `manualSleepOnly` 플래그 로직은 동일 유지.
- **CoreMotion 활동 분류**: Google `ActivityRecognition` API (권한 `com.google.android.gms.permission.ACTIVITY_RECOGNITION`) 로 대체 가능 — v1 은 걸음 페이스(`recentStepsPerMinute`) 기반만으로 시작해도 무방.
- **위젯 갱신**: `WidgetCenter.reloadAllTimelines()` → Glance `GlanceAppWidgetManager` + `updateAll()`. `SyncCoordinator.syncNow` 의 Android 판은 (상태 resolve → SharedAppState 저장 → 위젯 update) 로 축소.
- **백그라운드 갱신**: BGAppRefresh → WorkManager 주기 작업(15분 최소). 성공 시 `withu.lastBackgroundRefreshAt` 기록 (푸터/진단이 읽음).
- **알림**: `UNUserNotificationCenter` → 채널 분리 권장 (리마인더/생성완료). 취침 리마인더 22:30 반복은 `AlarmManager.setRepeating` 또는 WorkManager. 알림 탭 → 배치 화면 딥링크는 PendingIntent + Navigation deep link (`withu://gen/batch` 등) — iOS 의 `wantsOpenGenerationScreen` 플래그 패턴 불필요.
- **권한 배너**: 건강 = Health Connect `getGrantedPermissions` 부족, 위치 = `ACCESS_COARSE_LOCATION` denied, 알림 = `POST_NOTIFICATIONS` denied (API 33+). 탭 → `Settings.ACTION_APPLICATION_DETAILS_SETTINGS` (건강은 Health Connect 설정 화면이 더 정확하나 v1 은 앱 설정으로 통일).
- **설정 앱 열기 URL**: `UIApplication.openSettingsURLString` → 위 인텐트.
- **@AppStorage**: SharedPreferences + `remember`/DataStore Flow. 키 문자열은 iOS 와 동일하게 유지 (`withu.onboarded.v1` 등) — 크로스 참조 디버깅 편의.
- **NotificationCenter 브로드캐스트** (`characterProfileChanged`/`characterImageChanged`): 싱글턴 저장소에 `MutableSharedFlow` 노출로 대체.
- **타이머**: `Timer.publish` → `LaunchedEffect` 내 delay 루프. scenePhase 가드 → `Lifecycle.repeatOnLifecycle(STARTED)`.
- **랜덤 메시지**: iOS 는 재계산 시점에만 랜덤 — Compose 에서 recomposition 마다 바뀌지 않게 state 에 저장 (iOS 와 동일하게 `activityMessage` 를 상태로 유지).
- **애니메이션**: `.animation(.snappy)` → `animateContentSize`/`Crossfade` (캡션은 `AnimatedContent` fade).
- **DEBUG 런치 인자** (`--paywall` 등): 필요 시 `adb shell am start -e screen paywall` 스타일 intent extra 로 대응 (선택 구현).

## 6. 제외 항목 (SCOPE.md 기준)

- **워치 상태 카드** (홈 §1.1-6) 전체 — Wear OS 후속
- **설정 → 애플 워치 섹션** 전체
- **설정 → 계정 섹션** (로그아웃/계정 삭제) — Google 로그인 후속
- **로그인 게이트** (`LoginGateView` fullScreenCover) 및 `auth.restore()`
- **집중 모드(Focus)** 관련 전부 — resolver 의 focus 파라미터는 false/nil 고정, 진단의 수면·집중 모드 섹션 제외, 3초 폴링 제외
- **위젯 안내의 잠금 화면·시계 화면 카드** — 홈 화면 위젯 카드만
- **워치 이미지 재동기화/전송 상태 행** (진단 debugSection 내)
- **CoreMotion 폰 활동 분류** — v1 은 걸음 페이스 기반으로 근사 (후속 검토)
- **Play 결제 실구매** — 페이월은 표시하되 구매 버튼 '준비 중' (SCOPE)
