# 11 — 네트워킹 + 배치 백그라운드 큐 (APIClient / APIModels / BackgroundGenerationManager)

원본(진실의 원천):
- `withu/Networking/APIClient.swift`
- `withu/Networking/APIModels.swift`
- `withu/Networking/BackgroundGenerationManager.swift`
- 참조: `withu/Networking/APIConfig.swift` (baseURL/timeout — skip-worktree, 값만 인용), `NotificationManager.swift` (완료 알림 문구)

SCOPE.md 규칙: 서버는 기존 Worker 그대로 (`https://withu-api.ysy1398.workers.dev`, `X-Withu-Token`, `model=gpt-image-2`, 마젠타 크로마키). Google 로그인(/auth/google)·Play Billing 실결제는 제외 — Bearer 세션이 없는 상태로 동작해야 한다.

---

## 1. 모듈 구조 (UI 없음 — 레이어 구성)

이 스펙은 화면이 아니라 3개 레이어를 정의한다:

1. **`ApiClient`** — 순수 HTTP 클라이언트. `/health`(ping/preflight), `/generate`(단건). 인증 계열(`/auth/apple`, `/me`, `/iap/verify`, `/redeem`, `/referral/apply`)은 iOS 시그니처만 문서화하고 Android 파리티 범위에선 `/redeem`·`/referral/apply`·`/health`·`/generate` 만 실제 사용 (로그인 제외 → Bearer 없이 호출).
2. **`ApiModels`** — 요청/응답 DTO. 서버는 snake_case ↔ 클라 camelCase.
3. **`BackgroundGenerationManager`(→ WorkManager)** — 배치 생성 영속 큐. 잡 목록 디스크 영속, 순차 1개 실행, frame1 체이닝, 재큐잉, 캔디 차감, 완료 알림.

---

## 2. 사용자 문구 전량 (한국어 원문 그대로)

### 2.1 APIError.errorDescription (디버그성 — 로그/알럿 fallback)

| 케이스 | 문구 |
|---|---|
| invalidResponse | `서버 응답 형식이 잘못됐어요.` |
| server | `서버 오류 %d: %s` |
| decoding | `디코딩 실패: %s` |
| transport | `통신 실패: %s` |
| paymentRequired | `무료 횟수를 다 썼어요.` |

### 2.2 koreanizedDescription (사용자 노출용 — catch 블록에서 이것만 쓸 것)

| 조건 | 문구 |
|---|---|
| invalidResponse | `서버 응답이 이상해요. 잠시 후 다시 시도해 주세요.` |
| server 429 | `요청이 너무 많아요. 잠시 후 다시 시도해 주세요.` |
| server ≥500 | `서버에 문제가 생겼어요. 잠시 후 다시 시도해 주세요.` |
| server 422 | `프롬프트가 안전 정책에 걸렸어요. 단어를 살짝 바꿔서 다시 시도해 주세요.` |
| server 기타 | `서버 오류 (%d). 잠시 후 다시 시도해 주세요.` |
| decoding | `결과를 읽을 수 없어요. 다시 시도해 주세요.` |
| transport | 내부 에러를 재귀적으로 koreanize (아래 URLError 표) |
| paymentRequired | `무료 횟수를 다 썼어요. 충전하거나 구독해 주세요.` |
| 인터넷 없음 (notConnectedToInternet) | `인터넷에 연결돼 있지 않아요. Wi-Fi 또는 셀룰러를 확인해 주세요.` |
| 타임아웃 (timedOut) | `응답이 너무 오래 걸려요. 잠시 후 다시 시도해 주세요.` |
| 호스트 연결/발견 실패 (cannotConnectToHost, cannotFindHost) | `서버에 연결할 수 없어요. 네트워크 또는 서버 상태를 확인해 주세요.` |
| 연결 끊김 (networkConnectionLost) | `연결이 끊겼어요. 다시 시도해 주세요.` |
| 취소 (cancelled) | `요청이 취소됐어요.` |
| 기타 네트워크 | `네트워크 오류가 발생했어요. 다시 시도해 주세요.` |
| 최종 fallback (모든 Error) | `오류가 발생했어요. 잠시 후 다시 시도해 주세요.` |

주석의 '왜': *"기본 — 시스템 로컬라이즈된 메시지 (영문일 수 있음) 보다 깔끔한 한국어 폴백"* — Android도 `Throwable.message` 를 그대로 노출하지 말 것.

### 2.3 BackgroundGenerationManager 잡 에러 문구

| 상황 | 문구 |
|---|---|
| 사용자 취소 (cancelAll) | `취소했어요` |
| 요청 본문 파일 쓰기 실패 | `요청을 준비하지 못했어요` |
| 실행 시점 body 파일 없음 | `요청 파일이 없어요` |
| 402 | `무료 횟수를 다 썼어요` (+ `paymentRequired = true`) |
| 422 | `프롬프트가 안전 정책에 걸렸어요. 단어를 살짝 바꿔서 다시 시도해 주세요.` |
| 기타 비 2xx | `서버 오류 (%d). 잠시 후 다시 시도해 주세요.` |
| 2xx 인데 본문 없음 + 재큐잉 소진 | `이미지를 받지 못했어요` |
| transport 에러 | koreanizedDescription 결과 그대로 |

### 2.4 완료 로컬 알림 (NotificationManager)

| 상황 | 제목 | 본문 |
|---|---|---|
| rest 완료, 실패 0 | `캐릭터를 다 만들었어요` | `%d개 모습이 완성돼 바로 적용됐어요. 열어서 확인해 보세요.` |
| rest 완료, 실패 ≥1 | `캐릭터 생성이 끝났어요` | `%d개 완성, %d개는 못 만들었어요. 앱에서 다시 시도할 수 있어요.` |
| anchor 완료 (done>0) | `기준 모습이 준비됐어요` | `마음에 드는지 확인하고 나머지 모습을 이어서 만들어 보세요.` |
| retry 완료 | (알림 없음) | — |

---

## 3. /generate 요청 스키마 (전량)

### 3.1 요청 본문 — `GenerateImageRequest` (JSON, snake_case 전송)

```swift
struct GenerateImageRequest: Codable {
    let prompt: String
    let referenceImageBase64: String?   // → reference_image_base64
    let steps: Int
    let width: Int
    let height: Int
    let quality: String?   // "low" | "medium" | "high" | "auto"
    let artStyle: String?  // "casual" | "pixel"      → art_style
    let style: String?     // legacy
    var kind: String? = nil    // nil|"character" → 서버 SYSTEM_PROMPT 적용, "background" → raw prompt
    var model: String? = nil   // "gpt-image-2" 명시 시 마젠타 배경 → 클라 크로마키. nil = gpt-image-1.5 (진짜 투명)
}
```

배치 큐가 실제로 만드는 값: `steps: 30, width: 1024, height: 1024, quality: <잡 quality>, artStyle: <잡 artStyle>, style: "auto", model: "gpt-image-2"`.

### 3.2 헤더

| 헤더 | 값 | 왜 |
|---|---|---|
| `Content-Type` | `application/json` | |
| `X-Withu-Token` | `APIConfig.apiToken` (있고 비어있지 않을 때만) | Worker 의 비로그인 인증 경로 (ENFORCE_AUTH 미설정 시 허용). **Android 파리티에선 이것이 유일한 인증** — 값은 로컬 설정 파일(커밋 금지, iOS skip-worktree 와 동일 취급) |
| `Authorization` | `Bearer <sessionToken>` (Keychain 에 있을 때만) | Android: 로그인 제외 → 미전송 |
| `Idempotency-Key` | 단건: 요청마다 `UUID`. **배치: `job.id`** | 재시도/재전송 이중차감 방지. 배치는 잡 id 고정이라 프로세스 죽고 재전송돼도 서버가 중복 처리 안 함 |
| `X-Withu-Kind` | `"single"` 또는 `"batch"` | 서버 무료 버킷 구분 |
| `X-Withu-Batch` | batchId (배치일 때만) | 일괄 세션 묶음 |

### 3.3 응답

```swift
struct GenerateImageResponse: Codable {
    let imageBase64: String
    let seed: Int
    let revisedPrompt: String?
    var entitlement: Entitlement? = nil  // 차감 후 갱신 잔액(로그인 시)
    var freeConsumed: Bool? = nil        // true 면 서버가 '계정 무료 1회' 소진 → 클라 캔디 미차감
}
```

- **402** → `PaymentRequiredResponse { detail: String?, balance: Entitlement? }` 로 디코드 시도 → `paymentRequired(balance:)` 에러.
- 기타 비 2xx → `APIErrorDetail { detail: String }` 디코드 시도, 실패 시 raw body 문자열 → `server(status:detail:)`.

### 3.4 기타 DTO (참고 — Android 파리티에선 /redeem, /referral 만 사용)

```swift
struct Entitlement: Codable, Equatable {
    let freeBatchRemaining: Int
    let freeSingleRemaining: Int
    let credits: Int
    let subActive: Bool
    let subExpiresAt: Int?
    let referralCode: String?
}
struct RedeemRequest: Codable { let code: String }      // POST /redeem
struct ReferralRequest: Codable { let code: String }    // POST /referral/apply
// (제외 범위) AppleAuthRequest/Response, MeResponse, IapVerifyRequest
```

응답 래퍼: `/redeem`·`/referral/apply`·`/me`·`/iap/verify` 는 모두 `MeResponse { entitlement }` 형태.

---

## 4. 상태와 로직

### 4.1 ApiClient

- **타임아웃**: request idle 1800초(30분), 전체 리소스 3600초(60분), `waitsForConnectivity = true`. 주석의 '왜': 이미지 생성이 medium 1–3분/high 2–5분 — 짧게 잡으면 iOS 가 잘못된 "offline" 을 보고한다. Android(OkHttp)도 read timeout 을 30분으로.
- **`preflightPing()`**: `/health` 를 **별도 5초 타임아웃 클라이언트**로 GET. 본 세션은 30분 타임아웃이라 연결이 끊겼을 때 한참 매달리므로, generate 직전에 이걸로 즉시 실패 판정. 2xx 아니면 에러.
- **`ping()`**: 같은 `/health`, 기본 세션으로 Bool 반환.
- **`deleteAccount()`** (제외 범위, 참고): DELETE `/me`, 타임아웃 30초로 개별 단축 — "생성용 session 의 30분 timeout 상속 방지".
- **직렬화**: iOS 는 `actor` 로 호출을 직렬화하지 않고(actor 는 상태 보호용) URLSession 이 동시 처리 — Android 는 단일 OkHttpClient 공유로 충분.
- 에러 분류: HTTPURLResponse 아님 → invalidResponse / 비 2xx → server / JSON 실패 → decoding / 그 외 → transport. **catch 에서 APIError 는 그대로 재던지기** (transport 로 이중 래핑 금지).

### 4.2 배치 잡 모델

```swift
struct BackgroundGenJob: Codable, Identifiable {
    enum Status: String, Codable { case queued, running, done, failed }
    let id: String            // UUID — Idempotency-Key 로도 사용
    let stateRaw: String      // CharacterState.rawValue (디스크/메시지 호환 키)
    let frame: Int            // 0 = 기본, 1 = 움직임 프레임
    let quality: String
    let artStyle: String
    let batchId: String
    var wantsFrame1: Bool
    var frame1Prompt: String?
    var status: Status
    var errorMessage: String?
    var startedAt: Date?
    var paymentRequired: Bool?   // 402 실패 표시 — 뷰가 페이월 띄우는 근거
    var attempts: Int?           // 본문 없는 2xx 재큐잉 상한(2) 카운터
    var matchIdleColor: Bool?    // true = 색을 idle 앵커에 맞춤. idle 자신·per-state 사진은 false
    var prompt: String?          // 갤러리 '만든 기록' 저장용. 옛 잡은 nil
}
```

관찰 상태(뷰 공유): `jobs`, `phase`, `tick`(변경 신호 — 뷰가 onChange 로 당겨감), `images`(state#frame → 128px 썸네일, **메모리 전용** — 재시작 후엔 비어 있고 뷰는 CharacterImageStore.loadFrame 으로 fallback), 파생값 `isActive` / `doneCount` / `failedCount`.

**Phase**: `anchor`(기준 idle 1장) / `rest`(승인 후 나머지 전체) / `retry`(끝난 배치에서 한 장만 — 완료 알림/알럿을 배치처럼 띄우지 않음).

### 4.3 큐 semantics (순서대로)

1. **start(specs, quality, artStyle, batchId, phase)** — 이전 단계 잡 목록 **교체**, images 클리어, 잡 생성 후 persist → 실행.
2. **appendJob**: 잡 생성 + 요청 본문을 `<jobId>.body.json` 파일로 저장 (iOS background upload 는 파일 본문 필수 — Android 는 base64 참고사진이 커서 어차피 파일이 안전). 쓰기 실패 시 즉시 `failed` + `요청을 준비하지 못했어요`. spec.frame==1 이고 frame0Reference 가 있으면 `<state>_f0.png` 로 원본 저장 (frame1 정규화 기준).
3. **runNextIfIdle**: running 이 없을 때만 첫 queued 하나 실행 — **maxConcurrent = 1** (서버 부하/일관성). body 파일 없으면 `failed(요청 파일이 없어요)` 후 다음 잡. 헤더는 §3.2 (Idempotency-Key = job.id, X-Withu-Kind = "batch", X-Withu-Batch = batchId). running 전환 + startedAt + attempts+=1 → persist.
4. **process(jobId, data, response, error)** — 완료 콜백:
   - **가드**: 해당 잡이 `running` 이 아니면 무시하고 다음 잡 실행. 왜: 재시작 후 재큐잉본과 원래 태스크의 늦은 콜백이 겹쳐도 **이중 차감/이중 frame1 체이닝 없음**. 취소된 잡도 여기서 걸러짐.
   - 성공(2xx + 본문 있음 + 디코드 성공) 시 순서:
     1. base64 → 비트맵, `ImageProcessing.chromaKeyRemoved` (gpt-image-2 마젠타 → 투명. 투명 결과엔 no-op)
     2. frame==1 이면 `<state>_f0.png` 기준 `matchedToReference` 크기·위치 정규화
     3. 128×128 썸네일 생성
     4. 색 정렬: `matchIdleColor==true` → idle 의 f0 원본 기준 / 아니면 자기 f0 기준 (`colorMatched`) — "상태 간 색 어긋남 해소" vs "frame1 드리프트만 제거"
     5. `CharacterImageStore.save(..., applyToActiveSlot: false, batchId:, prompt:)` — **갤러리에만 저장**. 활성 슬롯 적용·워치 전송은 사용자가 '적용' 누를 때.
     6. 응답에 entitlement 있으면 반영
     7. **`GenerationQuota.record(cost(forQuality:))` — 캔디 차감은 이 성공 시점** (low 1 / medium 2 / high 3)
     8. `images["<stateRaw>#<frame>"]` 갱신
     9. frame==0 이면 flat PNG 를 `<state>_f0.png` 저장 → **frame1 체이닝**: `wantsFrame1 && frame1Prompt` 있으면 방금 받은 frame0 PNG 를 base64 reference 로 새 잡 append (wantsFrame1=false, matchIdleColor 승계)
   - **본문 없는 2xx 재큐잉**: data 가 nil/빈 데이터이고 `attempts < 2` 면 `queued` 로 되돌림 (startedAt=nil). 왜: 앱이 죽은 사이 완료된 upload task 는 iOS 가 응답 본문을 보존하지 않음 — 1회만 재생성. attempts 소진 시 `이미지를 받지 못했어요` 실패.
   - 402 → 실패 + `paymentRequired=true` / 422·기타 → §2.3 문구로 실패.
   - 재큐잉이 아니면 body 파일 삭제 (재큐잉이면 남겨야 재실행 가능). persist + tick.
   - 큐에 queued/running 이 남으면 다음 잡, 없으면 **finish()**.
5. **finish()** (큐 빌 때 1회): 위젯 갱신(`WidgetCenter.reloadAllTimelines` → Glance update) → 취소였으면 알림 없이 종료 → phase 별 알림 (§2.4).
6. **resumeIfNeeded()** (앱 런치 시): isActive 면 살아있는 태스크 id 집합과 비교해, running 인데 실제 태스크가 없는 잡을 `queued` 로 재큐잉 후 실행 재개. Idempotency-Key 덕에 서버 중복 처리 없음.
7. **cancelAll()**: 모든 태스크 취소, queued/running → `failed(취소했어요)`. wasCancelled 플래그로 finish 알림 억제.
8. **retry(spec, ...)**: 같은 state·frame 의 `failed` 잡 제거 후 새 잡 추가. 큐가 이미 비었으면 phase=`retry` 전환 (완료 알림 억제).

### 4.4 엣지 케이스 요약

- 프로세스 사망 → jobs.json 으로 복원, 증발한 running 은 재큐잉 (6).
- 늦은 중복 콜백 → running 가드로 무시 (4).
- 본문 유실 2xx → attempts<2 재큐잉, body 파일 보존 (4).
- 취소 후 늦은 콜백 → status 가 failed 라 가드에 걸림.
- 402 는 잡 실패로 기록하되 큐는 계속 진행 (다음 잡도 402 로 실패하며 소진) — 뷰가 paymentRequired 잡을 보고 페이월 표시.

---

## 5. 데이터 의존성

| 대상 | 위치/키 |
|---|---|
| 잡 목록 영속 | Application Support/`bggen/jobs.json` — `{ phase, jobs[] }` (기본 인코더, snake 변환 없음) |
| 요청 본문 | `bggen/<jobId>.body.json` (snake_case 인코딩된 GenerateImageRequest) |
| frame0 원본 | `bggen/<state.rawValue>_f0.png` (1024px, 크기·색 정규화 기준) |
| 결과 저장 | `CharacterImageStore.save` → gallery/<uuid>.png + metadata.json (batchId, prompt 포함), 활성 슬롯 미적용 |
| 캔디 차감 | `GenerationQuota.record(cost)` — App Group UserDefaults (Android: 공유 SharedPreferences/DataStore, 07 스펙) |
| 세션 토큰 | KeychainStore (Android 제외 — 로그인 없음) |
| API 설정 | baseURL `https://withu-api.ysy1398.workers.dev`, apiToken 로컬 전용(커밋 금지), timeout 1800/3600 |

---

## 6. Android 구현 노트 (WorkManager 설계)

### 6.1 레이어 매핑

| iOS | Android |
|---|---|
| `actor APIClient` + URLSession | `ApiClient` 싱글턴 + OkHttp (readTimeout 30분, callTimeout 60분) + kotlinx.serialization(`@SerialName` snake_case) |
| preflight ephemeral 5초 세션 | 별도 OkHttpClient (connect/read 5초) 또는 `newBuilder()` 파생 |
| background URLSession + upload task | **WorkManager `CoroutineWorker`** (`GenBatchWorker`) — unique work name `"bggen"` + `ExistingWorkPolicy.REPLACE`(start) / `APPEND_OR_REPLACE`(retry). Worker 하나가 큐 전체를 순차 처리 (잡당 Worker 분리보다 iOS 의 '순차 1개' 와 큐 상태 공유가 단순) |
| 화면 꺼짐/앱 종료에도 진행 | `setForeground()` — **Foreground Service 알림 필수** (dataSync 타입). 생성이 잡당 1–5분이라 expedited 로는 부족 |
| sessionSendsLaunchEvents / completionHandler 게이팅 | 불필요 — Worker 프로세스가 살아있는 동안 코루틴으로 처리. iOS 의 pendingLock/eventsDrained 대응물 없음 |
| jobs.json (Application Support) | `context.filesDir/bggen/jobs.json` — 동일 스키마 (Json 직렬화) |
| `@Observable` + tick | `StateFlow<BgGenState>` (jobs, phase, images) — Compose 는 collectAsState |
| resumeIfNeeded (런치) | Application.onCreate 에서 jobs.json 복원 → running 잡을 queued 로 강등 후, isActive 면 Worker enqueue (WorkManager 는 프로세스 사망 시 Worker 를 알아서 재시작하므로 iOS 의 getAllTasks 대조가 필요 없음 — 복원 시 무조건 running→queued 강등이 동일 효과) |
| 본문 없는 2xx 재큐잉 | OkHttp 는 본문 유실이 없으므로 이 경로는 사실상 안 탐 — 단 스키마 호환 위해 attempts 필드는 유지, 빈 본문 2xx 시 동일하게 1회 재큐잉 |
| UNUserNotificationCenter | NotificationManagerCompat + 채널 (POST_NOTIFICATIONS 런타임 권한, 03 스펙과 공유). 알림 탭 → 결과 화면 deep link |
| WidgetCenter.reloadAllTimelines | `GlanceAppWidget.updateAll(context)` |
| ImageProcessing.chromaKeyRemoved / matchedToReference / colorMatched | Bitmap 픽셀 연산 포팅 (별도 스펙 — 02 단건 생성과 공유) |
| Idempotency-Key = UUID/job.id | `java.util.UUID.randomUUID().toString()` 동일 |

### 6.2 Worker 실행 흐름 (의사코드)

```kotlin
class GenBatchWorker(ctx, params) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
        setForeground(genForegroundInfo())
        val queue = BgGenQueue(applicationContext)   // jobs.json 로드/저장 담당
        while (true) {
            val job = queue.nextQueued() ?: break
            queue.markRunning(job.id)                 // attempts+1, persist
            val result = runCatching { api.generateBatch(bodyFile(job.id), job) }
            queue.process(job.id, result)             // §4.4 로직 그대로 (성공 저장/차감/체이닝/재큐잉/실패)
        }
        queue.finish()                                // Glance 갱신 + phase 별 알림
        return Result.success()                       // 재시도 정책은 큐 내부 재큐잉으로 대체 — Worker Result.retry() 사용 안 함
    }
}
```

- **취소**: `cancelAll()` = `WorkManager.cancelUniqueWork("bggen")` + 큐의 queued/running → failed(`취소했어요`) + wasCancelled 플래그 persist. Worker 의 CancellationException 은 무시.
- **frame1 체이닝**: 큐 내부 append 이므로 while 루프가 자연히 이어 처리 — 별도 Worker 체이닝 불필요.
- **402 처리**: 잡에 paymentRequired 기록만 하고 루프 계속 (iOS 동일). 뷰(03 스펙)가 페이월 트리거.
- **주의**: Doze/배터리 최적화로 Foreground Service 라도 네트워크가 지연될 수 있음 — `setForegroundServiceType="dataSync"` + WorkManager Constraints(NetworkType.CONNECTED).
- **주의**: `images` 인메모리 맵은 프로세스 재시작 후 비므로 (iOS 동일) 뷰는 CharacterImageStore.loadFrame fallback 을 반드시 구현.
- **주의**: 캔디 차감(`GenerationQuota.record`)은 Worker 프로세스에서 실행 — 쿼터 저장소는 프로세스 간 안전한 SharedPreferences/DataStore 여야 함 (07 스펙과 동일 저장소).

### 6.3 직렬화 규칙

- 서버 통신: snake_case (`reference_image_base64`, `art_style`, `image_base64`, `revised_prompt`, `free_consumed`, `free_batch_remaining` 등). kotlinx.serialization `@SerialName` 명시가 안전.
- jobs.json: iOS 는 기본 인코더(camelCase) — Android 도 camelCase 로 저장 (파일은 플랫폼 로컬이라 교차 호환 불필요, 단 필드명은 동일하게).

---

## 7. 제외 항목 (SCOPE.md 기준)

- **Sign in with Apple / Google 로그인**: `authenticateApple`, `fetchMe`, `deleteAccount`, `KeychainStore`, Bearer 헤더 — 이번 범위 제외. `/generate` 는 `X-Withu-Token` 경로만 사용.
- **IAP 검증** (`verifyPurchase`, `/iap/verify`): Play Billing 후속 — 07 스펙의 '준비 중' 모델.
- **Entitlement 서버 동기화** (`syncCreditsUp`): 로그인 없어 서버 잔액이 없음 — 응답의 entitlement 필드는 무시(파싱만).
- **구독** (`subActive`/`subExpiresAt`): 표시·로직 모두 제외.
- **Wear OS 이미지 전송**: '적용' 시 워치 전송 훅 없음 (활성 슬롯 저장 + Glance 갱신까지만).
- `/redeem`·`/referral/apply` 는 Bearer 필요 API 라 **서버가 401 을 줄 수 있음** — 페이월(07)에서 호출 시 에러를 koreanized 문구로 표시하는 선까지만 (동작 보장은 로그인 도입 후).
