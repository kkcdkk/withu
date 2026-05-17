<div align="center">

# withu

**내가 그린 작은 친구와 사는 하루**

자고, 걷고, 뛰고, 같이 사진 찍는 — 그것 뿐.

![Platform](https://img.shields.io/badge/Platform-iOS%2026.4%2B%20%7C%20watchOS%2026.4%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-purple)
![Backend](https://img.shields.io/badge/Backend-FastAPI%20%2B%20OpenAI%20gpt--image--2-green)
![License](https://img.shields.io/badge/License-Personal-lightgrey)

</div>

---

## 🌱 프로젝트 소개

**iOS / watchOS 의 캐릭터 컴패니언 앱.** HealthKit·날씨·시간을 보고 캐릭터의 모습이 자동으로 바뀌고, 메인 화면 / 워치 시계 페이스 / iPhone 잠금화면·홈화면 / 카메라 합성 사진까지 한 캐릭터가 따라다님.

캐릭터는 두 가지 방법으로 만들 수 있어:
- **AI 생성** (OpenAI gpt-image-2) — 자체 호스팅 FastAPI 가 proxy
- **이미지 직접 첨부** — 내가 가진 사진/그림에서 Apple Vision 으로 배경 자동 제거

## ✨ 핵심 기능

| 기능 | 설명 |
|---|---|
| 🎨 **AI 캐릭터 생성** | 프롬프트로 캐릭터 생성. 그림체 (일반/픽셀) 선택, 참고 이미지 첨부, 결과 보고 이어서 다듬기 |
| 🖼 **이미지 직접 첨부** | 사진 → Apple Vision 배경 제거 + 1024×1024 정규화 → 캐릭터 슬롯으로 적용 (무료, 로컬) |
| 📸 **함께 사진 찍기** | AVFoundation 커스텀 카메라 + 캐릭터 오버레이 합성. 9개 상태 picker 로 즉시 변경 |
| 💤 **건강 데이터 연동** | HealthKit 수면·운동·걸음 수 → 캐릭터 상태 자동 변경 (running / sleeping / energetic …) |
| 🌤 **날씨 ↔ 캐릭터** | Open-Meteo 무료 API. 매우 더우면 해변, 비 오면 우산, 눈 오면 눈놀이 |
| ⌚️ **Apple Watch** | WatchConnectivity 로 캐릭터 상태 실시간 sync + 시계 페이스 컴플리케이션 (3 family) |
| 📱 **iOS 위젯** | 잠금화면 (accessory 3종) + 홈화면 (small / medium / large) |
| 🔔 **로컬 알림** | 걸음 목표 달성 / 취침 리마인더 / 워크아웃 종료 알림 |

## 🏗️ 아키텍처

```
                ┌────────────────────────────┐
                │   ☁️  OpenAI gpt-image-2    │
                │   (HTTPS, $0.011~0.17/img)  │
                └─────────────▲───────────────┘
                              │
              ┌───────────────┴─────────────┐
              │   💻 내 PC (FastAPI proxy)   │
              │   - SYSTEM_PROMPT 분기       │
              │   - images.generate / .edit  │
              └─────────────▲───────────────┘
                              │ LAN HTTP
   ┌──────────────┐           │
   │   📱 iPhone   │ ◄─────────┘
   │   withu.app   │
   └──────┬───────┘
          │ WCSession (App Group 공유)
   ┌──────▼───────┐
   │   ⌚️ Watch    │
   └──────────────┘

   HealthKit  ·  WeatherKit (Open-Meteo)  ·  Vision (배경 제거)
   AVFoundation  ·  Photos  ·  WidgetKit  ·  UserNotifications
```

## 🧱 기술 스택

### iOS / watchOS / Widget Extensions
- **언어**: Swift 6
- **UI**: SwiftUI (`@Observable`, `NavigationStack`, `TimelineView`)
- **동시성**: Swift Concurrency (async/await, actors, continuations)
- **프레임워크**: HealthKit · AVFoundation · Photos · WatchConnectivity · WidgetKit · UserNotifications · CoreLocation · **Vision** (iOS 17+)
- **데이터 공유**: App Group (`group.com.seoyoung.withu`) 으로 메인앱 / 워치앱 / 위젯 / 워치 컴플리케이션 4개 타겟 공유

### 백엔드 (별도 저장소 `~/dev/withu-server/`)
- **언어**: Python 3.14
- **프레임워크**: FastAPI + Uvicorn
- **AI**: OpenAI Python SDK 2.x → `gpt-image-2`
- **시크릿**: `.env` 의 `OPENAI_API_KEY` (gitignore)

## 📂 프로젝트 구조

```
withu/
├── withu/                            # iOS 앱
│   ├── Networking/                   # APIClient (actor), Codable, async/await
│   ├── HealthKit/                    # @Observable 매니저 + continuation 래퍼
│   ├── Character/                    # 상태머신 + 표시 뷰 (App Group/Asset/SF Symbol 3단 fallback)
│   ├── CharacterGen/                 # AI 생성 + 이미지 첨부 + Vision 배경 제거
│   ├── Camera/                       # AVCaptureSession + UIViewRepresentable + 합성/저장
│   ├── Connectivity/                 # WCSession (sender)
│   ├── Notifications/                # UserNotifications 로컬 알림
│   ├── Shared/                       # 4개 타겟 공유 (WatchMessage, SharedAppState, CharacterImageStore)
│   ├── Weather/                      # CLLocationManager + Open-Meteo
│   ├── Assets.xcassets/              # character_<state>.imageset 9개
│   ├── ContentView.swift
│   ├── withuApp.swift
│   └── Info.plist
├── withu Watch App/                  # watchOS 앱
├── withuComplication/                # watchOS Widget Extension (시계 페이스)
├── withuWidget/                      # iOS Widget Extension (잠금/홈)
└── withu.xcodeproj
```

## 🚀 시작하기

### 1. 백엔드 서버 (`~/dev/withu-server/`)

```bash
cd ~/dev/withu-server
python3 -m venv .venv
source .venv/bin/activate
pip install "fastapi[standard]" openai python-dotenv

# OpenAI 키 설정
cp .env.example .env
# .env 에 OPENAI_API_KEY=sk-... 채우기

uvicorn server:app --host 0.0.0.0 --port 8000
```

> ⚠️ OpenAI API 사용은 ChatGPT Plus 와 별개 결제. [platform.openai.com](https://platform.openai.com) 에서 credit 충전 필요. medium $0.04/이미지.

### 2. iOS / watchOS 앱

```bash
git clone <이 저장소>
cd withu
open withu.xcodeproj
```

Xcode 에서:
1. `withu/Networking/APIConfig.swift` 의 `baseURL` 을 본인 PC LAN IP 로 변경 (`ipconfig getifaddr en0`)
2. **Signing & Capabilities** → 4개 타겟 모두 Team 본인 Apple ID 로 설정
3. ▶ Run (`⌘R`)

> 시뮬레이터에선 카메라가 동작하지 않음 → 실기기 테스트 권장. 실기기 첫 빌드 후 폰에서 **설정 → 일반 → VPN 및 기기 관리** 에서 개발자 신뢰.

## 🧪 개발 / 검증

```bash
xcodebuild -list -project withu.xcodeproj
```

로컬 signing 설정 없이 컴파일만 확인:
```bash
xcodebuild -project withu.xcodeproj \
  -scheme withu \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 🤝 에이전트 / 협업 규칙

Codex, Claude 같은 에이전트는 [AGENTS.md](AGENTS.md) 의 한국어 git 운영 규칙을 따름.

- `main`: 배포 기준 / `develop`: 개발 통합 / `task/<작업명>`: 기능 브랜치
- 일반 PR base = `develop`, 배포 PR 만 `develop -> main`
- 로컬 signing / LAN IP / secret 은 커밋하지 않음 (`git update-index --skip-worktree`)

## 🗺️ 개발 로드맵

- [x] **Step 1** — 프로젝트 세팅 + FastAPI 통신 뼈대 (URLSession actor, Codable)
- [x] **Step 2** — HealthKit 권한 + 수면/운동/걸음 데이터
- [x] **Step 3** — 캐릭터 상태머신 + SwiftUI 반응형 화면 (`@Observable`)
- [x] **Step 4** — AVFoundation 커스텀 카메라 + 캐릭터 오버레이 합성
- [x] **Step 5** — watchOS 타겟 + WatchConnectivity
- [x] **Step 6** — 워치 컴플리케이션 (WidgetKit) + UserNotifications 로컬 알림
- [x] **Step 7** — iOS 잠금/홈화면 위젯 (App Group 공유)
- [x] **Step 8** — 날씨 ↔ 캐릭터 연동 (CLLocationManager + Open-Meteo)
- [x] **Step 9** — 캐릭터 일러스트 9컷 + SF Symbol fallback
- [x] **Step 10** — OpenAI gpt-image-2 통합 (FastAPI proxy)
- [x] **Step 11** — AI 생성 이미지를 캐릭터 슬롯에 적용 (App Group 파일 저장)
- [x] **Step 12** — 그림체/참고이미지 옵션 + timeout 안정화 + 카메라 picker
- [x] **Step 13** — 이미지 직접 첨부 + Apple Vision 배경 제거
- [ ] **다음** — 캐릭터 대사/멘트 (Qwen 또는 GPT-Text), App Store 트랙

## 💡 설계 노트

### 4개 타겟 데이터 공유
App Group 컨테이너에 `WatchMessage` (Codable JSON) 와 캐릭터 PNG 파일을 두고 모든 타겟이 같은 공간을 읽음. `WidgetCenter.shared.reloadAllTimelines()` 로 위젯도 즉시 갱신.

### CharacterImageView 우선순위 fallback
1) 사용자가 적용한 App Group 파일 → 2) Asset Catalog 9컷 → 3) SF Symbol 자동 fallback. 어느 단계든 데이터 없어도 화면이 깨지지 않음.

### Vision 으로 로컬 배경 제거
iOS 17+ 의 `VNGenerateForegroundInstanceMaskRequest` — Apple Photos "주제 추출" 과 동일 기술. 인터넷·서버·비용 X.

### `actor` APIClient
URLSession 호출이 여러 화면에서 동시에 일어날 수 있음 — 내부 상태를 actor 로 시리얼라이즈해 데이터 레이스 컴파일 타임 방지.

## 🔒 프라이버시

- HealthKit 은 사용자가 명시 허용한 항목만 읽음
- 위치 데이터는 날씨 API 호출에만 사용 (서버에 저장 X)
- AI 생성 시 프롬프트가 OpenAI 로 전송됨 — 외부 호출 명시
- 촬영 / 합성 사진은 사용자 사진 앱에만 저장
- API 키, LAN IP, signing 정보는 git 에 안 들어감 (skip-worktree)

## 📜 라이선스

개인 프로젝트. 외부 배포 계획 없음.

---

<div align="center">

Made with 🩵 + Swift + 🤖

</div>
