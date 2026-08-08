# 05 — 내 캐릭터 설정 (CharacterProfileView)

원본: `withu/Character/CharacterProfileView.swift` + 모델 `withu/Shared/CharacterProfile.swift`
iOS 진입: 홈 → 설정 시트 등에서 NavigationLink. 네비게이션 타이틀 **"내 캐릭터 설정"** (inline).

값 변경 시 **자동 저장** — 별도 저장 버튼 없음. `onChange(of: profile)` → `CharacterProfileStore.save()` + 위젯 리로드.

---

## 1. 화면/모듈 구조 (위→아래)

배경: 전체 화면에 `backgroundGradient(for: heroState)` — 현재 적용 중 상태(`SharedAppState.loadMessage()?.state`, 없으면 `.idle`)의 그라데이션. Form 은 배경 투명(`scrollContentBackground(.hidden)`).

### 1-1. 히어로 카드 (Section, inset 없음·배경 투명)
- 좌: `KoreanStateChip(state: heroState, size: 64)` — 현재 상태 캐릭터 칩
- 우 상단: 캐릭터 이름 (비었으면 "내 캐릭터") + 연필 아이콘(`pencil`, tertiary)
- 우 하단: `heroState.caption` (secondary)
- frosted 카드(cornerRadius 18)
- **카드 전체 탭 → 이름 편집 알럿** (성격 섹션 제거 후 유일한 이름 편집 진입점)
  - 알럿 제목 "캐릭터 이름", 메시지 "캐릭터를 부를 이름을 정해요."
  - TextField placeholder "예: 새싹이", 초기값 = 현재 이름 draft
  - 버튼 "저장" (trim 후 반영) / "취소" (cancel)

### 1-2. 수면 시간 Section — header "수면 시간"
행 순서:
1. **수면 상태 행** (`sleepStatusRow`)
   - 좌: "자는 중" / "깨어 있음" (semibold callout) — 판정 로직 §3-2
   - 우: **기준 칩** (Capsule, secondary 12% 배경) — 아이콘 + 현재 기준 라벨 + `chevron.up.chevron.down`. 탭 → 메뉴(Picker "수면 기준"):
     - "수면 모드 기준" (`moon.circle.fill`) → tag false
     - "설정 시간 기준" (`clock.fill`) → tag true
   - "수면 모드 기준" 선택 시(**false 로 set 될 때**) 안내 알럿 표시:
     - 제목 "수면 모드 기준으로 자요", 버튼 "확인"(cancel)
     - 메시지: "수면 모드가 켜지면 자고, 꺼지면 일어나요. 아이폰 건강 앱에서 수면 일정을 만들어두면 수면 모드가 매일 자동으로 켜지고 꺼져서, 캐릭터도 규칙적으로 자고 일어나요."
2. Toggle **"잠든 시간 자동으로 알아채기"** — on = 자동 감지 = `manualSleepOnly == false` (바인딩 반전 주의)
3. DatePicker **"잠드는 시간"** (시:분)
4. DatePicker **"일어나는 시간"** (시:분)
5. Button **"최근 수면 시간에 맞추기"** (아이콘 `moon.stars`) — 진행 중이면 우측에 소형 ProgressView + 버튼 disabled
6. (조건부) `sleepAlignMessage` 결과 텍스트 — caption, secondary. 성공/실패 메시지 §3-4

footer (`sleepFooterText`, 3분기 — §3-5):
- manualSleepOnly == true: "자동으로 알아채기를 껐어요. 위에서 정한 시간만 기준으로 해요."
- 수면 신호 미연결(focus filter 미수행 && 건강앱 수면일정 없음): "지금은 아이폰 수면 모드를 받아볼 수 없어서 위에서 정한 시간으로만 자요. 수면 모드에 맞춰 자게 하려면: 아이폰 설정 > 집중 모드 > 수면 > 필터 추가 > withu 를 켜 주세요. (건강 앱에서 수면 일정을 쓰고 있다면 자동으로 따라가요.)"
- 그 외: "먼저 아이폰의 수면·집중 모드를 따르고, 없으면 위에서 정한 시간을 사용해요. 수면 집중 모드가 켜져 있으면 캐릭터가 잠에 들어요."

### 1-3. 식사 시간 Section — header "식사 시간"
- DatePicker "점심 시간" (시:분)
- DatePicker "저녁 시간" (시:분)
- footer: "정한 시각부터 30분 동안 밥 먹는 캐릭터로 보여요."

### 1-4. 밤하늘 시간 Section — header "밤하늘 시간"
- DatePicker "밤이 시작되는 시각" (시:분)
- DatePicker "밤이 끝나는 시각" (시:분)
- footer: "날씨를 받아오면 실제 해 뜨고 지는 시각에 맞춰 해와 달이 저절로 바뀌어요. 위치를 알 수 없을 때만 여기서 정한 시간을 사용해요."
- 저장 단위 주의: hour/minute 이 아니라 **자정 기준 분(minute-of-day)** 단일 Int (`nightFallbackStartMinute`/`nightFallbackEndMinute`)

### 1-5. 상태별 캐릭터 Section — header "상태별 캐릭터"
- `CharacterState.userFacing` 각 상태마다 한 행 (NavigationLink → `StateFolderView(state:)` = 그 상태의 갤러리 폴더):
  - 좌: `KoreanStateChip(state:, size: 44)`
  - 제목: `state.koreanShortLabel`
  - 부제(조건부): `CharacterImageStore.hasImage(for: state)` 이면 "내 캐릭터가 적용됐어요", 아니면 "아직 기본 모습이에요"
- footer: "상태마다 어떤 캐릭터가 보일지 정할 수 있어요. 탭하면 그 상태의 갤러리 폴더가 열려요."

### 1-6. 움직임 Section — header "움직임"
- Toggle **"캐릭터 움직이게 하기"** — `CharacterImageStore.animationEnabled` (프로필과 별도 저장 — 위젯 타깃도 읽어야 하므로 분리, 원본 주석)
- 변경 시 `CharacterImageStore.setAnimationEnabled()` + 위젯 리로드
- footer: "움직이는 캐릭터로 만든 경우, 움직이게 보여줄지 정해요. 끄면 한 장으로만 보이고 배터리가 덜 닳아요."

### 1-7. 캐릭터 외형 한 줄 (고급) Section — header 없음
- DisclosureGroup 라벨 **"캐릭터 외형 한 줄 (고급)"** (접힘 기본)
  - TextField placeholder "예: 분홍 토끼, 큰 눈에 둥글둥글한 캐릭터" — `profile.aiPrompt`, 여러 줄(2~5줄)
  - 안내: "캐릭터를 만들 때 이 문장이 자동으로 채워져요. 영어로 적으면 더 잘 그려져요."

---

## 2. 사용자 문구 전량 (한국어 원문)

| 위치 | 문구 |
|---|---|
| 네비 타이틀 | 내 캐릭터 설정 |
| 히어로 이름 기본값 | 내 캐릭터 |
| 이름 알럿 제목 | 캐릭터 이름 |
| 이름 알럿 placeholder | 예: 새싹이 |
| 이름 알럿 버튼 | 저장 / 취소 |
| 이름 알럿 메시지 | 캐릭터를 부를 이름을 정해요. |
| 수면 상태 | 자는 중 / 깨어 있음 |
| 기준 메뉴 피커 제목 | 수면 기준 |
| 기준 메뉴 항목 | 수면 모드 기준 / 설정 시간 기준 |
| 기준 칩 라벨(동적) | 설정 시간 기준 / 수면 모드 기준 / 건강 앱 기준 |
| 수면 기준 팝업 제목 | 수면 모드 기준으로 자요 |
| 수면 기준 팝업 버튼 | 확인 |
| 수면 기준 팝업 메시지 | 수면 모드가 켜지면 자고, 꺼지면 일어나요. 아이폰 건강 앱에서 수면 일정을 만들어두면 수면 모드가 매일 자동으로 켜지고 꺼져서, 캐릭터도 규칙적으로 자고 일어나요. |
| 토글 | 잠든 시간 자동으로 알아채기 |
| 피커 | 잠드는 시간 / 일어나는 시간 |
| 버튼 | 최근 수면 시간에 맞추기 |
| 맞추기 실패 | 최근 수면 기록이 부족해요. 며칠 자고 나면 맞출 수 있어요. |
| 맞추기 성공 (format) | 최근 수면에 맞췄어요 — %02d:%02d ~ %02d:%02d |
| 수면 헤더 | 수면 시간 |
| 수면 푸터 1 (수동) | 자동으로 알아채기를 껐어요. 위에서 정한 시간만 기준으로 해요. |
| 수면 푸터 2 (신호 없음) | 지금은 아이폰 수면 모드를 받아볼 수 없어서 위에서 정한 시간으로만 자요. 수면 모드에 맞춰 자게 하려면: 아이폰 설정 > 집중 모드 > 수면 > 필터 추가 > withu 를 켜 주세요. (건강 앱에서 수면 일정을 쓰고 있다면 자동으로 따라가요.) |
| 수면 푸터 3 (기본) | 먼저 아이폰의 수면·집중 모드를 따르고, 없으면 위에서 정한 시간을 사용해요. 수면 집중 모드가 켜져 있으면 캐릭터가 잠에 들어요. |
| 식사 헤더 | 식사 시간 |
| 식사 피커 | 점심 시간 / 저녁 시간 |
| 식사 푸터 | 정한 시각부터 30분 동안 밥 먹는 캐릭터로 보여요. |
| 밤하늘 헤더 | 밤하늘 시간 |
| 밤하늘 피커 | 밤이 시작되는 시각 / 밤이 끝나는 시각 |
| 밤하늘 푸터 | 날씨를 받아오면 실제 해 뜨고 지는 시각에 맞춰 해와 달이 저절로 바뀌어요. 위치를 알 수 없을 때만 여기서 정한 시간을 사용해요. |
| 상태별 헤더 | 상태별 캐릭터 |
| 상태별 부제 | 내 캐릭터가 적용됐어요 / 아직 기본 모습이에요 |
| 상태별 푸터 | 상태마다 어떤 캐릭터가 보일지 정할 수 있어요. 탭하면 그 상태의 갤러리 폴더가 열려요. |
| 움직임 헤더 | 움직임 |
| 움직임 토글 | 캐릭터 움직이게 하기 |
| 움직임 푸터 | 움직이는 캐릭터로 만든 경우, 움직이게 보여줄지 정해요. 끄면 한 장으로만 보이고 배터리가 덜 닳아요. |
| 고급 접기 라벨 | 캐릭터 외형 한 줄 (고급) |
| 고급 placeholder | 예: 분홍 토끼, 큰 눈에 둥글둥글한 캐릭터 |
| 고급 안내 | 캐릭터를 만들 때 이 문장이 자동으로 채워져요. 영어로 적으면 더 잘 그려져요. |

※ iOS 푸터 2·3 은 "아이폰/집중 모드" 문맥 — Android 문구 조정은 §5 참고 (SCOPE 는 원문 유지 원칙이지만 플랫폼 지시문은 예외적으로 논의 필요; 기본은 원문 유지가 아닌 **Android 대응 문구로 치환** — 원문 그대로면 사용자를 iOS 설정으로 안내하게 됨).

---

## 3. 상태와 로직

### 3-1. 로컬 상태
```swift
@State profile: CharacterProfile          // CharacterProfileStore.load() 로 초기화
@State animationEnabled: Bool             // CharacterImageStore.animationEnabled
@State showNameEdit: Bool, nameDraft: String
@State isAligningSleep: Bool, sleepAlignMessage: String?
@State showSleepBasisTip: Bool
```
- `onChange(of: profile)` → save + 위젯 전체 리로드. **모든 필드 변경이 즉시 영속** (디바운스 없음).
- `onChange(of: animationEnabled)` → `setAnimationEnabled` + 위젯 리로드.

### 3-2. "자는 중" 판정 (`isSleepingNow`) — **CharacterStateResolver 의 수면 규칙과 동일해야 함** (원본 주석의 '왜')
순서:
1. `manualSleepOnly == true` → 수면 창(§3-3) 안이면 자는 중.
2. 수면 집중 필터 켜짐(`focus.filterSleepingCorrected(sleepEndHour:sleepEndMinute:)` — 기상 시각 보정 포함) **또는** `health.isInBedSchedule` → 자는 중.
3. 아무 집중 모드나 켜져 있고(`focus.isFocused`) + 수면 창 안 → 자는 중 (예약 수면 모드가 필터를 안 깨우는 경우 대비).
4. 시간대 fallback: 수면 창 안이지만 **이번 밤에 수면 모드를 껐으면 기상 존중** — `focus.lastFocusOffAt >= currentSleepWindowStart()` 이면 깨어 있음. 아니면 자는 중.
5. 그 외 깨어 있음.

`currentSleepWindowStart()`: 가장 최근에 지난 '잠드는 시간' 경계 (오늘 시각이 미래면 어제로 -1일).

### 3-3. 수면 창 포함 판정 (`isNowInProfileSleepWindow`)
분 단위 비교. `s < e` 이면 `[s, e)`, 아니면 자정 넘김 창 `nowMin >= s || nowMin < e`.

### 3-4. 최근 수면 맞추기 (`alignToRecentSleep`)
- 진행 플래그 on, 메시지 클리어 → 비동기로 `health.averageSleepWindow()` (최근 7일 실제 수면 기록의 평균 취침/기상; 워치 asleep 샘플 포함).
- nil → 실패 메시지. 성공 → profile 의 sleepStart/End 4필드 갱신(→자동 저장) + 성공 메시지(HH:mm ~ HH:mm).
- **왜**: 워치 수면 추적은 inBed 예측 신호가 없어 '설정 시간'이 사실상 판정 기준 — 그 설정 시간을 실제 수면 패턴에 맞춰주는 버튼.

### 3-5. 기준 칩 라벨/아이콘 (우선순위)
1. `manualSleepOnly == true` → "설정 시간 기준" / `clock.fill`
2. `focus.isFocusFilterSleeping || focus.recentlyUsedSleepFocus` → "수면 모드 기준" / `moon.circle.fill`
3. `health.isInBedSchedule || health.hasSleepSchedule` → "건강 앱 기준" / `heart.fill`
4. 기본 → "설정 시간 기준" / `clock.fill`

기준 칩 메뉴의 set: `manualSleepOnly = manual`; `manual == false` 선택 시 `showSleepBasisTip = true` (안내 팝업).
푸터 2 의 조건: `focus.focusFilterLastPerformAt == nil && !health.hasSleepSchedule` (집중 필터가 한 번도 수행 안 됐고 수면 일정도 없음).

### 3-6. DatePicker 바인딩
- 수면/식사: hour+minute 두 Int 필드 ↔ Date 변환 (`dateFor`/`hourMinute`).
- 밤하늘: minute-of-day 단일 Int(Optional) ↔ Date. get 은 `effectiveNightFallbackStart/End` (nil 기본 20:00=1200 / 06:00=360).

### 3-7. CharacterProfile 모델 (그대로 포팅)
```swift
struct CharacterProfile: Codable, Equatable {
    var name = "내 캐릭터"; var description = ""; var aiPrompt = ""
    var sleepStartHour = 22; var sleepStartMinute = 0
    var sleepEndHour = 7;  var sleepEndMinute = 0
    var lunchHour = 12; var lunchMinute = 0
    var dinnerHour = 18; var dinnerMinute = 0
    var manualSleepOnly: Bool?          // nil = false (옛 데이터 호환)
    var nightFallbackStartMinute: Int?  // nil = 1200 (20:00)
    var nightFallbackEndMinute: Int?    // nil = 360 (06:00)
}
```
Optional 3개는 **구버전 저장 데이터 호환** 목적 — Android 도 nullable 로 두고 JSON 라운드트립 호환 유지.

---

## 4. 데이터 의존성

| 대상 | 저장 위치 | 키/파일 |
|---|---|---|
| `CharacterProfile` | App Group UserDefaults JSON | `withu.characterProfile.v1` |
| 저장 후 브로드캐스트 | NotificationCenter | `withu.characterProfileChanged` (홈 즉시 갱신용) |
| 현재 상태(히어로) | `SharedAppState.loadMessage()?.state` | WatchMessage JSON |
| 상태별 적용 여부 | `CharacterImageStore.hasImage(for:)` | `characters/<state>.png` 존재 |
| 애니메이션 토글 | `CharacterImageStore.animationEnabled` | 이미지 스토어 쪽 별도 키 (위젯도 읽음) |
| 수면 기록 평균 | `HealthKitManager.averageSleepWindow()` | HealthKit 최근 7일 |
| 수면 모드 신호 | `FocusModeManager` (filterSleepingCorrected, isFocused, lastFocusOffAt, isFocusFilterSleeping, recentlyUsedSleepFocus, focusFilterLastPerformAt) | iOS 집중 모드 필터 |
| 위젯 갱신 | `WidgetCenter.shared.reloadAllTimelines()` | 프로필/애니메이션 변경 시 |

---

## 5. Android 구현 노트

- **화면**: Compose M3. iOS Form ≈ `LazyColumn` + 섹션 카드(헤더 = 소문자 라벨, 푸터 = 작은 secondary 텍스트). 배경 그라데이션은 홈과 같은 `backgroundGradient(state)` 재사용, 콘텐츠는 투명 위에.
- **저장**: App Group UserDefaults → `SharedPreferences`(또는 DataStore) — 위젯(Glance)과 같은 프로세스이므로 앱 내 공유로 충분. 키·JSON 스키마는 iOS 와 동일하게 (`withu.characterProfile.v1`, kotlinx.serialization / Moshi 로 camelCase 그대로).
- **자동 저장**: `snapshotFlow`/StateFlow 로 profile 변경 관찰 → save + `GlanceAppWidget.updateAll()` (WidgetCenter 대응).
- **브로드캐스트**: NotificationCenter → 저장소를 단일 StateFlow 로 노출하면 별도 이벤트 불필요 (홈이 collect).
- **DatePicker**: M3 `TimePickerDialog` (시:분). iOS 는 인라인 휠 — Android 는 행 탭 → 다이얼로그 패턴 권장. 표시 텍스트 HH:mm.
- **알럿**: `AlertDialog` (이름 편집 = TextField 포함 다이얼로그; 수면 기준 팁 = 확인 단일 버튼).
- **기준 칩 메뉴**: `DropdownMenu` + 체크 표시 두 항목.
- **집중 모드 대체**: Android 에 iOS Focus 필터 대응물 없음 → **방해 금지(DND) 모드** (`NotificationManager.getCurrentInterruptionFilter()` + `ACTION_INTERRUPTION_FILTER_CHANGED` 브로드캐스트; `ACCESS_NOTIFICATION_POLICY` 필요 없음 — 읽기는 권한 불필요). `FocusModeManager` 대응체를 만들어 isFocused ≈ DND on, lastFocusOffAt ≈ DND off 전환 시각 기록. `filterSleepingCorrected`/`recentlyUsedSleepFocus`/`focusFilterLastPerformAt` 는 "수면 DND" 를 구분할 수 없으므로: isFocusFilterSleeping ≈ (DND on && 수면 창 안), focusFilterLastPerformAt ≈ DND 신호를 한 번이라도 관측했는지(SharedPreferences 타임스탬프). 기준 칩 3단(설정/수면 모드/건강 앱) 우선순위는 유지.
- **HealthKit 대체**: Health Connect — `SleepSessionRecord` 최근 7일 읽기로 `averageSleepWindow()` 구현 (원형 평균: 자정 넘김 처리 위해 각도 평균 또는 기준 시각 offset 평균). `isInBedSchedule`/`hasSleepSchedule` 은 Health Connect 에 '수면 일정' 개념이 없음 → hasSleepSchedule ≈ 최근 7일 수면 세션 존재 여부, isInBedSchedule ≈ 현재 시각이 진행 중 수면 세션 안(사실상 실시간 세션은 못 읽으므로 false 고정 허용).
- **문구 치환 (플랫폼 지시문만)**: 수면 푸터 2·3 과 수면 기준 팝업 메시지의 "아이폰/집중 모드/건강 앱" 안내는 Android 실체(방해 금지 모드/Health Connect)에 맞게 치환 필요 — 예: "설정 > 소리 및 진동 > 방해 금지". **치환 문구는 구현 PR 에서 확정**, 그 외 문구는 원문 그대로.
- **아이콘**: SF Symbol → Material Icons 대응 (pencil→Edit, moon.stars→Bedtime/NightsStay, moon.circle.fill→Nightlight, clock.fill→Schedule, heart.fill→Favorite, chevron.up.chevron.down→UnfoldMore).
- **주의점**:
  - `manualSleepOnly` 토글과 기준 칩은 **같은 필드의 두 UI** — 한쪽 변경이 다른 쪽에 즉시 반영돼야 함.
  - `isSleepingNow` 는 반드시 Android 판 `CharacterStateResolver` 의 수면 분기와 **같은 함수를 공유**할 것 (원본은 중복 구현이라 "동일해야 한다" 주석으로 묶여 있음 — 포팅 시 공용 함수로 빼는 것이 안전).
  - 밤하늘 시각은 minute-of-day Int 저장 — hour/minute 분리 저장과 혼동 금지.
  - 애니메이션 토글은 profile 이 아닌 이미지 스토어 설정에 저장 (위젯이 profile 을 안 읽어도 되게 한 분리 — Android 도 동일 분리 유지).

## 6. 제외 항목 (SCOPE.md)

- Wear OS 연동 — iOS 의 ConnectivityManager 가 profile 을 워치로 보내는 부분 없음.
- iOS 집중 모드 **필터 확장**(Focus Filter Extension) 자체 — Android 대체는 DND 읽기뿐, 시스템 설정에 withu 필터를 등록하는 개념은 이식하지 않음.
- HealthKit '수면 일정(inBed schedule)' 파리티 — Health Connect 에 없음, §5 근사로 대체.
- 배경 생성(날씨 배경 AI) 관련 항목 없음 — 이 화면과 무관.
