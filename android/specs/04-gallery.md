# 04 — 캐릭터 갤러리 (CharacterGalleryView / GalleryGrid / GalleryReferencePicker / SquareCropView)

원본(진실의 원천):
- `withu/CharacterGen/CharacterGalleryView.swift` — landing(상태별/캐릭터별) + StateFolderView + GalleryGrid(그리드/상세/다중선택)
- `withu/CharacterGen/GalleryReferencePicker.swift` — 참고사진을 내 갤러리에서 고르는 시트
- `withu/CharacterGen/SquareCropView.swift` — 사진 첨부용 정사각 크롭 화면

---

## 1. 화면/모듈 구조 (위→아래 순서, 조건부 노출 포함)

### 1.1 CharacterGalleryView (landing)

내비게이션 타이틀: `캐릭터 갤러리` (inline). 배경: 현재 적용 중인 캐릭터 state(`SharedAppState.loadMessage()?.state`, 없으면 `idle`)의 `backgroundGradient` — 화면 전체.

1. **세그먼트 피커** — `상태별` / `캐릭터별` 2탭. 초기값 `상태별`.
2. **mode == 상태별 (`stateFolders`)**
   - 섹션 헤더 `상태별 폴더` + 우측 총 개수 캡션 `%d개` (grouped 전체 + legacy 합계)
   - 상태 폴더 행 목록 — `CharacterState.userFacing` 전체를 항상 표시(빈 폴더 포함). 정렬(§3.2 참고). 탭 → `StateFolderView` push.
   - **legacy가 비어있지 않을 때만**: `기타` 행 → 탭 시 `GalleryGrid(items: legacy, backgroundState: .idle)` push, 타이틀 `기타`, 헤더는 legacyHeader.
3. **mode == 캐릭터별 (`characterFolders`)**
   - characters 비었으면: 🎨(44pt) + 안내 2줄 (문구 §2)
   - 있으면: batch 그룹별 `characterCard` 목록. 카드 구성:
     - 상단 행(탭 → `GalleryGrid(items: group.items)` push, 타이틀 `이 캐릭터`): 대표 썸네일(44×44; idle 항목 우선, 없으면 첫 항목; 로드 실패 시 grid 아이콘) + `캐릭터 · %d개 모습` + 상대 시각(예: "3일 전") + chevron
     - 하단 CTA 버튼 `이 캐릭터로 모두 적용` → 확인 다이얼로그(§2 알림) 후 `applyCharacter`
4. **오버레이(하단)**: 토스트 텍스트(캡슐, ultraThinMaterial, 아래 40pt).
5. **오버레이(중앙)**: `totalCount == 0 && mode == 상태별` 일 때만 emptyState — 🎨 원형(withuPink 0.18, 120pt) + 안내 문구.

#### GalleryStateChip (상태 칩 컴포넌트)
- 원형 배경 `state.tint.opacity(0.22)`, 기본 크기 44.
- 이미지 우선순위: **적용본이 없고**(`!CharacterImageStore.hasImage(for: state)`) 그 상태 갤러리에 첫 항목이 있으면 그 첫 사진 → 아니면 `CharacterImageView(state:)` 3단 fallback(적용본→번들→심볼).
- 폴더 행에서는 칩 우상단에 **적용 중이면 초록 점**(9pt, 배경색 1.5pt 테두리).

#### 상태 폴더 행 (folderRow)
- 칩(44) + 제목 `state.koreanShortLabel` + 부제:
  - 항목 0개 → `아직 없어요`
  - 적용 중 → `%d개 · 지금 적용 중`
  - 그 외 → `%d개`
- 빈 폴더는 전체 opacity 0.55. chevron 우측. frostedCard 스타일.

#### legacy 행 / 헤더
- 행: tray 아이콘 원(44) + `기타` + `%d개 · 예전에 만든 캐릭터`
- 폴더 내부 헤더: tray 아이콘 원(56) + `예전에 만든 캐릭터` + `%d개`

### 1.2 StateFolderView (한 상태의 폴더)

타이틀: `state.koreanShortLabel` (inline). onAppear 시 refresh.

- **items 비었을 때**: 배경 그라데이션 + miniHero + emptyState:
  - 상태 tint 0.18 라운드 사각(96×96) 안에 `state.symbolEmoji`(44pt)
  - `%s 캐릭터가 아직 없어요` (%s = koreanShortLabel)
  - `이 순간에 어울리는 캐릭터를 만들어 보세요.`
  - 핑크 캡슐 버튼 `생성하러 가기` → CharacterGenView push
- **items 있을 때**: `GalleryGrid(items:, backgroundState: state)` + 헤더 miniHero.
- miniHero: 칩(56) + `state.caption` + (`아직 없어요` 또는 `%d개`), frostedCard.

### 1.3 GalleryGrid (재사용 그리드 — 적용/삭제/저장/다중선택)

Generic 헤더 슬롯. 배경: `backgroundGradient(for: backgroundState)`.

1. header()
2. `LazyVGrid` adaptive(minimum 110), spacing 12 — 카드 목록
3. 하단 토스트 오버레이
4. **툴바 우측**: 선택모드 아니면 `선택`, 선택모드면 `취소`(선택 해제+모드 종료)
5. **선택모드일 때만 하단 safeAreaInset 바(selectionBottomBar)**: 좌 `저장`(square.and.arrow.down 아이콘) · 중앙 `%d개 선택` · 우 `삭제`(trash, destructive). 두 버튼 모두 선택 0개면 disabled. regularMaterial 배경.

#### 카드 (card(for:))
- 정사각(aspect 1:1) regularMaterial 라운드(14). 이미지 로드 실패 시 photo 심볼.
- 조건부 오버레이:
  - 선택모드: 좌상단 체크 원(checkmark.circle.fill/circle, 선택 시 withuPink)
  - 선택모드 아님 && 어딘가 적용 중(`statesUsingGalleryItem` 비어있지 않음): 우상단 초록 점 10pt
  - 선택모드 아님 && `hasFrame1`: 우하단 배지 `연속` (10pt medium, ultraThin 캡슐)
- 선택 시 withuPink 3pt 테두리.
- 카드 아래: 생성 시각 상대 표기(10pt, tertiary, 좌정렬).
- **제스처**: 탭 — 선택모드면 토글, 아니면 상세 시트 오픈. 롱프레스 — 선택모드 아니면 선택모드 진입 + 해당 항목 선택.
- **컨텍스트 메뉴**(선택모드 아닐 때만): `다른 자리에 적용`(→ 적용 시트), `삭제`(destructive, → 삭제 확인).

#### 상세 시트 (galleryDetailSheet) — 위→아래

시트(NavigationStack + ScrollView). 타이틀 `%s 캐릭터` (%s = sourceState의 한국어 라벨; rawValue 매핑 실패 시 raw 그대로). 툴바: 좌 trash(destructive → 삭제 확인), 우 `닫기`.

시트 onAppear마다 초기화: `bgPreview=nil, bgCutout=nil, bgCutoutF1=nil, refineText=""` (항목별 리셋 — 이전 항목의 미리보기/입력이 남지 않게).

1. **이미지 영역**
   - frame1 있으면: 2장 나란히, 각 아래 `1번째` / `2번째` 캡션
   - 없으면: 단일 이미지(maxHeight 320, 라운드 16)
   - 표시 이미지는 `detailDisplay(base, cutout)` — bgPreview 반영(§3.5)
   - `frameSwapTick`을 읽어 프레임 스왑 시 강제 재로드 (메타데이터는 그대로고 파일만 바뀌므로 diffing이 감지 못함 — 이게 tick의 존재 이유)
2. **상태 행**: 적용 중이면 StatusPill(ok) `%s 자리에 적용 중` (%s = 적용 중 상태 라벨들 ", " join). 아니고 frame1 있으면 회색 캡션 `연속 이미지`. 우측에 상대 시각.
3. **만든 기록** (item.prompt 있고 비어있지 않을 때만): DisclosureGroup 라벨 `만든 기록` — 펼치면 프롬프트 전문(선택 가능 텍스트) + `프롬프트 복사` 버튼(클립보드 복사).
4. **연속 이미지 컨트롤** (hasFrame1일 때만), 가로 2개:
   - `프레임 바꾸기` — `swapGalleryFrames(id)` 성공 시: 이 항목이 적용 중인 모든 자리에 재적용(워치 재전송 포함) + `frameSwapTick += 1` + onChange
   - **적용 중일 때만** `움직임` 토글(라벨 숨김) — on = `!isAnimationDisabled(for: 첫 적용 상태)`; set 시 적용 중인 **모든** 상태에 `setAnimationDisabled(!on)` + 위젯 reload
5. **CTA** `'%s' 자리에 적용하기` (%s = backgroundState 라벨) → `apply(item, to: backgroundState)` 후 시트 닫기
6. 가로 2버튼: `저장`(단건 사진앱 저장) · `다른 자리에`(적용 시트 오픈)
7. **배경 보기 블록**:
   - 가로 2버튼 `배경 빼기` / `배경 있기` — 선택 중인 쪽 tint = withuPinkText, 아니면 secondary. 배경 제거 진행 중엔 둘 다 disabled.
   - 진행 중이면 스피너 + `배경 빼는 중…`
   - `bgPreview != nil` 일 때만 CTA `이대로 저장` → `saveBackgroundChoice`
8. **다듬기 블록**:
   - 라벨 `다듬기` (sparkles)
   - 멀티라인 텍스트필드, placeholder `바꾸고 싶은 점 (예: 모자를 씌워줘)`
   - 버튼: 진행 중이면 스피너+`다듬는 중…`, 아니면 `이대로 다듬기`. disabled 조건: 진행 중 || 입력 trim 후 빈 문자열.
   - 버튼 탭 → 확인 알림(`캔디를 사용해요`) → 확인 시 `refineItem`
   - 푸터 캡션: `다듬을 때마다 캔디 %d개를 써요. 결과는 갤러리에 새로 저장돼요.` (%d = `GenerationQuota.cost(forQuality: "low")` = 1)
9. 이미지 로드 실패 시: photo 심볼만.

### 1.4 GalleryReferencePicker (참고사진 고르기 시트)

타이틀 `내 캐릭터에서 고르기` (inline), 툴바 우측 `닫기`.
- onAppear: `CharacterImageStore.loadGalleryMetadata()` 전체(그룹 없이 flat).
- 비었으면: 🎨(44pt) + `아직 만든 캐릭터가 없어요` + `캐릭터를 만들면 여기서 참고사진으로 고를 수 있어요.`
- 있으면: adaptive(minimum 96) 그리드. 셀 = 정사각 썸네일 + 아래 상태 라벨(매핑 실패 시 `기타`). 이미지 로드 실패 셀은 아예 렌더하지 않음.
- 셀 탭 → `onPick(원본 UIImage)` 콜백 후 dismiss.

### 1.5 SquareCropView (정사각 크롭)

풀스크린, 검정 배경.
1. 상단 바: 좌 `취소`(흰색 텍스트) / 우 `선택`(흰 글씨, withuPink 캡슐)
2. 중앙 크롭 윈도우: side = min(화면 w, h) − 48. 이미지 scaledToFill + scaleEffect(scale×제스처 배율) + offset(누적+제스처 이동), 정사각 클립(라운드 12), 흰 2pt 테두리.
3. 아래 안내: `두 손가락으로 확대 · 드래그로 위치를 맞춰요` (흰색 70%)
- 제스처: 드래그(이동)와 핀치(확대) **동시(simultaneous)** 인식. 핀치 종료 시 `scale = max(1, scale × magnification)` — 1배 미만 축소 금지. 드래그 종료 시 offset 누적.
- `선택` → 현재 보이는 정사각을 **1024×1024**로 렌더(`ImageRenderer`, scale = 1024/side)해 `onDone(cropped)`. 렌더 실패 시 `onCancel()`.
- `CropTarget { image, onDone }` — 시트 트리거용 Identifiable 래퍼 (Android에선 단순 상태 홀더로 대체).

---

## 2. 사용자 문구 전량 (한국어 원문 그대로)

### CharacterGalleryView
| 위치 | 문구 |
|---|---|
| 내비 타이틀 | `캐릭터 갤러리` |
| 피커 라벨(접근성) | `보기` |
| 피커 탭 | `상태별` / `캐릭터별` |
| 섹션 헤더 | `상태별 폴더` |
| 총 개수 | `%d개` |
| 폴더 부제(빈) | `아직 없어요` |
| 폴더 부제(적용 중) | `%d개 · 지금 적용 중` |
| 폴더 부제 | `%d개` |
| legacy 행 제목 | `기타` |
| legacy 행 부제 | `%d개 · 예전에 만든 캐릭터` |
| legacy 폴더 타이틀 | `기타` |
| legacy 헤더 | `예전에 만든 캐릭터` / `%d개` |
| 캐릭터별 빈 안내 | `'여러 모습 만들기'로 만든 캐릭터가\n여기에 묶여요.` |
| 캐릭터별 빈 안내 2 | `하나씩 만든 캐릭터는 '상태별'에서 볼 수 있어요.` |
| 캐릭터 카드 제목 | `캐릭터 · %d개 모습` |
| 캐릭터 그리드 타이틀 | `이 캐릭터` |
| 모두 적용 버튼 | `이 캐릭터로 모두 적용` |
| 모두 적용 알림 제목 | `이 캐릭터로 모두 적용할까요?` |
| 모두 적용 알림 본문 | `%d개 상태 자리의 캐릭터가 모두 이 캐릭터로 바뀌어요.` |
| 알림 버튼 | `모두 적용` / `취소` |
| 모두 적용 토스트 | `%d개 모습을 모두 적용했어요` |
| landing 빈 상태 | `아직 만든 캐릭터가 없어요` |
| landing 빈 상태 2 | `캐릭터를 만들면 상태별 폴더에\n차곡차곡 모여요.` |

### StateFolderView
| 위치 | 문구 |
|---|---|
| miniHero 부제 | `아직 없어요` / `%d개` |
| 빈 상태 제목 | `%s 캐릭터가 아직 없어요` |
| 빈 상태 본문 | `이 순간에 어울리는 캐릭터를 만들어 보세요.` |
| 빈 상태 버튼 | `생성하러 가기` |

### GalleryGrid
| 위치 | 문구 |
|---|---|
| 툴바 | `선택` / `취소` |
| 선택 바 | `저장` / `%d개 선택` / `삭제` |
| 카드 배지 | `연속` |
| 컨텍스트 메뉴 | `다른 자리에 적용` / `삭제` |
| 적용 시트 제목 | `'%s' 캐릭터를 어디에 적용할까요?` |
| 적용 시트 항목 | `%s 자리에` (userFacing 상태별) / `취소` |
| 삭제 알림 제목 | `이 캐릭터를 지울까요?` |
| 삭제 알림 버튼 | `삭제` / `취소` |
| 삭제 토스트 | `지웠어요` |
| 사진 저장 알림 제목 | `사진 저장` / 버튼 `확인` |
| 다중 삭제 알림 제목 | `%d개를 지울까요?` (버튼 `삭제` / `취소`) |
| 다중 삭제 토스트 | `%d개를 지웠어요` |
| 적용 성공 토스트 | `%s 자리에 적용했어요` |
| 적용 실패 토스트 | `적용하지 못했어요` |
| 권한 거부 메시지 | `사진 추가 권한이 꺼져 있어요. 설정에서 켜주세요.` |
| 다중 저장 성공 | `%d장을 사진 앱에 저장했어요.` |
| 단건 저장 성공 | `사진 앱에 저장했어요.` |
| 저장 실패 | `저장하지 못했어요. 다시 시도해 주세요.` |

### 상세 시트
| 위치 | 문구 |
|---|---|
| 타이틀 | `%s 캐릭터` |
| 프레임 캡션 | `1번째` / `2번째` |
| 적용 중 필 | `%s 자리에 적용 중` |
| 연속 캡션 | `연속 이미지` |
| 만든 기록 | `만든 기록` / `프롬프트 복사` |
| 프레임/움직임 | `프레임 바꾸기` / `움직임` |
| CTA | `'%s' 자리에 적용하기` |
| 2버튼 | `저장` / `다른 자리에` |
| 배경 토글 | `배경 빼기` / `배경 있기` |
| 진행 중 | `배경 빼는 중…` |
| 배경 저장 CTA | `이대로 저장` |
| 배경 실패 토스트 | `배경을 빼지 못했어요` |
| 배경 저장 토스트 | `저장했어요` |
| 다듬기 라벨 | `다듬기` |
| 다듬기 placeholder | `바꾸고 싶은 점 (예: 모자를 씌워줘)` |
| 다듬기 버튼 | `이대로 다듬기` / 진행 중 `다듬는 중…` |
| 다듬기 푸터 | `다듬을 때마다 캔디 %d개를 써요. 결과는 갤러리에 새로 저장돼요.` |
| 다듬기 확인 제목 | `캔디를 사용해요` |
| 다듬기 확인 본문 | `이번 다듬기에 캔디 %d개를 써요. 성공했을 때만 차감돼요.` |
| 다듬기 확인 버튼 | `다듬기` / `취소` |
| 캔디 부족 토스트 | `캔디가 부족해요. 설정에서 충전할 수 있어요.` |
| 응답 실패 토스트 | `이미지를 받지 못했어요` |
| 다듬기 성공 토스트 | `다듬은 캐릭터를 갤러리에 저장했어요` |
| 닫기 버튼 | `닫기` |

### GalleryReferencePicker
| 위치 | 문구 |
|---|---|
| 타이틀 | `내 캐릭터에서 고르기` / `닫기` |
| 빈 상태 | `아직 만든 캐릭터가 없어요` |
| 빈 상태 2 | `캐릭터를 만들면 여기서 참고사진으로 고를 수 있어요.` |
| 셀 라벨 fallback | `기타` |

### SquareCropView
| 위치 | 문구 |
|---|---|
| 상단 | `취소` / `선택` |
| 안내 | `두 손가락으로 확대 · 드래그로 위치를 맞춰요` |

※ 상대 시각("3일 전" 등)은 iOS `.relative(presentation: .named)` — Android는 `DateUtils.getRelativeTimeSpanString` 사용(시스템 로케일 문구).

---

## 3. 상태(state)와 로직

### 3.1 CharacterGalleryView 상태
```
mode: byState | byCharacter (초기 byState)
grouped: [CharacterState: [GalleryItem]]         // loadGalleryGrouped().byState
legacy: [GalleryItem]                            // sourceState가 현재 enum에 매핑 안 되는 옛 항목
characters: [(batchId, createdAt, items)]        // loadGalleryByCharacter() — batchId 묶음
toastText: String?
pendingApplyAll: [GalleryItem]?                  // '모두 적용' 확인 대기 — 여러 자리를 한 번에 덮으므로 반드시 확인 후 실행
```
- `refresh()`는 onAppear + 하위 화면 onChange 콜백에서 호출 — 하위에서 삭제/적용해도 landing 카운트/정렬이 갱신되게.

### 3.2 폴더 정렬 (sortedFolders)
rank: 적용 중(hasImage) = 0 → 항목 있음 = 1 → 빈 폴더 = 2. 같은 rank 안에서는 `CharacterState.userFacing` 선언 순서 유지 (stable sort 필요 — Kotlin `sortedWith(compareBy { rank }, then 선언 인덱스)`).

### 3.3 applyCharacter (모두 적용)
각 item에 대해 `sourceState` rawValue → state 매핑(실패 시 skip) → `applyGalleryItem(id, to: state)` 성공 시 frame0 + (있으면) frame1을 워치로 전송, applied++. 루프 후 위젯 reload + 성공 햅틱 + 토스트(1.6s).

### 3.4 GalleryGrid 상태
```
selectedItem: GalleryItem?        // 상세 시트 트리거 겸 적용/삭제 대상
frameSwapTick: Int                // 파일만 바뀌고 메타데이터 동일한 경우(프레임 스왑, 배경 저장) 상세 이미지 강제 재로드
showApplySheet / showDeleteConfirm / showSaveAlert / showBulkDeleteConfirm
toastText / saveResultMessage
isSelectionMode, selectedIDs: Set<String>
bgPreview: nil | transparent | white   // nil = 저장된 그대로
bgCutout / bgCutoutF1: UIImage?        // Vision(배경제거) 결과 캐시 — 한 번만 계산
isRemovingBackground: Bool
refineText, isRefining, showRefineConfirm
```

### 3.5 배경 보기 (미리보기 → 저장)
- `detailDisplay(base, cutout)`: bgPreview nil → base / transparent → `cutout ?? base` / white → 흰색 합성(`flattenedOnWhite`).
- `showTransparentPreview`:
  1. cutout 캐시 없고 원본에 **투명 픽셀이 없으면**(32px 다운샘플 알파 스캔, alpha<250 하나라도 있으면 투명으로 판정) 배경제거 실행. 결과가 원본과 동일 객체(제거 실패)면 토스트 `배경을 빼지 못했어요` 후 **미리보기 전환 안 함**.
  2. frame1도 있으면 같이 제거해 `bgCutoutF1`에 캐시(실패 시 nil → 표시 시 원본 유지).
  3. 원본이 이미 투명하면 Vision 없이 즉시 transparent 미리보기.
- `saveBackgroundChoice`:
  - frame0/frame1 **둘 다 같은 배경으로** `replaceGalleryImage` — 두 장이 어긋나면 애니메이션이 깜빡이므로.
  - 적용 중인 모든 자리(statesUsingGalleryItem)에 재적용 + 워치 전송, 하나라도 있으면 위젯 reload.
  - 미리보기/캐시 리셋, frameSwapTick++, onChange, 토스트 `저장했어요`.

### 3.6 다듬기 (refineItem)
- 비용 = `GenerationQuota.cost(forQuality: "low")` (=1). `canGenerate(cost)` 실패 시 토스트 `캔디가 부족해요…` 후 종료.
- 갤러리 원본 PNG → base64 참고 이미지. 프롬프트(영문, 코드 그대로):
  ```
  "Use the reference image as the SAME character. Keep the EXACT same character — identity, face and expression style, body proportions, art style, colors and shading, line thickness, and every design detail. Change ONLY: \(trimmed). Transparent background — only the character, no shadows."
  ```
- 요청: `GenerateImageRequest(prompt:, referenceImageBase64:, steps: 30, width: 1024, height: 1024, quality: "low", artStyle: nil, style: "auto", kind: "refine", model: "gpt-image-2")`
  - **`kind: "refine"` 이 핵심** — 서버가 '계정 무료 1회'를 소진하지 않음(무료는 처음 만드는 화면 전용).
- 응답 base64 디코드 실패 → 토스트 `이미지를 받지 못했어요`.
- 성공: gpt-image-2 **마젠타 배경 → 크로마키 투명화**(`ImageProcessing.chromaKeyRemoved`) → **128×128 썸네일**로 축소 → `CharacterImageStore.save(small, for: sourceState, frame: 0, applyToActiveSlot: false, batchId: item.batchId, prompt: prompt)` — 갤러리에 **새 항목**으로 저장, 활성 슬롯은 건드리지 않음, 원본과 같은 batchId 유지(캐릭터별 그룹에 함께 묶이게).
- entitlement 응답 있으면 반영, `GenerationQuota.record(cost)` — **성공했을 때만 차감**.
- 입력 초기화 + 시트 닫기(그리드에 새 항목이 보이게) + onChange + 토스트.
- 에러: `error.koreanizedDescription` 토스트 (2.5s).

### 3.7 apply / 삭제 / 저장
- `apply(item, to:)`: `applyGalleryItem` → 성공 시 위젯 reload + frame0/frame1 워치 전송 + onChange + 토스트 `%s 자리에 적용했어요`; 실패 시 `적용하지 못했어요`.
- 삭제(단건/다중): `deleteGalleryItem(id)` 후 onChange + 토스트. 다중은 확인 알림 필수.
- 사진앱 저장(단건/다중): addOnly 권한 요청 → 거부 시 권한 안내 알림. 성공/실패 메시지를 알림으로 표시. 다중 저장 후 선택모드 종료 + 선택 해제.

### 3.8 엣지 케이스 모음
- 갤러리 이미지 파일 유실: 카드/시트는 photo 심볼 fallback, ReferencePicker 는 셀 미표시.
- `sourceState` rawValue 매핑 실패: landing에선 `legacy`(기타 폴더)로 분류, 라벨은 raw 문자열 그대로 표시, applyCharacter 에선 skip.
- 프레임 스왑/배경 저장은 **파일 내용만 바뀜** — 상태 diffing으로 감지 불가라 `frameSwapTick` 카운터로 recomposition 강제.
- 움직임 토글은 첫 적용 상태의 값을 읽고 **모든 적용 상태에 일괄 쓰기**.
- 크롭: scale 하한 1 (원본보다 작게 축소 금지). offset 은 clamp 하지 않음 — iOS 도 하지 않으므로 동일하게.

---

## 4. 데이터 의존성

| 의존 | 용도 |
|---|---|
| `CharacterImageStore.loadGalleryGrouped()` | `(byState, legacy)` — metadata.json 기준 상태별 그룹 + 미매핑 항목 |
| `loadGalleryByCharacter()` | batchId 그룹 `(batchId, createdAt, items)` 목록 (최신순) |
| `loadGalleryMetadata()` | flat 전체 목록 (ReferencePicker) |
| `loadGalleryImage(id:)` / `loadGalleryFrame1(id:)` | `gallery/<uuid>.png` / `<uuid>_f1.png` 로드 |
| `hasImage(for: state)` | 활성 슬롯 `characters/<state>.png` 존재 여부 |
| `applyGalleryItem(id, to: state)` | 갤러리 → 활성 슬롯 복사 (frame1 포함) |
| `statesUsingGalleryItem(id)` | 이 항목이 적용 중인 상태 목록 (활성 슬롯 메타로 역추적) |
| `deleteGalleryItem(id)` / `replaceGalleryImage(id, with:, frame:)` / `swapGalleryFrames(id)` | 삭제 / 파일 교체 / f0↔f1 스왑 |
| `isAnimationDisabled(for:)` / `setAnimationDisabled(_, for:)` | 상태별 움직임 on/off 플래그 |
| `save(_, for:, frame:, applyToActiveSlot:, batchId:, prompt:)` | 다듬기 결과 신규 저장 |
| `SharedAppState.loadMessage()?.state` | landing 배경 톤 |
| `GenerationQuota` | `cost(forQuality:)`, `canGenerate`, `record` — 로컬 캔디 (권위는 로컬, SCOPE 캔디 섹션) |
| `APIClient.generateImage` | `/generate` (X-Withu-Token, model=gpt-image-2) |
| `AuthManager.applyEntitlement` | 서버 entitlement 끌어올리기(max) |
| `ConnectivityManager.sendCharacterImage` | 워치 전송 — **Android 제외(Wear OS 후속)** |
| `WidgetCenter.reloadAllTimelines()` | 위젯 갱신 |
| `PHPhotoLibrary` | 사진 앱 저장 (addOnly) |
| `ImageProcessing` | `bestEffortTransparent`(Vision 배경제거), `flattenedOnWhite`, `chromaKeyRemoved` |

저장 스키마(SCOPE 규칙 — iOS와 동형): `gallery/<uuid>.png`, `gallery/<uuid>_f1.png`, `metadata.json`(GalleryItem 배열: id, sourceState, createdAt, hasFrame1?, batchId?, prompt?), 활성 슬롯 `characters/<state>.png`(+`_f1.png`).

---

## 5. Android 구현 노트

- **내비게이션**: landing → StateFolder / legacy / 캐릭터그리드는 Navigation-Compose route. GalleryGrid 는 route 화면이 아니라 **재사용 Composable**(items, backgroundState, onChange, header slot) — iOS 구조 그대로.
- **상세 시트**: `ModalBottomSheet`(M3) 또는 풀높이 시트. iOS `.sheet(item:)` 의 "item 바뀌면 onAppear 리셋" 동작은 `LaunchedEffect(item.id)` 로 재현.
- **frameSwapTick**: `mutableIntStateOf` 카운터를 이미지 로드 `remember(item.id, frameSwapTick)` 키에 포함.
- **confirmationDialog(적용 시트)**: 상태 목록 버튼이므로 `ModalBottomSheet` 리스트 또는 AlertDialog 커스텀 — userFacing 순서 유지.
- **컨텍스트 메뉴**: Compose `DropdownMenu` + `combinedClickable(onLongClick)` — 단, iOS 는 롱프레스=선택모드 진입이므로 컨텍스트 메뉴는 **롱프레스가 아닌 별도 트리거가 필요**. 권장: 롱프레스=선택모드(iOS 주 동작 유지), 컨텍스트 메뉴는 생략하고 동일 기능이 상세 시트에 있으므로 파리티 손실 없음. (컨텍스트 메뉴의 두 액션 = 시트의 `다른 자리에`/trash 와 동일.)
- **그리드**: `LazyVerticalGrid(GridCells.Adaptive(110.dp))`, ReferencePicker 는 96.dp. 단, landing 은 ScrollView 안 LazyVGrid 구조 — Android 는 화면 전체를 `LazyColumn` 으로 하고 그리드 행을 chunk 로 풀거나, 폴더 목록(리스트)이라 그리드 불필요. GalleryGrid 만 진짜 그리드.
- **사진 저장**: `MediaStore.Images` insert (API 29+ scoped storage — 권한 불필요, minSdk 28 은 `WRITE_EXTERNAL_STORAGE` 필요 → API 28 분기). 권한 거부 메시지 문구는 iOS 원문 유지.
- **클립보드**: `ClipboardManager.setText` (프롬프트 복사).
- **햅틱**: `HapticFeedback`(Compose LocalHapticFeedback) — 모두 적용 성공 시.
- **토스트**: Android Toast 가 아니라 iOS 캡슐 오버레이를 Compose 로 재현(하단 오버레이 + 자동 소멸 코루틴) — 문구·타이밍(1.0/1.2/1.6/2.0/2.5s) 유지.
- **배경 제거(Vision 대체)**: iOS 17 `VNGenerateForegroundInstanceMaskRequest` 는 대응 API 없음. 대체안:
  1. ML Kit **Subject Segmentation** (`com.google.mlkit:subject-segmentation`, 온디바이스, 무료) — 권장.
  2. 실패/미지원 기기는 iOS 의 "실패 시 원본 반환" 경로와 동일 → 토스트 `배경을 빼지 못했어요`.
  - 투명 픽셀 검사: 32×32 다운스케일 Bitmap 의 alpha 스캔(alpha<250) 동일 구현.
  - `flattenedOnWhite` = 흰 배경 Canvas 에 draw.
- **다듬기**: 포그라운드 단건 요청 — WorkManager 불필요(iOS 도 뷰 내 Task). OkHttp/Retrofit timeout 은 APIClient 공통 설정(30분) 따름. 마젠타 크로마키(`chromaKeyRemoved`)와 128px 축소는 공용 ImageProcessing 포팅 사용.
- **위젯 reload**: `WidgetCenter.reloadAllTimelines()` → Glance `updateAll()`.
- **워치 전송(`ConnectivityManager.sendCharacterImage`)**: SCOPE 제외 — 호출 지점마다 no-op 로 두되 apply/배경저장/프레임스왑의 호출 위치는 주석으로 남겨 후속 Wear OS 때 붙일 수 있게.
- **크롭 뷰**: Compose `detectTransformGestures`(pan+zoom 동시) + `graphicsLayer(scale, translation)` + 정사각 `clip`. 렌더는 iOS ImageRenderer 대신 **수학적 크롭**: 표시 변환(scaledToFill 배율 × scale, offset)을 역산해 원본 Bitmap 좌표의 정사각을 구해 `Bitmap.createBitmap` → 1024 리사이즈. (Compose 뷰 캡처보다 안전하고 픽셀/DP 혼동 없음 — iOS 에서 normalizeSquare 포인트/픽셀 버그 전례 있음.)
- **상대 시각**: `DateUtils.getRelativeTimeSpanString(millis)`.
- **frostedCard/배경 그라데이션/StatusPill/WithuCTAButtonStyle**: 공용 디자인 시스템 모듈(01-홈 스펙에서 정의된 것) 재사용.

---

## 6. 제외 항목 (SCOPE.md 기준)

- **워치 전송 전부** — `ConnectivityManager.sendCharacterImage` 호출(적용/모두 적용/배경 저장/프레임 스왑 내) 은 Wear OS 후속. no-op stub.
- **위젯 reload 는 포함**(Glance 는 SCOPE 포함) — 제외 아님, 혼동 주의.
- iOS 컨텍스트 메뉴(카드 롱프레스 메뉴)는 롱프레스 제스처 충돌로 미이식 — 동일 기능이 상세 시트에 존재.
- Play Billing 실결제: 캔디 부족 시 토스트까지만 파리티, 충전 흐름은 페이월 스펙(후속) 담당.
- Vision 동일 품질 보장 없음 — ML Kit 결과 차이는 허용(실패 경로 문구 동일).
