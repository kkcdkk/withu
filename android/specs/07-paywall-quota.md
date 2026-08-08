# 07 — 페이월 + 캔디 쿼터 (PaywallView / GenerationQuota)

원본(진실의 원천):
- `withu/Networking/PaywallView.swift`
- `withu/Networking/GenerationQuota.swift`
- 참조: `withu/Networking/StoreManager.swift` (팩 이름/개수만 — 실결제는 이번 범위 제외)

SCOPE.md 규칙: **Play Billing 실결제는 후속 — 구매 버튼은 '준비 중' 처리.**

---

## 1. 화면/모듈 구조 (위→아래 순서)

`PaywallView` = 전체 화면 시트. `NavigationStack` + `ScrollView`, 상단 타이틀 `"더 만들기"`(inline), 우상단 `"닫기"` 버튼. 배경은 현재 적용 중인 캐릭터 state(`SharedAppState.loadMessage()?.state ?? .idle`) 기반 그라디언트 — 홈과 같은 `backgroundGradient(for:)` 재사용 (홈 스펙 참조). 콘텐츠 좌우 패딩 20, 항목 간격 20.

위에서 아래로:

1. **header 카드** (frosted 카드, cornerRadius 18, 항상 노출)
   - 큰 글씨: `캔디 %d개 갖고 있어요` — 값 = `GenerationQuota.displayedCandy()`
   - 보조: `더 만들고 싶다면 캔디를 충전해요.`
2. **캔디 충전 섹션** — *조건: 상품 목록이 비어있지 않을 때만* (iOS: `!store.creditPacks.isEmpty`). Android는 실결제 미구현이므로 **4팩을 정적 데이터로 항상 표시** (아래 §3).
   - 섹션 헤더: `캔디 충전`
   - 팩 행 4개 (각각 frosted 카드): 왼쪽 44×44 라운드(12) 아이콘 배경(withuPink 18% 투명) + 지팡이·별 아이콘, 팩 이름 + (추천 팩이면 `가장 인기` 캡슐 배지), 아래 줄 `캔디 %d개 · 만료 없이 사용할 수 있어요`, 오른쪽에 가격. 추천 팩 = **50개 팩(파우치 팩)** 하나만, 카드 외곽선 withuPink 45% / 1.5pt 강조. 주석의 '왜': *"4팩이 다 같아 보이면 고르기 어려움 — 중간 팩 하나만 살짝 강조."*
3. **로딩/실패 상태** (iOS 원본 순서상 팩 섹션 아래) — Android에서는 정적 팩이므로 로딩 스피너(`불러오는 중…`)와 재시도 UI는 생략 가능하나, 문구는 §2에 보존.
4. **에러 배너** — `store.lastError` 가 있으면 `WarningBanner(text:)`. Android: '준비 중' 모델에선 발생 경로 없음 → 생략.
5. **할인코드 섹션**
   - 섹션 헤더: `할인코드`
   - frosted 카드 안: 텍스트필드(플레이스홀더 `코드 입력`, 자동 대문자, 자동수정 끔) + `적용` CTA 버튼(진행 중이면 스피너). 비활성 조건: 입력이 공백뿐이거나 적용 진행 중.
   - 결과 메시지 라벨 (redeemMessage, caption/secondary)
   - *조건: 테스트 캔디 코드 허용 빌드일 때만* 힌트 라벨: `테스트: '%s' 입력하면 캔디 %d개` (`CANDY20`, 20)
6. **친구 초대 섹션**
   - 섹션 헤더: `친구 초대`
   - *조건: 로그인 상태 + entitlement 에 referralCode 가 있을 때만* 내 코드 카드: 라벨 `내 초대 코드` + 코드 텍스트(title3 semibold) + 공유 버튼(ShareLink, 공유 문구는 §2). Android(파리티 범위): Google 로그인 제외라 entitlement 없음 → **이 카드는 노출되지 않음** (구현은 조건부로 남겨둠).
   - frosted 카드 안: 텍스트필드(플레이스홀더 `받은 초대 코드`, 자동 대문자) + `적용` 버튼 — 할인코드 행과 동일 구조.
   - 결과 메시지 라벨 (referralMessage)
7. **법적 링크 행**: `이용약관` · `개인정보처리방침` (caption2 semibold, withuPinkText 색 — 주석: *"링크는 글자 — 파스텔은 안 읽혀서 진한 로즈"*)
   - https://kkcdkk.github.io/withu/TERMS_OF_SERVICE.html
   - https://kkcdkk.github.io/withu/PRIVACY_POLICY.html
8. **HelperFooter**: `충전한 캔디는 만료 없이 계속 쓸 수 있어요.`

---

## 2. 사용자 문구 전량 (한국어 원문 그대로)

| 위치 | 문구 |
|---|---|
| 내비 타이틀 | `더 만들기` |
| 닫기 버튼 | `닫기` |
| 헤더 잔액 | `캔디 %d개 갖고 있어요` |
| 헤더 보조 | `더 만들고 싶다면 캔디를 충전해요.` |
| 섹션 헤더 | `캔디 충전` |
| 팩 이름 (10/30/50/100) | `미니 팩` / `포켓 팩` / `파우치 팩` / `파티 팩` |
| 팩 이름 fallback | `%d회 충전` |
| 추천 배지 | `가장 인기` |
| 팩 설명 | `캔디 %d개 · 만료 없이 사용할 수 있어요` |
| 로딩 | `불러오는 중…` |
| 상품 로드 실패 | `지금은 충전 상품을 불러올 수 없어요.\n아래 코드로 충전하거나 잠시 후 다시 열어 주세요.` |
| 재시도 버튼 | `다시 시도` |
| StoreManager 에러 | `상품 정보를 불러오지 못했어요.` / `결제 승인을 기다리고 있어요.` / `결제를 완료하지 못했어요. 다시 시도해 주세요.` |
| 섹션 헤더 | `할인코드` |
| 코드 플레이스홀더 | `코드 입력` |
| 적용 버튼 (양쪽 공통) | `적용` |
| 테스트 코드 힌트 | `테스트: '%s' 입력하면 캔디 %d개` |
| 테스트 코드 성공 | `🍬 캔디 %d개 충전됐어요! (테스트)` |
| 서버 코드 성공 | `적용됐어요! 잔액에 반영됐어요.` |
| 섹션 헤더 | `친구 초대` |
| 내 코드 라벨 | `내 초대 코드` |
| 공유 문구 | `withu 같이 해요! 초대 코드 %s 를 입력하면 둘 다 보너스를 받아요.` |
| 초대 코드 플레이스홀더 | `받은 초대 코드` |
| 초대 코드 성공 | `초대 코드가 적용됐어요! 보너스를 받았어요.` |
| 링크 | `이용약관` / `개인정보처리방침` |
| 푸터 | `충전한 캔디는 만료 없이 계속 쓸 수 있어요.` |
| 실패 메시지 (코드/초대 공통) | 에러의 한국어화 설명 (`error.koreanizedDescription`) — Android는 APIClient 에러 매핑 스펙(네트워킹 문서) 재사용 |
| **Android 추가: 준비 중** | 구매 탭 시: `아직 준비 중이에요. 곧 열릴게요!` *(iOS 원문 없음 — 신규 문구, strings.xml에 별도 키)* |

---

## 3. 상태(state)와 로직

### 3.1 PaywallScreen 상태

```kotlin
data class PaywallUiState(
    val candy: Int,                    // GenerationQuota.displayedCandy()
    val redeemInput: String = "",
    val redeemMessage: String? = null,
    val isRedeeming: Boolean = false,
    val referralInput: String = "",
    val referralMessage: String? = null,
    val isApplyingReferral: Boolean = false,
    val comingSoonShown: Boolean = false,  // 팩 탭 → '준비 중' 안내
)
```

- `onClose: () -> Unit` 콜백 필수 — iOS 주석: *"닫힐 때 호출 — 호출 측이 남은 횟수 등을 새로고침하도록."* 닫기 버튼 = `onClose()` 후 dismiss.
- **팩 버튼 탭**: iOS는 `store.purchase(pack)` 성공 시에만 `onClose()` (주석: *"적립까지 성공했을 때만 닫기 — 취소/실패면 열어 둬 에러 배너를 보여준다."*). Android 이번 범위: 결제 없음 → 스낵바/토스트로 `아직 준비 중이에요. 곧 열릴게요!` 표시, 화면 유지. 팩 데이터는 정적:

```kotlin
// StoreManager.ProductID 대응 — 가격은 결제 미연동이라 표시만
val packs = listOf(
    CandyPack("credits10", "미니 팩", 10),
    CandyPack("credits30", "포켓 팩", 30),
    CandyPack("credits50", "파우치 팩", 50, recommended = true),
    CandyPack("credits100", "파티 팩", 100),
)
```
  가격 자리(iOS `pack.displayPrice`)는 Play 연동 전까지 빈칸 대신 `준비 중` 라벨로 대체(신규 문구 재사용).

- **할인코드 적용** (`redeem()` 포팅):
  1. 입력 trim. `trimmed.uppercased() == "CANDY20"` 이고 `allowsTestCandyCode` 이면 **서버 안 감**: `GenerationQuota.addCredits(20)` → 메시지 `🍬 캔디 20개 충전됐어요! (테스트)` → 입력 비움 → 헤더 잔액 갱신. (주석: *"TestFlight/샌드박스 전용 캔디 코드 — 로컬 캔디 +20 (운영 빌드에선 무시 → 서버로 보냄)."*)
  2. 아니면 `isRedeeming = true` → `POST /redeem` → 성공 시 entitlement 반영(`syncCreditsUp`) + `적용됐어요! 잔액에 반영됐어요.` + 입력 비움 / 실패 시 한국어화 에러 메시지. 완료 후 `isRedeeming = false`.
  - Android 파리티 범위는 로그인 제외 → 서버 `/redeem` 은 세션이 없어 실패할 수 있음. **테스트 코드 경로는 로컬이므로 그대로 동작** — 이것이 결제 없는 Android 빌드의 유일한 충전 수단이자 QA 경로. 서버 경로는 구현하되 에러 메시지 그대로 노출.
- **초대 코드 적용** (`applyReferral()` 포팅): `POST /referral/apply` → 성공 시 entitlement 반영 + `초대 코드가 적용됐어요! 보너스를 받았어요.` / 실패 시 에러 메시지. 로그인 제외 범위에선 사실상 서버 에러 노출 — UI/로직은 파리티로 유지.
- 두 `적용` 버튼 비활성: `input.trim().isEmpty() || isBusy`.
- 텍스트필드: 대문자 자동화(`KeyboardCapitalization.Characters`), 자동수정 끔.

### 3.2 GenerationQuota 포팅 (정책 그대로)

저장소: **SharedPreferences** (iOS App Group UserDefaults 대응 — 위젯 Glance 와 같은 프로세스라 일반 SharedPreferences 로 충분). 키는 iOS 와 동일 문자열 유지:

- `withu.genQuota.count.v1` — 오늘 무료 사용 횟수(Int)
- `withu.genQuota.date.v1` — yyyymmdd 정수. *"자정 넘으면 값이 바뀌어 일일 카운트 자동 리셋."*
- `withu.genQuota.credits.v1` — 캔디 잔액(만료 없음)
- `withu.genQuota.lastSyncedServer.v1` — 서버 잔액 기준선

정책 상수/함수 (시그니처는 Swift 원문):

- `static let freeDailyLimit = 0` — **무료 없음, 캔디로만 생성.**
- `static func usedToday() -> Int` — 저장된 date == 오늘 stamp 일 때만 count, 아니면 0.
- `static func credits() -> Int`
- `static func remainingToday() -> Int` — `max(0, dailyAllowance - usedToday()) + credits()`. **DEBUG 빌드는 9999 반환** (주석: *"개발 빌드 — 무제한 테스트 (출시 빌드는 실제 한도)"*). Android: `BuildConfig.DEBUG`.
- `static func canGenerate(_ n: Int = 1) -> Bool` — `remainingToday() >= n`.
- `static func record(_ n: Int = 1)` — **DEBUG 는 no-op(차감 안 함)**. Release: 오늘 무료 한도부터 차감, 부족분을 credits 에서 차감 (`max(0, credits - fromCredits)`). freeDailyLimit=0 이라 사실상 전액 credits 차감이지만 로직은 원문 그대로 이식.
- `static func cost(forQuality quality: String) -> Int` — `"high" → 6`, `"medium" → 3`, 기본(low) `1`. 주석의 '왜': *"움직이는 캐릭터는 frame0·frame1 을 각각 생성·과금하므로 자동으로 2배가 된다."* (호출 측이 프레임마다 record — 여기서 2배 계산하지 말 것.)
- `static func addCredits(_ n: Int)` — `n > 0` 일 때 잔액 += n.
- `static func syncCreditsUp(to serverCredits: Int)` — **절대 절대값 덮어쓰기 금지.** 이유(원문 주석): 서버는 /generate 에서 차감하지 않으므로 서버 잔액은 '누적 적립 총액'. 덮어쓰면 로컬 차감이 새로고침마다 되돌아옴(캔디 안 닳는 버그).
  - 기준선 키가 없으면(최초 동기화): `serverCredits > credits()` 일 때만 credits 를 serverCredits 로 끌어올림, 기준선 저장.
  - 이후: `delta = serverCredits - lastSynced`; `delta > 0` 이면 `credits += delta`; 기준선은 항상 갱신.
- `static func resetServerBaseline()` — 로그아웃 시 기준선 키 삭제. 이유: 같은 기기 다른 계정 로그인 시 이전 기준선으로 delta 계산되어 새 계정 적립 왜곡 방지. **로컬 credits 는 유지** (미로그인 구매분 보호).
- `static func displayedCandy() -> Int` — `credits()` 그대로. 이유(원문): canGenerate 가 로컬 credits 만 보므로 배지도 같은 값 — 과대표시 방지.
- `static let testCandyCode = "CANDY20"` / `static let testCandyAmount = 20`
- `static var allowsTestCandyCode: Bool` — iOS: DEBUG 또는 sandboxReceipt. **Android 대응: `BuildConfig.DEBUG` 만 true** (sandbox receipt 개념 없음; Play 결제 도입 시 재검토). 운영 릴리즈에서 무료 캔디 악용 방지가 목적.

### 3.3 엣지 케이스

- 자정 넘김: date stamp 불일치 → usedToday()=0 으로 자동 리셋 (별도 타이머/워커 불필요).
- 잔액 음수 방지: 차감 시 `max(0, …)`.
- DEBUG 빌드에선 **차감이 전혀 안 되므로** 캔디/페이월 실동작 검증은 Release 빌드에서만 가능 — 스펙 그대로 유지.
- 테스트 코드 대소문자: 비교 전 uppercased — `candy20` 도 통과.
- syncCreditsUp 에서 delta < 0(서버 잔액 감소)은 무시 — 기준선만 갱신.

---

## 4. 데이터 의존성

| 이름 | 원본 | Android 대응 |
|---|---|---|
| 캔디 잔액/일일 카운트 | App Group UserDefaults (`group.com.seoyoung.withu`), 키 4종(§3.2) | SharedPreferences `"withu.shared"` (SharedAppState 스펙과 동일 파일), 키 문자열 동일 |
| 상품 목록/구매 | StoreManager (StoreKit 2) | 정적 `CandyPack` 리스트 — 결제 없음 |
| 세션/entitlement | AuthManager + KeychainStore | 이번 범위 제외 (referral 내 코드 카드 비노출) |
| 서버 | `POST /redeem`, `POST /referral/apply` (APIClient actor, snake_case) | 기존 Worker 그대로, Retrofit/Ktor + X-Withu-Token |
| 배경 그라디언트 state | `SharedAppState.loadMessage()?.state ?? idle` | SharedAppState 포팅본에서 동일하게 로드 |

캔디 차감 시점(참고, 다른 스펙 소관): 단건 생성 성공 시 뷰에서 `record(cost)`, 배치는 BackgroundGenerationManager(→WorkManager) 의 process() 성공 시점.

---

## 5. Android 구현 노트

- **화면**: `PaywallScreen` Composable + `PaywallViewModel`. `ModalBottomSheet` 대신 iOS 시트 느낌으로 전체화면 다이얼로그/네비게이션 목적지 중 홈 스펙의 시트 규약을 따름. Scaffold + TopAppBar(title `더 만들기`, actions에 `닫기` TextButton).
- **frosted 카드 / SectionHeader / HelperFooter / WarningBanner / WithuCTAButtonStyle**: 공통 컴포넌트 스펙(디자인 시스템 문서)의 대응물 재사용. frosted = 반투명 흰 배경 + 블러 대체(Compose 는 배경 블러 비용 큼 → 반투명 + 얇은 보더로 근사).
- **ShareLink 대응**: `Intent.ACTION_SEND` + `Intent.createChooser` (text/plain).
- **Link 대응**: `Intent.ACTION_VIEW` 로 브라우저 열기 (CustomTabs 선택).
- **ProgressView 인라인**: `CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)` 를 버튼 라벨 자리에.
- **GenerationQuota**: `object GenerationQuota` 싱글턴, `Context` 는 앱 컨텍스트 주입(초기화 1회). 시간: `Calendar.getInstance()` 로 yyyymmdd stamp — iOS 와 동일 산식 `(y*10000 + m*100 + d)`.
- **DEBUG 분기**: `BuildConfig.DEBUG` — remainingToday()=9999 / record() no-op / allowsTestCandyCode=true.
- **주의**: syncCreditsUp 의 read-modify-write 는 단일 프로세스 가정 — SharedPreferences `commit()` 아닌 `apply()` 로 충분하나, WorkManager 프로세스가 같은지 확인(기본 동일 프로세스면 OK).
- **주의**: 팩 가격 표시 — Play 연동 전 하드코딩 원화 금지(가격 정책 미확정). `준비 중` 라벨로.

---

## 6. 제외 항목 (SCOPE.md 기준)

- **Play Billing 실결제 전부**: StoreManager 의 loadProducts/purchase/Transaction.updates/`/iap/verify` 호출 — 팩 버튼은 '준비 중' 안내만. 관련 문구(`불러오는 중…`, 로드 실패, 재시도, 결제 에러 3종)는 strings.xml 에 키만 미리 등록(후속 결제 작업 대비), UI 노출은 안 함.
- **Google 로그인/entitlement**: `내 초대 코드` 카드 비노출 (referralCode 없음). `applyEntitlement` → `syncCreditsUp` 경로는 코드만 준비.
- **구독**: iOS 도 제거됨(파일 헤더 주석 "구독 없음") — 완전 제외.
- **Wear OS 관련 갱신 트리거**: 해당 없음.
