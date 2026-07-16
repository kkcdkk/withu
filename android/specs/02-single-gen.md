# 02 — 캐릭터 만들기 (단건 생성)

원본: `withu/CharacterGen/CharacterGenView.swift` (진실의 원천)
범위: `android/specs/SCOPE.md` 파리티 대상 — "캐릭터 만들기(단건)" 항목 전부.
같은 파일 하단의 `WeatherBackgroundGenView` 는 **이번 범위에서 제외** (§7 참고).

---

## 1. 화면/모듈 구조 (위→아래 순서)

네비게이션 타이틀: **캐릭터 만들기**
배경: 선택된 상태(`targetState`)의 상태별 그라데이션 (`backgroundGradient(for:)`), 상태 변경 시 snappy 애니메이션.
툴바 우측: **캔디 배지** (🍬 + 보유 개수, 탭 → 페이월 시트).
전체는 iOS `Form` = Android 에서는 섹션 카드형 `LazyColumn` (M3 리스트 그룹). 스크롤 시 키보드 내려감(`scrollDismissesKeyboard(.interactively)` 대응).

섹션 순서:

1. **batchSection** — 배치 생성 진입 링크 (항상 노출, 최상단)
   - NavigationLink → `BatchCharacterGenView` (스펙 03)
   - 제목 + 부제 2줄, footer 안내문
2. **modeSection** — 생성 옵션 (2개 라디오형 버튼, 체크마크 표시)
   - `AI로 캐릭터 생성하기` (aiGenerate) / `내 이미지로 캐릭터 생성하기` (importPhoto)
   - footer 는 선택 모드에 따라 다른 문구
   - 생성/처리 중(`isGenerating || isProcessing`) 비활성
3. **stateSection** — 상태 Picker (메뉴 스타일, `CharacterState.userFacing` 목록, 라벨 = `koreanShortLabel`)

### mode == aiGenerate 일 때만:

4. **promptSection** — "캐릭터 프롬프트"
   - 안내 캡션 1줄
   - 자유 설명 `TextEditor` (minHeight 100, 비어 있으면 placeholder 오버레이)
   - `DisclosureGroup("항목별 입력")` — 접이식 도우미 3필드: 주제 / 생김새 / 색감 (선택) + 캡션
5. **referenceSection** — "참고 사진 (Optional)"
   - 64×64 썸네일 (없으면 photo 아이콘 placeholder)
   - 버튼 2개 세로: `앨범에서 선택` (포토피커), `내 캐릭터에서 선택` (갤러리 sheet)
   - 참고사진 있을 때만: `사진 빼기` (destructive), "그대로 둘 것" 입력 + 예시 목록, "바꿀 것" 입력 + 예시 목록
   - footer: 참고사진 유무에 따라 문구 2종
6. **optionsSection** — "스타일" 섹션: 그림 스타일 segmented (`Soft`=casual / `Pixel`=pixel)
7. **generateButtonSection** — 만들기 (조건 3분기)
   - `isGenerating`: 진행 라벨("그리는 중… %d초", 0.5초 틱) + `그만두기` (destructive, 태스크 취소)
   - `remainingGenerations < cost && !hasFreeCreation`: `더 만들기 (충전)` → 페이월
   - 그 외: (`targetState.usesGeneratedMotion` 인 상태만) `움직이는 캐릭터로 만들기` 토글 + CTA `이 모습으로 만들기`
     - CTA disabled 조건: 설명 공백이고 참고사진도 없음
   - footer: 상황별 4종 문구 (§2)
8. **resultSection** — "결과" (resultImage != nil 일 때만)
   - 다듬은 버전을 보고 있으면 배지 라벨
   - frame0+frame1 둘 다 있으면 좌우 페이지 스와이프(TabView page 스타일, 점 인디케이터, height 260) + 아래 프레임 캡션 (`1번째` / `2번째 (움직임)`)
   - frame0 만 있으면 단일 이미지
   - 배경 segmented Picker: `흰 배경`(false) / `배경 빼기`(true) — 기본 true
   - 처리 중 표시 "배경 빼는 중…"
   - `revisedPrompt` 있으면 DisclosureGroup `실제로 사용한 설명 보기`
   - CTA `'%s' 자리에 적용하기` (%s = targetState.koreanShortLabel), 보조 `사진 앱에 저장`
   - lastError 있으면 WarningBanner 섹션
9. **refinementSection** — "이어서 다듬기" (resultImage != nil 일 때만)
   - 헤더: frame1 을 보고 있으면 `이어서 다듬기 (움직임 프레임)`, 아니면 `이어서 다듬기`
   - 다듬기 프롬프트 TextEditor (minHeight 80)
   - 버튼 `이대로 다듬기` (진행 중이면 "다듬는 중…"), disabled: isGenerating 또는 프롬프트 공백
   - footer 안내문
10. **versionHistorySection** — "다듬기 이력" (versions.count > 1 일 때만)
    - 가로 스크롤 썸네일 72×72, 선택 버전 핑크 테두리 2.5
    - 라벨: 원본은 `원본`, 이후는 `다듬음 %d`
    - footer 안내문

### mode == importPhoto 일 때만:

4'. **importSection** — "사진 고르기"
   - 포토피커 버튼: 아직 없으면 `사진 고르기`, 있으면 `다른 사진으로 바꾸기`
   - 처리 중 "배경 빼고 다듬는 중…"
   - footer 안내문
5'. **importResultSection** — "미리보기" (importedRawImage != nil 일 때만)
   - Toggle `배경 빼기` (기본 ON)
   - 미리보기 (투명 영역이 보이도록 배경 컨테이너 위에, maxHeight 300)
   - 처리 중 "배경 빼는 중…"
   - CTA `'%s' 자리에 적용하기`, 보조 `사진 앱에 저장`
   - lastError WarningBanner

### 오버레이/다이얼로그

- **캔디 안내 팝업** (AlertDialog) — 만들기/다듬기 버튼은 즉시 실행하지 않고 이 팝업 확인 후 실행 (§2, §3)
- **적용 알림**: 제목 `적용했어요`, 본문, 버튼 `확인`
- **저장 알림**: 제목 `저장했어요`, 본문 `사진 앱에 저장했어요.`, 버튼 `확인`
- **페이월 시트** (`PaywallView` — 별도 스펙), 닫히면 remainingGenerations 갱신
- **정사각 크롭 풀스크린** (`SquareCropView` — 사진 선택 직후 강제 크롭, 완료/취소 콜백)
- **갤러리 참고 선택 시트** (`GalleryReferencePicker` — 내 갤러리 이미지에서 참고사진 선택)

---

## 2. 사용자 문구 전량 (한국어 원문 그대로)

### 네비게이션/툴바
| 위치 | 문구 |
|---|---|
| 타이틀 | `캐릭터 만들기` |
| 캔디 배지 | `🍬 %d` (displayedCandy) |

### 모드 (enum rawValue)
- `AI로 캐릭터 생성하기`
- `내 이미지로 캐릭터 생성하기`

### batchSection
- 제목: `여러 상태 한 번에 만들기`
- 부제: `모든 상태의 모습을 한번에 만들어요`
- footer: `처음이라면 이걸 추천해요. 한 가지씩 만들고 싶으면 아래에서 골라요.`

### modeSection
- header: `생성 옵션`
- footer(aiGenerate): `프롬프트대로 새 캐릭터를 그려줘요. 만들 때마다 선택한 옵션에 따라 비용이 들어요.`
- footer(importPhoto): `가지고 있는 사진이나 그림을 그대로 이용헤요. 배경을 자동으로 제거하고 정사각형으로 다듬어요. 비용은 들지 않아요.`
  - 주의: "이용헤요" 는 원문 오타 그대로 유지 (파리티 원칙 — 문구 변경 금지)

### stateSection
- header: `상태` / Picker 라벨: `상태`

### promptSection
- header: `캐릭터 프롬프트`
- 캡션: `내 캐릭터가 어떤 모습인지 적어요. 상태별 동작·표정은 기본으로 시스템에 설정되어 있어요.`
- 설명칸 placeholder: `예: 둥근 초록 새싹 캐릭터, 큰 눈, 작은 몸`
- DisclosureGroup 라벨: `항목별 입력`
- 도우미 라벨/placeholder:
  - `주제` / `마시멜로 캐릭터`
  - `생김새` / `큰 눈, 둥근 몸, 새싹`
  - `색감 (선택)` / `연두 파스텔톤`
- 도우미 캡션: `채우면 위 설명칸에 자동으로 합쳐져요.`

### referenceSection
- header: `참고 사진 (Optional)`
- 버튼: `앨범에서 선택` / `내 캐릭터에서 선택` / `사진 빼기`
- "그대로 둘 것" 라벨: `그대로 둘 것`
- keep 입력 placeholder: `비우면 사진 그대로 유지돼요`
- keep 예시(멀티라인 캡션):
  ```
  - 캐릭터 정체성
  - 얼굴·표정 스타일
  - 몸 비율
  - 그림 스타일
  - 색·음영
  - 선 굵기
  - 전체 디자인
  ```
- "바꿀 것" 라벨: `바꿀 것`
- change 입력 placeholder: `바꿀 점을 적어요`
- change 예시(멀티라인 캡션):
  ```
  - 포즈: [원하는 포즈]
  - 행동: [행동]
  - 각도: [정면/측면/3/4]
  - 표정: [필요하면]
  - 소품: [필요하면]
  ```
- footer(참고사진 없음): `사진을 넣으면 그 모습을 참고해서 만들어요. 비워두면 텍스트로만 만들어요.`
- footer(참고사진 있음): `사진의 캐릭터는 그대로 두고 '바꿀 것'에 기입해 준 요소만 바뀌어요. 비우면 위에서 고른 상태의 포즈로 만들어요.`

### optionsSection
- header: `스타일` / Picker 라벨: `그림 스타일` / segmented: `Soft` / `Pixel`

### generateButtonSection
- 진행 라벨: `그리는 중… %d초` (시작시각 없으면 `그리는 중…`)
- 취소 버튼: `그만두기`
- 취소 후 에러: `이미지 생성을 그만뒀어요.`
- 충전 버튼: `더 만들기 (충전)`
- 애니메이션 토글: `움직이는 캐릭터로 만들기`
- CTA: `이 모습으로 만들기`
- footer(생성 중): `너무 오래 떠나 있으면 결과가 사라질 수 있으니, 화면에 머무르는 것을 권장해요.` (orange)
- footer(대기): `보통 20~30초 정도 걸려요.`
- footer(무료 1회): `첫 만들기 1번은 무료예요! 다음부터는 만들기·다듬기마다 캔디를 써요.` (핑크)
- footer(부족): `캔디가 부족해요. 충전하면 계속 만들 수 있어요.` (orange)
- footer(일반): `보유 캔디 %d개 · 이번 만들기 %d캔디`

### 캔디 안내 팝업
- 제목(무료 1회 보유): `첫 만들기는 무료예요`
- 제목(일반): `캔디를 사용해요`
- 확인 버튼: 다듬기면 `다듬기`, 아니면 `만들기`
- 취소 버튼: `취소`
- 본문(무료): `이번 1번은 무료로 만들어요. 다음부터는 만들기·다듬기마다 캔디를 써요 (한 장 1개).`
- 본문(새 생성): `이번 만들기에 캔디 %d개를 써요. 성공했을 때만 차감돼요.`
- 본문(다듬기): `이번 다듬기에 캔디 %d개를 써요. 성공했을 때만 차감돼요.`

### resultSection
- header: `결과`
- 다듬은 버전 배지: `다듬은 버전 %d 을 보고 있어요`
- 프레임 캡션: `1번째` / `2번째 (움직임)`
- 배경 Picker 라벨: `배경` / segmented: `흰 배경` / `배경 빼기`
- 처리 중: `배경 빼는 중…`
- DisclosureGroup: `실제로 사용한 설명 보기`
- CTA: `'%s' 자리에 적용하기`
- 보조: `사진 앱에 저장`

### refinementSection
- header: `이어서 다듬기` / `이어서 다듬기 (움직임 프레임)`
- 버튼: `이대로 다듬기` / 진행 중: `다듬는 중…`
- footer: `위 결과를 바탕으로 조금씩 바꿔가요. 다듬을 때마다 만들기와 같은 캔디가 들어요 (성공했을 때만 차감).`

### versionHistorySection
- header: `다듬기 이력`
- 라벨: `원본` / `다듬음 %d`
- footer: `탭해서 고른 버전이 적용 대상이 돼요. '원본'을 고르면 다듬기 전으로 돌아가요.`

### importSection / importResultSection
- header: `사진 고르기` / `미리보기`
- 피커 버튼: `사진 고르기` / `다른 사진으로 바꾸기`
- 처리 중: `배경 빼고 다듬는 중…` / `배경 빼는 중…`
- Toggle: `배경 빼기`
- footer: `사진을 고르면 정사각형으로 다듬어요. 배경을 뺄지는 아래에서 고를 수 있어요. 모두 기기 안에서 처리하고 비용은 들지 않아요.`
- CTA: `'%s' 자리에 적용하기` / 보조: `사진 앱에 저장`

### 알림(Alert)
- `적용했어요` / 본문: `%s 자리의 캐릭터를 바꿨어요. 홈 화면·위젯·워치에 바로 반영돼요.` / `확인`
  - Android 파리티: "워치" 문구는 원문 유지 (문구 변경 금지 원칙)
- `저장했어요` / 본문: `사진 앱에 저장했어요.` / `확인`

### 에러 문구
- `캔디가 부족해요. 충전하면 계속 만들 수 있어요.` (사전 쿼터 부족)
- `지금은 연결이 어려워요. 와이파이나 인터넷을 확인하고 다시 해주세요.` (preflight 실패)
- `이미지를 불러오지 못했어요. 다시 시도해 주세요.` (응답 base64 디코드 실패)
- `기존 이미지를 다시 불러오지 못했어요. 다시 시도해 주세요.` (다듬기 대상 슬롯 없음)
- `사진을 불러오지 못했어요.` (포토피커 로드 실패)
- `저장하지 못했어요. 다시 시도해 주세요.` (스토어 저장 실패)
- `이미지 생성을 그만뒀어요.` (사용자 취소)
- 그 외 API 오류: `error.koreanizedDescription` 매핑 (APIClient 스펙 참조)

---

## 3. 상태(state)와 로직

### 핵심 상태
```
mode: GenerationMode = aiGenerate            // 모드 전환 시 결과/에러/import 전부 reset
targetState: CharacterState = idle           // 변경 시 refinementPrompt 만 reset (prompt 는 유지 — 정체성은 상태 무관)
prompt: String = CharacterProfileStore.load().aiPrompt   // 진입 시 저장된 캐릭터 묘사로 시작
refinementPrompt, subjectField, looksField, colorField
quality = "low" (UI 노출 없음, 고정)         // 비용 = GenerationQuota.cost(forQuality:) → low 1
artStyle = "pixel"                           // "casual" | "pixel"
referenceImage, referenceKeep, referenceChange
importedRawImage, importedProcessedImage, removeBackground = true
isGenerating, isProcessing, isProcessingTransparent
resultImage(128px), resultFrame2(128px), lastFrame0FullRes(1024px)
generateAnimated = false, singleDetailFrame = 0
displayTransparent = true
revisedPrompt, lastSentPrompt, lastError
versions: [ResultVersion], selectedVersion = 0
remainingGenerations = GenerationQuota.remainingToday()
hasFreeCreation = (entitlement.freeSingleRemaining ?? 0) > 0   // 서버가 진실 — 재설치 무관 계정당 1회
lastFreeConsumed = false                     // 직전 응답의 free_consumed
pendingAction: newGeneration | refine(frame) // 캔디 팝업용
generateTask                                 // 취소 핸들 (coroutine Job)
```

### 항목별 도우미 → 자유 설명 합성 (`composeFromHelper`)
- 주제/생김새/색감 중 하나라도 바뀌면 발동: trim 후 비어있지 않은 것들을 `", "` 로 join → `prompt` 를 **덮어씀**.
- 모두 비어 있으면 prompt 를 건드리지 않음 (기존 자유 입력 보존).

### 프롬프트 조립 (`composedPrompt`)
- desc = prompt trim, pose = `targetState.generationHint`.
- **참고사진 있음** → Keep/Change 영어 템플릿 (그대로 이식):
  ```
  "Use the reference image. Keep the EXACT same character — identity, face and expression style, body proportions, art style, colors and shading, line thickness, and every design detail.{keepClause} Change ONLY: {changeClause}. Do not change the character design; keep all other visual details identical to the reference."
  ```
  - keepClause = keep 비어있지 않으면 `" Keep especially: {keep}."` 아니면 빈 문자열
  - changeClause 우선순위: **바꿀 것 > 캐릭터 프롬프트 > 상태 포즈** ('둘 중 하나만 채워도 됨' 설계)
- 참고사진 없음: desc 비면 pose 만, 아니면 `"{desc}, {pose}"`.

### 만들기 플로우 (`generate()`)
1. 버튼 → `pendingAction = .newGeneration` → 캔디 팝업 → 확인 시 실행 (취소 가능 Job 으로 보관).
2. 가드: `hasFreeCreation || GenerationQuota.canGenerate(cost)` 아니면 에러 후 종료.
3. isGenerating on, 시작시각 기록, frame2/투명캐시/에러 reset, `singleDetailFrame = 0`.
4. **background task assertion** (iOS: 30초 생존) — Android 노트 §5.
5. `APIClient.preflightPing()` — 실패 시 연결 에러 후 종료 ('왜': 30분 timeout 세션에 매달리지 않기 위한 사전 reachability 체크).
6. `saveDescription()` — prompt 를 `CharacterProfileStore.aiPrompt` 에 저장 (다음 진입 + 배치 생성이 같은 설명 공유).
7. `send(composedPrompt, reference=참고사진 PNG base64, frame=0)`.
8. **성공 판정 = resultImage 참조가 바뀌었는지** (prevResult 와 identity 비교 — '왜': 실패 시 이전 런 이미지가 남아 frame1 생성/캔디 차감으로 새는 것 방지).
9. `freeSession = lastFreeConsumed` — 서버가 이번을 계정 무료 1회로 소진했으면 **세션 전체(프레임 2장까지) 미차감**.
10. frame0 성공 && !freeSession → `GenerationQuota.record(cost)` (성공 시에만 차감).
11. **2프레임**: `generateAnimated && targetState.usesGeneratedMotion && frame0 성공` 이면:
    - `animPrompt = composedPrompt + "." + animationFrame2Instruction(targetState)` (아래 영어 지시문)
    - reference = frame0 **1024 원본** base64, `send(frame=1, matchReference=f0Full)`
    - frame1 성공 && !freeSession → 추가로 cost 차감 (총 2배 — 팝업/footer 의 `cost*2` 와 일치)
12. frame0 성공 시 **이력 리셋**: `versions = [원본 1개]`, selectedVersion = 0.

`animationFrame2Instruction` (그대로 이식):
```
" Use the reference image as the SAME character. Keep identical: face, outfit, colors, art/pixel style, line thickness, body proportions, size, scale, centered position, framing, and the flat solid background. This is the SECOND frame of a 2-frame animation loop, so the POSE MUST visibly CHANGE from the reference. Change the pose to: {state.animationFrame2Hint}. Change ONLY the pose — keep every design detail and the placement identical to the reference."
```

### 서버 전송 (`send(prompt:reference:frame:matchReference:)`)
- finalPrompt = `"{prompt}. Only the character on a transparent background — no background fill, no shadows, no extra elements."`
  ('왜': 일부 모델이 "투명"을 체커보드 격자로 그림 → 배경 지시 명시)
- 요청: `GenerateImageRequest(prompt, referenceImageBase64, steps=30, width=1024, height=1024, quality, artStyle, style="auto", model="gpt-image-2")`
- 응답 처리:
  1. base64 디코드 실패 → 에러.
  2. `ImageProcessing.chromaKeyRemoved(raw)` — gpt-image-2 는 마젠타 단색 배경으로 옴 → 크로마키 투명화 (이미 투명이면 no-op).
  3. frame==1 && matchReference 있으면 `ImageProcessing.matchedToReference(img, reference:)` — frame0 기준 크기·위치 정규화.
  4. **128×128 다운샘플** ('왜': 메인 200/워치 64/위젯 60 커버 + 디스크 절약).
  5. frame==1 이면 `ImageProcessing.colorMatched(small, reference: refSmall128)` — 색 드리프트 제거.
  6. frame0: resultImage=small, lastFrame0FullRes=processed(1024), revisedPrompt, lastSentPrompt=finalPrompt(갤러리 '만든 기록' 저장용). frame1: resultFrame2=small.
  7. `lastFreeConsumed = resp.freeConsumed ?? false`; entitlement 있으면 AuthManager 반영.
- `APIError.paymentRequired`(402) → 페이월 표시. 그 외 → koreanized 에러.

### 다듬기 플로우 (`refine(frame:)`)
- 버튼 → `pendingAction = .refine(frame: frame2 있으면 singleDetailFrame, 없으면 0)` — **보고 있는 프레임만 다듬음**.
- 가드: 캔디/무료 체크 → 부족 에러. 대상 슬롯(frame1 이면 resultFrame2) nil 이면 "기존 이미지를 다시 불러오지 못했어요…".
- reference(앵커): frame1 다듬기 → **frame0** 을 앵커로 (캐릭터/크기 일관성 유지), frame0 다듬기 → 자기 자신.
- frame1 다듬기 시 프롬프트에 추가:
  ```
  ". Animation frame 2 (for a 2-frame swap loop): {targetState.animationFrame2Hint}. CRITICAL: keep the character at the EXACT same size, scale, and centered position as the reference image; only the pose changes."
  ```
- 성공 판정 역시 슬롯 참조 비교. 성공 시:
  - `!lastFreeConsumed` 면 cost 차감.
  - `versions.append(isRefined=true)` 후 그 버전 선택. **8개 초과 시 index 1 제거** — 원본([0])은 항상 보존, 오래된 다듬기부터 정리.
- 끝나면 refinementPrompt = "".

### 버전 이력 (`selectVersion`)
- 조건: 유효 idx, 현재와 다름, !isGenerating.
- 선택 시 resultImage/resultFrame2/lastFrame0FullRes 를 그 버전으로 교체 (적용 대상 변경). frame2 없으면 singleDetailFrame=0.
- 투명 캐시는 버전별로 안 들고 있음 → 무효화.

### 배경 토글 (`currentDisplay(frame:)`)
- 서버 결과(raw)는 이미 투명. `배경 빼기` = raw 그대로, `흰 배경` = `ImageProcessing.flattenedOnWhite(raw)` 즉시 합성 (Vision/ML 불필요 — `ensureTransparentResults()` 는 레거시 no-op).
- 단, **다듬기 직후** '배경 빼기' 보기 중이면 해당 프레임만 `ImageProcessing.bestEffortTransparent` 재처리 (stale 방지).

### 적용 (`applyCurrentSelection` → `apply(_:to:)`)
1. `CharacterImageStore.save(image, for: state, frame: 0, prompt: lastSentPrompt)` — 실패 시 에러 + 에러 햅틱.
2. frame1 이 있으면 (현재 표시 모드 존중) frame 1 도 저장.
3. iOS: ConnectivityManager 로 워치 전송 (Android 제외), `WidgetCenter.reloadAllTimelines()` → Glance 위젯 갱신.
4. 성공 햅틱 + `적용했어요` 알림.

### 이미지 첨부 모드 (importPhoto)
1. 사진 선택 → **정사각 크롭 풀스크린** (SquareCropView) → 크롭 결과로 진행.
2. `processImport`: importedRawImage=크롭본, `ImageProcessing.prepareForCharacter` (온디바이스 배경 제거+정규화) → importedProcessedImage. 실패 시 에러 + processed=nil.
3. `displayedImport`: removeBackground ON 이면 processed(없으면 raw), OFF 면 raw.
4. 적용/저장은 AI 모드와 동일 함수 (prompt 는 nil — lastSentPrompt 는 AI 생성에만 존재).

### 엣지 케이스 정리
- 취소: Job.cancel() + 상태 원복 + `이미지 생성을 그만뒀어요.` (차감 없음 — record 는 성공 후에만).
- 모드 전환: resultImage/revisedPrompt/lastError/import 이미지 reset (versions 는 iOS 도 안 지움 — 그러나 resultImage nil 이라 결과/다듬기 섹션 숨음).
- targetState 변경: refinementPrompt 만 reset, prompt/결과 유지.
- 참고사진 제거(`사진 빼기`): referenceImage/pickerItem nil (keep/change 텍스트는 유지 — 원본 동작).
- 화면 진입 시: remainingGenerations 갱신 + `AuthManager.refreshEntitlement()` ('첫 만들기 무료' 배지가 옛 캐시로 잘못 뜨는 것 방지).
- 페이월 닫힘: remainingGenerations 갱신.
- DEBUG 빌드: 쿼터 무제한(9999) — CLAUDE.md 캔디 섹션과 동일하게 이식.

---

## 4. 데이터 의존성

| 의존 | 용도 | Android 대응 |
|---|---|---|
| `CharacterProfileStore` (`aiPrompt`) | 진입 시 설명 초기값 / 생성 직전 저장 | SharedPreferences(App Group 동형) 의 profile JSON |
| `GenerationQuota` | `remainingToday()`, `canGenerate(cost)`, `record(cost)`, `cost(forQuality:)` (low 1/medium 2/high 3), `displayedCandy()` | 포팅 (SCOPE: 로컬 쿼터가 권위, 서버는 max 끌어올리기만) |
| `AuthManager` | `entitlement.freeSingleRemaining`, `refreshEntitlement()`, `applyEntitlement()` | Auth 모듈 (스펙 별도) |
| `APIClient` | `preflightPing()`, `generateImage(GenerateImageRequest)` — snake_case 변환, timeout 1800s | Retrofit/Ktor + kotlinx.serialization SnakeCase, OkHttp read timeout 길게 |
| `CharacterImageStore` | `save(image, for:frame:prompt:)` → `characters/<state>.png` (+`_f1.png`), gallery `<uuid>.png` + `metadata.json` | 내부 저장소 동형 스키마 (SCOPE 기술 규칙) |
| `ImageProcessing` | `chromaKeyRemoved`, `flattenedOnWhite`, `matchedToReference`, `colorMatched`, `bestEffortTransparent`, `prepareForCharacter` | Bitmap 픽셀 연산 포팅 (크로마키/흰배경 합성은 순수 연산; prepareForCharacter 는 ML Kit Subject Segmentation 대체) |
| `PhotoSaver` | 사진 앱 저장 | MediaStore insert |
| `ConnectivityManager` | 워치 전송 | **제외** (Wear OS 후속) — 호출부 자체를 만들지 않음 |
| `WidgetCenter` | 위젯 리로드 | `GlanceAppWidgetManager` / `updateAll` |
| `CharacterState` | `userFacing`, `koreanShortLabel`, `generationHint`, `animationFrame2Hint`, `usesGeneratedMotion`, tint | 스펙 01(공유 모델) 포팅 |
| `PaywallView`, `SquareCropView`, `GalleryReferencePicker`, `BatchCharacterGenView`, `WarningBanner`, `WithuCTAButtonStyle` | 하위/공용 컴포넌트 | 각각 별도 스펙/공용 UI |

저장 키/파일명 (iOS 동형 유지):
- 활성 슬롯: `characters/<state.rawValue>.png`, frame1 은 `characters/<state.rawValue>_f1.png`
- 갤러리: `gallery/<uuid>.png` + `metadata.json` (prompt = lastSentPrompt 기록)

---

## 5. Android 구현 노트

- **화면**: Compose M3. iOS Form 룩 = `LazyColumn` + 섹션 카드(`Surface`/`Card`) + header/footer Text 스타일 통일. 상태별 그라데이션 배경은 `Brush.verticalGradient` + `animateColorAsState`.
- **프레임 스와이프**: `HorizontalPager` + `PagerIndicator` (TabView page 대응).
- **포토피커**: `PickVisualMedia` (Photo Picker API — 권한 불필요). 크롭은 자체 `SquareCropView` Compose 포팅 (uCrop 등 외부 라이브러리 대신 파리티 유지; iOS 커밋 45ad83d 의 포인트/픽셀 버그 교훈 — px 좌표계 하나로 통일할 것).
- **취소 가능 생성**: `viewModelScope.launch` Job 보관 → `그만두기` 에서 cancel. `send` 내부는 `ensureActive()` 체크.
- **백그라운드 생존**: iOS 의 `beginBackgroundTask`(30초) 대응 — 단건 생성은 화면 체류 전제("화면에 머무르는 것을 권장해요" footer 유지). WorkManager 로 옮기지 말 것(그건 배치 전용, 스펙 03). 필요하면 짧은 `setForeground` 없이 ViewModel 스코프로 충분 — 프로세스 킬 시 결과 유실은 iOS 와 동일한 한계로 수용.
- **경과 시간 타이머**: `TimelineView(0.5s)` → `LaunchedEffect` + `while(isActive) delay(500)` 로 elapsed 초 갱신.
- **이미지 처리**: UIImage → Bitmap. `preparingThumbnail(128)` → `Bitmap.createScaledBitmap` (filter=true). 크로마키/흰배경 합성/colorMatched/matchedToReference 는 픽셀 배열 연산으로 이식 (iOS ImageProcessing.swift 를 진실로 별도 스펙에서 상세화). `prepareForCharacter` 의 Vision 배경 제거 → **ML Kit Subject Segmentation** (온디바이스, 무비용) — 실패 시 원본 유지 + 에러 문구.
- **참조 동일성 성공 판정**: Swift 의 `!==` → Kotlin 도 Bitmap 인스턴스 `!==` 비교로 동일하게 (값 비교 금지 — 같은 이미지가 와도 새 인스턴스면 성공으로 침, iOS 와 같은 의미론).
- **햅틱**: `UINotificationFeedbackGenerator` → `HapticFeedback` (Compose `LocalHapticFeedback`) 또는 `Vibrator` effect.
- **알림/팝업**: iOS `.alert` → M3 `AlertDialog`. 시트 → `ModalBottomSheet`, 풀스크린 크롭 → 전체화면 `Dialog` 또는 네비게이션 목적지.
- **위젯 갱신**: `WidgetCenter.reloadAllTimelines()` → Glance `WithuWidget().updateAll(context)`.
- **entitlement 새로고침**: `.task {}` → `LaunchedEffect(Unit)`.
- **문구**: 전부 `strings.xml` (한국어 원문 그대로, §2). `%s`/`%d` 포맷 인자.
- **주의점**:
  - quality 는 UI 에 노출 안 됨 ("low" 고정) — 셀렉터를 임의 추가하지 말 것.
  - 캔디 차감은 **클라이언트 로컬** (서버 차감 없음 — 커밋 fd98948) + 성공 시에만. 이 모델 변경 금지.
  - 무료 1회(freeSingleRemaining)는 서버 entitlement 가 진실, 응답의 `free_consumed` 로 세션 미차감 판단.
  - base64 reference 는 1024px PNG — 요청 바디가 큼. OkHttp 타임아웃/메모리 주의.
  - `이용헤요` 오타 포함 원문 그대로.

---

## 6. 신규 파일 제안 (Android)

```
app/src/main/java/com/seoyoung/withu/gen/SingleGenScreen.kt        // 화면 (섹션 컴포저블 전부)
app/src/main/java/com/seoyoung/withu/gen/SingleGenViewModel.kt     // 상태 + generate/refine/send/버전이력
app/src/main/java/com/seoyoung/withu/gen/SingleGenModels.kt        // GenerationMode, PendingAction, ResultVersion
app/src/main/java/com/seoyoung/withu/gen/SquareCropView.kt         // 정사각 크롭 (공용 — import/reference 둘 다)
app/src/main/java/com/seoyoung/withu/gen/GalleryReferencePicker.kt // 내 캐릭터에서 참고사진 선택 시트
app/src/main/res/values/strings_single_gen.xml                     // §2 문구
```
(공유: ImageProcessing/GenerationQuota/CharacterImageStore/APIClient/CharacterState 는 스펙 01·공용 모듈.)

---

## 7. 제외 항목 (SCOPE.md 기준)

- **`WeatherBackgroundGenView` (날씨 배경 AI 생성) — 이번 범위 제외.** 같은 Swift 파일 하단에 있으나 SCOPE "제외 (후속): 배경 생성(날씨 배경 AI)" 에 해당. 진입점도 만들지 않음.
- **Wear OS 전송**: `ConnectivityManager.sendCharacterImage` 호출 전부 생략 (알림 문구의 "워치" 는 원문 유지).
- **Play Billing 실결제**: 페이월은 UI 만 (구매 버튼 '준비 중') — 캔디 배지/페이월 시트 연결 자체는 구현.
- **Google 로그인**: 무료 1회(entitlement) 는 인증 모듈 스펙에 따름 — 미로그인 상태 처리도 그쪽 스펙 참조.
