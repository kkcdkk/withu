-- withu Phase 1 — 계정 + 권리(entitlement) 기반 스키마
-- 서버 권위: 무료/크레딧/구독 잔액은 여기(서버)가 보유. 클라는 표시용 캐시.
-- 계정 키 = Apple Sign in 의 sub (영구 사용자 ID). 같은 Apple ID = 같은 행 → 재설치로 무료 리셋 불가.

CREATE TABLE IF NOT EXISTS accounts (
  sub               TEXT PRIMARY KEY,          -- Apple user id (영구)
  email             TEXT,                       -- 최초 로그인 시에만 옴 (없을 수 있음)
  my_referral_code  TEXT UNIQUE,                -- 이 사용자의 추천 코드 (Phase 6)
  created_at        INTEGER NOT NULL,           -- epoch seconds
  last_seen_at      INTEGER NOT NULL,
  revoked_at        INTEGER                     -- Apple 권한 철회/계정 삭제 시
);

CREATE TABLE IF NOT EXISTS entitlements (
  sub                    TEXT PRIMARY KEY,
  free_batch_remaining   INTEGER NOT NULL DEFAULT 1,   -- 평생 일괄 무료 (가입 시 1회만 시드)
  free_single_remaining  INTEGER NOT NULL DEFAULT 5,   -- 평생 단건 무료 (가입 시 5회만 시드)
  credits                INTEGER NOT NULL DEFAULT 0,    -- 충전 크레딧 (만료 없음)
  sub_active             INTEGER NOT NULL DEFAULT 0,    -- 구독 활성 (0/1)
  sub_expires_at         INTEGER,                       -- 구독 만료 epoch
  updated_at             INTEGER NOT NULL,
  FOREIGN KEY (sub) REFERENCES accounts(sub) ON DELETE CASCADE
);

-- 차감/적립 감사 + 멱등성 (Phase 3 에서 idempotency 키로 이중차감 방지)
CREATE TABLE IF NOT EXISTS generation_log (
  id               TEXT PRIMARY KEY,            -- idempotency key (클라가 시도마다 발급)
  sub              TEXT NOT NULL,
  kind             TEXT NOT NULL,               -- 'single' | 'batch'
  charged_from     TEXT,                        -- 'free_single' | 'free_batch' | 'credits' | 'subscription'
  at               INTEGER NOT NULL,
  FOREIGN KEY (sub) REFERENCES accounts(sub) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_generation_log_sub ON generation_log(sub, at);
