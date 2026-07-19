-- withu — 갤러리 클라우드 백업 (계정별 캐릭터 갤러리)
-- 재설치/기기 변경 후 로그인하면 만든 캐릭터가 다시 보이게. 로컬(App Group)이 권위,
-- 서버는 백업/복원용. 이미지는 D1 이 아니라 R2(GALLERY_BUCKET) gallery/<sub>/<id>.png 에
-- 저장하고 여기엔 메타만 둔다. (클라 GalleryItem — CharacterImageStore.swift 와 동형)

CREATE TABLE IF NOT EXISTS gallery_items (
  id           TEXT PRIMARY KEY,             -- 클라 GalleryItem.id (UUID — 클라 발급)
  sub          TEXT NOT NULL,                -- 소유 계정
  source_state TEXT,                         -- 처음 만들 때의 CharacterState.rawValue
  created_at   INTEGER,                      -- 클라에서 만든 시각 (epoch s)
  has_frame1   INTEGER NOT NULL DEFAULT 0,   -- 애니메이션 frame1 (<id>_f1.png) 존재 여부 (0/1)
  batch_id     TEXT,                         -- '한번에 만들기' 세션 (단건/옛 항목은 NULL)
  prompt       TEXT,                         -- 만들 때 서버로 보낸 프롬프트 ('만든 기록' 표시용)
  bytes        INTEGER,                      -- frame0 PNG 크기 (관측/용량 관리용)
  uploaded_at  INTEGER                       -- 서버에 업로드된 시각 (epoch s)
);

CREATE INDEX IF NOT EXISTS idx_gallery_items_sub ON gallery_items(sub);
