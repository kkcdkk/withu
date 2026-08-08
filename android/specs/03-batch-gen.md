# 03. 여러 모습 만들기 (배치 생성)

원본: `withu/CharacterGen/BatchCharacterGenView.swift` (진실의 원천, 1566줄)
관련: `Networking/BackgroundGenerationManager.swift`(백그라운드 큐), `Networking/GenerationQuota.swift`(캔디), `Shared/CharacterImageStore.swift`(저장), `CharacterGen/ImageProcessing.swift`(크로마키/흰배경 합성/색 매칭).

여러 `CharacterState`를 한 번에 생성한다. "캐릭터 정체성"(공통 설명) + state별 hint 조합. **idle(기본)을 먼저 만들어 사용자 승인을 받은 뒤(앵커), 나머지를 그 앵커 기준으로 일관되게 생성**하는 2단계 플로우가 핵심.

---

## 1. 화면/모듈 구조 (위→아래)

네비게이션 타이틀: **여러 모습 만들기**
툴바 우측: 캔디 배지 `🍬 %d` (탭 → 페이월 시트)

Form(리스트) 구성 — **승인 대기 중이면 (A)만, 아니면 (B)~(F)**:

### (A) 기준 모습 승인 섹션 `idleApprovalSection`
조건: `awaitingIdleApproval == true && results[.idle] != nil`. 이 섹션만 단독 표시(사진과 버튼이 바로 보이게).
1. idle 결과 이미지 (maxHeight 280, 라운드 16)
2. CTA 버튼 **이 모습으로 나머지 만들기** (prominent, 핑크)
3. 보조 버튼 **수정해서 생성하기** — 생성 중엔 `ProgressView + "만드는 중…"`. 수정사항 텍스트가 비어 있으면 비활성
4. 수정사항 TextField — 플레이스홀더 `수정사항을 적어주세요 (예: 더 둥글게, 색 연하게)`
5. 보조 버튼 **프롬프트 수정해서 다시** — 재생성하지 않고 결과/앵커를 전부 비우고 입력 화면으로 복귀 (캔디는 다음 '만들기 시작'에서 차감)
- 헤더: `기준 모습 확인`
- 푸터: `먼저 만든 '기본' 모습이에요. 이 모습을 기준으로 나머지를 일관되게 만들어요.\n· 마음에 들면 위에서 진행 · 살짝 고치려면 '수정해서 생성하기'(수정사항 입력) · 프롬프트부터 바꾸려면 '프롬프트 수정해서 다시'`

### (B) 상태 선택 섹션 `stateListSection`
- 헤더: `만들고 싶은 상태 (%d개)` (선택 개수)
- `CharacterState.userFacing` 별 행(`stateRow`) — 접이식(DisclosureGroup):
  - 라벨 행: 체크 토글(라벨 숨김) + `state.koreanShortLabel`(선택 해제 시 취소선) + 우측 결과 배지
    - 배지: 진행 중 → 스피너 + `%d초`(0.5s 갱신 경과시간) / 성공 → 체크 아이콘 / 실패 → 주황 경고 아이콘
  - 펼침 내용:
    1. state hint TextEditor (minHeight 60, 기본값 `state.generationHint`)
    2. 상태별 참고 이미지 피커 `stateReferencePicker`: 36×36 썸네일(없으면 사진 아이콘 placeholder) + 버튼 **앨범** / **내 캐릭터** + (사진 있을 때) **이 상태 사진 빼기** (destructive)
    3. `state.usesGeneratedMotion == true`인 상태만: 토글 **움직임 (2장 · 메인에서 움직여요)**
    4. 버튼 **기본값으로 되돌리기** (hint를 `generationHint`로 리셋)
- 마지막 행: **모두 켜기** / **모두 끄기**(destructive) — iOS 주석의 왜: Form 한 행에 버튼 여러 개면 행 아무 데나 눌러도 전부 실행됨 → 각각 borderless로 자기 탭만 받게. Compose에선 Row 안 TextButton 2개면 문제 없음.
- 푸터 2줄:
  - `%d개의 상태를 만들어요`
  - `약 %d캔디 (한 장당 %d캔디)` — `requiredCount * cost(quality)`

### (C) 캐릭터 프롬프트 섹션 `identitySection`
- TextEditor (minHeight 80), 초기값 = `CharacterProfileStore.load().aiPrompt` (단건 생성과 공유)
- 헤더: `캐릭터 프롬프트`
- 푸터: `모든 모습에 이 설명이 함께 쓰여요. 캐릭터의 생김새와 성격을 한 번에 정해 주세요.\n예: "주근깨 많은 분홍 토끼, 커다랗고 귀여운 눈"`

주의: 코드상 섹션 순서는 stateList → identity → reference → options → start → results.

### (D) 참고 사진 섹션 `referenceSection` (전역 참고 — state별 사진이 없을 때의 fallback)
- 64×64 썸네일(없으면 placeholder) + 세로 버튼 2개: **앨범에서 선택** / **내 캐릭터에서 선택**
- 사진 있을 때: **사진 빼기** (destructive)
- 사진 있을 때 추가 입력 2개:
  - 라벨 `그대로 둘 것` + TextField 플레이스홀더 `비우면 사진 그대로 유지돼요` (1~4줄)
    - 밑 설명(tertiary): `- 캐릭터 정체성\n- 얼굴·표정 스타일\n- 몸 비율\n- 그림 스타일\n- 색·음영\n- 선 굵기\n- 전체 디자인`
  - 라벨 `바꿀 것` + TextField 플레이스홀더 `모든 모습에 함께 반영할 변화 ( 씌워줘, 색 연하게)` (1~4줄)
    - 밑 설명: `각 상태의 포즈는 자동으로 적용되고, 여기 적은 변화가 모든 모습에 더해져요.`
- 헤더: `참고 사진 (Optional)`
- 푸터: `사진을 넣으면 그 캐릭터의 여러 모습으로 생성해요. 비워두면 위에 적은 설명만으로 새로 그려요.`

### (E) 스타일 섹션 `optionsSection`
- 세그먼트 피커 `그림 스타일`: **Soft**(tag "casual") / **Pixel**(tag "pixel") — 기본 pixel
- 조건부 토글 (선택 상태 중 `usesGeneratedMotion`인 게 있을 때): **모두 움직이는 캐릭터로 (한 모습당 2장)** — animatable 상태 전체가 `animatedStates`에 포함돼 있으면 on
- 상태별 움직임 칩 (가로 스크롤): 선택된 상태 중 `usesGeneratedMotion`인 것만. `emoji + koreanShortLabel` 캡슐 칩, on이면 핑크 배경/테두리. 상태 행 안의 '움직임' 토글과 같은 값 공유
- 헤더: `스타일`
- 푸터: `움직이는 캐릭터를 켜면 한 모습마다 두 장을 만들어 메인 화면에서 움직여요. 위에서 움직일 상태만 골라서 켤 수도 있어요.`
- 참고: quality 상태변수는 존재하지만("low" 고정) UI 피커 없음 — Android도 "low" 고정.

### (F) 시작 섹션 `startSection`
- CTA 버튼: 평시 **만들기 시작** (wand 아이콘) / 생성 중 `ProgressView + "만드는 중… %d/%d"` (완료+실패 수 / requiredCount)
  - 비활성 조건: 생성 중 ∨ 선택 상태 0개 ∨ baseIdentity 공백 ∨ `remainingGenerations < need`
- 생성 중일 때:
  - 안내: `앱을 닫거나 화면을 꺼도 계속 만들어요. 다 되면 알림으로 알려드려요. (%d/%d 완료)`
  - 버튼 **그만두기** (stop 아이콘, destructive) — Task cancel + `genManager.cancelAll()`, `didCancel=true`(완료 알럿 억제)
- 캔디 부족일 때 (`remainingGenerations < need`):
  - 주황 안내: `캔디 %d개로는 %d개 상태(약 %d캔디)를 한 번에 만들 수 없어요. 만들 상태를 줄이거나 캔디를 충전해 주세요.`
  - 버튼 **더 만들기 (구독·충전)** (sparkles, 핑크) → 페이월
- 그 외: `보유 캔디 %d개 · 이번 약 %d캔디`

### (G) 결과 섹션 `resultsSection`
조건: `!results.isEmpty || !errors.isEmpty`
- 헤더: `만들어진 모습`
- **수동 2열 그리드** — iOS 주석의 왜: LazyVGrid가 Form 섹션 안에서 높이 계산이 어긋나 잘림 → stride(by:2) HStack. Compose에선 LazyColumn 안 중첩 grid 제약 동일 → Row 2열 수동 배치 또는 FlowRow.
- 표시 대상: `CharacterState.allCases` 중 `displayedImage != nil || errors != nil` (선언 순서 유지)
- **결과 카드** `resultCard`:
  - 이미지(height 120, 라운드 12) — 탭 → 상세 시트
  - frame1 있으면 우하단 40×40 미니 썸네일 (흰 테두리 2)
  - 하단 행: `koreanShortLabel` + (적용됨이면) 초록 체크 아이콘
  - 버튼: 미적용 **적용** (핑크) / 적용됨 **적용됨** (secondary)
- **에러 카드** `errorCard` (카드 전체가 재시도 버튼, 진행 중엔 비활성):
  - 주황 박스(height 120) + 새로고침 아이콘 + `눌러서 다시 만들기`
  - `koreanShortLabel` + 에러 메시지(caption2, secondary)
- 결과 1개 이상이면 하단 버튼들:
  1. CTA **모두 적용하기 (%d개)**
  2. 나란히: **배경 모두 지우기** (처리 중 `다듬는 중…`) / **처음 그림으로** (destructive)
  3. **사진 앱에 모두 저장 (%d장)** (frame0+frame1 합계) — 저장 중 `저장하는 중…`

### (H) 상세 시트 `resultDetailSheet` (결과 카드 이미지 탭)
NavigationStack + ScrollView. 타이틀 **자세히 보기**, 툴바 우측 **닫기**.
1. 프레임 페이저(TabView, height 320): frame0 ↔ frame1 좌우 스와이프. frame1 있을 때만 페이지 점 표시
2. 캡션: frame1 있으면 `%s · 기본` / `%s · 움직임 프레임`, 없으면 `koreanShortLabel`만
3. 세그먼트 피커 `배경`: **흰 배경**(false) / **배경 빼기**(true) — 선택 즉시 `applyTransparentOne` 실행(활성 슬롯+워치까지 반영). 처리 중이면 `배경 빼는 중…` 표시
4. frame1 있을 때만 행:
   - 버튼 **프레임 바꾸기** — frame0↔frame1 스왑, 이미 적용된 상태였으면 즉시 재적용
   - 토글 (라벨 숨김, 의미는 **움직임**) — `CharacterImageStore.setAnimationDisabled` 반전 + 위젯 reload
5. 수정 입력:
   - 라벨: frame1 보는 중이면 `이 움직임 프레임을 어떻게 바꿀까요`, 아니면 `어떻게 바꿀까요`
   - TextField 플레이스홀더 `예: 더 귀엽게, 표정 밝게, 모자 씌워줘` (2~4줄)
   - 수정용 참고사진: 36×36 썸네일 + **사진 넣기**(없을 때)/**변경**(있을 때) + **제거**(destructive) — 선택 후 정사각 크롭 거침
6. 나란히: **저장** (현재 보는 프레임을 사진 앱에) / CTA **바꾸기** (수정 중 스피너, 텍스트 공백이면 비활성)
7. `revisionError` 있으면 주황 caption으로 표시 — 왜: 예전엔 조용히 실패해 '반영 안 됨'으로 보였음

### 알럿/시트
- 완료 알럿 — 타이틀 `다 만들었어요`, 본문 `%d개 완성, %d개 못 만들었어요. 아래 '적용' 또는 '모두 적용하기'로 홈/워치에 반영해요.`, 버튼 `확인`
- 사진 저장 알럿 — 타이틀 `사진 저장`, 본문 = saveResultMessage, 버튼 `확인`
- 페이월 시트(PaywallView), 정사각 크롭 fullScreenCover(SquareCropView), 갤러리 참고 피커 시트(GalleryReferencePicker — 전역/상태별 공용)

---

## 2. 사용자 문구 전량 (한국어 원문)

### 네비/툴바/배지
| 키(제안) | 원문 |
|---|---|
| batch_title | `여러 모습 만들기` |
| candy_badge | `🍬 %d` |

### 상태 선택
| | |
|---|---|
| header | `만들고 싶은 상태 (%d개)` |
| all_on | `모두 켜기` |
| all_off | `모두 끄기` |
| footer_count | `%d개의 상태를 만들어요` |
| footer_cost | `약 %d캔디 (한 장당 %d캔디)` |
| motion_toggle | `움직임 (2장 · 메인에서 움직여요)` |
| reset_hint | `기본값으로 되돌리기` |
| ref_album_small | `앨범` |
| ref_gallery_small | `내 캐릭터` |
| ref_remove_state | `이 상태 사진 빼기` |
| elapsed | `%d초` |

### 캐릭터 프롬프트
| | |
|---|---|
| header | `캐릭터 프롬프트` |
| footer | `모든 모습에 이 설명이 함께 쓰여요. 캐릭터의 생김새와 성격을 한 번에 정해 주세요.\n예: "주근깨 많은 분홍 토끼, 커다랗고 귀여운 눈"` |

### 참고 사진
| | |
|---|---|
| header | `참고 사진 (Optional)` |
| footer | `사진을 넣으면 그 캐릭터의 여러 모습으로 생성해요. 비워두면 위에 적은 설명만으로 새로 그려요.` |
| pick_album | `앨범에서 선택` |
| pick_gallery | `내 캐릭터에서 선택` |
| remove | `사진 빼기` |
| keep_label | `그대로 둘 것` |
| keep_placeholder | `비우면 사진 그대로 유지돼요` |
| keep_hint | `- 캐릭터 정체성\n- 얼굴·표정 스타일\n- 몸 비율\n- 그림 스타일\n- 색·음영\n- 선 굵기\n- 전체 디자인` |
| change_label | `바꿀 것` |
| change_placeholder | `모든 모습에 함께 반영할 변화 (예: 모자 씌워줘, 색 연하게)` |
| change_hint | `각 상태의 포즈는 자동으로 적용되고, 여기 적은 변화가 모든 모습에 더해져요.` |

### 스타일
| | |
|---|---|
| header | `스타일` |
| style_picker_label | `그림 스타일` |
| style_soft / style_pixel | `Soft` / `Pixel` |
| all_motion | `모두 움직이는 캐릭터로 (한 모습당 2장)` |
| footer | `움직이는 캐릭터를 켜면 한 모습마다 두 장을 만들어 메인 화면에서 움직여요. 위에서 움직일 상태만 골라서 켤 수도 있어요.` |

### 시작
| | |
|---|---|
| start | `만들기 시작` |
| generating | `만드는 중… %d/%d` |
| bg_note | `앱을 닫거나 화면을 꺼도 계속 만들어요. 다 되면 알림으로 알려드려요. (%d/%d 완료)` |
| stop | `그만두기` |
| not_enough | `캔디 %d개로는 %d개 상태(약 %d캔디)를 한 번에 만들 수 없어요. 만들 상태를 줄이거나 캔디를 충전해 주세요.` |
| paywall_cta | `더 만들기 (구독·충전)` |
| balance | `보유 캔디 %d개 · 이번 약 %d캔디` |

### 기준 모습 승인
| | |
|---|---|
| header | `기준 모습 확인` |
| approve | `이 모습으로 나머지 만들기` |
| revise | `수정해서 생성하기` |
| revising | `만드는 중…` |
| revision_placeholder | `수정사항을 적어주세요 (예: 더 둥글게, 색 연하게)` |
| back_to_prompt | `프롬프트 수정해서 다시` |
| footer | `먼저 만든 '기본' 모습이에요. 이 모습을 기준으로 나머지를 일관되게 만들어요.\n· 마음에 들면 위에서 진행 · 살짝 고치려면 '수정해서 생성하기'(수정사항 입력) · 프롬프트부터 바꾸려면 '프롬프트 수정해서 다시'` |

### 결과
| | |
|---|---|
| header | `만들어진 모습` |
| retry_card | `눌러서 다시 만들기` |
| apply / applied | `적용` / `적용됨` |
| apply_all | `모두 적용하기 (%d개)` |
| bg_remove_all | `배경 모두 지우기` |
| bg_removing | `다듬는 중…` |
| bg_restore_all | `처음 그림으로` |
| save_all | `사진 앱에 모두 저장 (%d장)` |
| saving | `저장하는 중…` |

### 상세 시트
| | |
|---|---|
| title | `자세히 보기` |
| close | `닫기` |
| frame_caption | `%s · 기본` / `%s · 움직임 프레임` |
| bg_picker | `배경` / `흰 배경` / `배경 빼기` |
| bg_processing | `배경 빼는 중…` |
| swap_frames | `프레임 바꾸기` |
| motion_toggle_label | `움직임` |
| revise_q | `어떻게 바꿀까요` |
| revise_q_f1 | `이 움직임 프레임을 어떻게 바꿀까요` |
| revise_placeholder | `예: 더 귀엽게, 표정 밝게, 모자 씌워줘` |
| ref_add / ref_change / ref_remove | `사진 넣기` / `변경` / `제거` |
| save / revise_cta | `저장` / `바꾸기` |

### 알림/에러
| | |
|---|---|
| done_title | `다 만들었어요` |
| done_body | `%d개 완성, %d개 못 만들었어요. 아래 '적용' 또는 '모두 적용하기'로 홈/워치에 반영해요.` |
| save_alert_title | `사진 저장` |
| confirm | `확인` |
| err_server | `서버에 연결할 수 없어요. 네트워크 또는 서버 상태를 확인하고 다시 시도해 주세요.` |
| err_no_image | `이미지를 받지 못했어요` |
| err_no_image_retry | `이미지를 받지 못했어요. 다시 시도해 주세요.` |
| err_failed_generic | `만들지 못했어요` |
| err_ref_load | `참고 이미지를 불러올 수 없어요. 다른 사진으로 시도해 주세요.` |
| photos_denied | `사진 추가 권한이 거부됐어요. 설정 → withu 에서 허용해 주세요.` |
| photos_saved_one | `사진 앱에 저장됐어요.` |
| photos_saved_n | `%d장 사진 앱에 저장됐어요.` |
| photos_save_failed | `저장하지 못했어요. 다시 시도해 주세요.` |

(Android는 `설정 → withu` 문구를 그대로 사용하되 시스템 설정 이동 인텐트를 연결.)

---

## 3. 상태(state)와 로직

### 주요 뷰 상태
| 이름 | 타입 | 의미 |
|---|---|---|
| baseIdentity | String | 공통 설명. 초기값 = 프로필 aiPrompt. 시작 시 프로필에 저장(saveDescription — 값이 바뀐 경우만) |
| stateHints | Map<State,String> | 상태별 포즈 hint, 기본 generationHint |
| selectedStates | Set<State> | 초기값 = userFacing 전체 |
| quality | String | "low" 고정 (UI 없음) |
| artStyle | String | "pixel" 기본, "casual"(Soft) 선택 가능 |
| animatedStates | Set<State> | frame1 만들 상태들 |
| referenceImage / stateReferenceImages | 전역/상태별 참고 사진 (상태별이 우선) |
| referenceKeep / referenceChange | 그대로 둘 것 / 바꿀 것 — **사용자 참고사진이 실제 쓰일 때만** 프롬프트 반영 |
| idleAnchor / idleFullRes | 승인된 idle 앵커. results는 128 썸네일이라 reference 품질이 떨어짐 → 원본(1024)을 별도 보관, 재시작 후엔 매니저 디스크에서 복구 |
| awaitingIdleApproval | Bool | 승인 게이트 표시 |
| results / resultsFrame1 | Map<State,Bitmap> | frame0/frame1 결과 (128 썸네일) |
| errors | Map<State,String> | 실패 메시지 |
| appliedStates | Set<State> | '적용' 누른 상태 — 배치는 갤러리에만 저장되므로 반영은 수동 |
| displayTransparentByState | Map<State,Bool> | 표시 모드. 기본 true(투명). false면 흰배경 합성 |
| inProgressStates / stateStartedAt | 진행 중 상태 + 시작 시각 (병렬 표기) |
| batchSessionId | UUID 문자열 | 서버가 같은 세션을 free_batch로 묶는 식별자. 시작마다 갱신 |
| remainingGenerations | Int | GenerationQuota.remainingToday() |

### 파생값
- `requiredCount = (idle 포함 여부 보정된 선택 수) + (움직임 상태 수)`:
  ```swift
  let base = selectedStates.contains(.idle) ? selectedStates.count : selectedStates.count + 1
  let anim = animatedStates.intersection(selectedStates.union([.idle])).count
  return base + anim
  ```
  idle을 선택 안 해도 앵커로 항상 먼저 만들므로 +1.
- `need = requiredCount * GenerationQuota.cost(forQuality: quality)` (low=1)

### 플로우 ① 만들기 시작 `startBatch()`
1. `isGenerating=true`, `batchSessionId` 갱신, 설명을 프로필에 저장, 모든 결과/에러/캐시/앵커 초기화
2. 알림 권한 요청 (첫 1회만 시스템 다이얼로그)
3. `preflightPing()` 실패 → `errors[.idle] = "서버에 연결할 수 없어요…"` 후 중단
4. idle frame0 스펙 1개만 매니저에 시작 — `phase = .anchor`. 참고사진은 사용자 사진(상태별→전역)이 있으면 그것, keep/change 반영
5. 뷰는 매니저 tick 관찰(`syncFromManager`)로만 갱신

### 플로우 ② 앵커 완료 → 승인 대기
- 매니저 `isActive`가 true→false로 떨어지고 `phase == .anchor`이며 `results[.idle] != nil`이면 `awaitingIdleApproval = true`
- 화면 재진입(onAppear) 시에도 같은 조건으로 승인 화면 복원

### 승인 화면 3버튼
- **이 모습으로 나머지 만들기** `approveIdleAndContinue()`:
  - 연타 재진입 차단 — awaitingIdleApproval을 await 전에 동기로 끔
  - 앵커 = `idleFullRes ?? 매니저 디스크 원본 ?? results[.idle]` (원본 1024 우선)
  - 나머지 선택 상태(idle 제외) 스펙 생성: reference = 상태별 명시 사진 ?? 앵커 b64. `matchIdleColor = (상태별 사진 없음)` — 앵커 기반이면 idle 색에 통일, 명시 사진은 그 사진 색 존중
  - **전역 첨부사진·keep/change는 idle 만들 때만 반영** — 나머지엔 앵커만
  - 움직임 상태는 `wantsFrame1=true` + frame1 프롬프트 동봉 (단 `usesGeneratedMotion` 상태만 — 미세 모션 상태는 절차적 애니메이션이라 2프레임 안 만듦: 색·이목구비 드리프트 방지)
  - 스펙이 비면(idle만 선택+움직임 없음) 즉시 완료 알럿 + 위젯 reload
  - 매니저 `phase = .rest` 로 시작
- **수정해서 생성하기** `reviseIdle()` — 승인 대기 유지한 채 idle만 재생성:
  - 현재 idle을 reference로, 프롬프트 = `"{설명, 포즈}. User modification: {수정사항}. Transparent background — only the character, no background fill, no shadows."`
  - **매니저 경유 아님** — APIClient 직접 호출 (kind:"batch", batchId 동봉)
  - 성공: 크로마키 투명화 → 128 썸네일 → results/idleFullRes 갱신, `CharacterImageStore.save`(갤러리+활성), 워치 전송, entitlement 반영, `GenerationQuota.record(cost)` 차감, 위젯 reload
  - 402 → 페이월. 그 외 에러 → `errors[.idle]`
- **프롬프트 수정해서 다시** — API 호출 없음. 결과/앵커/에러 전부 비우고 입력 화면 복귀 (차감은 다음 시작 때)

### 플로우 ③ 완료
- `isActive` true→false && `phase == .rest` && jobs 비어있지 않음:
  - job 중 `paymentRequired == true` 있으면 완료 알럿 대신 **페이월**
  - 아니면 완료 알럿. idle 제외 에러 없으면 성공 햅틱, 있으면 경고 햅틱 (Android: 진동 또는 생략)
- `didCancel`이면 아무 알럿도 안 띄움

### syncFromManager() — 매니저 → 뷰 단방향 동기화
- job 순회: queued/running → inProgress + startedAt / done → 이미지(메모리 캐시 ?? 디스크 `CharacterImageStore.loadFrame`) 를 frame별 results에 / failed → `errors[state] = errorMessage ?? "만들지 못했어요"`
- frame0 성공 시 해당 state 에러 제거, idle이면 idleFullRes 디스크 복구
- rest 단계엔 앵커(idle) job이 목록에 없음 → `results[.idle]`이 비면 활성 슬롯에서 복원
- `isGenerating = genManager.isActive`, 캔디 잔량 갱신

### 적용/배경/저장
- **적용(개별)** `applyOne`: 현재 표시본(frame0, 있으면 frame1도)을 `CharacterImageStore.saveActiveSlotOnly`(활성 슬롯만 — stale frame1 정리됨) + 워치 전송 + 위젯 reload + appliedStates 추가. 왜: 배치 생성은 갤러리에만 저장되므로 실제 반영은 이 버튼이 유일한 경로
- **모두 적용하기**: results 있는 모든 상태에 applyOne + 성공 햅틱
- **배경 모두 지우기** `applyTransparentToAll`: raw(모델 출력=투명 원본)를 그대로 활성 슬롯+워치 적용, 표시모드 true. Vision 불필요 (서버가 transparent PNG 반환)
- **처음 그림으로** `restoreOriginalToAll`: `ImageProcessing.flattenedOnWhite`(흰색 합성)로 활성 슬롯 적용, 표시모드 false
- **개별 배경 토글** `applyTransparentOne(state, on)`: 상세 시트 세그먼트 — on=투명 원본/off=흰 합성, 즉시 활성 슬롯+워치 반영. **주의: 표시만 바꾸는 게 아니라 적용까지 일어남**
- `displayedImage(state, frame)`: raw = 결과맵. `displayTransparentByState[state] ?? true`면 raw 그대로, false면 흰배경 합성
- **사진 앱 저장**: add-only 권한. 전체 저장은 CharacterState 선언 순서로 frame0→frame1 순 저장(사진 앱에서도 같은 순서). 결과 메시지 알럿

### 재시도 `retryOne(state)` (에러 카드 탭)
- 에러 제거 후 매니저 큐에 재추가 (`genManager.retry`)
- idle: 전역 첨부사진 + keep/change, matchIdleColor=false
- 나머지: 상태별 명시 사진 ?? 앵커(메모리→디스크→results 순 복구). keep/change 없음, matchIdleColor = 명시 사진 없음

### 상세 시트 '바꾸기' `reviseOne(state, frame, text)`
- 사전 캔디 체크 `GenerationQuota.canGenerate(cost)` 실패 → 페이월
- reference 우선순위: 수정용 첨부사진 > (frame1이면 frame0 앵커) > 해당 프레임 기존본
- 프롬프트: `"{설명, 포즈}. User modification: {텍스트}"` + frame1이면 `". Animation frame 2 (for a 2-frame swap loop): {animationFrame2Hint}. CRITICAL: keep the character at the EXACT same size, scale, and centered position as the reference image; only the pose changes."` + `". Transparent background — only the character, no shadows."`
- APIClient 직접 호출(매니저 경유 X). 성공 시:
  - 크로마키 투명화 → frame1이면 `matchedToReference`(frame0 원본 기준 크기·위치 정규화) → 128 썸네일 → frame1이면 `colorMatched`(frame0 색 드리프트 제거)
  - 결과맵 갱신 + 투명 캐시 무효화 + `displayTransparentByState[state] = false` (새 raw → 흰배경 기준 리셋)
  - **갤러리에만 저장** (`applyToActiveSlot: false`) + `appliedStates.remove(state)` — 바꾼 결과는 아직 적용 전이므로 표시 리셋
  - entitlement 반영 + `GenerationQuota.record(cost)` 차감
- 402 → 페이월, 실패 → `revisionError` 표시 (시트 안, 조용한 실패 금지)

### 프롬프트 조립 `buildPrompt(for:consistencyPrefix:keepNote:changeNote:frame:)`
- frame==1: `"Use the reference image as the SAME character. Keep identical: face, outfit, colors, art/pixel style, line thickness, body proportions, size, scale, centered position, framing, and the flat solid white background. This is the SECOND frame of a 2-frame animation loop, so the POSE MUST visibly CHANGE from the reference. Change the pose to: {animationFrame2Hint}. Change ONLY the pose — keep every design detail and the placement identical to the reference."`
  - 왜: 예전 "tiny hint of life / do not change overall appearance" 문구가 큰 포즈 변화를 억눌렀음
- frame==0 + reference 있음: `"Use the reference image. Keep the EXACT same character — identity, face and expression style, body proportions, art style, colors and shading, line thickness, and every design detail.{ The character is: 설명.}{ Keep especially: keep.} Change ONLY: {포즈(, and also 바꿀것)}. Do not change the character design; keep all other visual details identical to the reference."`
- frame==0 + reference 없음: `"{설명, 포즈}{, 바꿀것}"`
- 공통 접미: `". Transparent background — only the character, no background fill, no shadows."` (서버는 model=gpt-image-2 + 마젠타 크로마키 파이프라인)
- '바꿀 것'은 포즈에 **추가**(대체 아님) — 포즈는 상태마다 다르므로

### 엣지 케이스
- 화면 이탈/앱 종료 → 매니저(백그라운드)가 계속 실행, 재진입 시 onAppear에서 jobs 복원 + 승인 대기 복원
- 그만두기 → `didCancel`로 완료 알럿 억제, 매니저 cancelAll
- 402(캔디 소진) 실패 job이 하나라도 있으면 완료 알럿 대신 페이월
- 사진 로딩 실패: 전역 참고는 `errors[.idle]`에 에러 표기, 상태별/수정용은 조용히 무시
- 모든 사진 선택(전역/상태별/수정용)은 **정사각 크롭 화면을 거친 뒤** 확정

---

## 4. 데이터 의존성

| 대상 | 용도 | Android 대응 |
|---|---|---|
| `CharacterProfileStore` (aiPrompt) | 공통 설명 로드/저장 — 단건 생성과 공유 | 동일 스토어 포팅 (SharedPreferences/DataStore) |
| `BackgroundGenerationManager.shared` | 백그라운드 생성 큐. jobs/tick/isActive/phase(.anchor/.rest)/images 캐시/cancelAll/retry/start/loadFrame0FullRes. 디스크 큐 = Application Support/bggen/jobs.json (순차 1개씩) | WorkManager + 자체 잡 저장소 (`filesDir/bggen/jobs.json` 동형) + StateFlow로 tick/jobs 노출 |
| `GenerationQuota` | remainingToday / cost(quality) / canGenerate / record / displayedCandy | 포팅본 (App Group UserDefaults → SharedPreferences) |
| `CharacterImageStore` | save(갤러리+메타) / saveActiveSlotOnly / loadFrame / isAnimationDisabled / setAnimationDisabled | 동형 스키마: `characters/<state>.png`(+`_f1.png`), `gallery/<uuid>.png` + `metadata.json` |
| `APIClient` | preflightPing / generateImage(req, kind:"batch", batchId) — 응답 imageBase64 + entitlement | Retrofit/Ktor, X-Withu-Token, model="gpt-image-2", quality/artStyle/style:"auto", 1024×1024, 타임아웃 길게(생성 1–5분) |
| `AuthManager.applyEntitlement` | 서버 잔액 끌어올리기(max만) | GenerationQuota.syncCreditsUp 동형 |
| `ImageProcessing` | chromaKeyRemoved(마젠타→투명) / flattenedOnWhite / matchedToReference / colorMatched | Bitmap 픽셀 연산 포팅 |
| `ConnectivityManager.sendCharacterImage` | 워치 전송 | **제외** (Wear OS 후속) |
| `WidgetCenter.reloadAllTimelines` | 위젯 갱신 | Glance `updateAll` |
| `NotificationManager` | 완료 로컬 알림 권한 | POST_NOTIFICATIONS(API 33+) + NotificationChannel |
| `PHPhotoLibrary` (addOnly) | 사진 앱 저장 | MediaStore insert (Q+ 권한 불필요) |
| PhotosPicker / SquareCropView / GalleryReferencePicker / PaywallView | 사진 선택/크롭/갤러리 피커/페이월 | Photo Picker(ActivityResultContracts.PickVisualMedia) / 크롭 화면(01/02 스펙 공용) / 갤러리 피커 공용 / 페이월 공용 |

서버 계약: `POST /generate` — batchId 동봉 시 같은 세션 free_batch 묶음. 서버는 캔디 차감 안 함(차감은 클라 로컬, 커밋 fd98948 모델 유지).

---

## 5. Android 구현 노트

- **화면**: `BatchGenScreen` — Compose LazyColumn (Form 대응). M3 ListItem/Section 스타일은 단건 생성 스펙(02)과 통일. 승인 대기 시 리스트를 승인 섹션 하나로 교체.
- **ViewModel**: `BatchGenViewModel` — 위 상태 전부 보유. `BackgroundGenerationManager`(Android판)의 `StateFlow<List<Job>>` + `tick` 을 collect → syncFromManager 동형 함수. 화면 재진입 복원 로직(onAppear 동형)은 init에서.
- **백그라운드 큐**: WorkManager `OneTimeWorkRequest` 체인(순차 1개씩) 또는 단일 워커가 jobs.json 소비. `setForeground`(진행 알림)로 장시간 생성 보호. phase(anchor/rest)·batchId·paymentRequired 를 잡 레코드에 저장. 완료 시 로컬 알림(탭 → 배치 결과 화면 딥링크 — SCOPE 요구).
- **iOS 전용 개념 대체**:
  - `TimelineView(0.5s)` 경과 표시 → `LaunchedEffect` + `delay(500)` 루프 또는 `produceState`
  - fullScreenCover 크롭 → 전체화면 다이얼로그/별도 route
  - TabView 페이저 → `HorizontalPager` + 인디케이터
  - DisclosureGroup → expandable Column (animateContentSize)
  - 햅틱 → `HapticFeedback` 또는 생략
  - `.alert` → `AlertDialog`, `.sheet` → `ModalBottomSheet`
  - PhotosPicker → PickVisualMedia (권한 불필요)
- **주의점**:
  - 결과 그리드는 LazyColumn 안이므로 LazyVerticalGrid 중첩 금지 → 2개씩 Row (iOS와 동일한 이유)
  - `displayTransparentByState` 기본값 true — getOrDefault(state, true)
  - 상세 시트 배경 세그먼트는 표시 변경이 아니라 **즉시 적용**임을 유지
  - '바꾸기' 성공 후 appliedStates 에서 제거(적용 배지 리셋) 잊지 말 것
  - 승인 버튼 연타 방지 — 클릭 즉시 awaitingIdleApproval=false 동기 처리
  - 결과 썸네일 128px, 앵커 reference는 원본(1024) 사용 구분 유지
  - 문자열 보간은 strings.xml `%1$d` 포지셔널로
  - DEBUG 무제한 쿼터(9999) 동작도 GenerationQuota 포팅 시 유지 (BuildConfig.DEBUG)

---

## 6. 제외 항목 (SCOPE.md)

- **워치 전송 전부** — `ConnectivityManager.sendCharacterImage` 호출 지점은 전부 no-op (Wear OS 후속). 단 문구(`홈/워치에 반영해요` 등)는 원문 유지.
- **Play Billing 실결제** — 페이월은 UI만, 구매 버튼 '준비 중' (공용 페이월 스펙 따름).
- **Vision 배경 제거** — iOS도 이 화면에선 Vision을 안 쓰고 크로마키/흰합성만 사용하므로 그대로. `transparentResults`/`transparentResultsFrame1` 캐시는 현재 코드에서 채워지는 경로가 사실상 없음(레거시) — Android에선 생략 가능.
- **quality 선택 UI** — 원본에 없음. "low" 고정.
- 백그라운드 URLSession의 "본문 없는 2xx 1회 재큐잉" iOS 한계 대응 — WorkManager엔 해당 없음(응답 본문 유실 이슈 없음), 일반 재시도 정책으로 대체.
