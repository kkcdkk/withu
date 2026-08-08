# PARITY-GAPS — iOS → Android 파리티 갭 종합

iOS 대비 Android 구현의 차이를 severity 순으로 정리한 수정 목록. 유사 갭은 병합했고, 워치/잠금화면 등 **scope-leak 문구**는 별도 섹션에 모아 일괄 처리 가능하게 했다.

집계: **high 1건, medium 11건, low 12건** (원 리뷰 24개 항목 → 병합 후 관리 단위 기준).

---

## A. 즉시 수정 권장 (사용자가 바로 체감)

### A-1. [home] 일일 건강 지표가 세션 중 프리즈 — 자동 갱신 경로 없음 · medium/behavior
- **fix**: 30초 폴링(또는 ON_RESUME)에 `HealthManager.loadAll()` 추가. iOS 는 옵저버(HKObserverQuery) 대체로 30초 폴링이 유일 갱신 경로인데 Android 폴링은 `fetchInBedSchedule + refreshWorkoutInference + syncNow` 만 호출해 걸음/kcal/활동분/수면이 안 갱신되고 `scheduleStepGoalIfNeeded` 도 발화 안 함.
- iOS: `ContentView.swift:186-199` (30초 타이머) + `health.startObservingChanges()` (119) + step-goal `onChange` (135-140)
- Android: `HomeScreen.kt:192-202` (폴링), `205-215` (ON_RESUME, health loadAll 없음)

### A-2. [batch] 개수 집계 버그 4건 (병합) — count 이 iOS 와 불일치 · medium×3 + low×1 / behavior·wrong-text
공통 원인: (1) `resultsFrame1`(움직임 frame1)을 개수에 잘못 포함, (2) `selectedStates.size` 대신 `requiredCount` 사용. iOS 는 항상 frame0(`results.count`)·`selectedStates.count` 기준.
- **fix a** — 상태 선택 푸터 '%d개 상태를 만들어요': `batch_footer_count` 인자를 `vm.requiredCount` → `vm.selectedStates.size` (iOS `BatchCharacterGenView.swift:277-281` / Android `BatchGenScreen.kt:338`)
- **fix b** — 캔디 부족 경고 '%d개 상태': `batch_not_enough` 2번째 인자를 `vm.requiredCount` → `vm.selectedStates.size` (iOS `:665` / Android `:684-686`)
- **fix c** — 완료 알럿 '%d개 완성': `done` 을 `vm.results.size` 만으로 계산 (`resultsFrame1` 제외) (iOS `:205` / Android `:295-296,300`)
- **fix d (low)** — 진행 카운터 '만드는 중… %d/%d': `done` 을 `vm.results.size + vm.errors.size` 로 (frame1 제외) (iOS `:639,652` / Android `:660`)

### A-3. [gallery] Landing 화면이 하위 화면 복귀 후 stale · medium/behavior
- **fix**: `GalleryLandingScreen` 에 `LifecycleResumeEffect`(또는 ON_RESUME 옵서버) 추가 → RESUMED 마다 `refreshTick++` 로 재조회 (iOS `onAppear` 재현). 현재는 `applyAll` 경로에서만 tick 증가, 하위 route 는 로컬 tick 만 올려 폴더 개수·총개수·'적용 중' 점·정렬·배경이 stale.
- iOS: `CharacterGalleryView.swift:85` (`onAppear { refresh() }`) + StateFolderView onChange 전파
- Android: `GalleryLandingScreen.kt:125` (`produceState(refreshTick)`, ON_RESUME 없음)

### A-4. [single-gen] 화면 진입 시 서버 entitlement 미갱신 · medium/behavior
- **fix**: 화면 진입 시 entitlement fetch 추가(auth 모듈 도입 후) → `첫 만들기 무료` 배지·캔디 다이얼로그·푸터가 첫 생성 전 서버 상태를 반영. 현재 Android 는 로컬 quota 만 갱신, entitlement 는 null 로 시작해 `/generate` 응답에서만 업데이트.
- iOS: `CharacterGenView.swift:139` (`.task { refreshEntitlement() }`)
- Android: `SingleGenScreen.kt:108` / `SingleGenViewModel.kt:117`
- **비고**: auth 모듈 랜딩에 의존 — 그 전까지는 보류.

### A-5. [profile] 수면 기준 칩 라벨이 라이브 신호로 잘못 추론 · medium/behavior
- **fix**: 칩 라벨/아이콘을 오로지 `profile.isManualSleepOnly` 로만 결정(설정 시간 기준 / 수면 모드 기준) — iOS 와 일치. `dndOn`/health 분기와 선택 불가한 '건강 앱 기준'(`profile_basis_health`) 라벨 삭제. (자동 감지 ON + 신호 없음일 때 수동 라벨 '설정 시간 기준'을 잘못 표시하는 버그.)
- iOS: `CharacterProfileView.swift:258-267` ("살아있는 신호로 추론하지 않는다")
- Android: `ProfileScreen.kt:524-529`

### A-6. [state-resolver] 시간창 수면 fallback 이 manualSleepOnly 로 게이트 안 됨 · medium/behavior ⚠️의사결정 필요
- **fix(조건부)**: window-only 수면 분기를 `profile.isManualSleepOnly` 로 게이트해 iOS 와 일치. 구체 divergence: 기본 프로필 22:00–07:00, manualSleepOnly=false, 23:00, 운동/DND/수면세션 없음, focusWokeAt=null → iOS=IDLE, Android=SLEEPING.
- iOS: `CharacterStateResolver.swift:88-91` / Android: `CharacterStateResolver.kt:95-102`
- **⚠️ 주의**: spec 08 §3.2/§5 는 이 always-on window fallback 을 **의도된 Android 적응**으로 문서화(Android 엔 신뢰할 Sleep Focus 신호 없음). 변경 전 이 의도가 유효한지 확인 필요 — 유효하면 이 갭은 문서상 무시.

---

## B. 후속 (low / 엣지 · 여유 있을 때)

### B-1. [home] 기온 표시 버림 vs 반올림 · low/bug
- **fix**: `temperatureC.toInt()` → `temperatureC.roundToInt()`. 22.7°C 가 iOS '23°' vs Android '22°'.
- iOS `ContentView.swift:268` (`%.0f`) / Android `HomeScreen.kt:380`

### B-2. [home] 마지막 백그라운드 갱신 값이 stale · low/behavior
- **fix**: `HomeScreen.kt:533` / `DiagnosticsScreen.kt:174` 의 `remember { AppPrefs.lastBackgroundRefreshAt }` 에서 `remember` 제거 → recomposition 마다 읽거나 tick/lifecycle 키 연동. iOS 는 매 렌더 계산되는 computed property(`:537-553`).

### B-3. [home] 상단 타이틀 좌측 정렬 (4화면) · low/layout
- **fix**: `CenterAlignedTopAppBar` 사용 → iOS `.inline`(가운데) 일치. 대상: `HomeScreen.kt:236`, `SettingsSheet.kt:144`, `WidgetGuideSheet.kt:58`, `DiagnosticsScreen.kt:86`.

### B-4. [home] 날씨 스위치 접근성 라벨 없음 · low/behavior
- **fix**: `HomeScreen.kt:392` Switch 에 `Modifier.semantics { contentDescription = home_weather_toggle }`(이미 정의됨, 미사용). iOS 는 `labelsHidden` Toggle 에 '날씨 표시' 라벨.

### B-5. [single-gen] 적용/저장 성공·실패 햅틱 없음 · low/missing-feature
- **fix**: `applyImage`/`saveToPhotos` 성공·실패 분기에 success/error 햅틱(LocalHapticFeedback 또는 Vibrator). spec 02 §5 필수. iOS `CharacterGenView.swift:1068,1072,1080,1084` / Android `SingleGenViewModel.kt:545-561,570-581`.

### B-6. [single-gen] 스크롤 시 키보드 미해제 · low/behavior
- **fix**: nestedScroll/imeNestedScroll 연결 또는 스크롤 시 `clearFocus`. iOS `.scrollDismissesKeyboard(.interactively)` (`:136`) / Android `SingleGenScreen.kt:149`.

### B-7. [single-gen] 단일 프레임 결과 이미지 260dp 캡 · low/layout
- **fix**: 단일 프레임 분기의 `.heightIn(max = 260.dp)` 제거 → iOS 처럼 full width(scaledToFit). 260dp 캡은 pager 전용. iOS `CharacterGenView.swift:543-548` / Android `SingleGenScreen.kt:732-742`.

### B-8. [batch] 기준 모습 승인 섹션 버튼/필드 순서 반대 · low/layout
- **fix**: `IdleApprovalSection` 에서 revise 버튼/스피너 블록을 `idleRevisionText` TextField **위로** 이동. iOS=버튼→필드(`:590-604`) / Android=필드→버튼(`BatchGenScreen.kt:727-749`).

### B-9. [batch] 상세 시트 '움직임' 텍스트 라벨 노출 · low/layout
- **fix**: spec (H)4 '라벨 숨김'에 맞춰 '움직임' Text 제거(라벨 없는 스위치 유지). iOS `Toggle(...).labelsHidden()` (`:1267-1274`) / Android `BatchGenScreen.kt:1041-1049`.

### B-10. [gallery] 상세 시트 '움직임' 토글 첫 프레임 ON 플래시 · low/behavior
- **fix**: `GalleryGrid.kt:999` `produceState(initialValue = true, ...)` 의 IO 로드 전 기본값 true 가 먼저 그려져 깜빡임. 로드 완료 전 스위치 미노출 또는 초기값을 마지막 알던 상태로. iOS 는 동기 읽기(`CharacterGalleryView.swift:740`)라 무깜빡.

### B-11. [gallery] 갤러리 클라우드 백업/복원 미구현 · missing-feature
- 갤러리 클라우드 백업/복원 (iOS 구현됨 — 서버 `/gallery` API. Android 포트 필요: `ApiClient` + `CharacterImageStore` reconcile).

---

## C. Scope-leak (워치/잠금화면 등 iOS 전용 개념 문구) — 일괄 처리

SCOPE.md 는 Wear OS·잠금화면 위젯을 제외. 아래는 문구/아이콘만 손보면 되는 batch 작업. 대부분 `strings_onboarding.xml` 문자열 교체 + 아이콘 교체.

| # | severity | 위치 | 문제 | fix |
|---|---|---|---|---|
| C-1 | **high** | `strings_onboarding.xml:77-78` (help_step4), `HelpGuideSheet.kt:96-100` (Icons.Filled.Watch) | Help 4단계 전체가 애플워치 컴플리케이션 설정을 그대로 안내 — Android 에 존재 불가 | step-4 워치 카드 제거(또는 in-scope Android 기능으로 대체), '애플워치'/'워치(심박)'/'아이폰의 움직임' 기기명 문구 삭제. iOS `HelpGuideView.swift:31-33` |
| C-2 | medium | `strings_onboarding.xml:41-45` (onboarding_focus_*) | 온보딩 focus 단계가 iOS Focus-mode 문구('수면 집중 모드', '집중·수면 필터에 withu 연결') 유지 — Android 엔 없는 필터 | Android DND(방해 금지) 문구로 치환(이미 `profile_sleep_footer_no_signal` 등에서 한 방식). iOS `OnboardingView.swift:245-258` |
| C-3 | medium | `strings_onboarding.xml:15-16` (onboarding_feature3_*), `OnboardingScreen.kt:395-399` (Watch 아이콘) | 온보딩 환영 feature 3 이 '워치 동기화'/'애플워치 시계 화면' 약속 | in-scope 기능(예: 홈 화면·위젯 동기화)으로 교체, '애플워치'/Watch 아이콘 제거. iOS `OnboardingView.swift:139-141` |
| C-4 | medium | `strings_onboarding.xml:75-76` (help_step3_*) | Help 3단계가 '홈·잠금화면 위젯', '잠금 화면을 길게 눌러' 안내 — 잠금화면은 iOS 개념 | 잠금화면 문구 삭제, Android 홈 화면 위젯 추가 플로우(홈 길게 눌러 → 위젯)만 서술. iOS `HelpGuideView.swift:28-30` |
| C-5 | low | `strings_onboarding.xml:74` (help_step2_body) | Help 2단계 적용 대상에 '홈·위젯·워치' 나열 | '홈·위젯·워치' → '홈·위젯'. iOS `HelpGuideView.swift:26-27` |

---

## D. iOS 선반영 신규 개선 (2026-07 배치) — Android 후속 포트 필요

iOS 에 먼저 들어간 7개 개선. Android 는 미구현 — 포트 시 대응 iOS 파일 확인.

> **[2026-07-26 이식 반영]** D-2 / D-3 은 이번 2026-07 이식(백로그 A-3-d / A-3-c)에서 **해소됐다.**
> D-1 은 저장소 헬퍼만 생기고 UI 는 여전히 미구현. D-4 는 그대로 남아 §E N-12 와 동일 항목.

### D-1. [gallery] 사진 캐릭터 '움직이는 캐릭터 만들기' · missing-feature — **부분 해소**
- 갤러리 상세 시트에서 frame1 없는 항목에 움직임 프레임(frame 1) 생성·부착. kind=refine + 항목 이미지 reference, 캔디 1개(확인 알럿), 성공 시 `attachGalleryFrame1`(파일 + hasFrame1 메타) — 적용 중이던 자리는 활성 슬롯 frame1 도 갱신.
- iOS: `CharacterGalleryView.swift` `makeMotionFrame` + `CharacterImageStore.swift` `attachGalleryFrame1`
- **남은 것**: 2026-07 이식에서 `CharacterImageStore.attachGalleryFrame1(id, image)` 는 **public 으로 추가됐다**(`shared/CharacterImageStore.kt:266`). 갤러리 상세 시트의 `makeMotionFrame` **UI·호출 경로는 여전히 없음**.

### D-2. [gallery] 다듬기 전/후 비교 후 선택 · behavior — ✅ **해소 (2026-07-26)**
- 갤러리 '다듬기' 성공 시 바로 반영하지 않고 전/후 비교 시트("이전"/"다듬은 결과") → '다듬은 걸로 바꾸기'(원본 교체 + 활성 슬롯 반영) / '이전 그대로'(폐기). 선택 전까지 원본 미변경. 기존 '새 항목 자동 저장' 동작은 제거됨.
- iOS: `CharacterGalleryView.swift` `refineItem` → `refineCompareSheet` / `adoptRefined`
- **이식됨**: 백로그 A-3-d 로 버전 이력 스트립 모델까지 포함해 통일. `gallery/GalleryGrid.kt` (`refineCompare`/`adoptRefined`) + 신규 `gallery/GalleryRefineHistoryStore.kt` (`gallery_refine/<itemId>/`).

### D-3. [single-gen] 단건 결과 갤러리 자동저장 · behavior — ✅ **해소 (2026-07-26)**
- 단건 생성(CharacterGenView) 결과가 적용 여부와 무관하게 갤러리에 자동 저장되도록 변경.
- iOS: `CharacterGenView.swift`
- **이식됨**: 백로그 A-3-c. `gen/SingleGenViewModel.kt` `autoSaveToGallery()` — `generate()`/`refine()` 성공 시점 양쪽에서 호출.

### D-4. [single-gen] 움직임 프레임(frame1) 로딩 표시 · behavior
- frame1 생성 중임을 사용자에게 표시 (frame0 완료 후 조용히 이어지던 구간).
- iOS: `CharacterGenView.swift`
- **상태**: 미이식 유지. §E **N-12** 와 동일 항목 — 상세 근거는 그쪽 참고.

### D-5. [crop] 자르기 제스처 버그 수정 · bug ⚠️iOS 전용 여부 확인
- iOS 크롭 화면 제스처 버그 수정. Android 는 자체 크롭 구현 — 동일 증상 있는지 확인 후 없으면 무시.
- iOS: `CharacterGen/` 크롭 뷰

### D-6. [single-gen] 참고사진만으로 생성 허용 · behavior
- 설명 입력 없이 참고사진만으로도 생성 가능하게 완화.
- iOS: `CharacterGenView.swift`

### D-7. [health] 건강 권한 표시 로직 개선 · behavior
- 건강(HealthKit) 권한 상태 표시/안내 로직 변경. Android 는 Health Connect 대응 지점 확인.
- iOS: 건강 권한 안내 관련 뷰

---

## E. 2026-07 이식 중 새로 확인된 갭 (N-계열)

`13-IOS-2026-07-BACKLOG.md` 를 이식하면서 **백로그에도 이 문서에도 없던** 미이식 동작으로 확인된 것.
번호는 이식 계획서의 '백로그 누락분' 표 번호를 그대로 쓴다.

### N-7. [batch] 기준모습 첫 다듬기 무료 — 플랫폼별 과금이 갈림 · medium/behavior ✅ 2026-07 이식 완료(사용자 승인)
- **현상**: iOS 는 배치 기준모습(idle) 다듬기가 **처음 한 번은 무료**다. `idleRevisionsUsed == 0` 이면 `idleRevisionCost = 0` 이고 버튼에 `무료` / `캔디 N개` 를 구분해 표시한다. 재진입 시 `restorePendingRevisions` 가 `idleRevisionsUsed` 를 이력 길이로 되살려 '무료' 오표시를 막는다.
- Android 는 `idleRevisionsUsed` **개념 자체가 없어** 첫 다듬기부터 **항상 캔디를 차감**한다 → **같은 앱인데 플랫폼별 과금이 다르다.**
- iOS: `BatchCharacterGenView.swift:68, 828-830, 903-905, 1584-1587, 2174`
- Android: `gen/BatchGenViewModel.kt` (`idleRevisionsUsed` grep 0건)
- **fix**: iOS 와 동일하게 `idleRevisionsUsed` 도입 + `PendingRevisionStore` 복원 시 `max(used, versions.size - 1)` 보정.
- ✅ **이식 완료** — 사용자 승인 후 iOS 와 동일하게 도입. `IdleRevisionPolicy` (순수 함수, `IdleRevisionPolicyTest`)
  + `BatchGenViewModel.idleRevisionsUsed/idleRevisionCost` + 버튼/팝업 무료 분기.
  `PendingRevisionStore` 스키마는 그대로 두고 버전 개수로 복원(iOS 와 동일).

### N-11. [single-gen] `generateImportMotionFrame` — 가져온 사진의 움직임 프레임 미생성 · medium/missing-feature
- **현상**: iOS '내 이미지로 만들기'는 가져온 사진을 reference 로 **움직임 프레임(frame 1) 을 따로 생성**할 수 있다. 캔디 안내 팝업(`PendingAction.importMotion`) → 확인 시 생성.
- Android `SingleGenViewModel` 의 `PendingAction` 은 **NewGeneration / Refine 2종뿐** — 이 경로가 없다.
- iOS: `CharacterGenView.swift:94, 99, 197, 405, 996, 1380-1417`
- Android: `gen/SingleGenViewModel.kt` (`PendingAction`)
- **fix**: `PendingAction.ImportMotion` 추가 + kind=refine 으로 가져온 이미지를 reference 삼아 frame1 생성 → `attachGalleryFrame1`(이미 존재).
- **비고**: 2026-07 변경분이 아니라 **그 전부터 있던 파리티 갭**이라 이번 이식 범위 밖으로 뒀다. 기록만.

### N-12. [single-gen] '움직임 프레임 만드는 중' 표시 · low/behavior
- **§D-4 와 동일 항목** — 중복 관리하지 말 것.
- 근거 보강: iOS 는 `isGeneratingMotionFrame` 플래그 + 결과 우하단 **40×40 미니 로딩 슬롯**(`motionFrameLoadingSlot`) 으로 "frame0 만 나온 상태를 완성으로 착각"하는 걸 막는다.
- iOS: `CharacterGenView.swift:76, 668-676, 759-767, 1167-1171`
- Android: `gen/SingleGenViewModel.kt` / `gen/SingleGenScreen.kt` (해당 상태 없음)

---

## F. iOS·Android 공통 결함 — 고치려면 **양쪽을 같이** 고쳐야 함

Android 가 iOS 를 정확히 이식한 결과, **iOS 의 결함까지 파리티로 물려받은** 것들.
Android 만 고치면 파리티가 깨지므로 **iOS 를 먼저(또는 동시에) 고치는 게 맞다.**

### F-1. [batch] 기준모습 '이어서 다듬기'가 스트립 선택본이 아니라 원본을 참조 · medium/bug
- **현상**: 배치 기준모습(idle) 의 `이어서 다듬기` 가 버전 스트립에서 **고른 버전이 아니라 원본**을 reference 로 보낸다. 화면 힌트 `선택한 버전을 기준으로 다듬어요.` 와 어긋난다.
- iOS: `BatchCharacterGenView.swift:1553-1557` `reviseIdle()` → `let current = idleFullRes ?? results[.idle]` (다듬기 체인을 안 봄)
- Android: `gen/BatchGenViewModel.kt:536-538` — 동일 (`idleFullRes ?: results[CharacterState.IDLE]`)
- **정상 동작 대조군**: 결과 상세의 `reviseOne` 은 체인을 본다 (iOS `:2008-2096` — 이력 있으면 `chain.current` / `chain.currentFull`). idle 경로만 누락.
- **fix**: `reviseIdle` 도 `revisedDone[IDLE]` 체인의 선택 버전(풀해상도)을 앵커로 쓰도록.

### F-2. [single-gen] 화면 복귀 후 첫 다듬기가 128px 썸네일을 참조 · medium/bug
- **현상**: 다듬기 이력을 복원할 때 `fullRes` 자리에 **128px 썸네일(`small`)** 을 넣는다. 그래서 화면을 나갔다 온 뒤의 첫 다듬기는 썸네일을 reference 로 보낸다 → 반복할수록 화질이 무너진다. 백로그 **A-3-f "다듬기 참조는 128px 썸네일이 아니라 1024 원본"** 과 정면으로 상충.
- iOS: `CharacterGenView.swift:901-903` `ResultVersion(small: $0.small, frame2: $0.frame2, fullRes: $0.small, …)`
- Android: `gen/SingleGenViewModel.kt:641-643` `ResultVersion(it.small, it.frame2, it.small, …)` — 동일
- **원인**: `RefineHistoryStore` 가 **galleryId 체인만** 저장하고 풀해상도를 보관하지 않아, 복원 시 갤러리 저장본(=128)밖에 없다.
- **fix**: 복원 시 갤러리 풀해상도를 다시 로드하거나(존재한다면), 이력 저장 시 풀해상도도 함께 보관.

### F-3. [home] iOS 홈 배경 그라데이션이 VibeKit 과 불일치 · low/layout — **iOS 쪽만 해당**
- **현상**: iOS 홈만 아직 옛 그라데이션 `withuGreen 14% → state.tint 4% → systemBackground` 를 쓴다. VibeKit 이 정의한 warm 그라데이션(`withuWarmBackground → tint 5% → withuCardFill`)과 어긋난다.
- iOS: `ContentView.swift:283-294` (주석은 "VibeKit 과 동일" 이라고 적혀 있지만 실제로는 다름)
- Android: **통일된 VibeKit 버전을 쓴다** (`ui/UiKit.kt` `rememberBackgroundGradient`) — 즉 Android 가 맞고 iOS 가 잔재.
- **fix**: iOS `backgroundGradient` 를 VibeKit 값으로 교체. Android 는 변경 불필요.

### F-4. [batch/gallery] 배치로 적용한 캐릭터가 갤러리에서 '적용 중' 배지를 못 받음 · medium/bug
- **현상**: 배치에서 만들어 '적용'한 캐릭터는 갤러리에서 **'적용 중' 표시가 안 뜬다.** 나아가 그 항목을 갤러리에서 다듬어 '적용'해도 홈/위젯에 반영되지 않는다.
- **원인**: `applyOne` 이 `saveActiveSlotOnly` 만 호출한다. 이 함수는 주석 그대로 "활성 슬롯 파일만 덮어쓰기 (갤러리 항목/매핑 건드리지 않음)" 라서 `withu.activeSourceMap.v1` 에 **기록이 남지 않는다.** 매핑이 없으니 `statesUsingGalleryItem(id)` 가 빈 배열 → 갤러리 다듬기의 '적용'이 반영할 슬롯을 못 찾는다.
- iOS: `BatchCharacterGenView.swift:1153-1163` (`applyOne`) / `Shared/CharacterImageStore.swift:236-258, 471-483` (`setActiveSource` 는 **private**, `saveActiveSlotOnly` 는 매핑 무관)
- Android: `gen/BatchGenViewModel.kt:657-667` (`applyOneInternal`) / `shared/CharacterImageStore.kt:156, 438, 448` — 동일 구조
- **fix**: `applyOne` 이 그 state 에 대응하는 **갤러리 id 를 알고 `setActiveSource(state, id)` 를 호출**하도록. `setActiveSource` 를 내부 공개로 올리거나, 배치 결과 저장 시점의 갤러리 id 를 `results` 와 함께 들고 다녀야 한다. **iOS·Android 를 같이** 바꿔야 파리티가 유지된다.

---

## G. 릴리스 영향 (2026-07 이식으로 새로 생김)

- **APK 약 +10MB** — `res/font/` 3개(`dunggeunmo.ttf` 7.35MB · `pretendard_light.otf` 1.60MB · `pretendard_bold.otf` 1.58MB). DungGeunMo 가 한글 전체 글립을 담고 있어 대부분을 차지한다. → **서브셋팅 검토 대상.**
- **폰트 라이선스 재확인 필요** — DungGeunMo · Pretendard 둘 다 무료 배포이지만, **Play 스토어 배포 기준으로 재확인**해야 한다. `release-assets/RELEASE-PLAY.md` 체크리스트 항목으로 넣을 것.

---

## 병합 메모
- **A-2** 는 원 리뷰 batch 4개 항목(footer/warning/완료알럿/진행카운터)을 한 원인(resultsFrame1 포함 · requiredCount 오용)으로 묶음 — 한 PR 에서 함께 처리 권장.
- **C 섹션** 5건은 모두 `strings_onboarding.xml` + 온보딩/도움말 화면 아이콘 교체라 일괄 커밋 가능.
- **A-3 / A-1 / A-4** 는 서로 다른 메커니즘이지만 공통 테마 '화면 복귀·진입 시 갱신 누락' — lifecycle 리프레시 작업으로 함께 검토하면 효율적.
- **N-12 는 D-4 와 같은 항목**이다 (§E N-12). 둘 중 하나만 닫으면 다른 쪽도 같이 닫을 것.
- **F 섹션 4건은 Android 단독 수정 금지** — iOS 를 같이 고쳐야 파리티가 유지된다. F-3 은 iOS 만 고치면 된다.
- 머리말 집계(high 1 / medium 11 / low 12)는 **A·B·C 섹션 기준**이다. D·E·F 는 별도 관리 단위.
