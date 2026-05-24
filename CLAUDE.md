# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Read first

- **AGENTS.md** — 한국어 작업 규칙. 브랜치 모델 (`main` / `develop` / `task/<이름>`), PR base, 한국어 커밋·이슈·PR 본문, signing/LAN IP/secret 커밋 금지, 일반 PR base = `develop` (배포 PR만 `develop → main`). Claude도 이 규칙을 따른다.
- **README.md** — 사용자/세팅 관점 개요.

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

## 백엔드 (둘 중 하나)

앱은 `withu/Networking/APIConfig.swift` 의 `baseURL` 한 곳만 본다. `baseURL` 은 **개인 Tailscale/LAN IP가 박혀 있으니 커밋하지 말 것** (`git update-index --skip-worktree withu/Networking/APIConfig.swift` 권장).

| 백엔드 | 위치 | 비고 |
|---|---|---|
| FastAPI proxy | 별도 저장소 `~/dev/withu-server/` | 현재 디버그 흐름. 로컬 PC에서 `uvicorn server:app --host 0.0.0.0 --port 8000`. |
| Cloudflare Worker | 이 저장소 `cloudflare/withu-api/` | 같은 API 계약 (`GET /health`, `POST /generate`). `npm run dev` / `npm run deploy`. 배포 URL `https://withu-api.withu-yjs6813.workers.dev`. **앱 전환은 별도 작업으로 계획한 뒤 진행.** |

`APIClient` 는 `actor` — URLSession 동시 호출 직렬화. `convertFromSnakeCase` / `convertToSnakeCase` 로 서버 (snake_case) ↔ Swift (camelCase) 변환. 이미지 생성이 medium 1–3분, high 2–5분 걸리니 `timeout = 1800`, `resourceTimeout = 3600`, `waitsForConnectivity = true` — 짧게 줄이면 iOS가 잘못된 "offline" 보고를 한다.

## 기타 운영 메모

- **신규 `CharacterState` 추가 시**: rawValue가 디스크/Watch 메시지 호환 키이므로 기존 값 rename 금지. `imageAssetName`, `symbolName`, `caption`, `tint`, `generationHint`, `symbolEmoji` 를 모두 채워야 컴파일/UI가 깨지지 않는다 (enum이라 switch가 강제).
- **App Group ID** (`group.com.seoyoung.withu`) 는 4개 타깃 Capabilities에 등록되어 있어야 한다. 새 타깃 추가 시 누락되면 `containerURL` 이 nil 반환 → 공유 깨짐.
- **Vision 배경 제거** (`CharacterGen/ImageProcessing.swift`)는 iOS 17+ `VNGenerateForegroundInstanceMaskRequest` — 외부 호출/비용 없음.
