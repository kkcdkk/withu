# withu-api

withu 이미지 생성 API를 Cloudflare Workers에서 실행하기 위한 백엔드입니다.

## 엔드포인트

- `GET /health`: 서비스 상태와 `OPENAI_API_KEY` secret 설정 여부를 반환합니다.
- `POST /generate`: iOS 앱의 `GenerateImageRequest`와 같은 JSON을 받고 `image_base64`, `seed`, `revised_prompt`를 반환합니다.

## 로컬 개발

```bash
npm install
npm run dev
```

## 배포

```bash
npx wrangler secret put OPENAI_API_KEY
npm run deploy
```

배포 URL:

```text
https://withu-api.withu-yjs6813.workers.dev
```

## 전환 방향

현재 Swift 쪽 디버그 흐름은 건드리지 않습니다. 이 Worker는 기존 백엔드 API 계약을 복제해 두는 용도이며, 앱 쪽 전환 작업을 별도로 계획한 뒤 배포/QA 빌드에서 `127.0.0.1` 대신 Worker URL을 바라보도록 넘기면 됩니다.
