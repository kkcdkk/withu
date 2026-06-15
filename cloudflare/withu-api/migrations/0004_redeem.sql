-- Phase 5 — 할인코드.
-- redeem_codes: 발급된 코드(운영이 seed). code_redemptions: 1인 1회 제약.

CREATE TABLE IF NOT EXISTS redeem_codes (
  code        TEXT PRIMARY KEY,
  kind        TEXT NOT NULL,          -- 'credits' | 'free_single' | 'sub_days'
  amount      INTEGER NOT NULL,
  max_uses    INTEGER NOT NULL DEFAULT 1,
  used_count  INTEGER NOT NULL DEFAULT 0,
  expires_at  INTEGER                  -- NULL 이면 무기한
);

CREATE TABLE IF NOT EXISTS code_redemptions (
  code  TEXT NOT NULL,
  sub   TEXT NOT NULL,
  at    INTEGER NOT NULL,
  PRIMARY KEY (code, sub)             -- 같은 코드 1인 1회
);
