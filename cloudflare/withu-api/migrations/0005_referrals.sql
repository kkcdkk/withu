-- Phase 6 — 친구추천.
-- referee_sub 를 PK 로 써서 피추천인은 평생 1회만 추천 보상.
-- 자기추천/중복은 서버 로직 + PK 로 차단.

CREATE TABLE IF NOT EXISTS referrals (
  referrer_sub  TEXT NOT NULL,
  referee_sub   TEXT PRIMARY KEY,    -- 피추천인 평생 1회
  rewarded      INTEGER NOT NULL DEFAULT 0,
  at            INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_referrals_referrer ON referrals(referrer_sub);
