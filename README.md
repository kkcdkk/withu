<div align="center">

# withu

**나만의 AI 캐릭터와 함께하는 iOS / watchOS 스마트 비서**

내가 만든 캐릭터가 내 수면·운동·일상에 따라 살아 움직이고,
함께 사진도 찍을 수 있는 개인 맞춤형 컴패니언 앱.

![Platform](https://img.shields.io/badge/Platform-iOS%2017%2B%20%7C%20watchOS%2010%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-purple)
![Backend](https://img.shields.io/badge/Backend-FastAPI%20%2B%20Qwen%20%2B%20SD-green)
![License](https://img.shields.io/badge/License-Personal-lightgrey)

</div>

---

## 🌱 프로젝트 소개

상용 AI 서비스에 의존하지 않고, **내 PC에서 직접 돌리는 오픈소스 모델**(Qwen, Stable Diffusion 등)에 SwiftUI 앱이 LAN으로 붙어 움직이는 구조.

- 외부에 데이터가 안 나가서 **프라이버시 안전**
- API 사용료 **0원**
- 캐릭터의 화풍·반응까지 내가 정의

## ✨ 핵심 기능

| 기능 | 설명 |
|---|---|
| 🎨 **AI 캐릭터 생성** | 텍스트/이미지 입력으로 나만의 캐릭터 생성 (Stable Diffusion) |
| 📸 **함께 사진 찍기** | AVFoundation 커스텀 카메라에 캐릭터를 오버레이해서 합성 촬영 |
| 💤 **건강 데이터 연동** | HealthKit으로 수면·운동·걸음 수를 읽어 캐릭터가 반응 |
| ⌚️ **Apple Watch 위젯** | 활동 상태에 따라 컴플리케이션 이미지가 동적으로 변경 |
| 🔔 **알림 반응** | 전화·메시지 알림에 캐릭터가 반응 (Apple 정책 범위 내) |

## 🏗️ 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                       내 LAN 네트워크                        │
│                                                              │
│   ┌──────────────┐         REST          ┌────────────────┐  │
│   │   📱 iPhone   │ ◄─────────────────► │  💻 내 PC      │  │
│   │  withu.app   │   JSON / base64       │   FastAPI     │  │
│   │  (Swift)     │                       │   ├─ Qwen     │  │
│   └──────┬───────┘                       │   └─ SD       │  │
│          │ WatchConnectivity              └────────────────┘  │
│   ┌──────▼───────┐                                            │
│   │  ⌚️ Watch     │                                            │
│   └──────────────┘                                            │
└─────────────────────────────────────────────────────────────┘
        │                              │
        ▼                              ▼
   HealthKit                      AVFoundation
   UserNotifications              Photos
   CallKit                        WidgetKit
```

## 🧱 기술 스택

### iOS / watchOS
- **언어**: Swift 6
- **UI**: SwiftUI (`@Observable`, `NavigationStack`, modern concurrency)
- **동시성**: Swift Concurrency (async/await, actors)
- **프레임워크**: AVFoundation · HealthKit · Photos · WatchConnectivity · WidgetKit · UserNotifications

### 백엔드 (별도 저장소)
- **언어**: Python 3.14
- **프레임워크**: FastAPI + Uvicorn
- **AI 모델**: Qwen (텍스트) · Stable Diffusion (이미지)

## 📂 프로젝트 구조

```
withu/
├── withu/
│   ├── Networking/          # FastAPI 통신 (URLSession actor, Codable, async/await)
│   │   ├── APIClient.swift
│   │   ├── APIConfig.swift
│   │   └── APIModels.swift
│   ├── HealthKit/           # 수면·운동·걸음 데이터 (Observable, async wrappers)
│   │   └── HealthKitManager.swift
│   ├── Character/           # 상태 머신 + 표시 뷰
│   │   ├── CharacterState.swift
│   │   ├── CharacterStateResolver.swift
│   │   └── CharacterView.swift
│   ├── Camera/              # AVCaptureSession + UIViewRepresentable + 합성/저장
│   │   ├── CameraSession.swift
│   │   ├── CameraPreviewView.swift
│   │   ├── CameraView.swift
│   │   ├── PhotoCompositor.swift
│   │   └── PhotoSaver.swift
│   ├── ContentView.swift
│   ├── withuApp.swift
│   └── Info.plist
└── withu.xcodeproj
```

## 🚀 시작하기

### 1. 백엔드 서버 (`withu-server` 별도 저장소)

```bash
cd ~/dev/withu-server
python3 -m venv .venv
source .venv/bin/activate
pip install "fastapi[standard]" uvicorn
uvicorn server:app --host 0.0.0.0 --port 8000
```

> `--host 0.0.0.0` 빼면 시뮬레이터/실기기에서 접근 못 함.

### 2. iOS 앱

```bash
git clone <이 저장소>
cd withu
open withu.xcodeproj
```

Xcode에서:
1. `withu/Networking/APIConfig.swift` 의 `baseURL` 을 본인 PC LAN IP로 변경
   ```swift
   static let baseURL = URL(string: "http://192.168.x.x:8000")!
   ```
   확인: 터미널에서 `ipconfig getifaddr en0`
2. **Signing & Capabilities** → Team 본인 Apple ID로 설정
3. **HealthKit Capability** 활성화 (Step 2 에서 자동 추가됨)
4. ▶ Run (`⌘R`)

> 시뮬레이터에선 카메라가 동작하지 않음 → 실기기 테스트 필요

## 🗺️ 개발 로드맵

단계별 점진적 구현 방식.

- [x] **Step 1** — 프로젝트 세팅 + FastAPI 통신 뼈대 (URLSession actor, Codable)
- [x] **Step 2** — HealthKit 권한 + 수면/운동/걸음 데이터 읽기
- [x] **Step 3** — 캐릭터 상태머신 + SwiftUI 반응형 화면 (`@Observable`)
- [x] **Step 4** — AVFoundation 커스텀 카메라 + 캐릭터 오버레이 합성 + 저장
- [ ] **Step 5** — watchOS 타겟 추가 + WatchConnectivity
- [ ] **Step 6** — WidgetKit/ClockKit 컴플리케이션 + UserNotifications

## 💡 설계 노트

### 왜 `@Observable` 인가
iOS 17부터 도입된 새 매크로. 옛 `ObservableObject` + `@Published` 보일러플레이트 제거.

```swift
// Before (iOS 13~16)
class HealthKitManager: ObservableObject {
    @Published var sleep: SleepSummary?
}

// After (iOS 17+)
@Observable
class HealthKitManager {
    var sleep: SleepSummary?
}
```

### 왜 `actor` 인가 (APIClient)
네트워크 요청은 여러 곳에서 동시에 호출될 가능성이 있음. `actor` 는 내부 상태 변경을 시리얼라이즈해서 데이터 레이스를 컴파일 타임에 방지.

### 왜 순수 함수로 상태 계산하나
`CharacterStateResolver.resolve(now:sleep:workouts:todaySteps:)` 는 시간을 인자로 받는 순수 함수.
→ 시간을 주입해서 테스트 가능, 비즈니스 로직을 뷰에서 분리.

## 🔒 프라이버시

- 모든 건강 데이터는 **HealthKit 권한 범위 내에서만** 읽음
- AI 추론은 **사용자 본인 PC에서만** 실행됨 (외부 API 호출 없음)
- 촬영한 사진은 사용자의 사진 앱에만 저장

## 📜 라이선스

개인 프로젝트. 외부 배포 계획 없음.

---

<div align="center">

Made with 🩵 + Swift + 🤖 self-hosted AI

</div>
