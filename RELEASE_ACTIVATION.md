# Apple Developer 승인 후 — 활성화 가이드

승인되면 이 순서대로만 하면 결제 시스템 + 출시가 일사천리로 켜진다.
대부분 복붙. `←` 표시된 곳만 값 입력.

---

## 0. 현재 상태 (이미 된 것)
- [x] Cloudflare Worker 배포 + D1 연결 (`/health` 가 `openai_configured:true, db_configured:true`)
- [x] 결제 시스템 6단계 코드 (Phase 1~6) + 클라/서버 전부
- [x] APIConfig Release URL = `https://withu-api.ysy1398.workers.dev` (skip-worktree, 로컬)
- [x] bundle ID = `sy.withu` (서버 aud 검증과 일치)

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

## 7. 출시 전 보안 강화 (P1 — 권장)
- [ ] **JWS 서명 검증** — `cloudflare/withu-api/src/auth.js` 의 `decodeJwsPayload` TODO. 현재 멱등+온디바이스만. 위조 결제 완전 차단하려면 x5c 인증서 체인 검증.
- [ ] **구독 일일 상한** — `db.js` chargeGeneration 의 subscription 분기(현재 무제한) 에 일일 카운터.
- [ ] **OpenAI 월 사용 한도** — platform.openai.com 대시보드 (코드 밖, 비용 안전망).

---

## 8. 아카이브 → 심사
1. Xcode → Product → Archive (Release)
2. Info.plist ATS: 프로덕션은 HTTPS 라 통과 (전면 허용 이미 제거됨)
3. TestFlight 베타 한 바퀴 → App Store 심사 제출

---

### 활성화 순서 한 줄 요약
capability → 마이그레이션·배포 → 상품·계약 → 법적 호스팅·URL → TestFlight 검증 → `ENFORCE_AUTH=true` → 아카이브·심사
