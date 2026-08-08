# withu/Withy — 안드로이드 수익화 + 크로스플랫폼 로그인 + 갤러리 백업 실행 계획

작성 근거: 실제 코드/스키마 정독 (`cloudflare/withu-api/src/*`, `migrations/0001~0008`, iOS `withu/Auth`·`Networking`, Android `app/.../{net,quota,paywall,gallery,shared}`). 구현 전 계획서 — 이 문서는 실행 순서·파일 단위 작업·서버 변경·위험을 정리한다.

> **핵심 제약 (절대 위반 금지)**: 이 Worker(`withu-api.ysy1398.workers.dev`)는 **App Store 라이브 iOS 앱이 그대로 쓰는 프로덕션 서버**다. 모든 스키마/라우트 변경은 **iOS 하위호환**이어야 한다 — 새 컬럼은 nullable, 새 테이블/라우트만 추가, 기존 `/auth/apple`·`/me`·`/iap/verify`·`/gallery`·`/generate` 응답 형태 불변.

---

## 0. 결정 확정됨 (2026-07-19 사용자 답변)

| # | 항목 | **확정** | 비고 |
|---|---|---|---|
| **D1** | 인증 방식 | **Google 로그인** (2026-07-20 변경) | 사용자 "구글로그인 ㄱㄱ". 이메일 발송 인프라 불필요(구글이 검증). **Android=Google Sign-In → 서버 `/auth/google`(ID token 검증). iOS는 Apple 유지 + 크로스플랫폼은 identities 매핑.** ⚠️트레이드오프 아래 |
| ~~D2~~ | ~~이메일 발송~~ | **불필요** (D1=구글이라 폐기) | 구글이 이메일 소유를 대신 검증 → 발송 서비스/도메인 필요 없음 |
| **D3** | 캔디 권위 | **서버 권위로 전환 (해)** | 다기기 중복 지출 구멍 해소. ⚠️ **고위험(라이브 402 desync 재발 가능)** → 플래그 뒤 구현, 테스트 후에만 배포 |
| **D4** | 가격 | **iOS와 동일** | 캔디팩 4종 수량·가격 iOS parity. 구독 없음(iOS도 제거됨) |
| **D5** | 순서 | **A (로그인→갤러리→결제)** | 사용자 "맘대로" → 의존성상 A가 유일하게 타당(§2) |

> **밤새 진행 범위(위험 0)**: 결정 기록 + 추가 전용 마이그레이션 초안(`0009_identities.sql`, 미적용). **자율 금지**: 서버 배포, 라이브 캔디 권위 전환 실적용, Google OAuth 클라이언트 생성(사용자 계정), Play Console. 이들은 사용자와 함께.

### 0-c. Google 로그인 트레이드오프 (사용자 인지 필요)

- **Android 신규/자기 기기 동기화**: 완전 무결. Google 로그인 → `/auth/google` → 계정. 다른 Android 기기서 같은 구글로 로그인하면 캔디·갤러리 그대로.
- **iOS ↔ Android 크로스 동기화**: 기존 iOS 사용자는 **Apple `sub`** 로 계정이 있음. Android의 Google identity 와 **자동으로 안 이어진다**(Apple relay 이메일이라 이메일 자동매칭도 불가). → 이으려면 둘 중:
  - (권장) iOS 앱에 **'Google 계정 연결'** 버튼 추가 → 로그인된 Apple 계정에 google identity 매핑(`identities`). 그 뒤 Android Google 로그인 = 같은 계정. **iOS에 Google SDK 추가 필요(4.8은 SIWA 있어 충족)** — 라이브 iOS 업데이트라 사용자와 함께.
  - (대안) 지금은 **Android만 Google**로 독립 출시, iOS 연동은 후속. Android 자체는 완결.
- **필요 셋업(사용자, ~10분)**: Google Cloud 프로젝트 → OAuth 동의화면 → OAuth 클라이언트 2개: **Web**(서버가 ID token audience 검증용, 제일 중요) + **Android**(package `com.seoyoung.withu` + SHA-1). SHA-1은 아래.
  - 로컬 테스트(debug): `92:7B:E3:64:A5:93:2C:84:0B:FA:18:15:0A:3B:EB:6B:D5:8E:CA:8D`
  - 업로드키: `8F:06:C8:0B:DE:AD:8C:8A:94:30:81:3C:91:9B:0D:11:4D:FB:69:25`
  - 프로덕션(Play 배포 후): Play Console → 앱 무결성의 **Play 앱 서명 SHA-1**도 등록해야 실기기 Play 설치본에서 로그인됨.

---

## 0-b. (원본) 결정 근거 — 자는 사용자가 깨면 결정할 것 (BLOCKER 5)

아래 5개는 **코드로 결정 못 하는 제품/인프라 선택**이라, 착수 전에 사용자 확인이 필요하다.

| # | 결정 항목 | 기본 권고 | 왜 사람이 정해야 하나 |
|---|---|---|---|
| **D1** | **인증 방식** — 이메일 OTP(매직코드) vs Google 로그인 추가 vs Apple유지+Google | **이메일 OTP를 신규 공용 아이덴티티로, 기존 Apple 로그인은 그대로 유지 + '이메일 연결' 마이그레이션** (§1 분석) | Apple 4.8·기존 라이브 사용자 마이그레이션·인프라 비용이 걸림. 되돌리기 비쌈 |
| **D2** | **이메일 발송 서비스** (D1이 이메일 OTP면) — Resend / Postmark / AWS SES / Cloudflare Email Sending | **Resend** (Workers 친화, 무료 3k/월, 도메인 DKIM 간단) | 계정·도메인·요금 발생. `cloudflare-email-service` 스킬 참고 |
| **D3** | **캔디 잔액 권위 모델** — 현행 '로컬 권위'를 다기기 로그인에서도 유지할지, **서버 권위로 전환**할지 (§5) | **로그인+billing 시점에 서버 권위(dormant `chargeGeneration`)로 전환** | 현행 로컬 권위는 다기기에서 캔디 중복 지출 구멍(§5). 정책·리스크 판단 필요 |
| **D4** | **Play 상품 ID·가격 확정** — 캔디팩 4종(미니10·포켓30·파우치50·파티100). **구독은 iOS에서 이미 제거됨** (§3, §4) | iOS 캔디 수량 그대로, 원화 가격은 Play Console에서 티어로 | 실결제·심사·환불 정책과 직결. iOS StoreManager는 consumable만 판다 |
| **D5** | **진행 순서** — A(로그인+갤러리→결제) / B(결제 먼저) / C(전체 한번에) | **A** (아래 §의 의존성 분석 결론) | 릴리스 리듬·리스크 허용도는 제품 판단 |

---

## 1. 인증 방식 최종 권고 (D1 — 사용자 최종확인 필요)

### 1.1 현재 서버 아이덴티티 모델 (코드 근거)

- `auth.js:verifyAppleIdentityToken` → Apple `identityToken`(RS256) 검증 → **`sub` = Apple 영구 사용자 ID**를 계정 키로 씀.
- `db.js:upsertAccount(env, sub, email)` → `accounts.sub` PK. `entitlements.sub`, `gallery_items.sub`, `iap_transactions.sub` 등 **모든 테이블이 이 `sub` 하나에 외래키로 매달림**.
- 세션 토큰(`signSession`)의 `sub` 클레임 = 이 계정 키. `subFromRequest` 가 매 요청에서 이걸 꺼낸다.
- **결론**: "같은 계정으로 iOS+Android 동기화"란 곧 **두 플랫폼의 로그인이 같은 `account_sub` 로 귀결**되게 만드는 문제다. Apple `sub` 와 Google `sub` 는 서로 다른 값이라 그냥은 안 이어진다.

### 1.2 기존 iOS 라이브 사용자 마이그레이션 문제 (핵심)

- iOS 사용자는 이미 **Apple `sub`** 로 계정이 생성돼 캔디/갤러리/구매기록을 보유.
- `accounts.email` 은 **nullable**이고, Apple은 이메일을 **최초 인가 1회만** 주며 사용자가 **"이메일 가리기"(private relay `@privaterelay.appleid.com`)** 를 고르면 실주소를 못 받는다 → **기존 Apple 사용자를 이메일로 자동 매칭 불가**. 자동 통합은 불가능하고, **사용자가 앱에서 명시적으로 '이메일 연결'을 해야** 안전하게 이어진다.

### 1.3 옵션 비교

| 기준 | A. 이메일 OTP (신규 공용) | B. Google 추가 (양 플랫폼) | C. Apple유지 + Google추가(iOS) |
|---|---|---|---|
| 크로스디바이스 동기화 | ✅ 플랫폼 무관, 프로바이더 불일치 없음 | ⚠️ 양쪽 Google이면 됨, but iOS Apple 사용자 고립 | ⚠️ 프로바이더 2개 → 링크 없으면 한 사람이 계정 2개 |
| Apple 가이드라인 4.8 | ✅ **회피** — 이메일 OTP는 3rd-party 소셜 로그인이 아님 → SIWA 강제 대상 아님 | ❌ iOS에 Google(소셜) 붙이면 4.8 발동 → SIWA 병행 필수(이미 있음) | ⚠️ 4.8 충족(SIWA 있음)이나 계정 링크 복잡 |
| 기존 iOS 사용자 마이그레이션 | ⚠️ '이메일 연결' 플로우 필요(자동 불가) but **가장 깔끔** — Apple 계정에 이메일 identity 추가 | ❌ Apple↔Google 링크 없으면 마이그레이션 안 됨 | ⚠️ 명시적 링크 플로우 필수 |
| 필요 인프라 | 이메일 발송 서비스(D2) + OTP 저장(KV) | Google OAuth(iOS+Android 클라 설정, `/auth/google` 서버 검증) | Google OAuth + 링크 로직 |
| 비용 | 이메일 발송(무료~소액) | 무료(Google) | 무료(Google) |
| 프라이버시/마찰 | 이메일 1개면 끝, 비번 없음 | Google 계정 필요 | 최다 마찰 |

### 1.4 권고 — **A (이메일 OTP) + 기존 Apple 유지 + 링크 마이그레이션**

- **신규 공용 아이덴티티 = 이메일 OTP.** 안드로이드 신규 사용자는 이메일로 로그인 → 계정 생성.
- **iOS는 `/auth/apple` 그대로 유지** (라이브 깨지 않음). 기존 Apple 사용자는 설정에서 **'이메일 연결'**(OTP 인증)로 자기 계정에 email identity를 추가 → 그 이메일로 안드로이드에서 로그인하면 **같은 `account_sub`** 로 붙어 캔디·갤러리 공유.
- 이를 위해 아이덴티티를 계정에서 분리하는 **`identities` 매핑 테이블**(신규, additive)을 둔다. 기존 Apple 사용자는 **Apple `sub` 자체가 canonical `account_sub`** (마이그레이션 불필요), 이메일 identity는 그 위에 추가로 매핑.
- **4.8 회피**가 핵심 이점: 이메일 OTP는 소셜 로그인이 아니라 Apple이 SIWA 병행을 강제하지 않는다. (Google을 iOS에 넣는 순간 4.8이 발동하므로 피한다.)

> 사용자 확인 필요: 이메일 OTP 방향 확정 여부, 그리고 D2 발송 서비스.

---

## 2. 진행 순서 — 의존성 기준 평가 (D5)

### 2.1 실제 의존성 (코드 근거)

- **모든 `/gallery` 라우트는 Bearer(로그인) 게이트** (`index.js:322,343` `subFromRequest` → 없으면 401). → **갤러리 백업은 로그인 선행 필수.**
- **Play 결제를 계정에 귀속**(재설치·다기기 유지)하려면 `/iap/verify` 가 Bearer 필요(`index.js:242`). 로그인 없으면 iOS처럼 **로컬 fallback 적립만** 가능(기기 국한, 앱 삭제 시 소실). → **계정 귀속 결제는 로그인 선행 필수.**
- 즉 **로그인은 갤러리·결제 양쪽의 하드 선행조건.** → **옵션 B(결제 먼저)는 로그인 없이는 '반쪽'** (로컬 적립만) 이고, 다기기 동기화라는 목표를 못 이룬다.

### 2.2 결론 — **옵션 A 권장** (로그인 → 갤러리 → 결제)

1. **인증 기반(서버+안드로이드)** 먼저 — 갤러리·결제의 공통 토대.
2. **갤러리 백업** 다음 — 돈이 안 걸려 **저위험**이고, 새 auth 스택을 **엔드투엔드로 검증**(업로드/다운로드/삭제 reconcile)하는 좋은 첫 실사용.
3. **Play 결제** 마지막 — **최고위험**(실결제·Play 심사·환불·서버 검증)이라, 이미 검증된 auth 위에 얹는다. D3(서버 권위 전환)도 여기서 함께.

> 옵션 C(전체 한번에)는 auth·gallery·billing·서버 스키마·Play Console을 동시에 흔들어 **롤백 단위가 커지고 iOS 회귀 위험**이 겹침 → 비권장. 단, auth가 안착하면 **갤러리와 결제 서버검증은 병렬 진행 가능**.

---

## 3. 서버 작업 (Cloudflare Worker) — iOS 하위호환 필수

> 배포 위험 등급을 각 항목에 표기. **iOS 라이브 영향 = 모든 배포는 기존 라우트 응답 불변을 회귀 테스트한 뒤**.

### 3.1 마이그레이션 `0009_identities.sql` (신규, additive) — 위험 낮음
아이덴티티를 계정에서 분리. **기존 데이터 무변경** (Apple 사용자는 `sub` 가 곧 `account_sub`).

```sql
-- 로그인 방법 → canonical 계정 매핑. 한 계정에 여러 identity(apple/email/google) 가능.
CREATE TABLE IF NOT EXISTS identities (
  provider      TEXT NOT NULL,          -- 'apple' | 'email' | 'google'(후속)
  provider_sub  TEXT NOT NULL,          -- apple sub / 정규화 이메일 / google sub
  account_sub   TEXT NOT NULL,          -- accounts.sub (canonical)
  created_at    INTEGER NOT NULL,
  PRIMARY KEY (provider, provider_sub)
);
CREATE INDEX IF NOT EXISTS idx_identities_account ON identities(account_sub);
```
- 적용: `npx wrangler d1 migrations apply withu-prod --remote`.
- **하위호환**: `/auth/apple` 는 계속 `accounts.sub` 를 그대로 쓰되, 로그인 성공 시 `identities` 에 `('apple', appleSub, appleSub)` 행을 **best-effort upsert** (신규 코드가 있어야 채워짐 — 없어도 기존 동작 무변경).

### 3.2 이메일 OTP 라우트 (신규) — 위험 중간(신규 인프라)
`src/auth.js` + `src/index.js`:
- **`POST /auth/email/start`** `{ email }` → 6자리 코드 생성, **`RATE_KV` 에 `otp:<emailHash>` 해시로 TTL 10분 저장**(평문 코드 저장 금지), 발송 서비스로 메일 전송. IP·이메일별 요청 rate limit(`checkRateLimit` 패턴 재사용). 응답은 **존재 여부 오라클 노출 금지** — 항상 `{ ok: true }`.
- **`POST /auth/email/verify`** `{ email, code }` → 코드 대조(상수시간). 성공 시:
  - `identities` 에서 `('email', normEmail)` 조회 → 있으면 그 `account_sub`, 없으면 **새 계정 생성**(`upsertAccount` 를 email-provider용으로 일반화: canonical sub = `crypto.randomUUID()` 또는 `email:` 프리픽스 결정성 키) + `identities` 행 추가.
  - `signSession(account_sub)` → iOS와 동일한 세션 토큰 반환 (`{ session_token, expires_at, entitlement }`).
- **`POST /auth/email/link`** (Bearer 필요) `{ email, code }` → **로그인 상태에서 자기 계정에 email identity 추가** (기존 iOS Apple 사용자 마이그레이션 경로). 이미 다른 계정에 연결된 이메일이면 409.
- **발송 인프라**(D2): `cloudflare-email-service` 스킬 참고. Resend면 `RESEND_API_KEY` secret + 발신 도메인 DKIM/SPF/DMARC. Worker에서 `fetch('https://api.resend.com/emails', ...)`.
- **하위호환**: 전부 신규 경로 — iOS 무영향.

### 3.3 `upsertAccount` 일반화 — 위험 낮음
`db.js:upsertAccount(env, sub, email)` → 이메일 provider도 쓸 수 있게 시그니처 유지하되 내부에서 `identities` 매핑을 세운다. **entitlements 시드 로직(무료 단건 1) 불변** — 기존 iOS 동작 보존.

### 3.4 Google Play 결제 검증 (`/iap/verify` 확장 또는 신규 `/iap/google/verify`) — 위험 중간
- **Play는 JWS가 아니라 purchase token 모델.** 기존 Apple JWS 경로(`verifyAppleJws`)를 건드리지 말고 **분기 추가**:
  - 권장: 신규 **`POST /iap/google/verify`** `{ product_id, purchase_token }` (Bearer).
- **검증 방식** (2택, D 관련):
  1. **Google Play Developer API** `purchases.products.get`(consumable) — **서비스 계정(GCP) 필요**(§4). 정품·소비상태·환불까지 확인. **권장.**
  2. (경량 대안) Play 서명 데이터를 앱 라이선싱 공개키로 검증 — 서비스계정 불필요하나 소비/환불 상태 미확인 → 비권장.
- 검증 통과 시 `db.js:applyPurchase` 를 **Google 상품맵으로 확장**: 현재 `PRODUCT_CREDITS` 는 Apple ID 키(`com.seoyoung.withu.credits.30` 등). **Google 상품 ID는 다르므로 별도 맵**(`GOOGLE_PRODUCT_CREDITS`) + `iap_transactions` 에 `platform`/`provider` 구분 컬럼(마이그레이션 `0010_iap_platform.sql`, nullable) 추가. `transaction_id` 는 Google `orderId` 사용(멱등 PK 재사용).
- **secret**: `GOOGLE_PLAY_SA_JSON`(서비스계정), 필요 시 `GOOGLE_PLAY_PACKAGE`.
- **하위호환**: Apple `/iap/verify` 불변, 신규 경로/맵/nullable 컬럼만.

### 3.5 (D3) 캔디 서버 권위 전환 — 위험 **높음** (별도 단계, 결제와 함께)
- 현재 `index.js:generateImage` 는 **차감을 안 한다**(로컬 권위). `chargeGeneration`/`refundGeneration`(`db.js`)은 **import만 되고 호출 안 됨 = dormant**. 다기기 로그인 시 캔디 중복 지출(§5) 때문에 결제 붙일 때 재도입 검토.
- **롤백 안전 설계**: `ENFORCE_AUTH` 처럼 **새 플래그 `SERVER_AUTHORITATIVE_CREDITS`** 로 게이트. off면 현행(로컬 권위) 그대로 → iOS 회귀 없음. on 전에 **iOS·Android 양쪽이 서버 잔액을 신뢰하도록 클라 동시 배포** 필요(순서 중요 — 커밋 `fd98948` 의 402 desync 교훈).
- 이건 **결제 단계에서만** 손대고, 그 전(로그인·갤러리)엔 손대지 않는다.

### 3.6 배포 위험·롤백 요약

| 변경 | iOS 영향 | 롤백 |
|---|---|---|
| `0009_identities` / `0010_iap_platform` (nullable/신규 테이블) | 없음 | 테이블 drop (데이터 무손실) |
| 이메일 OTP 라우트 | 없음(신규) | 라우트 제거 |
| `/iap/google/verify` + Google 상품맵 | 없음(신규 분기) | 라우트 제거 |
| **캔디 서버 권위(D3)** | **높음** — 플래그 off면 무영향, on은 클라 동시배포 필수 | 플래그 off 즉시 원복 |

---

## 4. Play Console (사람 몫)

1. **인앱 상품 등록** — 캔디팩 4종(consumable/INAPP). 상품 ID 확정(D4). iOS 수량과 동일(10·30·50·100), 가격은 Play 티어. **구독 상품은 만들지 않음**(iOS에서 이미 제거 — StoreManager는 consumable만 판다).
2. **Play 결제 검증용 서비스계정** — GCP 프로젝트 → 서비스계정 생성 → JSON 키 → **Play Console에 연결**하고 "주문/재무 보기" 권한 부여 → JSON을 Worker secret `GOOGLE_PLAY_SA_JSON` 으로. (§3.4 방식1)
3. **앱 서명/패키지명** — `com.seoyoung.withu` 로 Play 앱 등록, 업로드 키/Play 앱 서명.
4. **심사 고려** — 데이터 안전(Data Safety) 폼(이메일 수집·계정), 계정 삭제 경로(이미 `DELETE /me` 있음 — Android에서도 노출 필요), 결제 테스트 트랙(내부 테스트로 실결제 검증). 이메일 발송 도메인 준비(D2).

---

## 5. 캔디 모델 리스크 — 다기기 캔디 중복 (코드 검증)

### 5.1 현행 모델 실검증
- `GenerationQuota.syncCreditsUp`(iOS/Android 동일): 서버 잔액을 **절대값 덮어쓰기 하지 않고**, 기기 로컬의 `lastSyncedServer` 기준선 대비 **증가분(delta>0)만 로컬 credits에 가산**. **소비(record)는 순수 로컬**이고 **서버로 전송되지 않는다** (`index.js` 는 차감 안 함).
- 서버 `entitlements.credits` 는 `applyPurchase`/`redeem`/`referral` 로 **누적 적립만** 되고 **절대 감소하지 않는다**.

### 5.2 다기기 로그인 시 실제 문제 → **YES, 중복 지출 구멍**
- `lastSyncedServer` 기준선은 **기기별 로컬 저장**(App Group / SharedPreferences — 기기 간 비공유). 소비도 기기별 로컬.
- 시나리오: 사용자가 30캔디 구매(서버 credits=30). 폰·태블릿 둘 다 로그인 → 각 기기 로컬 30. 폰에서 30 다 씀(폰 로컬 0, **서버는 여전히 30**). 태블릿은 서버 총액 기준이라 **여전히 30 사용 가능** → **실효 60캔디**.
- iOS 단독도 한 Apple ID로 iPhone+iPad면 이미 잠재 존재하나, **안드로이드 추가 = 노출 배가**. 결제(실돈)가 붙으면 손실 직결.

### 5.3 결제 붙일 때 대응안 (권장)
- **서버 권위로 전환**(§3.5, D3): dormant `chargeGeneration`(멱등키·우선순위·402 이미 구현됨)을 `SERVER_AUTHORITATIVE_CREDITS` 플래그 뒤에서 `/generate` 에 재도입. 서버가 **순 잔액(net)** 을 관리 → 모든 기기가 같은 잔액을 본다.
- 클라(iOS+Android)는 `syncCreditsUp` 대신 **서버 잔액을 신뢰**하도록 동시 전환. **순서 필수**: 서버 켜기 전에 양 클라 배포(안 그러면 `fd98948` 의 402 desync 재발).
- 최소 대안(전환 부담 시): 서버가 `credits_spent` 카운터를 두고 `net = credits - credits_spent` 를 `getEntitlement` 로 노출, 클라는 net을 기준선으로. — 그래도 소비 보고 경로가 필요하므로 결국 서버 권위와 유사.

---

## 6. 안드로이드 앱 작업 (파일 단위)

> 원칙(`00-PLAN §0`): 키·파일명 iOS 바이트 동일, 문구 iOS 원문, 공유 API에 Context 파라미터 없음, 파일 I/O는 `Dispatchers.IO`.

### 6.1 인증 (신규 — iOS `Auth/` 대응)
- **신규 `auth/SessionStore.kt`** — iOS `KeychainStore` 대응. **EncryptedSharedPreferences**(androidx.security-crypto)로 `session_token`·(선택)`account_email` 저장. 키명은 iOS와 무관(플랫폼 저장소라 파일 호환 대상 아님).
- **신규 `auth/AuthManager.kt`** — iOS `AuthManager` 대응. state(unknown/signedOut/signedIn), `entitlement`, `restore()`(토큰 있으면 낙관적 signedIn + `refreshEntitlement` + GallerySync kick), `startEmailLogin(email)`/`verifyEmail(code)`, `applyEntitlement`(→ `GenerationQuota.syncCreditsUp`), `refreshEntitlement`(401→signOut), `signOut`(토큰 clear + `GenerationQuota.resetServerBaseline`), `deleteAccount`(→ `DELETE /me` + 로컬 wipe).
- **신규 `auth/LoginScreen.kt`** — iOS `LoginGateView` 대응. 이메일 입력 → 코드 입력 2스텝. **문구는 iOS Localizable 원문 확인 후** 대응(없으면 신규 문구는 사용자 확인).
- **`MainActivity.kt`** — nav 그래프에 로그인 게이트/라우트 추가(11 route → +로그인). 온보딩 게이트와 나란히. **로그인은 선택적 게이트**로 시작(둘러보기 허용 여부는 iOS와 맞춤 — iOS는 `LoginGateView` 가 게이트).
- **`home/SettingsSheet.kt`** — 현재 "계정 섹션 SCOPE 제외"(주석 line 83). **계정 섹션 추가**: 로그인/로그아웃, 이메일 연결, 계정 삭제(`DELETE /me`), 내 초대코드 표시.

### 6.2 네트워킹 확장 (`net/ApiClient.kt`, `net/ApiModels.kt`)
- **`ApiClient.kt`** — Bearer 헤더 헬퍼 추가(`SessionStore.token()` → `Authorization: Bearer`). 신규 메서드:
  - `emailStart(email)`, `emailVerify(email, code)` → `AppleAuthResponse` 대응 `EmailAuthResponse`(session_token/expires_at/entitlement).
  - `emailLink(email, code)`(Bearer).
  - `fetchMe(): Entitlement`(Bearer, GET `/me`).
  - `deleteAccount()`(Bearer, DELETE `/me`).
  - `verifyGooglePurchase(productId, purchaseToken): Entitlement`(Bearer, POST `/iap/google/verify`).
  - 갤러리: `fetchGalleryList()`, `uploadGalleryItem(body, id)`, `downloadGalleryImage(id, frame)`, `deleteGalleryItem(id)` — iOS `APIClient` 시그니처 대응.
  - **`redeem`/`applyReferral` 에 Bearer 추가** — 현재 미인증이라 서버가 401(주석에도 명시). 로그인 후 정상 동작.
- **`ApiModels.kt`** — 신규 DTO: `EmailAuthResponse`, `GalleryBackupItem`(id/sourceState/createdAt/hasFrame1/batchId/prompt — snake_case `@SerialName`), `GalleryListResponse{items}`, `GalleryUploadRequest`(image_b64/frame1_b64/source_state/created_at/has_frame1/batch_id/prompt). `Entitlement`·`MeResponse` 는 이미 존재(재사용).

### 6.3 갤러리 클라우드 동기화 (신규 — iOS `GallerySyncManager` 대응, `PARITY-GAPS B-11`)
- **신규 `sync/GallerySyncManager.kt`** — iOS `GallerySyncManager` 로직 동형:
  - `reconcile()`: 로그인(토큰) 있을 때만. pendingDeletes 재시도 → 서버 목록 ↔ 로컬 `metadata.json`(`CharacterImageStore`) 비교 → 로컬-only 업로드, 서버-only 다운로드.
  - **소유 태깅**(`itemOwner`/`knownAccounts`/`pendingDeletes`) — 계정 전환 시 교차 유출 방지. 저장은 공유 SharedPreferences(키명 iOS와 맞출 필요 없음 — 서버 데이터가 아니라 로컬 정책). **주의**: 로컬 태그 키는 iOS와 바이트 동일일 필요 없음(공유 저장소 파일이 아님), 단 `gallery/<uuid>.png`+`metadata.json` **스키마는 iOS 동형 유지**.
  - 트리거: 로그인/복원 직후, 앱 포그라운드, 갤러리 저장/삭제. iOS는 `.galleryChanged` NotificationCenter — Android는 기존 갤러리 저장/삭제 지점에서 `GallerySyncManager.kick()` 호출 배선.
- **`shared/CharacterImageStore.kt`** — `importGalleryItem(id, imageData, frame1Data, sourceState, createdAt, batchId, prompt)`(id/메타 보존 저장), `galleryImageData(id, frame)` 가 있는지 확인, 없으면 추가(iOS 대응).
- `WorkManager`(`sync/`) 로 백그라운드 reconcile 예약 가능(기존 `BackgroundRefreshWorker` 패턴 재사용).

### 6.4 Play Billing (신규 — iOS `StoreManager` 대응, 결제 단계)
- **의존성**: `com.android.billingclient:billing-ktx`.
- **신규 `billing/BillingManager.kt`** — iOS `StoreManager` 대응:
  - 상품 조회(`queryProductDetails`, 캔디팩 4종 INAPP), 구매 플로우(`launchBillingFlow`), `purchasesUpdated` 리스너.
  - 구매 성공 → **로그인 상태면** `ApiClient.verifyGooglePurchase(productId, purchaseToken)` → `AuthManager.applyEntitlement` → `consumeAsync`(consumable). **로그인 전/서버 실패 시 로컬 fallback** `GenerationQuota.addCredits`(iOS `grant` 동형).
  - 멱등: 처리한 `orderId`/token 로컬 기록(iOS `processedTransactionIds` 대응) + 서버 `iap_transactions` PK 멱등.
  - 앱 시작 시 미소비 구매 복구(`queryPurchasesAsync`) — 결제됐는데 미적립 방지(iOS `Transaction.updates` 대응).
- **`paywall/PaywallSheet.kt`** — 현재 팩 탭이 `showComingSoon()` 토스트(line 174), 가격 `paywall_price_pending`. **실결제로 교체**: `PackRow` 가 `BillingManager` 상품 가격 표시 + 탭 시 구매. 정적 `packs`(line 83) → `BillingManager` 상품맵으로. "내 초대 코드" 카드(line 244 `조건 미충족`)는 로그인+entitlement 도입 후 노출.

### 6.5 기존 파리티 갭 동시 해소
- **`PARITY-GAPS A-4`**(single-gen 진입 시 entitlement 미갱신) — auth 랜딩 후 화면 진입 `refreshEntitlement()` 배선(iOS `CharacterGenView.swift:139`).

---

## 7. 파일별 작업 요약 표

| 영역 | 파일 | 작업 |
|---|---|---|
| 서버 | `migrations/0009_identities.sql` | 신규 identities 매핑 테이블 |
| 서버 | `migrations/0010_iap_platform.sql` | iap_transactions에 provider/platform nullable |
| 서버 | `src/auth.js` | 이메일 OTP 생성/검증, (후속)Google 토큰 |
| 서버 | `src/index.js` | `/auth/email/{start,verify,link}`, `/iap/google/verify` 라우트, apple 로그인 시 identities upsert |
| 서버 | `src/db.js` | upsertAccount 일반화, GOOGLE_PRODUCT_CREDITS 맵, (D3)chargeGeneration 재도입 게이트 |
| 서버 | `wrangler.toml`/secrets | `RESEND_API_KEY`, `GOOGLE_PLAY_SA_JSON`, `SERVER_AUTHORITATIVE_CREDITS` 플래그 |
| AOS | `auth/SessionStore.kt` | EncryptedSharedPreferences 세션 저장 (신규) |
| AOS | `auth/AuthManager.kt` | 로그인 상태·entitlement·이메일 OTP (신규) |
| AOS | `auth/LoginScreen.kt` | 이메일→코드 2스텝 UI (신규) |
| AOS | `MainActivity.kt` | 로그인 라우트/게이트 배선 |
| AOS | `home/SettingsSheet.kt` | 계정 섹션(로그인/삭제/이메일연결/초대코드) |
| AOS | `net/ApiClient.kt` | Bearer 헬퍼 + email/me/gallery/google-iap 메서드 |
| AOS | `net/ApiModels.kt` | EmailAuthResponse·Gallery DTO 추가 |
| AOS | `sync/GallerySyncManager.kt` | 갤러리 reconcile (신규, iOS 동형) |
| AOS | `shared/CharacterImageStore.kt` | importGalleryItem/galleryImageData 확인·추가 |
| AOS | `billing/BillingManager.kt` | Play Billing (신규, iOS StoreManager 동형) |
| AOS | `paywall/PaywallSheet.kt` | '준비 중' → 실결제, 초대코드 카드 노출 |
| 문서 | `android/specs/SCOPE.md`·`PARITY-GAPS.md` | 제외 항목 이동/갭 종료 표기 |

---

## 8. 권장 실행 순서 (마일스톤)

1. **M0 — 결정 확정**: D1(인증)·D2(이메일)·D3(권위)·D4(상품)·D5(순서).
2. **M1 — 서버 인증 기반**: `0009_identities`, 이메일 OTP 라우트, apple→identities upsert. iOS 회귀 확인(무영향). 발송 서비스 연결.
3. **M2 — 안드로이드 로그인**: SessionStore/AuthManager/LoginScreen/Settings 계정 섹션/ApiClient Bearer. redeem·referral·내 초대코드 정상화. (`A-4` 갭 동시 해소)
4. **M3 — 갤러리 백업**: 서버 `/gallery` 는 이미 있음 → 안드로이드 `GallerySyncManager` + CharacterImageStore 확장. 저위험 실사용 검증.
5. **M4 — Play 결제**: Play Console 상품/서비스계정(§4), 서버 `/iap/google/verify`+상품맵, `BillingManager`, PaywallSheet 실결제. **D3 서버 권위 전환**(플래그 → 양 클라 동시배포 → 서버 on)로 다기기 캔디 중복(§5) 봉인.
6. **M5 — (후속) Google 로그인**: 4.8 재검토 후 필요 시 `/auth/google` + `identities('google', …)`.

---

## 부록 — 조사 중 발견한 사실 정정 (task 배경과 실제 코드 차이)

- **구독은 iOS 클라이언트에서 이미 제거됨.** `StoreManager.swift` 는 consumable 캔디팩만 판다(`구독 없음 — 원가 손실 위험으로 제거`). 서버 `db.js` 는 `subscription.monthly` 를 아직 처리하지만(구 빌드 호환) 신규 판매 대상 아님. → **Android도 구독 상품 만들지 말 것.**
- **실제 상품 ID**: `credits.10 / credits.30 / credits.50 / candy.100`(`credits.100`은 ASC에서 영구 소각되어 `candy.100`으로 대체). task가 말한 `credits.30/credits.100/subscription.monthly` 와 다름.
- **`chargeGeneration`/`refundGeneration` 는 dormant** — `index.js` 가 import만 하고 호출하지 않음(로컬 권위). 서버 권위 전환의 발판이 이미 존재.
- **`ENFORCE_AUTH` 현재 미강제** — `/generate` 는 `X-Withu-Token` 경로로 통과(shadow). Android도 이 경로로 동작 중.
