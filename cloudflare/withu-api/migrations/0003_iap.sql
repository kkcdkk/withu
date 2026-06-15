-- Phase 4 — StoreKit 결제 멱등 적립.
-- 클라가 구매 성공 시 transaction JWS 를 /iap/verify 로 제출 → 서버가 멱등 적립.
-- original_transaction_id 를 PK 로 써서 같은 구매가 두 번 적립되지 않게.

CREATE TABLE IF NOT EXISTS iap_transactions (
  transaction_id           TEXT PRIMARY KEY,   -- transactionId (장당 고유)
  original_transaction_id  TEXT,               -- 구독 갱신 묶음
  sub                      TEXT NOT NULL,
  product_id               TEXT NOT NULL,
  kind                     TEXT NOT NULL,       -- 'credits' | 'subscription'
  expires_at               INTEGER,             -- 구독 만료 (consumable 은 NULL)
  applied_at               INTEGER NOT NULL,
  FOREIGN KEY (sub) REFERENCES accounts(sub) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_iap_sub ON iap_transactions(sub);
