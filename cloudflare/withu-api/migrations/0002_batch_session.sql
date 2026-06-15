-- Phase 3 — 일괄(batch) 세션 무료 추적용 컬럼.
-- 일괄 생성은 1장씩 N회 호출하되 같은 batch_id 를 공유 → 첫 장이 free_batch 소진하면
-- 같은 세션의 나머지 장은 무료(free_batch_session)로 처리.

ALTER TABLE generation_log ADD COLUMN batch_id TEXT;

CREATE INDEX IF NOT EXISTS idx_generation_log_batch ON generation_log(batch_id);
