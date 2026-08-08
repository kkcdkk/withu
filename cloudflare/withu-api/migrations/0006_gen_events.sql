-- withu — 생성 모니터링 로그 (프롬프트/결과/수정 체인)
-- /generate 매 호출을 1행으로 남긴다. 서버 차감용 generation_log 와 별개(감사 아님, 관측용).
-- 결과 이미지는 D1 이 아니라 R2(LOG_BUCKET)에 저장하고 여기엔 키만 둔다.
-- 사용자 참고사진(개인정보)은 저장하지 않는다 — had_reference 플래그만.

CREATE TABLE IF NOT EXISTS gen_events (
  id             TEXT PRIMARY KEY,            -- 시도마다 서버가 발급 (crypto.randomUUID)
  at             INTEGER NOT NULL,            -- epoch ms
  sub            TEXT,                        -- 계정 (로그인 전이면 NULL)
  session_id     TEXT,                        -- 수정 체인 키 (클라 X-Withu-Session). NULL 이면 단독 취급
  refine_index   INTEGER NOT NULL DEFAULT 0,  -- 0 = 원본, 1+ = 같은 세션의 n번째 수정 (서버 계산)
  type           TEXT NOT NULL,               -- single | refine | batch | background
  state          TEXT,                        -- CharacterState.raw (X-Withu-State)
  art_style      TEXT,                        -- casual | pixel
  model          TEXT,                        -- gpt-image-2 | gpt-image-1.5
  platform       TEXT,                        -- ios | android (X-Withu-Platform)
  prompt         TEXT,                        -- 사용자가 입력한 원문 설명
  revised_prompt TEXT,                        -- OpenAI 가 다시 쓴 프롬프트 (있으면)
  had_reference  INTEGER NOT NULL DEFAULT 0,  -- 참고사진 첨부 여부 (0/1) — 사진 자체는 저장 안 함
  status         TEXT NOT NULL,               -- ok | error | blocked
  error          TEXT,                        -- 실패/차단 사유
  latency_ms     INTEGER,                     -- OpenAI 왕복 소요 (성공 시)
  image_key      TEXT                         -- R2 결과 이미지 키 (성공 시 results/<id>.png)
);

CREATE INDEX IF NOT EXISTS idx_gen_events_at ON gen_events(at);
CREATE INDEX IF NOT EXISTS idx_gen_events_session ON gen_events(session_id, refine_index);
CREATE INDEX IF NOT EXISTS idx_gen_events_sub ON gen_events(sub);
