# Apple Developer 승인 후 — 활성화 가이드

승인되면 이 순서대로만 하면 결제 시스템 + 출시가 일사천리로 켜진다.
대부분 복붙. `←` 표시된 곳만 값 입력.

---

## 0. 현재 상태 (이미 된 것)
- [x] Cloudflare Worker 배포 + D1 연결 (`/health` 가 `openai_configured:true, db_configured:true`)
- [x] 결제 시스템 6단계 코드 (Phase 1~6) + 클라/서버 전부
- [x] APIConfig Release URL = `https://withu-api.ysy1398.workers.dev` (skip-worktree, 로컬)
- [x] bundle ID = `sy.withu` (서버 aud 검증과 일치)
- [x] **§2 완료 (2026-06-27)**: D1 마이그레이션 0002~0005 원격 적용 + `SESSION_SECRET` 설정 + 최신 코드 배포(계정삭제·보안수정 라이브). `/auth/apple`·`DELETE /me`·`/me` 정상 응답 확인. (`ENFORCE_AUTH` 는 §5 까지 off 유지)

---

## 1. Xcode — Sign in with Apple capability
1. Xcode → withu 타깃 → **Signing & Capabilities**
2. Team 이 유료(=`(Personal Team)` 딱지 없음)인지 확인
3. **`+ Capability` → 검색창에 `sign` → "Sign in with Apple"** 더블클릭
4. `withu/withu.entitlements` 에 `com.apple.developer.applesignin` 가 자동 추가됨

---

## 2. 서버 — 마이그레이션 + 재배포 (인증/결제는 아직 끄고)
```
cd ~/Desktop/withu/cloudflare/withu-api
npx wrangler d1 migrations apply withu-prod --remote     # 0002~0005 적용
npx wrangler deploy
curl https://withu-api.ysy1398.workers.dev/health        # 모두 true 확인
```
> `ENFORCE_AUTH` 는 **아직 켜지 않는다** (TestFlight 로그인 검증 후 3단계 끝에).

(선택) 봇 1차 차단 토큰:
```
npx wrangler secret put WITHU_API_TOKEN                  # ← 임의 긴 문자열
```
→ 같은 값을 `withu/Networking/APIConfig.swift` 의 `apiToken` 에 넣기 (skip-worktree, 로컬만).

(선택) IP rate limit:
```
npx wrangler kv namespace create RATE_KV                 # → id 를 wrangler.toml 의 주석 풀어 채우고 재배포
```

---

## 3. App Store Connect
1. **유료 계약 + 은행·세금 정보** (Agreements) — 없으면 결제 자체가 작동 안 함
2. **인앱 상품 3종** 등록 (productID 정확히 일치):
   - `com.seoyoung.withu.credits.30` (소비성)
   - `com.seoyoung.withu.credits.100` (소비성)
   - `com.seoyoung.withu.subscription.monthly` (자동갱신 구독)
   - 가격은 `withu/withu.storekit` 의 테스트값 참고해 책정
3. **개인정보처리방침 URL** 등록 (4단계에서 호스팅한 주소)
4. **개인정보 항목 신고** — `PrivacyInfo.xcprivacy` 와 일치 (건강·위치·사진·사용자 콘텐츠)

---

## 4. 법적 문서 호스팅 (심사 필수)
1. `legal/PRIVACY_POLICY.md`, `legal/TERMS_OF_SERVICE.md` 를 HTML 로 변환 → GitHub Pages 등에 배포
2. 200 으로 열리는 주소 확보
3. `withu/ContentView.swift` 의 개인정보처리방침·이용약관 `Link` URL 을 그 주소로 교체
   (현재 `kkcdkk.github.io/withu/...` 는 404 — 이 URL 교체는 문구가 아니라 링크 주소)

---

## 5. TestFlight 로그인 검증 → 인증 강제
1. 실기기에서 Sign in with Apple 로그인 동작 확인 (DEBUG 빌드는 "둘러보기" 우회 있음)
2. 로그인·무료차감·결제·할인코드·추천이 정상이면:
```
cd ~/Desktop/withu/cloudflare/withu-api
npx wrangler secret put ENFORCE_AUTH                     # ← true
```
이제 토큰 없는 `/generate` 는 401 → 앱은 로그인 게이트로.

---

## 6. 할인코드 발급 (필요 시)
```
npx wrangler d1 execute withu-prod --remote --command \
  "INSERT INTO redeem_codes (code, kind, amount, max_uses, used_count, expires_at) VALUES ('WELCOME', 'free_single', 5, 1000, 0, NULL)"
```
kind: `credits` | `free_single` | `sub_days`.

---

## 7. 유료 출시 전 보안 강화 (코드리뷰 지적 — 유료 결제 켜기 전 필수)
- [ ] 🔴 **`ALLOW_SANDBOX_IAP` 제거** — 정식 출시 시 `cloudflare/withu-api/wrangler.toml` 의 `ALLOW_SANDBOX_IAP = "1"` 줄을 지우고 재배포. 안 지우면 누구나 Sandbox 테스터 계정으로 무료 캔디 무한 적립 가능 (TestFlight 기간에만 켜 둠).
- [ ] 🔴 **Idempotency 완전 멱등** — 현재 `APIClient.generateImage` 가 호출마다 키 발급. 네트워크 응답 유실 시 재시도 이중차감 가능. 생성 시도 단위 영속 키 + 서버 멱등 응답(결과 재반환) 필요.
- [ ] **구독 일일 상한** — `db.js` chargeGeneration 의 subscription 분기(현재 무제한)에 일일 카운터. (만료일 체크는 반영 완료.)
- [ ] **OpenAI 월 사용 한도** — platform.openai.com 대시보드 (코드 밖, 비용 안전망).

### 코드리뷰에서 이미 반영한 것
- [x] **StoreKit JWS 서명 검증** — auth.js `verifyAppleJws` 가 ES256 강제 + x5c 체인 전체를 Apple Root CA G3 까지 검증
- [x] **Sandbox 구매 차단** — db.js `applyPurchase` 가 `environment !== "Production"` 거부 (QA 기간엔 `ALLOW_SANDBOX_IAP=1` 로 임시 허용, §7 참고)
- [x] **구매 이중 적립 레이스 제거** — 서버: INSERT(PK 클레임) 먼저 → 적립. 클라: StoreManager 가 처리한 transactionId 영속 추적(purchase+updates 이중 경로 dedup)
- [x] **환불(revocationDate) 반영** — 환불 트랜잭션 적립 거부 + 구독이면 sub_active=0
- [x] 서버 구독 **만료일 체크** (만료 후 무제한 생성 방지) — db.js
- [x] JWS payload **bundleId 1차 확인** — db.js
- [x] refine 시 이전 연속 프레임 잔상 제거 — CharacterGenView
- [x] 온보딩 슬라이드 트랜지션 → opacity (VibeKit) — OnboardingView
- [x] `.headline` 5곳 → `.callout.semibold` (VibeKit 타이포) — 생성/갤러리/온보딩
- [x] PaywallView 배경 동적 tint + 크레딧 서버 잔액 표시
- [x] **계정 삭제(회원탈퇴)** — 설정 > 계정 (로그아웃·삭제), 서버 `DELETE /me` 가 sub 참조 6테이블 삭제 + 로컬 캐릭터/갤러리/배경/데코까지 `wipeAll()`. **Apple 5.1.1(v) 충족** (단 토큰 revoke 는 아래 8 참고)
- [x] **렉 제거** — CharacterImageStore 디코드 캐시(홈 0.7초 swap·갤러리 스크롤) + ImageProcessing CIContext 재사용
- [x] **Info.plist 정리** — ATS 평문 예외(개인 Tailscale IP) 제거, `ITSAppUsesNonExemptEncryption=false`. ⚠️ 로컬 FastAPI 를 HTTP 로 직접 붙는 디버그는 이제 ATS 에 막힘 → 디버그도 HTTPS Worker(APIConfig) 사용.

---

## 8. 감사로 새로 발견한 출시 차단 (문서에 없던 것)
- [ ] 🔴 **watchOS 앱 아이콘** — `withu Watch App/Assets.xcassets/AppIcon.appiconset` 에 PNG 0개(`Contents.json` 만). Watch 앱 아카이브/업로드 실패. 1024 아이콘 추가 필요 (user-action).
- [ ] 🔴 **Sign in with Apple 토큰 revoke** — 계정 삭제 시 Apple REST API 로 토큰 폐기까지 해야 5.1.1(v) 완전 충족(심사 요구 가능). 현재는 서버 데이터 삭제 + 로컬 로그아웃까지만 구현. Apple `.p8` 키(team id/key id/client secret JWT) 설정 후 `/me` DELETE 핸들러에 revoke 호출 추가 — 유료 가입 후 자격 생기면 작업.

---

## 9. 아카이브 → 심사
1. Xcode → Product → Archive (Release)
2. Info.plist ATS: 프로덕션은 HTTPS 라 통과 (전면 허용 이미 제거됨)
3. TestFlight 베타 한 바퀴 → App Store 심사 제출

---

### 활성화 순서 한 줄 요약
capability → 마이그레이션·배포 → 상품·계약 → 법적 호스팅·URL → TestFlight 검증 → `ENFORCE_AUTH=true` → 아카이브·심사
