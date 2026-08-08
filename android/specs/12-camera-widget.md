# 12 — 카메라 합성 (CameraX) + 홈 위젯 (Glance)

진실의 원천 (Swift):
- `withu/Camera/CameraView.swift` — 화면 본체
- `withu/Camera/CameraSession.swift` — AVCaptureSession 래퍼 (권한/구성/셔터/전후면 전환)
- `withu/Camera/CameraPreviewView.swift` — 프리뷰 레이어 브릿지
- `withu/Camera/PlacedCharacter.swift` — 배치 캐릭터 모델 (정규화 좌표)
- `withu/Camera/PhotoCompositor.swift` — 오프스크린 합성
- `withu/Camera/PhotoSaver.swift` — 사진 라이브러리 저장
- `withuWidget/withuWidget.swift` — 위젯 (개념 참조용; Android 는 Glance 로 홈 위젯만)

---

## Part A. 카메라 합성 화면

### A-1. 화면/모듈 구조 (위→아래, ZStack 레이어 순)

전체가 풀스크린 ZStack (`ignoresSafeArea`). 조건 분기:

**분기 0 — 권한 거절 회복 화면** (`isPermissionDenied && backgroundImage == nil` 일 때만; 앨범 배경을 골랐으면 카메라 없이도 진행 가능하므로 숨김):
1. Spacer
2. 오렌지 원(130pt, orange 18% 배경) + `camera.fill.badge.ellipsis` 아이콘 56pt 오렌지
3. 제목 "카메라 권한이 필요해요" (title2 semibold)
4. 본문 "캐릭터와 함께 사진을 찍으려면 카메라 접근을\n허용해 주세요." (callout, secondary, 가운데 정렬)
5. Spacer
6. 주 버튼 (핑크 배경, 흰 글자, gear 아이콘): "iOS 설정 열기" → 시스템 설정 앱의 앱 설정 화면 열기 (Android: "설정 열기" 로 문구 조정 필요 — 아래 구현 노트)
7. 보조 링크 (핑크 텍스트, PhotosPicker 트리거): "또는 앨범 사진으로 만들기"

**분기 1 — 정상 화면** (레이어 아래→위):
1. `cameraLayer` — 배경:
   - `backgroundImage != nil` → 고른 앨범 사진을 `scaledToFill` 로 풀스크린 (라이브 카메라 대신)
   - 시뮬레이터(에뮬레이터 대응) → 검은 화면 + `camera.metering.unknown` 아이콘 60pt + "시뮬레이터엔 카메라가 없어요\n실기기에서 테스트하세요" (흰색 70%, 가운데)
   - 그 외 → 라이브 카메라 프리뷰
2. `overlayLayer` — GeometryReader 안 ZStack, 배치된 캐릭터 타일들 (A-3)
3. `controlsLayer` — VStack:
   - 우상단: 상태 캡슐 텍스트 `statusText` (caption, ultraThinMaterial 캡슐, top 60 / trailing 16)
   - Spacer
   - `characterPicker` (하단 셔터 위, bottom 12):
     - 힌트 라벨 (caption2, 흰색 70%): "탭하면 캐릭터 추가 · 드래그로 이동 · 두 손가락으로 크기 · 길게 눌러 삭제"
     - 가로 스크롤 (인디케이터 없음): `CharacterState.userFacing` = `[idle, sleeping, wakingUp, eating, walking, running, cycling, energetic]` 8종. 각 칩 = 56×56 원(ultraThinMaterial) + `CharacterImageView(state:)` (padding 6) + 하단 `plus.circle.fill` 흰색 배지(검정 40% 원 배경). 탭 → 캐릭터 추가
   - 하단 컨트롤 HStack (horizontal 30, bottom 50):
     - 좌: `backgroundImage != nil` 이면 `camera.fill` 버튼 (앨범 배경 해제 → 라이브 카메라 복귀, `backgroundImage = nil; backgroundPickerItem = nil`); 아니면 `photo.on.rectangle` PhotosPicker (앨범 배경 고르기). 둘 다 50×50 원, ultraThinMaterial
     - 중앙: 셔터 버튼 — 흰 테두리 원 78pt(선 4) + 흰 채움 원 64pt, `isCapturing` 이면 중앙에 검정 ProgressView. `isCapturing` 동안 disabled
     - 우: `backgroundImage == nil` 이면 `camera.rotate.fill` 전후면 전환 버튼 (`isCapturing` 동안 disabled); 앨범 배경 모드에선 의미 없어 `Color.clear` 50×50 로 자리만 유지 (레이아웃 대칭)
4. `previewCaptured != nil` → 캡처 프리뷰 오버레이 (A-4)
5. `showSavedToast` → 토스트 "갤러리에 저장했어요"
6. `showDeleteHint` → 토스트 "드래그로 이동 · 두 손가락으로 크기 · 길게 눌러 삭제"
   - **주의**: 원본에서 `showDeleteHint` 는 선언만 되고 어디서도 true 로 세팅되지 않는 죽은 상태값. Android 도 동작 파리티만 맞추면 됨 (문구는 characterPicker 힌트 라벨에 이미 노출됨) — 구현 생략 가능하나 문구는 strings 에 보존.

토스트 스타일: ultraThinMaterial 캡슐, 하단에서 140 위, opacity 트랜지션.

### A-2. 사용자 문구 전량 (한국어 원문 그대로)

| 위치 | 문구 |
|---|---|
| 초기 상태 캡슐 | `초기화 중…` |
| 준비 완료 상태 캡슐 | `준비됨` |
| 상태 캡슐 (에러 fallback) | `에러` |
| 저장 토스트 | `갤러리에 저장했어요` |
| 삭제 힌트 토스트(죽은 코드) | `드래그로 이동 · 두 손가락으로 크기 · 길게 눌러 삭제` |
| 픽커 힌트 라벨 | `탭하면 캐릭터 추가 · 드래그로 이동 · 두 손가락으로 크기 · 길게 눌러 삭제` |
| 권한 화면 제목 | `카메라 권한이 필요해요` |
| 권한 화면 본문 | `캐릭터와 함께 사진을 찍으려면 카메라 접근을\n허용해 주세요.` |
| 권한 화면 주 버튼 | `iOS 설정 열기` → Android 는 `설정 열기` (en: "Open Settings") |
| 권한 화면 보조 링크 | `또는 앨범 사진으로 만들기` |
| 시뮬레이터 안내 | `시뮬레이터엔 카메라가 없어요\n실기기에서 테스트하세요` → Android: `에뮬레이터엔 카메라가 없어요\n실기기에서 테스트하세요` (에뮬레이터가 가상 카메라를 제공하면 이 분기 자체 불필요 — 구현 노트) |
| 프리뷰 취소 버튼 | `취소` |
| 프리뷰 저장 버튼 | `저장` |
| CameraError.notAuthorized | `카메라 권한이 없어요. 설정에서 켜주세요.` |
| CameraError.noCamera | `이 기기에서 카메라를 찾을 수 없어요.` |
| CameraError.configurationFailed | `카메라 구성에 실패했어요.` |
| CameraError.captureFailed | `사진 캡처에 실패했어요.` |
| CameraError.unavailableOnSimulator | `시뮬레이터에서는 카메라를 쓸 수 없어요. 실기기로 테스트해주세요.` |
| 전환 실패 (CameraSession.lastError) | `카메라 전환 실패` |
| PhotoSaveError.notAuthorized | `사진 저장 권한이 없어요. 설정에서 허용해주세요.` |
| PhotoSaveError.writeFailed | `저장 실패: %s` (원문 `저장 실패: \(e.localizedDescription)`) |

위젯 (Part B) 문구:

| 위치 | 문구 |
|---|---|
| 위젯 이름 (configurationDisplayName) | `withu 캐릭터` |
| 위젯 설명 | `내 캐릭터의 지금 상태를 보여줘요.` |
| 걸음 행 | `👟 %d보` |
| 활동 분 행 | `🏃 %d분` |
| 칼로리 행 | `🔥 %dkcal` |
| 수면 행 | `💤 %s` (formatHours 결과) |
| 수면 1시간 미만 | `%d분` |
| 수면 정수 시간 | `%dh` / 소수 있으면 `%d.%dh` |
| 온도 | `%d°` (반올림 정수) |

### A-3. 상태(state)와 로직

CameraView 상태:
```swift
@State private var placed: [PlacedCharacter]      // 시작값: [PlacedCharacter(state: .idle, position: (0.5, 0.6))] — "카메라는 항상 idle 하나로 시작"
@State private var selectedID: UUID?              // 선택된 캐릭터 (흰 테두리 3pt 표시)
@State private var dragStartPosition: CGPoint?    // 제스처 시작 스냅샷 (드래그 delta 기준)
@State private var pinchBaseSize: CGFloat?        // 핀치 시작 시 size
@State private var rotationBase: CGFloat?         // 회전 시작 시 각도
@State private var statusText: String             // 상태 캡슐 텍스트
@State private var isCapturing: Bool
@State private var previewCaptured: UIImage?      // 캡처 결과 (nil 아니면 프리뷰 오버레이)
@State private var showSavedToast: Bool
@State private var isPermissionDenied: Bool
@State private var backgroundImage: UIImage?      // 앨범 배경 모드
```

**PlacedCharacter 모델** — 모든 좌표는 화면 크기로 **정규화 (0~1)**:
```swift
struct PlacedCharacter: Identifiable, Equatable {
    let id: UUID
    var state: CharacterState
    var position: CGPoint   // 정규화 중심 좌표, (0.5, 0.5) = 정중앙
    var size: CGFloat       // 정규화 사이즈(정사각), 기본 0.35 = 화면 너비의 35%
    var rotation: CGFloat   // 라디안, 시계방향 +
}
func rect(in containerSize: CGSize) -> CGRect  // w = size*width, h = w (정사각), 중심 기준 배치
```
정규화의 '왜': 프리뷰 뷰 좌표계와 실제 사진 픽셀 좌표계가 다르므로, 0~1 로 들고 있다가 합성 시 사진 크기에 다시 매핑 — 화면에서 보던 상대 위치가 결과 사진에 그대로 재현됨.

**캐릭터 타일 제스처** (인스타 스티커 UX — 드래그+핀치+회전 동시):
- 탭 → `selectedID` 갱신 (선택 표시)
- 길게 누름 0.4초 → 해당 캐릭터 삭제 (`placed.removeAll`; 선택돼 있었으면 selectedID = nil)
- 드래그 → 시작 시점 position 스냅샷(`dragStartPosition`) + translation/containerSize 를 더해 이동. **x, y 모두 0~1 로 클램프**
- 핀치 → 시작 size 스냅샷 × 배율. **0.1~0.95 클램프**
- 회전 → 시작 각도 스냅샷 + 회전 라디안 (클램프 없음)
- 세 제스처 모두 `simultaneously` — 두 손가락으로 크기+회전+이동 동시 가능
- 모든 제스처 onChanged 첫 줄에서 `selectedID` 를 그 캐릭터로 세팅 (조작 = 선택)
- onEnded 에서 스냅샷 nil 리셋
- 스냅샷 변수의 '왜': SwiftUI 제스처 value 는 누적값이므로 시작 기준값을 잡아둬야 함. Compose 의 `detectTransformGestures` 는 delta(pan/zoom/rotation 증분) 를 주므로 스냅샷 없이 직접 누적해도 됨 — 클램프만 동일하게.

**타일 렌더 순서 주의**: `.rotationEffect` 후 `.position` — 회전은 캐릭터 자기 중심 기준.

**버튼별 동작**:
- 픽커 칩 탭 → `addCharacter(state)`: 새 PlacedCharacter(position (0.5, 0.55), size 0.35, rotation 0) append + 선택
- 셔터 → `shoot()`:
  - `isCapturing = true` (defer 로 해제)
  - 앨범 배경 모드면 카메라 캡처 없이 `PhotoCompositor.compose(photo: backgroundImage, placed:)` 즉시 합성
  - 라이브 모드면 `camera.capturePhoto()` await → 합성 → `previewCaptured` 세팅 (에러 시 statusText 에 한국어 에러)
- 좌측 버튼: 앨범 사진 픽커 열기 ↔ (배경 모드일 때) 라이브 카메라 복귀
- 우측 버튼: `camera.switchCamera()` 전면↔후면 토글
- 프리뷰 "취소" → `previewCaptured = nil` (재촬영)
- 프리뷰 "저장" → `saveCurrent`: 기기 갤러리 저장 → 프리뷰 닫기 → 저장 토스트 1.6초 표시 후 숨김 (애니메이션). 실패 시 statusText 에 에러

**라이프사이클**:
- `.task { setupCamera() }` — 권한 요청 → 세션 구성 → start → `statusText = "준비됨"`. `CameraError.notAuthorized` 면 `isPermissionDenied = true` (회복 화면), 그 외 CameraError 는 errorDescription 을 statusText 로
- `.onDisappear { camera.stop() }`
- CameraSession 은 **싱글턴** — '왜': 카메라는 시스템 단일 자원이고, NavigationStack 재진입 시 같은 세션 재사용. `configure()` 는 멱등 (이미 input/output 있으면 skip; 부분 잔존 시 전부 제거 후 재구성 — 재진입 시 canAddInput false 로 noCamera 오보되던 버그 방지)
- 초기 카메라 = 후면 광각

**PhotoCompositor.compose(photo:placed:)** — 사진 원본 크기 캔버스에:
1. 사진 draw
2. 각 캐릭터를 `rect(in: photo.size)` 로 픽셀 좌표 환산, rotation != 0 이면 rect 중심 기준 캔버스 회전 후 draw
3. 캐릭터 이미지 3단 fallback: ① `CharacterImageStore.load(state)` (사용자 적용 PNG) ② 번들 에셋 `character_<state>` ③ 심볼 fallback (tint 18% 원 배경 + tint 색 심볼, 크기 = rect 너비의 55%)
4. draw 는 항상 **aspect-fit** (rect 안 중앙 정렬)

**엣지 케이스**:
- 캐릭터 0개 상태 가능 (idle 도 길게 눌러 삭제 가능) — 그냥 사진만 찍힘
- 권한 거절 후에도 "또는 앨범 사진으로 만들기" 로 전체 플로우 사용 가능 (backgroundImage 가 생기면 회복 화면 조건이 풀려 정상 화면 진입)
- 앨범 배경 모드에서 셔터는 즉시 (비동기 캡처 없음)
- 드래그 클램프 덕에 캐릭터 중심이 화면 밖으로 못 나감 (가장자리 절반 걸침까지만)
- 저장 권한: iOS 는 addOnly 권한 요청 → 거절 시 `사진 저장 권한이 없어요...`. Android 10+ 는 MediaStore 삽입에 권한 불필요 — 이 에러 경로는 API 28 (WRITE_EXTERNAL_STORAGE) 에서만 발생

### A-4. 캡처 프리뷰 오버레이

- 검정 90% 풀스크린
- 합성 이미지 `scaledToFit` + padding
- 버튼 2개 가로: "취소" (bordered) · "저장" (borderedProminent, 핑크 계열 filled)

### A-5. 데이터 의존성

- **읽기**: `CharacterImageStore.load(state)` — App Group(→Android: 앱 내부 스토리지) `characters/<state>.png` 활성 슬롯. Android 파리티 스키마 (SCOPE.md): `filesDir/characters/<state>.png`
- **읽기**: `CharacterState.userFacing` 8종 + 각 state 의 `imageAssetName` / `symbolName` / `tint` (08-state-resolver 스펙의 enum 포팅 재사용)
- **쓰기**: 기기 갤러리(MediaStore) 에만 저장. **앱 내부 gallery/ 나 metadata.json 은 건드리지 않음**
- 네트워크/서버 의존 없음

### A-6. Android 구현 노트 (CameraX)

- **프리뷰+캡처**: CameraX `Preview` + `ImageCapture` 유스케이스, `PreviewView` 를 `AndroidView` 로 Compose 에 임베드. `CameraSelector.DEFAULT_BACK_CAMERA` 시작, 전환 버튼으로 토글 후 rebind. `ProcessCameraProvider` 가 lifecycle 바인딩을 해주므로 iOS 의 싱글턴/멱등 configure 로직은 불필요 — `bindToLifecycle` 로 대체
- **회전 주의**: `ImageCapture` 결과 JPEG 의 EXIF orientation 을 반영해 업라이트 Bitmap 으로 디코드한 뒤 합성할 것 (아니면 캐릭터 좌표가 90° 틀어짐). `ImageCapture.takePicture` 의 in-memory 콜백(`onCaptureSuccess(ImageProxy)`) 사용 시 `imageInfo.rotationDegrees` 로 회전 적용
- **전면 카메라 미러링**: iOS AVCapturePhotoOutput 은 전면 캡처가 비미러(실제 방향) — CameraX 도 기본 동일. 프리뷰만 미러로 보이는 차이는 iOS 와 같으므로 그대로 둠
- **제스처**: 타일별 `pointerInput { detectTransformGestures { _, pan, zoom, rotation -> ... } }` — position += pan/containerSize (0~1 클램프), size = (size*zoom).coerceIn(0.1f, 0.95f), rotation += rotationRad. 탭/롱프레스는 `detectTapGestures(onTap, onLongPress)` 를 별도 pointerInput 으로. 롱프레스 0.4초는 시스템 기본(≈500ms) 사용 허용 (파리티 오차 무시)
- **타일 렌더**: `Modifier.graphicsLayer { rotationZ = deg }` + `offset`/`size`. 선택 테두리 = `border(3.dp, Color.White, RoundedCornerShape(12.dp))`
- **합성**: `Bitmap.createBitmap(photo.width, photo.height)` + `Canvas` — `canvas.save(); canvas.rotate(deg, cx, cy); drawBitmap(aspectFitRect); canvas.restore()`. 3단 fallback: 사용자 PNG → 번들 drawable `character_<state>` → 벡터 아이콘+tint 원 (Material 아이콘으로 symbolName 매핑, 08 스펙의 매핑 테이블 재사용)
- **저장**: `MediaStore.Images` insert (`RELATIVE_PATH = Pictures/withu` 권장, API 29+; API 28 은 WRITE_EXTERNAL_STORAGE 런타임 권한 + 레거시 경로)
- **앨범 픽커**: Photo Picker (`PickVisualMedia.ImageOnly`) — 권한 불필요
- **권한**: `CAMERA` 런타임 권한. 거절 시 회복 화면 + "설정 열기" → `Settings.ACTION_APPLICATION_DETAILS_SETTINGS`. "다시 묻지 않음" 구분 없이 iOS 처럼 거절=회복 화면 단일 처리
- **상태 캡슐**: `초기화 중…` → 권한 승인+bind 성공 시 `준비됨`. CameraX 에러는 CameraError 문구 테이블로 매핑
- **에뮬레이터**: Android 에뮬레이터는 가상 카메라를 제공하므로 iOS 의 시뮬레이터 분기 불필요 — 카메라 없음 기기만 `noCamera` 문구로 처리. (시뮬레이터 안내 문구는 strings 에 보존만)
- **PhotosPickerItem → Bitmap**: picker Uri → `contentResolver.openInputStream` → `BitmapFactory` (대형 사진 OOM 방지 위해 `inSampleSize` 로 화면 크기 2배 이하로 다운샘플 권장; 합성 결과 크기는 배경 사진 크기 기준 — iOS 동일)
- **UI 재질**: `.ultraThinMaterial` → 반투명 흰/검 (`Color.White.copy(alpha = 0.25f)` 계열 + blur 없이) 로 근사. 기존 스펙들(01-home)의 재질 근사 규칙 따름

### A-7. 신규 파일 제안

```
app/src/main/java/com/seoyoung/withu/camera/CameraScreen.kt        // CameraView 대응 (레이어/컨트롤/프리뷰 오버레이)
app/src/main/java/com/seoyoung/withu/camera/CameraController.kt    // CameraSession 대응 (CameraX bind/셔터/전환)
app/src/main/java/com/seoyoung/withu/camera/PlacedCharacter.kt     // 정규화 모델 (data class)
app/src/main/java/com/seoyoung/withu/camera/PhotoCompositor.kt     // Canvas 합성
app/src/main/java/com/seoyoung/withu/camera/PhotoSaver.kt          // MediaStore 저장
```

---

## Part B. 홈 위젯 (Glance) — 개념 이식

iOS 위젯은 6개 패밀리 (잠금 3 + 홈 3). Android 는 **홈 위젯만** — 잠금화면 accessory 계열은 대응 개념 없음(제외). Glance `sizeMode = SizeMode.Responsive` 로 small/medium/large 3개 브레이크포인트를 근사.

### B-1. 구조

**데이터 (CharacterEntry 대응)** — `SharedAppState.loadMessage()` (WatchMessage JSON, Android 는 앱-위젯 공유 SharedPreferences/DataStore) 에서 읽음. 없으면 placeholder (idle, 걸음 4321, 활동 38분, 412kcal, 수면 7.5h, ☀️ 18°):
- state, todaySteps, todayActiveMinutes, todayActiveKcal, lastSleepHours, weatherEmoji, weatherTempC, weatherSunrise, weatherSunset

**Small (systemSmall 대응)** — 세로:
1. 날씨 한 줄 (있을 때만): `{이모지} {온도}°` bold 11
2. 캐릭터 46×46 + 날씨 데코 오버레이 (y -3)
3. 압축 메트릭 한 줄 (9pt secondary): `👟{걸음} · 💤{수면}` (0/nil 은 생략, `·` 구분)

**Medium** — 가로:
1. 좌: 캐릭터 64×64 + 날씨 데코 (y -4) + 아래 state caption (caption2 bold)
2. 우: 날씨 한 줄 (있을 때만) + fitnessRows compact (👟보/🏃분/🔥kcal/💤 — 각 행은 값이 있고 >0 일 때만; 걸음은 nil 아니면 0 이어도 표시)

**Large** — 세로:
1. 날씨 한 줄 (headline)
2. 캐릭터 120×120 + 날씨 데코 (y -7)
3. state caption (subheadline bold)
4. Divider
5. fitnessRows expanded

**공통**:
- 배경 **투명** (`Color.clear` — 월페이퍼 비치는 스티커 느낌). Glance: `GlanceModifier.background(Color.Transparent)`; 런처가 배경을 강제하지 않도록 `android:widgetFeatures` 확인
- 위젯 탭 → 앱 메인 열기 (iOS: `withu://main` deeplink. Android: `actionStartActivity<MainActivity>()`)
- 날씨 데코 조건: 일출/일몰로 야간이면 night, 아니면 weatherEmoji → sunny/cloudy/rainy/snowy 매핑 (`WeatherBackgroundCondition.from(emoji:)` 포팅 — 01-home 스펙의 데코와 공유)

### B-2. 로직

- **fitnessRows**: 걸음 `👟 %d보` (nil 만 생략) · 활동 `🏃 %d분` (>0) · 칼로리 `🔥 %dkcal` (>0) · 수면 `💤 formatHours(h)` (>0)
- **formatHours(h)**: h<1 → `{h*60}분`; 소수 첫째자리 0 → `{정수}h`; 아니면 `{정수}.{소수1}h`
- **weatherLine**: 온도 있으면 `{이모지 }{반올림온도}°` (이모지 없으면 온도만); 온도 없고 이모지만 있으면 이모지; 둘 다 없으면 표시 안 함
- **smallMetricLine**: 걸음(>0) + 수면(>0) 만 ` · ` join
- **캐릭터 이미지**: 3단 fallback 동일 (사용자 PNG `characters/<state>.png` → 번들 → 아이콘). iOS 는 `maxPixelSize` 256/512 로 다운샘플 로드 (위젯 메모리 한계) — Glance 도 RemoteViews Bitmap 한도가 있으므로 동일하게 다운샘플 (small/medium 256px, large 512px)
- **갱신**: iOS 는 15분 간격 entry 8개 타임라인 (`policy: .atEnd`) — '왜': 시스템이 reload 를 자주 안 해줘도 미리 만든 entry 로 자동 전환. Android 대응: `android:updatePeriodMillis` 최소 30분 + 앱에서 상태/이미지 변경 시 `WidgetCenter.reloadAllTimelines()` 대응으로 **`GlanceAppWidget.updateAll(context)` 명시 호출** (캐릭터 적용·상태 재계산·날씨 갱신 시점). 상태는 표시 시점에 저장된 스냅샷을 읽으므로 15분 미리계산은 불필요 — updateAll 훅이 파리티의 핵심
- 위젯 이름/설명 (위젯 픽커 노출): `withu 캐릭터` / `내 캐릭터의 지금 상태를 보여줘요.`

### B-3. 데이터 의존성

- 읽기: 공유 스냅샷 (iOS `SharedAppState` UserDefaults ↔ Android 는 08 스펙의 SharedAppState 포팅 — 앱과 같은 프로세스이므로 DataStore/SharedPreferences 직접 읽기) + `characters/<state>.png`
- 쓰기: 없음 (읽기 전용)

### B-4. 신규 파일 제안

```
app/src/main/java/com/seoyoung/withu/widget/CharacterWidget.kt          // GlanceAppWidget + 3 브레이크포인트 레이아웃
app/src/main/java/com/seoyoung/withu/widget/CharacterWidgetReceiver.kt  // GlanceAppWidgetReceiver
app/src/main/res/xml/character_widget_info.xml                          // appwidget-provider 메타
```

---

## 제외 항목 (SCOPE.md 기준)

- **Wear OS 전체** — 컴플리케이션(`withuComplication/`), iPhone↔Watch sync(ConnectivityManager) 대응 없음
- **잠금화면 위젯** (accessoryCircular/Rectangular/Inline) — Android 홈 위젯만
- 잠금화면 전용 문자열 (lockRectHeader/lockRectMetric/inlineText) — 홈 위젯에 안 쓰이므로 이번 범위 밖 (문구 카탈로그에는 포함 안 함)
- `containerBackgroundRemovable` 류 iOS 17 배경 토글 — Android 대응 개념 없음
- 카메라 화면의 동영상/줌/플래시 — iOS 원본에도 없음 (추가 금지)
