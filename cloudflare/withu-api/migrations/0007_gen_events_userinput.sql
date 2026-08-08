-- gen_events — 사용자 원본 입력 표시용 컬럼.
-- prompt 는 서버가 실제로 OpenAI 에 보낸 합성 프롬프트(포즈·영어 가드레일 포함) 그대로 두고,
-- user_input = 사용자가 실제로 입력한 한국어 원문, input_field = 그게 어떤 입력칸이었는지 라벨.
-- 참고사진(첨부)은 별도 컬럼 없이 had_reference=1 이면 R2 refs/<id>.png 로 저장된다.

ALTER TABLE gen_events ADD COLUMN user_input TEXT;
ALTER TABLE gen_events ADD COLUMN input_field TEXT;
