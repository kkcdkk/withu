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

순수 함수. HealthKit/날씨/시간 → `CharacterState`. **우선순위**: 운동 (최근 1시간) → 수면 (HealthKit 일정 또는 `CharacterProfile` 의 sleep window) → 기상 직후 1시간 → 식사 시간 → 날씨. `now`/`calendar` 주입 가능 — 시간 의존 로직 테스트 가능하게 설계됨.

## 백엔드 — Cloudflare Worker (`cloudflare/withu-api/`)

앱은 `withu/Networking/APIConfig.swift` 의 `baseURL` 한 곳만 본다. Debug/Release 모두 배포된 Worker (`https://withu-api.ysy1398.workers.dev`) 를 사용. **이 파일은 skip-worktree 로 커밋 제외** (`apiToken` 실값이 로컬에만 있음) — diff 에 안 보여도 정상이고, 수정 시 커밋하지 말 것. (예전 FastAPI proxy `~/dev/withu-server/` 는 레거시 — 필요 시 APIConfig 주석 참고.)

Worker 구성 (`src/index.js` 라우팅 · `src/auth.js` Apple JWT/JWS 검증 · `src/db.js` D1):
- **라우트**: `GET /health`, `POST /auth/apple` (identityToken → sessionToken), `GET|DELETE /me`, `POST /iap/verify` (StoreKit 2 signed transaction → entitlement), `POST /redeem`, `POST /referral/apply`, `POST /generate`.
- **바인딩/시크릿**: D1 `withu-prod` (마이그레이션 `migrations/0001~0005`, 적용은 `npx wrangler d1 migrations apply withu-prod --remote`), KV `RATE_KV` (IP 일일 상한 60/일), secrets `OPENAI_API_KEY` / `WITHU_API_TOKEN` / `SESSION_SECRET`, flag `ENFORCE_AUTH` (미설정이면 /generate 는 X-Withu-Token 경로 허용 — shadow 배포).
- `/generate` 는 프롬프트 길이 제한 + OpenAI Moderation 사전검사 (참고사진 포함). **서버는 캔디를 차감하지 않는다** — 차감은 클라이언트 (아래 캔디 섹션).
- 개발: `npm run dev` / 배포: `npm run deploy` (해당 디렉터리에서).

`APIClient` 는 `actor` — URLSession 동시 호출 직렬화. `convertFromSnakeCase` / `convertToSnakeCase` 로 서버 (snake_case) ↔ Swift (camelCase) 변환. 이미지 생성이 medium 1–3분, high 2–5분 걸리니 `timeout = 1800`, `resourceTimeout = 3600`, `waitsForConnectivity = true` — 짧게 줄이면 iOS가 잘못된 "offline" 보고를 한다.

## 인증 + 결제 (캔디)

- **인증** (`withu/Auth/`): `AuthManager` — Sign in with Apple → `/auth/apple` → 세션 토큰을 `KeychainStore` 에 저장. `LoginGateView` 가 게이트. 계정 삭제 = `DELETE /me` (App Review 5.1.1(v) 필수 기능).
- **구매** (`Networking/StoreManager.swift`): StoreKit 2. 제품 = 캔디팩 `credits.30`/`credits.100` + 구독 `subscription.monthly` (`withu.storekit` 로컬 테스트 구성). 구매 JWS 를 `/iap/verify` 로 보내 서버 entitlement 에 적립.
- **캔디 잔액의 권위는 로컬** (`Networking/GenerationQuota.swift`, App Group UserDefaults): 생성 가능 판정·차감 모두 로컬 `credits`. 서버 잔액은 `syncCreditsUp(to:)` 로 **끌어올리기만** (max) — 로컬 적립분을 덮어쓰지 않음. 이 모델을 바꾸면 402 desync 가 재발한다 (커밋 `fd98948` 참고).
- 캔디 비용은 퀄리티별: low 1 · medium 2 · high 3 (`GenerationQuota.cost(forQuality:)`).
- **DEBUG 빌드는 쿼터 무제한** (`remainingToday() = 9999`, 차감 없음) — 캔디/페이월 흐름은 Release 빌드나 TestFlight 에서만 실제 동작을 검증할 수 있다. 테스트 캔디 코드 `CANDY20` 은 sandbox/DEBUG 전용.

## 기타 운영 메모

- **신규 `CharacterState` 추가 시**: rawValue가 디스크/Watch 메시지 호환 키이므로 기존 값 rename 금지. `imageAssetName`, `symbolName`, `caption`, `tint`, `generationHint`, `symbolEmoji` 를 모두 채워야 컴파일/UI가 깨지지 않는다 (enum이라 switch가 강제).
- **App Group ID** (`group.com.seoyoung.withu`) 는 4개 타깃 Capabilities에 등록되어 있어야 한다. 새 타깃 추가 시 누락되면 `containerURL` 이 nil 반환 → 공유 깨짐.
- **Vision 배경 제거** (`CharacterGen/ImageProcessing.swift`)는 iOS 17+ `VNGenerateForegroundInstanceMaskRequest` — 외부 호출/비용 없음. 단, 기본 생성은 서버에서 `background=transparent` PNG 로 받아 Vision 없이 그대로 사용.
- **프롬프트 실험** 은 `tools/prompt_lab.py` — 로컬 미니 서버가 브라우저 UI 를 띄우고 Worker 로 중계. 상태별 `generationHint` 튜닝은 앱 빌드 없이 여기서.
- **배치 생성은 백그라운드 실행** (`Networking/BackgroundGenerationManager.swift`): background URLSession + 디스크 영속 작업 큐 (Application Support/bggen/jobs.json, 순차 1개씩). 화면 꺼짐/앱 종료에도 진행되고 끝나면 로컬 알림. 앱이 죽은 사이 완료된 upload task 는 응답 본문이 유실될 수 있어(iOS 한계) 본문 없는 2xx 는 1회 재큐잉. 캔디 차감은 이 매니저의 process() 성공 시점 — 뷰(BatchCharacterGenView)는 tick 관찰로 미러링만 한다.
