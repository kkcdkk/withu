# 06 — 온보딩 + 사용법 안내 (OnboardingView / HelpGuideView)

진실의 원천:
- `withu/OnboardingView.swift` (Color 팔레트 extension 포함)
- `withu/HelpGuideView.swift`
- 게이팅/영속화: `withu/ContentView.swift` (`@AppStorage` 플래그)
- 공용 컴포넌트: `withu/Design/VibeKit.swift` (`StatusPill`, `StatusKind`, `WithuCTAButtonStyle`)

---

## 1. 화면/모듈 구조

### 1-A. OnboardingView — 첫 실행 전체화면(fullScreenCover) multi-step

스텝 enum (순서 고정):

```swift
private enum OnboardingStep: Int, CaseIterable {
    case welcome, health, location, notification, focus, done
}
```

위→아래 레이아웃 (모든 스텝 공통 골격):

1. **진행 바** — `step != .welcome` 일 때만 노출. 캡슐 5개(welcome 제외한 스텝 수), `i <= step.progressIndex` 이면 `withuPink`, 아니면 `secondary.opacity(0.2)`. 높이 4, 좌우 패딩 24, 상단 12.
2. **본문 content** — 스텝별로 교체, `transition(.opacity)` + `.snappy` 애니메이션. 스텝 변경 시 뷰 identity 교체(`.id(step)`).
3. **하단 bottomBar** — 좌우 패딩 24, 하단 24.
4. **배경** — 세로 LinearGradient `withuPinkBackground → systemBackground`, safe area 무시.

#### welcome 스텝
- 원(240×240, `withuPink.opacity(0.22)`) 안에 `pawprint.fill` 아이콘 80pt, 색 `withuPinkText`
- 타이틀 "with U" + 서브 "내 캐릭터가 일상에 함께해요"
- 기능 소개 3행 (featureRow: 40×40 라운드 아이콘 칩 + 제목 + 설명):
  | 아이콘 | tint | 제목 | 설명 |
  |---|---|---|---|
  | wand.and.stars | withuPink | 내 캐릭터 만들기 | 원하는 외형과 성격으로 캐릭터를 만들어요 |
  | heart.text.square.fill | mint | 건강 데이터 연동 | 운동·수면·걸음에 맞춰 캐릭터 상태가 바뀌어요 |
  | applewatch | cyan | 워치 동기화 | 애플워치 시계 화면과 메인 화면에도 함께해요 |
- 하단 버튼: **"시작할게요"** → `advance()`

#### 권한 스텝 4개 — 공통 템플릿 `permissionPage(icon:tint:title:body:details:result:skipNote:)`
위→아래: 원형 아이콘(120×120, tint 22% 배경 + 48pt 아이콘) → 제목(title3 semibold) → 본문(callout, secondary, 가운데 정렬) → 상세 불릿 리스트(아이콘 18pt 폭 + caption 텍스트) → (있으면) skipNote(caption2) → (요청 결과 있으면) StatusPill.

하단 bar (권한 스텝 공통):
- primary 버튼: 평소 **"허용하고 다음으로"**, 요청 중이면 **"요청 중…"** (`.disabled`)
- `result == .pending` 일 때만 그 아래 텍스트 버튼 **"건너뛰기"** (footnote, secondary)

| 스텝 | 아이콘 | tint | 제목 | 본문 |
|---|---|---|---|---|
| health | heart.text.square.fill | mint | 건강 데이터 | 걸음·운동·수면 데이터를 캐릭터 상태에 반영해요. |
| location | cloud.sun.fill | cyan | 지금 날씨를 받아올게요 | 현재 위치의 날씨를 받아 배경에 반영해요. |
| notification | bell.badge.fill | orange | 알림 | 걸음 목표 달성·잠잘 시간·운동 종료를 알려드려요. |
| focus | moon.zzz.fill | indigo | 캐릭터와 함께 수면 | 수면 집중 모드를 감지해 캐릭터를 재워줘요. |

상세 불릿 (문구 전량, §2 참조). skipNote 는 health 스텝에만 있음.

#### done 스텝
- 원(120×120, withuPink 22%) + `checkmark.circle.fill` 48pt (`withuPinkText`)
- "준비가 끝났어요" / "이제 내 캐릭터를 만들어 봐요"
- 요약 카드 (regularMaterial, 라운드 16): 4행 `summaryRow` — 라벨 + StatusPill
  - 라벨: "건강 데이터" / "날씨" / "알림" / "수면 감지"
  - Pill 짧은 라벨: granted→"연결됨", denied/skipped→"나중에", pending/requesting→"아직"
- 푸터 caption2: "켜지 않은 권한은 메인 화면 설정에서 다시 켤 수 있어요."
- 하단 버튼: **"캐릭터 만들러 가기"** → `onComplete()`

### 1-B. HelpGuideView — 사용법 안내 시트(sheet)

NavigationStack + ScrollView. 위→아래:
1. 헤더: "withu 사용법" (title2 bold) + "캐릭터를 만들고 내 하루에 맞춰 보여줘요." (callout, secondary)
2. 스텝 카드 5개 (각각 regularMaterial 라운드 14 카드, 아이콘 32×32 `withuPinkText` + 제목 + 본문 footnote secondary)
3. **"확인"** 버튼 (WithuCTAButtonStyle = 초록 CTA) → `onDone()`
4. 내비게이션 타이틀 "사용법" (inline), 우상단 툴바 버튼 **"닫기"** → `onDone()`

조건부 노출 없음 — 항상 5개 스텝 전부 표시.

---

## 2. 사용자 문구 전량 (한국어 원문 그대로)

### OnboardingView

| 키(제안) | 문구 |
|---|---|
| onboarding_welcome_title | with U |
| onboarding_welcome_subtitle | 내 캐릭터가 일상에 함께해요 |
| onboarding_feature1_title | 내 캐릭터 만들기 |
| onboarding_feature1_desc | 원하는 외형과 성격으로 캐릭터를 만들어요 |
| onboarding_feature2_title | 건강 데이터 연동 |
| onboarding_feature2_desc | 운동·수면·걸음에 맞춰 캐릭터 상태가 바뀌어요 |
| onboarding_feature3_title | 워치 동기화 |
| onboarding_feature3_desc | 애플워치 시계 화면과 메인 화면에도 함께해요 |
| onboarding_start | 시작할게요 |
| onboarding_health_title | 건강 데이터 |
| onboarding_health_body | 걸음·운동·수면 데이터를 캐릭터 상태에 반영해요. |
| onboarding_health_detail1 | 운동을 시작하면 캐릭터도 같이 운동해요 |
| onboarding_health_detail2 | 잠든 시간에는 캐릭터도 잠들어요 |
| onboarding_health_detail3 | 허용하지 않으면 시간대만 보고 움직여요 |
| onboarding_health_skip_note | 허용해도 데이터는 기기 안에서만 처리돼요. |
| onboarding_location_title | 지금 날씨를 받아올게요 |
| onboarding_location_body | 현재 위치의 날씨를 받아 배경에 반영해요. |
| onboarding_location_detail1 | 비·눈·맑음·밤에 따라 배경이 바뀌어요 |
| onboarding_location_detail2 | 위치는 기기 안에서만 쓰고 서버에 저장하지 않아요 |
| onboarding_location_detail3 | 허용하지 않으면 배경 없이 캐릭터만 보여요 |
| onboarding_notification_title | 알림 |
| onboarding_notification_body | 걸음 목표 달성·잠잘 시간·운동 종료를 알려드려요. |
| onboarding_notification_detail1 | 방해되지 않게 하루 몇 번만 보내요 |
| onboarding_notification_detail2 | 허용하지 않아도 주요 기능은 모두 작동해요 |
| onboarding_focus_title | 캐릭터와 함께 수면 |
| onboarding_focus_body | 수면 집중 모드를 감지해 캐릭터를 재워줘요. |
| onboarding_focus_detail1 | 설정에서 집중·수면 필터에 withu 를 연결하면 더 정확해요 |
| onboarding_focus_detail2 | 연결 방법은 메인 화면 설정에서 다시 볼 수 있어요 |
| onboarding_focus_detail3 | 허용하지 않으면 프로필에 적은 수면 시간만 써요 |
| onboarding_request_button | 허용하고 다음으로 |
| onboarding_requesting | 요청 중… |
| onboarding_skip | 건너뛰기 |
| onboarding_status_granted | 연결되었어요 |
| onboarding_status_later | 나중에 설정에서 켤 수 있어요 |
| onboarding_done_title | 준비가 끝났어요 |
| onboarding_done_subtitle | 이제 내 캐릭터를 만들어 봐요 |
| onboarding_summary_health | 건강 데이터 |
| onboarding_summary_weather | 날씨 |
| onboarding_summary_notification | 알림 |
| onboarding_summary_sleep | 수면 감지 |
| onboarding_summary_connected | 연결됨 |
| onboarding_summary_later | 나중에 |
| onboarding_summary_pending | 아직 |
| onboarding_done_footer | 켜지 않은 권한은 메인 화면 설정에서 다시 켤 수 있어요. |
| onboarding_finish | 캐릭터 만들러 가기 |

주의: denied 와 skipped 는 같은 문구("나중에 설정에서 켤 수 있어요" / "나중에")를 쓰지만 StatusPill 종류가 다르다 — denied = warning(주황 삼각형), skipped = off(회색 X).

### HelpGuideView

| 키(제안) | 문구 |
|---|---|
| help_nav_title | 사용법 |
| help_title | withu 사용법 |
| help_subtitle | 캐릭터를 만들고 내 하루에 맞춰 보여줘요. |
| help_step1_title | 1. 캐릭터 만들기 |
| help_step1_body | '여러 모습 만들기'로 한 캐릭터의 여러 상태를 한 번에, 또는 '단건'으로 하나씩 만들어요. 참고 사진을 넣으면 그 모습을 살려서 그려요. |
| help_step2_title | 2. 상태별로 적용하기 |
| help_step2_body | 만든 모습을 '적용'하면 지금 상태(자는 중·산책·식사 등)에 맞춰 홈·위젯·워치에 그 캐릭터가 나와요. 갤러리 '캐릭터별'에서 '이 캐릭터로 모두 적용'으로 한 번에 다 적용할 수도 있어요. |
| help_step3_title | 3. 홈·잠금화면 위젯 추가 |
| help_step3_body | 홈 화면이나 잠금 화면을 길게 눌러 위젯을 추가하면, 캐릭터와 걸음·수면 같은 정보가 위젯에 떠요. |
| help_step4_title | 4. 애플워치에 추가 |
| help_step4_body | 워치 페이스를 길게 눌러 편집 → 컴플리케이션 칸에 withu를 넣으면 시계 화면에도 캐릭터가 나와요. 산책·달리기 같은 운동은 워치가 연결돼 있으면 워치(심박)로, 워치가 없으면 아이폰의 움직임으로 알아채요. |
| help_step5_title | 5. 캔디 |
| help_step5_body | 캐릭터를 만들 땐 캔디를 써요 — 한 장에 1개, 움직이는 캐릭터는 2개예요. 캔디는 상점에서 충전할 수 있어요. |
| help_confirm | 확인 |
| help_close | 닫기 |

**Android 문구 조정 판단 필요 (원문 유지 원칙과의 충돌 지점, 임의 변경 금지 — 사용자 확정 필요):**
- help_step3 "홈 화면이나 잠금 화면을…" — Android 는 잠금화면 위젯이 없음(홈 위젯만). 파리티 원칙상 iOS 원문 유지가 기본이나, 사실과 다르므로 확인 요망.
- help_step4 "애플워치…" — Wear OS 는 SCOPE 제외 항목. 스텝 자체 노출 여부 확인 요망 (제외 시 스텝 번호 재조정 필요: 5. 캔디 → 4. 캔디).
- 온보딩 welcome feature3 "워치 동기화" / focus 스텝(집중 모드)도 동일 이슈 (§6 참조).
- 보간(\(x)) 은 이 두 파일에 없음 — 전 문구 정적.

---

## 3. 상태(state)와 로직

### OnboardingView

```swift
struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var step: OnboardingStep = .welcome
    @State private var healthResult: PermissionResult = .pending
    @State private var locationResult: PermissionResult = .pending
    @State private var notificationResult: PermissionResult = .pending
    @State private var focusResult: PermissionResult = .pending
}
```

```swift
private enum PermissionResult { case pending, requesting, granted, denied, skipped }
```

- **PermissionResult → StatusPill 매핑**: pending/requesting → 표시 안 함(nil), granted → ok(초록 체크), denied → warning(주황 경고), skipped → off(회색 X).
- **advance()**: 다음 스텝으로. 마지막(done)에서 호출되면 `onComplete()` — 방어 로직이지만 실제 done 버튼이 직접 onComplete 를 부른다.
- **"허용하고 다음으로"**: 해당 매니저에 권한 요청 → 결과를 result 에 반영 → **0.5초 대기 후 자동 advance()** (결과 pill 이 잠깐 보이도록 하는 의도). 요청 중엔 버튼 비활성 + 라벨 "요청 중…".
- **"건너뛰기"**: result 를 `.skipped` 로 표시하고 즉시 advance(). 요청을 이미 시작했으면(pending 아님) 건너뛰기 버튼 숨김.
- **설계 의도(원본 파일 주석)**: "권한 4종을 한 번에 우르르 요청하지 않고 각자 한 페이지씩, 거절해도 흐름 막히지 않게." — 거절/건너뛰기가 절대 진행을 막지 않는다.

권한별 요청 로직:

1. **health** — `HealthKitManager.shared.requestAuthorization()`; throw 하면 denied. (참고: iOS HealthKit 은 실제 허용 여부를 숨기므로 요청 성공 = granted 로 취급.)
2. **location** — `WeatherManager.shared.refresh(force: true)` 가 권한 시트를 띄우고, **0.5초 간격 최대 20회(10초) 폴링**으로 `authorizationStatus` 관찰. authorizedWhenInUse/Always → granted, denied/restricted → denied. 10초 지나도 미정이면 `.skipped` 처리(엣지 케이스: 사용자가 시트 무시). 그 후 0.5초 대기 → advance.
3. **notification** — `NotificationManager.shared.requestAuthorization()` 후 status 가 authorized/provisional 이면 granted.
4. **focus** — `FocusModeManager.shared.requestAuthorization()` 후 `isAuthorized` 로 판정. (iOS 집중 모드 감지 — Android 대응은 §5/§6.)

엣지 케이스:
- 이미 시스템에서 거절된 권한은 시트 없이 즉시 denied 로 돌아온다 → pill "나중에 설정에서 켤 수 있어요" 표시 후 자동 진행.
- 뒤로가기 없음 — 스텝은 앞으로만 간다.

### HelpGuideView

- 상태 없음. `onDone: () -> Void` 하나. "확인"과 "닫기" 둘 다 onDone 호출.

### 게이팅/영속화 (ContentView.swift)

```swift
@AppStorage("withu.onboarded.v1") private var onboarded: Bool = false
@AppStorage("withu.seenGuide.v1") private var seenGuide: Bool = false
@State private var showGuide: Bool = false
```

- `!onboarded` 이면 OnboardingView 를 fullScreenCover 로 강제 표시 (dismiss 불가 — set 무시). `onComplete` 에서 `onboarded = true`.
- 온보딩 완료 후 로그인 게이트(LoginGateView)가 뜨고, **로그인 완료 && !seenGuide** 이면 HelpGuideView 자동 표시 (`maybeShowGuide()`). onDone 에서 `seenGuide = true`.
- 설정 메뉴에서 HelpGuideView 를 언제든 다시 열 수 있음 (이때 onDone 은 닫기만, seenGuide 재기록 없음).
- 설정에 `onboarded = false` 리셋 경로 존재 (온보딩 다시 보기).

---

## 4. 데이터 의존성

| 항목 | iOS | Android 대응 |
|---|---|---|
| `withu.onboarded.v1` (Bool) | 표준 UserDefaults (@AppStorage) | 일반 SharedPreferences 또는 DataStore — App Group 공유 불필요 (위젯이 안 읽음) |
| `withu.seenGuide.v1` (Bool) | 표준 UserDefaults | 상동 |
| HealthKitManager | 권한 요청만 | Health Connect 권한 요청 |
| WeatherManager | 위치 권한 트리거 + status 폴링 | FusedLocation / 위치 권한 |
| NotificationManager | UNUserNotificationCenter | POST_NOTIFICATIONS (API 33+) |
| FocusModeManager | INFocusStatusCenter | 대응물 없음 — §6 |

두 화면 모두 CharacterImageStore/SharedAppState/서버를 직접 읽지 않는다. 문구·아이콘·플래그 2개가 전부.

---

## 5. Android 구현 노트

- **화면**: 단일 `OnboardingScreen` composable + `OnboardingStep` enum, `Crossfade(targetState = step)` 로 iOS 의 opacity transition 재현. 전체화면 강제는 홈 NavHost 진입 전 분기 (`if (!onboarded) OnboardingScreen(...)`) — 시스템 뒤로가기는 무시하거나 앱 종료(BackHandler 로 스텝 후퇴 없음, iOS 와 동일하게 전진만).
- **권한 대응물**:
  - health → **Health Connect**: `PermissionController.createRequestPermissionResultContract()` (걸음 READ_STEPS, 수면 READ_SLEEP, 운동 READ_EXERCISE). Health Connect 미설치 기기면 결과를 denied 로 처리하고 진행(흐름 안 막기 원칙).
  - location → `ACCESS_COARSE_LOCATION` (SCOPE: 반올림 2자리라 coarse 로 충분) — `rememberLauncherForActivityResult(RequestPermission)`. iOS 의 10초 폴링은 불필요 — Android 는 결과 콜백이 동기적으로 온다. 콜백 후 500ms delay → advance 만 유지.
  - notification → API 33+ `POST_NOTIFICATIONS` 런타임 권한. API 32 이하는 권한 개념 없음 → 즉시 granted 처리하고 pill 표시 후 진행.
  - focus → **직접 대응물 없음** (§6에서 제외). 스텝 자체를 뺄지, DND(NotificationListener/`NotificationManager.isNotificationPolicyAccessGranted`) 로 대체할지 사용자 확정 필요. 기본 제안: **이번 파리티에서는 focus 스텝 생략** (진행 바 캡슐 4개, done 요약 3행).
- **자동 진행 딜레이**: 각 요청 결과 후 `delay(500)` → advance — iOS 의 `Task.sleep(seconds: 0.5)` 그대로.
- **StatusPill**: 공용 composable 로 포팅 (다른 스펙 화면들도 사용). ok = `Icons.Filled.CheckCircle` 초록, warning = `Icons.Filled.Warning` 주황, off = `Icons.Filled.Cancel` 회색. 텍스트는 secondary 색 caption.
- **WithuCTAButtonStyle**: 초록 CTA — 배경 `withuCTAGreen`, 흰 글자, 라운드 12, 눌림 시 검정 22% 오버레이 + scale 0.97 (`interactionSource` + `animateFloatAsState`). 비활성 opacity 0.45.
- **primaryButton(온보딩 전용)**: 배경은 CTA 그린이 아니라 **withuPink** + 흰 글자, 라운드 14 — HelpGuide 의 "확인"(그린)과 다르다는 점 주의.
- **HelpGuideScreen**: `ModalBottomSheet` 또는 전체 화면 다이얼로그 — iOS sheet 감성 유지하려면 `ModalBottomSheet(skipPartiallyExpanded)` 권장. TopAppBar title "사용법" + actions 에 "닫기" TextButton.
- **regularMaterial 카드**: `Surface(color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha=…))` 또는 `surfaceContainerHigh`, 라운드 14/16. 블러 재현은 불필요.
- **SF Symbol → 대체**: pawprint.fill(커스텀 벡터 필요), wand.and.stars→AutoFixHigh, heart.text.square.fill→MonitorHeart, applewatch→Watch, cloud.sun.fill→WbCloudy(또는 커스텀), bell.badge.fill→NotificationsActive, moon.zzz.fill→Bedtime, checkmark.circle.fill→CheckCircle, square.grid.2x2.fill→GridView, sparkles→AutoAwesome, figure.run→DirectionsRun, moon.fill→DarkMode, clock→Schedule, cloud.rain.fill→WaterDrop/Umbrella, lock.shield.fill→Shield, person.fill→Person, hand.raised.fill→PanTool, checkmark.circle→CheckCircleOutline, gearshape→Settings, bed.double.fill→Bed.

### Color 팔레트 (OnboardingView.swift 하단 extension — 앱 전역 테마의 원천)

sRGB 0–1 → hex 변환값 포함. Compose 에선 `isSystemInDarkTheme()` 분기 or M3 ColorScheme 커스텀 토큰.

| 이름 | Light | Dark | 용도 (원본 주석) |
|---|---|---|---|
| withuPink | (1.0, 0.78, 0.85) `#FFC7D9` | (0.55, 0.32, 0.42) `#8C526B` | 메인 핑크. 라이트=파스텔, 다크=채도 낮은 와인. 면적(버튼 배경)용 |
| withuPinkSoft | (1.0, 0.85, 0.92) `#FFD9EB` | (0.45, 0.28, 0.36) `#73475C` | 캐릭터 원 배경, soft chip 배경 등 더 옅은 톤 |
| withuPinkText | (0.78, 0.32, 0.47) `#C75278` | (0.95, 0.62, 0.72) `#F29EB8` | 글자·링크·배지 텍스트용 진한 로즈 — 파스텔 핑크는 글자 대비가 낮아 안 읽힘. 면적=withuPink, 텍스트=이것 |
| withuCTAGreen | (0.20, 0.78, 0.35) `#33C759` | (0.16, 0.62, 0.29) `#299E4A` | CTA 버튼용 진한 그린(아이폰 메시지 초록 톤). 흰 글자 대비 확보 |
| withuGreen | (0.55, 0.80, 0.58) `#8CCC94` | (0.30, 0.48, 0.36) `#4D7A5C` | 브랜드 그린 — 새싹 캐릭터 색. 배경 그라데이션 기조 |
| withuPinkBackground | (1.0, 0.95, 0.97) `#FFF2F7` | (0.12, 0.08, 0.10) `#1F141A` | 온보딩 배경 gradient 상단 — 거의 흰 핑크 / 매우 어두운 와인 |

시스템 색 사용처: mint(건강 tint), cyan(위치/워치 tint), orange(알림 tint), indigo(수면 tint), green/orange/secondary(StatusPill). Compose 에서 상수 정의 필요 (iOS 시스템 값 근사: mint `#00C7BE`, cyan `#32ADE6`, orange `#FF9500`, indigo `#5856D6`, green `#34C759`).

---

## 6. 제외 항목 (SCOPE.md 기준)

- **focus(수면 집중 모드) 스텝** — iOS INFocusStatus 전용 개념. Android 직접 대응물 없음. 이번 파리티에서 스텝 생략 제안 (done 요약의 "수면 감지" 행도 함께 제거). 수면 판정은 CharacterStateResolver 의 프로필 sleep window + Health Connect 수면으로 커버됨 → focus_detail3 문구("허용하지 않으면 프로필에 적은 수면 시간만 써요")가 곧 Android 의 기본 동작.
- **Wear OS 관련 문구/스텝** — welcome feature3 "워치 동기화", HelpGuide 스텝 4 "애플워치에 추가": Wear OS 는 SCOPE 제외. 노출 여부는 사용자 확정 필요 (기본 제안: 이번 릴리스에서 숨김, 스텝 번호 재조정).
- **로그인 게이트(LoginGateView) 연동** — Google 로그인은 SCOPE 제외. 따라서 가이드 자동 표시 조건은 iOS 의 `onboarded && signedIn && !seenGuide` 대신 **`onboarded && !seenGuide`** 로 단순화.
- **잠금화면 위젯** — HelpGuide 스텝 3 문구 속 개념. Android 는 홈 위젯(Glance)만. 문구 조정은 사용자 확정 후.
- HelpGuide 스텝 5 캔디의 "상점" — 페이월 UI 는 포함이나 Play 실결제는 제외(구매 버튼 '준비 중'). 문구 자체는 그대로 유지 가능.
