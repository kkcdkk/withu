# 13 — iOS 2026-07 변경분 Android 이식 백로그

2026-07-21 ~ 07-26 사이 iOS(`withu` 타깃)에서 개발된 내용을 Android 로 옮기기 위한 작업 목록.
브랜치 `task/watch-image-sync` (커밋 `82d6be7` ~ `340c9b4`) 기준.

> **[커밋 범위 교정 2026-07-26]** 원래 머리말은 `68aed4c ~ c7c31bc` 였으나 부정확했다.
> - `68aed4c` 는 2026-07-22 중간 커밋이고, **A-3 / A-5 / A-7 / A-8 은 그보다 앞선 07-22 커밋**
>   (`6d7620c`, `57b519b`, `f0579e6`, `498ace1`, `36f9fc3`, `4cd303d`, `320fa15`, `3b0e034` 등)에 들어 있다.
> - **A-4** 는 07-21 (`82d6be7`).
> - 마지막 커밋은 `c7c31bc` 가 아니라 **`340c9b4`** (그 뒤로 CTA 패딩 원복·다듬기 버튼 축소가 들어감).
>
> 그래서 이 문서를 diff 로 재구성하지 말고 **현재 iOS 워킹트리 파일을 진실로** 볼 것.

**읽는 법**
- `P0` = 사용자가 바로 체감하는 기능/버그, `P1` = 디자인 통일, `P2` = 선택
- **iOS**: 참고할 원본 파일. **Android**: 손댈 파일(추정, 실제 구조 확인 후 조정)
- ⚠️ 표시는 **스키마/키가 iOS 와 바이트 동일해야 하는 것** — rename 시 데이터 호환 깨짐
- 제목 옆 **`[완료]` / `[부분]` / `[제외]` / `[이미 됨]`** 은 **2026-07-26 Android 이식 결과**
  (자세한 내용은 문서 끝 §G 이식 결과 요약)
- **`교정`** 으로 표시한 값은 **이 백로그가 stale 해서 iOS 실제 코드 값으로 고친 것**.
  이식 코드는 교정된 값을 따랐다.

> 원칙 (`00-PLAN.md §0` 그대로): 저장 키·파일명·`CharacterState.raw` 는 iOS 와 동일,
> 문구는 iOS `Localizable.xcstrings` 한국어 원문 그대로, 캔디는 로컬 권위.

---

## A. 기능 (P0)

### A-1. 캐릭터 이름 ⚠️ `[완료]`
한 캐릭터(batchId 로 묶인 그룹)에 사용자가 이름을 붙이고, 갤러리에서 그 이름으로 본다.

- **저장**: App Group(Android=SharedPreferences) 키 **`withu.characterNames.v1`**, 타입 `Map<String,String>` (batchId → 이름). 공백이면 키 삭제.
  - `GalleryItem` 스키마는 **건드리지 않았다** (구버전 호환). 이름은 별도 맵.
- **여러 장 만들기**: 프롬프트 위에 "캐릭터 이름" 섹션(TextField, placeholder `이 캐릭터의 이름 (선택)`).
  생성 시작 시 새 `batchSessionId` 에 저장 + 생성 후 수정해도 즉시 반영(onChange).
- **하나씩 만들기**: **결과 아래**에 이름 입력칸. 세션 id(`currentSessionId`)를 `batchId` 로 재사용해 단건도 캐릭터별에 뜬다.
  - 새 생성마다 이름 초기화. **재진입 시** 저장된 갤러리 항목의 batchId 로 이름/세션 복원.
- iOS: `Shared/CharacterImageStore.swift`(characterName/setCharacterName), `CharacterGen/BatchCharacterGenView.swift`(nameSection), `CharacterGen/CharacterGenView.swift`(결과 하단)
- Android: `shared/CharacterImageStore.kt`, `gen/BatchGenScreen.kt`, `gen/SingleGenScreen.kt`

### A-2. 갤러리 '캐릭터별' → 2열 썸네일 그리드 `[완료]`
- 카드+버튼 목록 → **2열 그리드**(대표 썸네일 + 그 아래 이름). 탭하면 그 캐릭터의 모습들 그리드.
- **"이 캐릭터로 모두 적용" 버튼은 상세 화면 상단으로 이동**. (확인 알럿을 상세 화면에 붙여야 함 — 리스트에 두면 푸시된 화면에서 안 뜸)
- **이름 없는 단건은 캐릭터별에서 숨김**: `이름 있음 || 상태 2개 이상` 만 노출. 이름 붙이면 즉시 등장.
- iOS: `CharacterGen/CharacterGalleryView.swift` (characterTile / characterDetailHeader / refresh 필터)

### A-3. 다듬기 = 버전 이력 모델로 통일 + **화면 나갔다 와도 유지** ⚠️ `[완료]` (a~g 전부)
다듬기가 있던 **5곳**(배치 기준모습 승인 / 배치 결과 상세 / 하나씩 만들기 / 갤러리 상태별 / 갤러리 캐릭터별)을
**같은 UI·같은 규칙**으로 통일했다.

- **UI**: 상단 큰 미리보기 + 아래 **버전 스트립**(`원본`, `다듬음 1`, `다듬음 2`…) 탭해서 선택 →
  `이어서 다듬기` 입력 + `적용`/`취소`. 힌트 문구: `선택한 버전을 기준으로 다듬어요.`
- **버튼 문구**: 첫 다듬기는 전부 **`다듬기`**, 이력에서 이어갈 땐 **`이어서 다듬기`**.
- **`적용` 의미**: 고른 버전으로 **사진을 교체**하고 홈/위젯/워치에 반영.
- **버전 상한 8** — `[0]`(원본)은 항상 보존하고 오래된 다듬기(index 1)부터 제거.
- **품질**: 다듬기 참조는 **128px 썸네일이 아니라 1024 원본**을 쓴다. (썸네일로 다듬으면 반복할수록 화질 붕괴)
- **영속(핵심)** — 화면을 나갔다 다시 들어와도 이력이 남아야 함:
  - 하나씩 만들기: `single_refine_history.json` (App Group). 이미지는 저장 안 하고 **galleryId 체인만** 보관 → 복원 시 갤러리에서 다시 로드.
  - 갤러리 다듬기: `gallery_refine/<itemId>/` 폴더
  - 배치: `pending_revisions/` 폴더, 파일명 **`<state>.v<i>.png`**(썸네일) · **`<state>.f<i>.png`**(풀해상도) · `<state>.json`(meta: frame/selected/count/prompt)
  - 새 캐릭터로 덮어써질 때만 이력 초기화.
- iOS: `CharacterGenView.swift`(RefineHistoryStore), `CharacterGalleryView.swift`(GalleryRefineHistoryStore), `BatchCharacterGenView.swift`(PendingRevisionStore)

### A-4. 저장 안 한 변경 보호 `[완료]`
- '내 캐릭터 설정'을 **자동 저장 → 명시적 `저장` 버튼** 모델로 전환. 변경이 생기면 상단에 `저장` 등장.
- 저장 안 하고 나가려 하면 확인 시트: `저장하고 나가기` / `저장 안 하고 나가기` / `계속 편집`
- 갤러리·배치 상세 시트도 **편집 중 닫으면 경고**.
- iOS: `Character/CharacterProfileView.swift`(hasChanges/showDiscardConfirm)

### A-5. 무료 1회 정책 — 사진 넣으면 캔디 ⚠️서버 연동 `[완료]`
- 무료 1회는 **사진 없이 프롬프트로만** 만들 때만. 사진 첨부 시 캔디 차감.
- 클라이언트가 사진 있을 때 `kind: "photo"` 를 `/generate` 에 보냄 → 서버가 `free_single` 을 소진하지 않음.
- iOS: `CharacterGenView.swift` (`creationIsFree = hasFreeCreation && referenceImage == nil`)

### A-6. 생성 중 앱 종료(튕김) 방지 ⚠️버그 `[부분]`
- 단건 생성의 백그라운드 태스크에 **만료 핸들러가 없어** 화면 끄고 시간이 지나면 OS 가 앱을 강제 종료했다.
- Android 대응: 생성 작업을 **WorkManager/foreground service** 로 유지하고, 취소·만료 콜백에서 정리하도록 확인.
- iOS: `CharacterGenView.swift` `beginBackgroundTask(withName:expirationHandler:)`
- **이식 결과 — 1단계만 완료 / 2단계는 의도적 미실행**
  - 1단계 `[완료]`: A-3-c 의 **결과 자동 갤러리 저장**으로 유실을 방어한다. 결과가 오는 즉시 디스크에 남아
    화면/프로세스가 죽어도 갤러리에서 회수된다. 배치는 원래부터 `bggen/GenBatchWorker.kt` 의
    `setForeground(dataSync)` 로 보호돼 있다.
  - 2단계 `[제외]`: **단건 생성을 foreground service 로 승격하는 작업은 하지 않았다.**
    단건은 `versions`/`transparent` 등 화면 상태와 강결합이라 배치 큐 스키마(`BgGenJob`/`BgGenSpec`/
    `bggen/jobs.json`)를 건드려야 하고 배치 회귀 위험이 이득보다 크다. 백로그의 Android 지시도 "확인"까지였다.
  - ⚠️ **사용자 결정 대기**: 승격하면 화면을 나가도 단건 생성이 계속되고 완료 알림이 뜬다(UX 변화). 할지 말지 확인 필요.

### A-7. 서버 거절(가드레일) 메시지 노출 `[완료]`
- OpenAI 콘텐츠 정책 거절은 "서버 오류"가 아니라 **422 + 사용자용 안내 문구**로 표시.
- 서버(`cloudflare/withu-api/src/index.js`)는 이미 배포됨. Android 는 **422 응답의 detail 을 그대로 보여주면 됨**.

### A-8. 연결 확인(preflight) 완화 `[완료]`
- 생성 전 `/health` 체크가 너무 빡세서 화면 재진입 시 "연결이 어려워요" 오탐 → **timeout 8초 + 2회 재시도**.
- iOS: `Networking/APIClient.swift` `preflightPing()`

---

## B. 수면 판정 (P0)

### B-1. '오늘 활동' 수면 시간 = **지난 밤만** ⚠️버그 `[완료]`
- 기존: 최근 7일 `asleep` 샘플을 **전부 합산** → 값이 부풀거나, 새 기록이 없으면 옛 총합이 **2.0h 로 고정**되는 버그.
- 수정 규칙:
  1. `asleep*`(Unspecified/Core/Deep/REM)만 집계. `inBed` 는 제외.
  2. 가장 최근 수면 종료 시각이 **36시간 이내**일 때만 유효. 아니면 `-` 표시.
  3. 그 종료 시각 기준 **14시간 창** 안에서 시작한 샘플만 = 한 번의 수면 세션.
- iOS: `HealthKit/HealthKitManager.swift` `fetchSleep()`

### B-2. 수면 Focus 필터 미연결 안내 카드 `[제외]` (이식 대상 아님)
- '수면 모드 기준'인데 필터 신호를 한 번도 못 받았으면(`focusFilterLastPerformAt == nil`)
  설정 화면 수면 섹션에 **연결 안내 카드** 표시 + '설정 앱 열기'. 신호 한 번 오면 자동으로 사라짐.
- ⚠️ Android 에는 iOS Focus 개념이 없음 → **이식 대상 아님**. 대신 Android 는 시간창/DND 기준을 쓰므로 그대로 둔다.

### B-3. 수면 판정 방어 규칙 `[완료]`
- '설정 시간 기준'의 **수면 시간창 안에서는 폰 모션(걷기 등)이 수면을 덮지 않는다.**
- iOS: `Character/CharacterStateResolver.swift` (`inManualSleepWindow` 가드) — **Android resolver 도 동일 가드 필요**
- (참고) iOS 전용으로 `sleepWindowFallback` 파라미터가 있으나 Focus 감지 불가 환경 전용이라 Android 는 무시.

### B-4. 진단 화면 확장 (선택) `[완료]`
- '수면 시간 설정' 섹션: 수면 기준 / 설정한 수면 시간창 / **'잠 깨는 중' 구간** / 지금 판정 결과.
  - `잠 깨는 중`은 **일어나는 시간부터 1시간** 동안 나오는 상태라, 시간 설정이 틀리면 한밤중에 뜬다. 이걸 눈으로 확인하는 용도.
- '신호 모니터'(`withu.focusSignalLog.v1`)는 iOS Focus 디버깅 전용 → Android 이식 불필요.

---

## C. 디자인 시스템 (P1) — 레트로 픽셀 + 파스텔

### C-1. 색 팔레트 ⚠️ `[완료]`
라이트 모드 전용(앱이 라이트 고정). 다크 값은 iOS `OnboardingView.swift` 하단 `extension Color` 참고.

> **`교정`** 아래 HEX 중 5건은 원래 표가 float→int **절삭**으로 적혀 있어 실제보다 1 작았다.
> iOS 는 `UIColor(red:green:blue:)` 실수값이므로 **반올림**이 맞다 (`OnboardingView.swift:519-575`).
> `withuCTAGreen` 은 표에 아예 빠져 있었다.

| 토큰 | 라이트 HEX | 쓰임 |
|---|---|---|
| `withuPixelOutline` | `#5C4530` `교정`(← `#5B4430`) | **모든 테두리·아이콘·카드 상단바** (따뜻한 중간 갈색) |
| `withuCardFill` | `#FCF7E8` | 카드 표면 (크림) |
| `withuWarmBackground` | `#F5E8CC` `교정`(← `#F4E8CC`) | 화면 배경 상단 (베이지) |
| `withuSage` | `#8CA880` `교정`(← `#8CA87F`) | **초록 버튼 채움 · 보조 액센트 · 토글 ON** |
| `withuPinkSoft` | `#B8E3BD` `교정`(← `#B7E2BC`) | 히어로 카드 채움 (이름은 Pink 지만 실제 **연초록**) |
| `withuPinkText` | `#338047` `교정`(← `#337F47`) | 강조 글자 |
| `withuCTAGreen` | `#57CC75` `교정`(표 누락) | 선택 테두리 · 칩 · 스피너 tint. iOS 에서 **26곳 사용 중**(+정의 1). Android 구값 `#33C759` 는 오류 |

- **배경**: `withuWarmBackground → state.tint 5% → withuCardFill` 세로 그라데이션 (전 화면 공통).
  캐릭터 만들기 플로우만 상단을 `withuPinkSoft` 로 바꿔 초록 배경.
  - ⚠️ iOS **홈 화면만** 아직 옛 그라데이션(`withuGreen 14% → tint 4% → systemBackground`,
    `ContentView.swift:283-294`)을 쓴다 — VibeKit 과 불일치. **Android 는 통일된 VibeKit 버전을 쓴다.**
    (PARITY-GAPS §E 참고 — iOS 쪽에 남은 불일치)
- `withuCTABorder` 는 **죽은 토큰** (iOS 에 정의만 있고 사용처 0) → Android 로 가져가지 않았다.
- 흩어져 있던 `.mint/.brown` 등 tint 는 **세이지로 통일**.

### C-2. 픽셀 테두리 / 카드 `[완료]`
- **`PixelBorderShape`**: 모서리를 **2계단**으로 깎은 사각형. 계단 한 칸 `pixel = 5`(토글은 3).
  각 모서리에서 `(2p,0) → (p,0) → (p,p) → (0,p) → (0,2p)` 형태.
- **홈 카드** = 픽셀 계단 테두리 + 크림 채움 + 테두리 2pt.
- **하위 화면 카드** = 픽셀 대신 **둥근 사각형(radius 14) + 갈색 테두리 2pt**.
  (Form 안에서 픽셀 모서리가 잘려서 분리함)
- **Form 섹션 = 카드 하나**: 섹션의 행들을 하나의 카드로 묶고 `listRowInsets` 좌우 16 여백. 여백 0 이면 화면 끝에서 테두리가 잘린다.
- iOS: `Design/VibeKit.swift` (`PixelBorderShape` / `pixelCardSurface` / `plainCard` / `plainFrostedCard`)

### C-3. 버튼 · 토글 · 입력칸 `[완료]`
- **초록 CTA**: 세이지 채움 + **갈색 픽셀 테두리 2.5pt** + 흰 글자 + **둥근모꼴 16pt**,
  패딩 **가로 14 / 세로 11** `교정`(← 12 / 7), 누르면 검정 18% 오버레이 + 0.97 축소. **아이콘 없이 텍스트만.**
  - `교정` 근거: `VibeKit.swift:232-233`. 마지막 커밋 `340c9b4` 가 "(CTA 버튼 패딩은 원복)" 으로 되돌려서
    백로그 값(12/7)이 stale 해졌다. Android 는 이미 14/11 이라 패딩은 손댈 게 없었다.
  - ⚠️ **`둥근모꼴 16pt` 는 모서리 반경이 아니라 폰트다.** `둥근모꼴` = **DungGeunMo 폰트 이름**
    (`VibeKit.swift:230` `.font(.galmuri(16, relativeTo: .callout))`). 모서리는 `PixelBorderShape` 가 담당.
    radius 16 으로 오해하면 안 된다.
- **픽셀 토글**(iOS 기본 초록 스위치 대체): 트랙 42×24 계단 사각형,
  OFF = 크림 / ON = 세이지, 노브 12×12 사각(원형 금지) + 여백 4, 테두리 2pt. 앱 전역 적용.
- **입력칸**: 크림 카드에 묻히지 않게 **흰 배경 60% + radius 8 + 갈색 45% 테두리 1.5pt**.
  프롬프트/다듬기 입력 전부 적용.
- **다듬기 버튼**(하나씩 만들기): 입력칸 **오른쪽 하단**에 네모 픽셀 세이지 버튼(`다듬기` 텍스트),
  **최소 52×34 · 글씨 13** `교정`(← 최소 64×46). 근거 `CharacterGenView.swift:793-801` (커밋 `340c9b4` 가 축소).

### C-4. 홈 위계 `[완료]`
- 균등 4행 → **히어로 1 + 2열 그리드 3**.
  - 히어로 = `함께할 캐릭터 생성하기`, 연초록 카드, 아이콘 34pt
  - 그리드 = `함께 사진 찍기` / `캐릭터 갤러리` / `내 캐릭터 설정하기`, 아이콘 30pt, 최소 높이 96
- **카드 상단 갈색 바**: '오늘 활동'·'Apple Watch' 카드 제목을 갈색 배경 + 크림 글자 바로.
- **활동 수치 강조**: 값이 `0`/없음이면 **작고 흐리게**(15pt, secondary, 아이콘 30%),
  의미 있는 값은 **크게**(19pt, primary). 허전함 완화용.
- **캐릭터 뒤 tint 원 제거** — 투명 캐릭터만.

### C-5. 폰트 ⚠️에셋 필요 `[완료]`
| 용도 | 폰트 · 크기 |
|---|---|
| 홈 텍스트(캐릭터 상태문·활동 숫자·메뉴 제목) · **초록 버튼 글씨** | **둥근모꼴 (DungGeunMo)** 16pt |
| 네비 타이틀 | **둥근모꼴** **inline 17pt / large 26pt** `교정`(표 누락) |
| 그 외 앱 전체 본문 (기본값) | **Pretendard Light 17pt** `교정`(크기 누락) |
| Form `Section(header:)` 헤더 | **Pretendard Bold 16pt** |
| `SectionHeader` 컴포넌트 헤더 | **Pretendard Bold 14pt** `교정`(표 누락 — 헤더는 두 종류다) |
| footer 설명 | Pretendard **11pt** `교정`(← 12pt) |

- `교정` 근거
  - 본문 17pt · 네비 large 26pt · inline 17pt = `withuApp.swift:26,29,43`
  - **섹션 헤더가 두 종류**: Form 안의 `Section(header:)` 는 `.pretendardBold(16)` (`ContentView.swift:744` 등),
    VibeKit 의 `SectionHeader` 컴포넌트는 `.pretendardBold(14)` (`VibeKit.swift:407`). 둘 다 Bold 지만 크기가 다르다.
    백로그는 16 만 적어 놨었다.
  - footer 는 `.pretendard(11)` (`VibeKit.swift:566`, `ContentView.swift:747`) — 커밋 `d65d99f`
    "하단 설명(footer) 글씨 축소" 반영. 백로그 12pt 는 stale.
- **Pretendard 웨이트는 Light / Bold 둘뿐**이다. Android 코드가 쓰던 `FontWeight.SemiBold` / `Medium` 은
  합성 렌더링이 되므로 Light·Bold 로 정리했다.
- iOS 는 앱 루트에 기본 폰트를 지정해서 **`.font()` 안 준 텍스트(폼 라벨·토글·버튼)까지** Pretendard 로 바뀌게 했다.
  Android 는 `MaterialTheme.typography` 기본값을 Pretendard 로 잡으면 동일 효과.
- 폰트 파일: `withu/Fonts/DungGeunMo.ttf`, `Pretendard-Light.otf`, `Pretendard-Bold.otf`
  → Android `res/font/` 로 복사 (`dunggeunmo.ttf` / `pretendard_light.otf` / `pretendard_bold.otf`).
  - ⚠️ **릴리스 영향**: 3개 합계 약 **10.0 MB** (DungGeunMo 만 7.35MB — 한글 전체 글립).
    APK 가 그만큼 커진다 → **서브셋팅 검토 대상**.
  - ⚠️ **라이선스는 둘 다 무료 배포지만 Play 배포 기준으로 출시 전 재확인 필요** (릴리스 체크리스트 항목).

### C-6. 아이콘 — 이모지 제거 ⚠️에셋 필요 `[완료]`
기성 이모지가 픽셀 세계관을 깨서 **손그림 컬러 픽셀 아이콘**으로 교체했다.
에셋은 iOS `withu/Assets.xcassets/` 에 있으니 PNG 를 그대로 가져다 쓰면 된다 (배경 투명, `interpolation(.none)` = Android `FilterQuality.None`).

| 에셋 | 쓰임 |
|---|---|
| `menu_camera` / `menu_gallery` / `menu_settings` | 홈 2열 그리드 3개 |
| `menu_wand` | 히어로(캐릭터 생성) |
| `metric_steps` | 활동 카드 '걸음' |
| `msg_sun` / `msg_leaf` / `msg_stretch` / `msg_water` | 활동 격려 문구 옆 아이콘 |

- 활동 카드 나머지 3개(활동분/kcal/수면)는 **단색 도트 아이콘**(코드로 그린 픽셀 그리드) — `PixelIcon` + 시계/불꽃/달.
- **날씨 아이콘은 기존 픽셀 PNG 재사용** (`weather_sunny/cloudy/rainy/snowy/night`). 헤더도 캐릭터 옆 장식과 같은 그림을 쓰도록 통일(야간 판정 포함).
- **설정(톱니)·새로고침은 일반 시스템 아이콘 유지** (픽셀로 만들었다가 되돌림).

### C-7. 문구에서 이모지 제거 ⚠️문구 `[완료]`
Android 는 문구를 그대로 옮기므로 **아래는 반드시 같이 반영**:
- `CharacterState.caption` 24개: `잠 깨는 중 🥱` → `잠 깨는 중` 등 **이모지 전부 삭제**(한글은 그대로)
- 운동 종류 7개: `달리기 🏃` → `달리기`, 자전거/걷기/등산/수영/요가/근력 동일
- 활동 격려 문구 7개: 이모지 빼고 **아이콘으로 대체**
  - `좋은 아침! 오늘도 함께해요`(msg_sun) / `새 하루 시작이에요`(msg_leaf) / `기지개 펴고 시작해봐요`(msg_stretch) / `물 한 잔 마시는 거 잊지 마세요`(msg_water) / `오늘 알찬 하루였네요! 평소보다 많이 움직였어요`(msg_stretch) / `오늘 %d보 걸었어요`(msg_leaf) / `가벼운 산책 어때요`(msg_leaf)
- **삭제된 문구**: `사진을 넣으면 그 모습을 참고해서 만들어요. 비워두면 텍스트로만 만들어요.` (참고 사진 섹션 footer)
- **유지되는 이모지**: 캔디 `🍬`, 알림(`🎉`,`✨`,`💤`), 날씨 이모지(데이터/폴백), `symbolEmoji`(캐릭터 그림 없을 때 최후 폴백)
- `교정` **`values-en` 의 en 문구에도 같은 이모지가 있다** — 백로그는 한국어만 적어 놨었다.
  `values/` 와 `values-en/` 을 **같이** 손봐야 한다.
- `교정` 이모지가 제거된 `CharacterState.caption` 은 **24개 전부를 훑되 실제로 이모지가 있던 건 21건**이다.

---

## D. 워치 / Wear OS (P1)

### D-1. 워치가 운동을 **스스로** 감지 `[이미 됨]` (코드 변경 없음)
- 문제: 운동해도 워치 화면이 안 바뀌고 **폰 앱을 열어야** 반영됐다.
  원인은 폰이 백그라운드에서 늦게 감지 → 워치로 전달이 지연.
- iOS 조치: 워치 앱이 `CMMotionActivityManager` 로 **손목에서 직접** 걷기/달리기/자전거를 감지해
  폰 왕복 없이 워치 상태를 갱신(컴플리케이션 즉시 reload). 운동 종료 시 폰이 준 마지막 비운동 상태로 복귀.
- **Android(Wear OS) 는 이미 `wear/.../motion/` 에 자체 모션 감지가 있음** → 동작하는지 확인만.
  없다면 같은 정책(신뢰도 낮은 추정 무시, 종료 시 폰 상태로 복귀)으로 맞출 것.
- iOS: `withu Watch App/WatchMotionManager.swift`

### D-2. 상태 변화는 우선 채널로 push `[이미 됨]` (코드 변경 없음)
- 상태가 바뀔 때만 컴플리케이션 전용 전송(하루 예산 제한이 있어 아껴 씀).
- Android Data Layer 는 이미 즉시 전달이라 별도 작업 불필요. **이미지 DataItem 에 `updatedAt` 넣는 규칙 유지.**

---

## E. 작업 순서 제안

1. **A-1 캐릭터 이름** → **A-2 갤러리 그리드** (서로 붙어 있음, 사용자 체감 큼)
2. **A-3 다듬기 이력 + 영속** (분량 가장 큼. 5곳 통일이라 컴포넌트 하나 만들고 재사용)
3. **B-1 수면 시간 계산** + **B-3 방어 규칙** (버그, 작음)
4. **A-4 저장 보호**, **A-5 무료 정책**, **A-6 생성 중 종료 방지**, **A-7/A-8 네트워크**
5. **C 디자인** — C-1 색 → C-5 폰트 → C-2/C-3 카드·버튼·입력칸 → C-4 홈 위계 → C-6/C-7 아이콘·문구
6. **D 워치** 확인

---

## F. 검증

```bash
cd android
./build.sh :app:assembleDebug     # 기본 검증
./build.sh test                   # 유닛 테스트 (resolver 규칙 변경 시 필수)
./build.sh :wear:assembleDebug    # 워치 건드렸을 때
```

- **B-1/B-3 은 `CharacterStateResolverTest` 에 케이스 추가**할 것 (순수 함수라 테스트 쉬움).
- 캔디/결제 흐름은 DEBUG 에서 무제한이라 **Release 빌드로만** 실제 검증 가능.

---

## G. 이식 결과 요약 (2026-07-26)

### G-1. 완료

| 묶음 | 항목 |
|---|---|
| 기능 | **A-1** 캐릭터 이름 · **A-2** 갤러리 캐릭터별 2열 그리드 · **A-3(a~g)** 다듬기 버전 이력 + 영속 5곳 통일 · **A-4** 저장 안 한 변경 보호 · **A-5** 무료 1회 = 사진 없을 때만 · **A-7** 422 detail 노출 · **A-8** preflight 8초 + 2회 재시도 |
| 수면 | **B-1** 지난 밤만 계산(36h/14h) · **B-3** 수면 시간창 모션 가드 · **B-4** 진단 '수면 시간 설정' 섹션 |
| 디자인 | **C-1** 색 팔레트(교정값) · **C-2** 픽셀 테두리/카드 · **C-3** 버튼·토글·입력칸 · **C-4** 홈 위계 · **C-5** 폰트 · **C-6** 아이콘 · **C-7** 문구 이모지 제거 |

신규 파일: `gen/RefineHistoryStore.kt`, `gen/PendingRevisionStore.kt`, `gallery/GalleryRefineHistoryStore.kt`,
`ui/PixelShapes.kt`, `ui/PixelIcon.kt`, `ui/theme/Type.kt`, `res/font/` (3), `res/drawable-nodpi/` (9).

### G-2. 이식 대상 아님 / 부분

- **A-6** `[부분]` — 1단계(결과 자동 갤러리 저장)만. **단건 생성 foreground service 승격은 미실행.**
- **B-2** `[제외]` — iOS Focus 개념이 Android 에 없음. Android 는 DND/시간창 기준 유지.
- **D-1 / D-2** `[이미 됨]` — Wear 모듈에 이미 구현돼 있어 **코드 변경 없음**.
  (`wear/.../motion/WatchMotionManager.kt`, `app/.../watch/WearSyncManager.kt`)
- 이식하지 않기로 명시된 iOS 전용: `sleepWindowFallback` / `isFocusUndetectable`,
  `FocusSignalLog`(`withu.focusSignalLog.v1`), `GallerySyncManager.forceUpload`(Android 는 클라우드 백업 자체가 미구현).

### G-3. 사용자 결정 대기

1. **A-6 2단계** — 단건 생성을 배치처럼 foreground service 로 승격할지.
   승격하면 화면을 나가도 생성이 계속되고 완료 알림이 뜬다(UX 변화). 배치 큐 스키마 회귀 위험 있음.
2. **A-4 프로필 자동 저장 폐지** — 이제 시간 설정을 바꿔도 `저장` 을 눌러야 반영된다.
   iOS 와 동일하지만 **기존 Android 사용자에겐 동작 변화**라 고지가 필요하다.
3. **배치 기준모습 첫 다듬기 무료** — iOS 에만 있는 정책(`idleRevisionsUsed == 0` 이면 무료).
   **캔디 소비 정책 변경이라 임의 도입하지 않았다.** 도입하면 플랫폼별 과금이 통일되고, 안 하면 갈린다.
   → PARITY-GAPS **N-7**.
4. **N-11 가져온 사진 → 움직임 프레임 생성** — 2026-07 변경분이 아니라 기존 파리티 갭이라 범위 밖으로 뒀다.
   → PARITY-GAPS **N-11**.
5. **폰트 3개로 APK 약 +10MB** — 서브셋팅할지, 그대로 갈지.

### G-4. 실기기 검증이 필요한 항목

빌드/유닛테스트로는 못 잡는 것들.

- **A-3 영속 3종** — 화면을 완전히 나갔다 다시 들어와도 버전 스트립이 남는지
  (단건 `single_refine_history.json` · 갤러리 `gallery_refine/<itemId>/` · 배치 `pending_revisions/`).
  특히 갤러리 항목이 삭제된 뒤의 복원 실패 경로(전부 nil 처리).
- **A-5 / 캔디·무료 정책** — DEBUG 는 쿼터 무제한(9999)이라 **Release 빌드 또는 내부 테스트 트랙**에서만 실제 확인 가능.
  게다가 Android 는 아직 `Authorization: Bearer` 를 안 보내 서버가 `sub` 를 못 잡으므로,
  **로그인이 붙은 뒤에야** `free_single` 미소진이 실제로 의미를 갖는다.
- **A-6 1단계** — 생성 중 홈 버튼 → 복귀 시 결과가 갤러리에 남아 있는지.
- **A-7** — 실제 정책 위반 프롬프트를 실서버에 보내 **서버 안내 문구가 그대로** 보이는지.
- **A-8** — 기내 모드 ON→OFF 직후 생성 시도 시 "연결이 어려워요" 오탐이 안 나는지.
- **B-1** — Health Connect 실데이터로 지난 밤 값이 맞는지, 36시간 넘은 기록만 있을 때 `-` 로 뜨는지.
- **B-4** — 수면 종료 07:00 설정 후 07:30 에 '잠 깨는 중' 구간이 맞게 표시되는지.
- **D-1** — 워치에서 `ACTIVITY_RECOGNITION` 런타임 권한이 실제 승인되는지,
  산책 시작 후 ENTER 전환까지 걸리는 시간(Play Services 특성상 수십 초~수 분),
  `WATCH_ACT_FRESH_MS = 10분` 이 과하지 않은지(운동 끝나고 10분간 산책 상태 유지됨).
- **C-5 / C-6** — 폰트·픽셀 아이콘이 저해상도/큰 글씨 접근성 설정에서 깨지지 않는지.
