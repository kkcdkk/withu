# 작업 핸드오프 메모 (2026-07-21)

> 다른 컴퓨터의 Claude Code 가 이어서 작업하기 위한 메모.
> 브랜치: `task/watch-image-sync`. 이번 세션 변경은 **전부 iOS 파일이고 Windows 환경이라 빌드 검증을 못 했음.**
> **가장 먼저 할 일: Mac 에서 빌드 통과 확인.**
> ```bash
> xcodebuild -project withu.xcodeproj -scheme withu -configuration Debug \
>   -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
> ```

---

## A. 이번 세션에 이미 반영한 변경 (검증 대기)

전부 `withu/CharacterGen/BatchCharacterGenView.swift` 중심. 문구·버튼 스타일 일부는 Android/iOS 문자열도 함께.

1. **문구 변경 (iOS+Android 파리티)**
   - `약 %1$d캔디 (한 장당 %2$d캔디)` → `%1$d캔디 소모` (`strings_batch.xml:12` `batch_footer_cost`, iOS `BatchCharacterGenView.swift` footer, Kotlin `BatchGenScreen.kt` 호출부에서 두 번째 인자 제거)
   - `보유 캔디 %1$d개 · 이번 약 %2$d캔디` → `보유 캔디 %1$d개 · %2$d캔디 소모` (`batch_balance`, iOS 대응부)
   - KDoc 주석 `참고 사진 (Optional)` → `참고사진(선택)` (`SingleGenScreen.kt:462`)

2. **상세 시트 버튼 모양 통일**: `저장` 버튼(`.bordered`)에 `.buttonBorderShape(.roundedRectangle(radius: 12))` + 세로 패딩 → 옆 `바꾸기`(WithuCTAButtonStyle, radius 12)와 코너 일치.

3. **"더 수정할까요?" 위계**: 라벨 `.caption`→`.subheadline.weight(.semibold)` + primary 색, 예시 입력칸 body→`.footnote`.

4. **결과 섹션 배경 버튼 탭 분리 + 라벨**: `배경 모두 지우기`/`흰 배경으로` 두 버튼에 `.buttonStyle(.borderless)` (Form 한 줄 다중버튼 탭 전파 방지). `처음 그림으로`→`흰 배경으로`(square.fill), 실제 기능이 '흰 배경 복원'이라 라벨 명확화.

5. **전전 결과가 결과 그리드에 뜨는 버그 수정**: `syncFromManager()` 의 `.done` job 이미지 폴백을 활성슬롯(`CharacterImageStore.loadFrame`, = 마지막 '적용'한 다른 배치)에서 → **이 배치의 bggen frame0 원본**(`genManager.loadFrame0FullRes`)으로 교체. idle 앵커 복원도 동일하게.

6. **상세 '바꾸기' 후 시트 닫아도 로딩 표시**: `revisingFrame: [CharacterState:Int]` 추가. `reviseOne`에서 set/clear. 결과 카드에 고치는 프레임에만 로딩(frame0=메인 오버레이+경과초, frame1=우하단 미니 스피너). 헬퍼 `revisingOverlay(_:)`.

7. **배치 캔디 소모 확인 팝업 (단건과 동일하게)**: `PendingBatchAction`(start/approveRest/reviseIdle) enum + `pendingAction` 상태 + 공용 `.alert("캔디를 사용해요")`. 상세 '바꾸기'는 시트 위라 별도 `pendingReviseConfirm` alert. 메시지·확인라벨 헬퍼 `pendingActionMessage`/`pendingActionConfirmLabel`. 트리거 4곳(만들기 시작 `.start`, 나머지 만들기 `.approveRest`, 수정해서 생성하기 `.reviseIdle`, 상세 바꾸기 `pendingReviseConfirm`)이 직접 실행 대신 팝업 경유로 변경.

8. **배경 버튼 = 미리보기 전용 (홈/워치 즉시 반영 금지)**:
   - `applyTransparentToAll`/`restoreOriginalToAll`/`applyTransparentOne` → `previewTransparentAll`/`previewWhiteAll`/`previewTransparentOne` 로 교체. **활성슬롯 쓰기·워치 전송·위젯 reload 제거**, `displayTransparentByState`만 바꾸고 `appliedStates`에서 제거(카드 '적용' 다시 뜸) + 햅틱 + `bgPreviewChanged=true`.
   - 실제 반영은 `모두 적용하기`(`applyAll`)/카드 `적용`(`applyOne`)만. `applyAll`에서 `bgPreviewChanged=false`, `startBatch`에서도 리셋.
   - 결과 섹션에 안내 라벨 "미리보기를 바꿨어요. 홈·워치엔 '모두 적용하기'로 반영돼요." (`bgPreviewChanged`일 때).
   - dead `isProcessingTransparentBulk` 제거(상세 시트 '배경 빼는 중…' 스피너 포함).

> **Android 파리티 미반영**: 위 4~8은 iOS 전용. Android `bggen/BatchGenScreen.kt` 등 대응 반영 필요 여부 확인.

### 갤러리 상세 시트 재정리 (`CharacterGalleryView.swift`, 검증 대기)
9. **'다른 자리에' 위치**: 적용 중이면 "oo 자리에 적용 중" pill 오른쪽에 컴팩트 메뉴버튼("다른 자리에")을 같은 줄에. 아직 미적용이면 큰 적용 CTA + 아래 전체폭 "다른 자리에 적용하기" 메뉴(기존 유지). (메뉴 content 두 분기에 인라인 중복 — 원하면 `@ViewBuilder` 헬퍼로 정리 가능)
10. **다듬기 그룹핑**: TextField 와 "이대로 다듬기" 버튼 사이 `Divider()` 제거 → 헤더+입력칸+버튼이 한 묶음. 구분선은 다음 섹션(움직임) Divider 또는 카드 끝이 담당.
11. **움직임 섹션 문구**: 헤더 "움직이게 만들기"→"움직이는 캐릭터 만들기", 버튼 "움직이는 캐릭터 만들기"→**"이대로 움직이게"**(헤더와 중복 제거, "이대로 다듬기"와 대칭).
12. **사진 저장 위치**: 맨 아래 전체폭 "저장"(사진앱) 버튼 제거 → 상단 툴바 '닫기' 왼쪽에 `square.and.arrow.down` 아이콘 버튼으로 이동(`item.id` 로 이미지 재로드해 `saveOneToPhotos`).

### ⛔ 미구현(스키마 변경 필요) — '만든 기록' 프롬프트 노출 문제
13. **문제**: 갤러리 상세 '만든 기록'(`CharacterGalleryView.swift`, DisclosureGroup)이 `item.prompt`(= 서버로 보낸 **전체 조합 프롬프트**: 영문 generationHint·"Transparent background…"·"User modification:" 등 내부 프롬프트 엔지니어링 전부)를 그대로 노출. **사용자가 실제 입력한 텍스트만** 보여야 함.
   - `GalleryItem`(`Shared/CharacterImageStore.swift:89`)엔 `prompt`만 있고 유저 원문 필드 없음.
   - **필요 작업**: (1) `GalleryItem`에 `var userInput: String?` 추가(Codable optional → 옛 메타 하위호환). (2) `save()`/`addToGalleryInternal()`에 `userInput` 파라미터 추가. (3) 생성 호출부 전부에서 유저 원문 전달 — 단건 생성(description/`refinementPrompt`), 배치 생성(`baseIdentity`)·배치 수정(`revisionText`), 갤러리 다듬기(`refineText`)·움직임. (4) '만든 기록'에서 `item.userInput` 표시(없으면 섹션 숨김). (5) **Android 파리티 필수** — `metadata.json` 스키마는 iOS/Android 바이트 동일 규칙(CLAUDE.md)이라 `shared/CharacterImageStore.kt` GalleryItem + 저장/표시도 동일 필드 추가.
   - 빌드·파리티 검증 필요 → 검증 세션에서.
   - (임시안: 검증 전까지 '만든 기록' 섹션을 아예 숨기는 것도 가능하나, 원문 필드 추가가 정식.)

---

## B. 남은 큰 작업 — 편집화면 '적용/닫기' 리팩터 (사용자 결정: 자동저장 제거 + 명시적 적용/닫기 + 닫을 때 삭제 경고)

### 조사된 현재 저장 모델
| 화면 | 파일 | 현재 | 문제 |
|---|---|---|---|
| 내 캐릭터 설정 | `Character/CharacterProfileView.swift:12` | **전부 자동저장** (`onChange(of: profile)` `:129`가 매 변경 저장; `aiPrompt`는 키스트로크마다). 이름만 alert 안 "저장" 버튼 | 사라지진 않지만 저장 버튼 없어 헷갈림 + 이름 alert만 버튼 있어 비일관 |
| 설정(취침 리마인더) | `ContentView.swift:650`(SettingsView), DatePicker `:942`, "저장" 버튼 `:945` | 시각은 `@AppStorage`(`:673`) 즉시저장, **알림 재등록은 버튼 눌러야** | 닫으면 "시각은 저장됐는데 알림은 안 바뀜" |
| 캐릭터 만들기 설명 | `CharacterGenView.swift:22`(`prompt` `:31`) / `BatchCharacterGenView.swift`(`baseIdentity`) | **생성할 때만** `saveDescription()` 저장 (`CharacterGenView.swift` 생성부, 배치 `startBatch`) | 생성 안 하고 닫으면 수정 유실 |

### 결정된 방향
- 각 편집 화면을 **draft 상태 + "적용"/"닫기" 버튼** 모델로. 자동저장 제거.
- "적용" 안 하고 닫기(dismiss/back/시트닫기) 시 dirty 면 **"변경사항이 지워져요" 확인 알림**.
- `CharacterProfileView` 가 주 대상: `profile` 직접 바인딩을 draft copy 로 바꾸고, `animationEnabled`(별도 `CharacterImageStore`)도 draft 에 포함, `.onChange(of: profile)` 자동저장 제거, 적용 시 `CharacterProfileStore.save` + `SyncCoordinator.syncNow` + 위젯 reload.
- `SettingsView` 취침 리마인더: DatePicker 변경 시 즉시 알림 재등록(자동 적용)하거나, 닫을 때 미적용 경고.
- 캐릭터 만들기 설명은 화면 성격상 draft/적용보다 `onDisappear` 자동저장이 자연스러울 수 있음 — 사용자와 방향 재확인 권장(현재 결정은 "적용/닫기 통일").

---

## C. 새로 보고된 버그 2건 (진단 완료, 수정은 검증 세션에서)

### C-1. 갤러리 초록불(적용 표시)이 실제 적용과 어긋남
- **표시 근거**: `CharacterGalleryView.swift:598` `isActive = !CharacterImageStore.statesUsingGalleryItem(item.id).isEmpty` → 초록점 `:617`.
- `statesUsingGalleryItem` (`CharacterImageStore.swift:252`) 는 `activeSourceMap`(state→galleryId) 역검색.
- **근본 원인**: `activeSourceMap` 을 갱신하는 건 `applyGalleryItem`(`:834`)과 `save(applyToActiveSlot:true)`(`:545`) 뿐. **`saveActiveSlotOnly`(`:473`)는 활성 슬롯 PNG 만 쓰고 map 을 안 건드림.** 배치 `applyOne`(`BatchCharacterGenView` — `saveActiveSlotOnly` 사용)·단건 적용으로 슬롯을 덮어도 map 은 옛 갤러리 id 를 그대로 가리킴 → **이전에 적용했던 갤러리 항목에 초록불이 계속 뜨고, 실제 적용된 배치 결과엔 안 뜸.**
- **제안 수정**:
  - (정확) 배치 결과에 각 state 별 갤러리 id 를 보관해 `applyOne` 에서 `setActiveSource(state:galleryId:)` 호출. 단 현재 `results[state]`는 UIImage 만 들고 있어 gallery id 추적 추가 필요(생성 시 `save`가 반환하는 id 를 `[state:id]` 로 저장).
  - (최소/안전) `saveActiveSlotOnly` 에 optional `galleryId` 파라미터를 받아, 있으면 `setActiveSource`, 없으면 `setActiveSource(state, nil)` 로 **stale 매핑 제거**(적어도 틀린 초록불은 사라짐). `setActiveSource`가 `private` 이라 내부 호출로.

### C-2. 워치가 바로바로 안 바뀜
- 이미지 전송은 `ConnectivityManager.sendCharacterImage`(`:135`) → `session.transferFile`(`:161`). **`transferFile` 은 기회적(opportunistic) 백그라운드 전송이라 즉시 도착 보장 없음** (워치 unreachable 이면 큐잉되어 나중에). 상태 메시지는 `updateApplicationContext`(last-value)라 역시 즉시성 아님.
- **즉시성 개선 방향**: 워치가 `session.isReachable` 일 때는 `sendMessageData`(reachable 전용, 실시간) 로 **다운샘플 이미지 즉시 전송** fast-path 를 추가하고, 실패/unreachable 이면 기존 `transferFile` 폴백. 워치 수신측(`withu Watch App` 의 WCSession delegate `didReceiveMessageData`)에 대응 핸들러 추가 필요.
- 실기기 2대(폰+워치) 없이는 검증 불가 — 반드시 on-device.
- 참고: 이번 세션 배경-버튼 미리보기 전환(A-8)은 "적용" 시점엔 여전히 `sendCharacterImage` 를 호출하므로 워치 전송 경로 자체를 끊지 않음.

---

## D. 참고
- 캔디/무료: "만들기 화면(단건)"의 만들기·다듬기는 같은 무료-단건 경로(kind=character, header≠batch)라 **무료 횟수 남아있으면** 먼저 쓰는 것부터 무료. 신규계정(무료 1)은 첫 만들기가 소진 → 이후 수정은 캔디. (2026-07-03 이전 가입=5개, DEBUG=무제한이라 무료처럼 보임.) 사용자가 "만들기 화면 수정 1회 항상 무료"를 원하면 별도 규칙 필요.
- 커밋/문구/파리티 규칙은 `CLAUDE.md`/`AGENTS.md` 준수.
