# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Read first

- **AGENTS.md** — 한국어 작업 규칙. 브랜치 모델 (`main` / `develop` / `task/<이름>`), PR base, 한국어 커밋·이슈·PR 본문, signing/LAN IP/secret 커밋 금지, 일반 PR base = `develop` (배포 PR만 `develop → main`). Claude도 이 규칙을 따른다.
- **README.md** — 사용자/세팅 관점 개요.
- **RELEASE_ACTIVATION.md** — Apple Developer 승인 후 결제/인증 활성화 체크리스트 (무엇이 이미 켜져 있고 무엇이 대기 중인지의 단일 소스).

## Build & verify

`withu.xcodeproj` 단일 프로젝트, scheme = `withu`. 테스트 타깃은 아직 없음.

스킴/타깃 확인:
```bash
xcodebuild -list -project withu.xcodeproj
```

로컬 signing 없이 컴파일만 검증 (Claude의 기본 검증 루트):
```bash
xcodebuild -project withu.xcodeproj -scheme withu \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

카메라(AVFoundation) 플로우 전체는 실기기만 검증 가능 — 시뮬레이터에서 빌드 통과 ≠ 카메라 동작 확인.

## Xcode 타깃 4개 (한 프로젝트 안)

| 타깃 | 폴더 | 역할 |
|---|---|---|
| `withu` | `withu/` | iOS 앱 |
| `withu Watch App` | `withu Watch App/` | watchOS 앱 |
| `withuWidgetExtension` | `withuWidget/` | iOS 잠금/홈화면 위젯 |
| `withuComplicationExtension` | `withuComplication/` | watchOS 시계 페이스 컴플리케이션 |

**4개 타깃이 공유하는 파일은 `withu/Shared/` 와 `withu/Character/` 일부에 모여 있음.** 새 파일을 여기에 두거나 이쪽 파일을 수정할 때는 Xcode UI에서 **Target Membership 4개 모두 체크**돼 있는지 확인해야 함 (체크 누락 시 위젯/워치 빌드만 조용히 깨짐).

대표 공유 파일:
- `Shared/SharedAppState.swift` — App Group UserDefaults 래퍼 (`group.com.seoyoung.withu`)
- `Shared/WatchMessage.swift` — iPhone→Watch 스냅샷 (Codable)
- `Shared/CharacterImageStore.swift` — App Group 컨테이너 안의 PNG/메타 저장소
- `Character/CharacterState.swift` / `CharacterImageView.swift`

## 데이터 공유 아키텍처

모든 타깃은 같은 App Group (`group.com.seoyoung.withu`) 안의 두 채널을 통해 동기화:

1. **`SharedAppState` (UserDefaults 안의 `WatchMessage` JSON)** — 캐릭터 state, 걸음/수면/날씨 스냅샷.
2. **`CharacterImageStore` (파일)**
   - `characters/<state>.png` — 활성 슬롯. 위젯/컴플리케이션/메인뷰가 모두 이걸 읽음. `_f1.png` suffix는 애니메이션 frame 1.
   - `gallery/<uuid>.png` + `metadata.json` — 전체 이력.

iOS 앱이 저장 후에는 `WidgetCenter.shared.reloadAllTimelines()` 로 위젯 갱신을 트리거해야 함.

## iPhone ↔ Watch sync (`Connectivity/ConnectivityManager.swift`)

- **상태 메시지**: `updateApplicationContext` (last-value sync; reachable 아니어도 다음에 반영).
- **이미지 파일**: `session.transferFile` + metadata. `characterImageMetadataKey` / `characterFrameMetadataKey` 로 어느 state·frame인지 표시.
- **반드시 다운샘플** 후 전송 (`watchImageMaxPixelSize = 100`). 1024×1024 원본을 그대로 보내면 워치 RAM/전송 둘 다 터짐.
- 이미지 전송 후 마지막 `WatchMessage` 의 timestamp만 갱신해 재전송 → 워치 쪽 `WidgetCenter` reload 트리거.
- 같은 메시지 중복 전송 방지를 위해 `lastSentMessage` 비교 후 skip.

## 캐릭터 표시 3단 fallback (`Character/CharacterImageView.swift`)

```
1) CharacterImageStore (App Group PNG, 사용자 적용본)
2) Assets.xcassets/character_<state>  (번들 일러스트)
3) SF Symbol (state.symbolName)        — 최후 fallback, 절대 깨지지 않음
```

이 순서는 **건드리지 말 것**. 위젯에선 `maxPixelSize` 로 `loadThumbnail` 호출 (메모리 한계 위반 방지). 컴플리케이션은 `outlineOnly: true` (단색 강제 환경).

## 상태 결정 로직 (`Character/CharacterStateResolver.swift`)

순수 함수. HealthKit/날씨/시간 → `CharacterState`. **우선순위**: 운동 (최근 1시간) → 수면 (HealthKit 일정 또는 `CharacterProfile` 의 sleep window) → 기상 직후 1시간 → 식사 시간 → 날씨. `now`/`calendar` 주입 가능 — 시간 의존 로직 테스트 가능하게 설계됨. 운동 신호는 HealthKit 워크아웃 외에 CoreMotion 실시간 감지 (`HealthKit/MotionActivityManager.swift` — 워치 없이 산책/달리기/자전거, cadence 임계값으로 걷기/달리기 구분) 도 들어온다.

## 백엔드 — Cloudflare Worker (`cloudflare/withu-api/`)

앱은 `withu/Networking/APIConfig.swift` 의 `baseURL` 한 곳만 본다. Debug/Release 모두 배포된 Worker (`https://withu-api.ysy1398.workers.dev`) 를 사용. **이 파일은 skip-worktree 로 커밋 제외** (`apiToken` 실값이 로컬에만 있음) — diff 에 안 보여도 정상이고, 수정 시 커밋하지 말 것. (예전 FastAPI proxy `~/dev/withu-server/` 는 레거시 — 필요 시 APIConfig 주석 참고.)

Worker 구성 (`src/index.js` 라우팅 · `src/auth.js` Apple JWT/JWS 검증 · `src/db.js` D1):
- **라우트**: `GET /health`, `POST /auth/apple` (identityToken → sessionToken), `GET|DELETE /me`, `POST /iap/verify` (StoreKit 2 signed transaction → entitlement), `POST /redeem`, `POST /referral/apply`, `POST /generate`, `GET /admin` (생성 모니터링 대시보드).
- **바인딩/시크릿**: D1 `withu-prod` (마이그레이션 `migrations/0001~0007`, 적용은 `npx wrangler d1 migrations apply withu-prod --remote`), KV `RATE_KV` (IP 일일 상한 60/일), R2 `LOG_BUCKET` (`withu-gen-logs`), secrets `OPENAI_API_KEY` / `WITHU_API_TOKEN` / `SESSION_SECRET` / `ADMIN_TOKEN`, flag `ENFORCE_AUTH` (미설정이면 /generate 는 X-Withu-Token 경로 허용 — shadow 배포). var `ALLOW_SANDBOX_IAP="1"` 은 TestFlight 기간 한정 — 정식 출시 시 제거 필수 (wrangler.toml 주석·RELEASE_ACTIVATION.md 참고).
- `/generate` 는 프롬프트 길이 제한 + OpenAI Moderation 사전검사 (참고사진 포함). **서버는 캔디를 차감하지 않는다** — 차감은 클라이언트 (아래 캔디 섹션).
- **생성 모니터링**: `/generate` 매 호출을 D1 `gen_events` 에 1행 기록 (type/state/프롬프트/사용자 원문 입력/status), 결과 이미지는 R2 `results/<id>.png`, 참고사진은 `refs/<id>.png`. `/admin?token=<ADMIN_TOKEN>` 대시보드에서 세션(수정 체인)·계정별로 조회. 관측용 로그라 서버 차감(generation_log)과는 별개.
- 개발: `npm run dev` / 배포: `npm run deploy` (해당 디렉터리에서).

`APIClient` 는 `actor` — URLSession 동시 호출 직렬화. `convertFromSnakeCase` / `convertToSnakeCase` 로 서버 (snake_case) ↔ Swift (camelCase) 변환. 이미지 생성이 medium 1–3분, high 2–5분 걸리니 `timeout = 1800`, `resourceTimeout = 3600`, `waitsForConnectivity = true` — 짧게 줄이면 iOS가 잘못된 "offline" 보고를 한다.

## 인증 + 결제 (캔디)

- **인증** (`withu/Auth/`): `AuthManager` — Sign in with Apple → `/auth/apple` → 세션 토큰을 `KeychainStore` 에 저장. `LoginGateView` 가 게이트. 계정 삭제 = `DELETE /me` (App Review 5.1.1(v) 필수 기능).
- **구매** (`Networking/StoreManager.swift`): StoreKit 2. 제품 = 캔디팩 `credits.30`/`credits.100` + 구독 `subscription.monthly` (`withu.storekit` 로컬 테스트 구성). 구매 JWS 를 `/iap/verify` 로 보내 서버 entitlement 에 적립.
- **캔디 잔액의 권위는 로컬** (`Networking/GenerationQuota.swift`, App Group UserDefaults): 생성 가능 판정·차감 모두 로컬 `credits`. 서버 잔액은 `syncCreditsUp(to:)` 로 **끌어올리기만** (max) — 로컬 적립분을 덮어쓰지 않음. 이 모델을 바꾸면 402 desync 가 재발한다 (커밋 `fd98948` 참고).
- 캔디 비용은 퀄리티별: low 1 · medium 2 · high 3 (`GenerationQuota.cost(forQuality:)`). 앱은 low 만 사용.
- **계정 무료 1회는 '처음 만드는 화면'(단건 CharacterGenView) 전용.** 서버 `/generate` 가 body `kind` 가 nil/"character" 이고 헤더 `X-Withu-Kind != batch` 일 때만 `free_single_remaining` 을 소진한다. 배치(X-Withu-Kind=batch)·날씨 배경(kind=background)·갤러리 다듬기(kind=refine)는 무료를 먹지 않는다 — 예전엔 body kind 만 봐서 배치/배경이 free_single 을 소진하는 버그가 있었음. (또한 2026-07-03 이전 가입 계정은 무료가 5개라 "첫 만들기 무료" 배지가 여러 번 뜨는 게 정상이었음.)
- **이미지 모델은 gpt-image-2** (클라이언트가 `model: "gpt-image-2"` 명시, 서버 기본은 1.5 — 구 빌드 호환). v2 는 투명 미지원이라 서버가 프롬프트에 **순수 마젠타(#FF00FF) 단색 배경**을 지시하고, 클라이언트가 수신 즉시 `ImageProcessing.chromaKeyRemoved()` (가장자리 연결 BFS 크로마키)로 투명화한다. 이 함수는 마젠타 없으면 no-op — 1.5 투명 결과에도 안전.
- **DEBUG 빌드는 쿼터 무제한** (`remainingToday() = 9999`, 차감 없음) — 캔디/페이월 흐름은 Release 빌드나 TestFlight 에서만 실제 동작을 검증할 수 있다. 테스트 캔디 코드 `CANDY20` 은 sandbox/DEBUG 전용.
- **캔디 코드(redeem) 관리**: D1 `redeem_codes` 에 직접 INSERT/DELETE (`cloudflare/withu-api` 에서 `npx wrangler d1 execute withu-prod --remote --command "..."`). 계정당 1회는 `code_redemptions` PK 가 자동 보장. 생성 예: `INSERT INTO redeem_codes (code, kind, amount, max_uses, used_count, expires_at) VALUES ('CANDY25','credits',25,1000000,0,NULL)`. 종료 = `DELETE FROM redeem_codes WHERE code='...'`, 현황 = `SELECT code, amount, used_count FROM redeem_codes`. 운영 중 코드: `CANDY25` (25캔디).

## Android 앱 (`android/`)

iOS 앱의 **파리티 포트** — Kotlin + Compose(M3), 같은 Cloudflare Worker 를 그대로 쓴다. **Swift 원본이 진실**: 문구·레이아웃·저장 스키마·캔디 모델을 그대로 옮긴 것이라, Android 쪽을 고칠 때는 대응하는 iOS 파일과 어긋나지 않는지 먼저 확인한다. 스코프·설계 계약은 `android/specs/` 에 있다 (`SCOPE.md`, `00-PLAN.md` = 파일 소유권 지도, `01~12` = 화면별 스펙, `PARITY-GAPS.md` = iOS 대비 남은 갭 목록).

빌드/테스트 (`android/` 디렉터리, `build.sh` 가 JDK 21·ANDROID_HOME 고정):
```bash
./build.sh :app:assembleDebug        # Claude 의 기본 검증 루트
./build.sh test                      # JVM 유닛테스트 (Robolectric)
./build.sh test --tests "*CharacterStateResolverTest"   # 단일 테스트
```
`gradlew` 를 직접 호출하지 말 것 — JAVA_HOME 이 안 잡혀 실패한다. 항상 `./build.sh` 경유.

파리티를 지탱하는 불변 규칙 (`00-PLAN.md §0`):
- **키·파일명은 iOS 와 바이트 동일**: SharedPreferences 키 (`withu.*.v1`), 저장 스키마 (`characters/<raw>.png`, `gallery/<uuid>.png`+`metadata.json`), `CharacterState.raw` 문자열. **rename 절대 금지** (iOS 와 데이터 호환이 깨짐).
- **문구는 iOS Localizable 한국어 원문 그대로** (`res/values/strings.xml`, `values-en` = 카탈로그 en). 오타까지 보존. 서버 프롬프트 영문 (`generationHint`) 은 리소스가 아니라 **코드 상수**.
- **캔디는 로컬 권위** (`quota/GenerationQuota.kt`) — iOS 와 동일. 서버 차감 없음, `syncCreditsUp` 은 max 끌어올리기만. DEBUG = 무제한 9999·차감 no-op.
- 공유 싱글턴은 `WithuApp.appContext` 를 내부에서 쓴다 — **공유 API 시그니처에 Context 파라미터 없음**. 파일 I/O 는 `Dispatchers.IO`, Compose 에서 저장소 직접 호출 금지.
- **제외(후속)**: Google 로그인(`/auth/google`), Play Billing 실결제, 날씨 배경 AI. 호출 지점은 no-op + 주석 처리.

주요 대응 관계 (iOS → Android, 로직/스키마 동형):
- `Shared/CharacterImageStore.swift` → `shared/CharacterImageStore.kt` (활성 슬롯/갤러리/애니 토글/야간 판정)
- `Character/CharacterStateResolver.swift` → `character/CharacterStateResolver.kt` (순수 함수 상태 결정)
- `Networking/APIClient.swift` → `net/ApiClient.kt` (+ `ApiModels.kt`/`ApiError.kt`, `okhttp`)
- `Networking/GenerationQuota.swift` → `quota/GenerationQuota.kt`
- `CharacterGen/ImageProcessing.swift` (크로마키) → `gen/ImageProcessing.kt` + `gen/ChromaKey.kt`
- 배치 백그라운드 큐: iOS `BackgroundGenerationManager` (background URLSession) → Android `bggen/` (WorkManager `GenBatchWorker`)
- 위젯: iOS WidgetKit → Android `widget/` (Glance).
- 워치: iOS watchOS 앱/컴플리케이션 → **Wear OS 모듈 `android/wear/`** (`:wear` Gradle 모듈, 빌드는 `./build.sh :wear:assembleDebug`). 캐릭터 Tile + 컴플리케이션 + 워치 단독 손목 모션 감지(`motion/`), 폰→워치는 Data Layer (`wear/.../sync/`, 폰 쪽 송신은 `app/.../watch/WearSyncManager.kt`). 이미지 DataItem 에 `updatedAt` 을 넣어야 갱신이 전달된다.
- `MainActivity.kt` = 전체 nav graph(11 route) + 온보딩 게이트 + 알림 딥링크. 화면끼리 직접 호출하지 않고 이동은 전부 여기 콜백으로 배선.
- 서버 토큰은 `local.properties` 의 `WITHU_API_TOKEN` → `BuildConfig` (iOS `APIConfig.swift` 와 같은 커밋-제외 정책).

Play 스토어 배포 자료 (문구·아이콘·피처그래픽·스크린샷·체크리스트)는 `android/release-assets/` (`RELEASE-PLAY.md`).

## 기타 운영 메모

- **신규 `CharacterState` 추가 시**: rawValue가 디스크/Watch 메시지 호환 키이므로 기존 값 rename 금지. `imageAssetName`, `symbolName`, `caption`, `tint`, `generationHint`, `symbolEmoji` 를 모두 채워야 컴파일/UI가 깨지지 않는다 (enum이라 switch가 강제).
- **App Group ID** (`group.com.seoyoung.withu`) 는 4개 타깃 Capabilities에 등록되어 있어야 한다. 새 타깃 추가 시 누락되면 `containerURL` 이 nil 반환 → 공유 깨짐.
- **Vision 배경 제거** (`CharacterGen/ImageProcessing.swift`)는 iOS 17+ `VNGenerateForegroundInstanceMaskRequest` — 외부 호출/비용 없음. 단, 기본 생성은 서버에서 `background=transparent` PNG 로 받아 Vision 없이 그대로 사용.
- **프롬프트 실험** 은 `tools/prompt_lab.py` — 로컬 미니 서버가 브라우저 UI 를 띄우고 Worker 로 중계. 상태별 `generationHint` 튜닝은 앱 빌드 없이 여기서.
- **법적 문서**: 원문은 `legal/*.md`, 공개 페이지는 `docs/` (개인정보처리방침·이용약관 HTML, `en/` 영문판) — 스토어 심사에 제출되는 URL 소스이므로 두 쪽을 같이 고칠 것.
- **배치 생성은 백그라운드 실행** (`Networking/BackgroundGenerationManager.swift`): background URLSession + 디스크 영속 작업 큐 (Application Support/bggen/jobs.json, 순차 1개씩). 화면 꺼짐/앱 종료에도 진행되고 끝나면 로컬 알림. 앱이 죽은 사이 완료된 upload task 는 응답 본문이 유실될 수 있어(iOS 한계) 본문 없는 2xx 는 1회 재큐잉. 캔디 차감은 이 매니저의 process() 성공 시점 — 뷰(BatchCharacterGenView)는 tick 관찰로 미러링만 한다.
