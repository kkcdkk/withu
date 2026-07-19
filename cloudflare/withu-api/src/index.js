import { verifyAppleIdentityToken, signSession, subFromRequest, verifyAppleJws } from "./auth.js";
import { upsertAccount, getEntitlement, chargeGeneration, refundGeneration, applyPurchase, redeemCode, applyReferral, deleteAccount } from "./db.js";
import UPNG from "upng-js";

const OPENAI_IMAGE_MODEL = "gpt-image-1.5";

// OpenAI 호출 베이스. AI_GATEWAY_BASE(시크릿)가 설정되면 Cloudflare AI Gateway 경유 —
// Worker 직접 호출의 출구 IP 지역이 요청마다 달라 OpenAI 가 간헐적 403("Country ... not supported")을
// 주던 문제를, 게이트웨이의 안정적 출구로 회피한다. 미설정이면 OpenAI 직접 호출(폴백).
//   형식: https://gateway.ai.cloudflare.com/v1/<account_id>/<gateway>/openai
function openaiBase(env) {
  return (env.AI_GATEWAY_BASE || "https://api.openai.com/v1").replace(/\/$/, "");
}

// 인증(Authenticated) AI Gateway 면 cf-aig-authorization 헤더 필요. 토큰 미설정이면 빈 객체(비인증 게이트웨이/직접호출).
function gatewayHeaders(env) {
  return env.AI_GATEWAY_TOKEN ? { "cf-aig-authorization": `Bearer ${env.AI_GATEWAY_TOKEN}` } : {};
}

// 입력 안전 가드 — 길이 컷 + OpenAI Moderation API 사전검사.
// 차감·이미지 생성 전에 호출해 부적절/과도한 프롬프트를 차단한다.
// Moderation API 는 무료. 호출 실패는 fail-open(이미지 생성 API 자체 moderation 이 2차 방어막).
const MAX_PROMPT_LEN = 1500;

async function checkPromptSafe(prompt, referenceB64, env) {
  if (prompt.length > MAX_PROMPT_LEN) {
    return { ok: false, status: 400, reason: "설명이 너무 길어요. 더 짧게 적어 주세요." };
  }
  // 멀티모달 — 텍스트 + (있으면) 참고사진을 함께 검사. omni-moderation 은 이미지도 본다.
  const input = [{ type: "text", text: prompt }];
  if (referenceB64) {
    input.push({ type: "image_url", image_url: { url: `data:image/png;base64,${referenceB64}` } });
  }
  try {
    const res = await fetch(`${openaiBase(env)}/moderations`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${env.OPENAI_API_KEY}`,
        "Content-Type": "application/json",
        ...gatewayHeaders(env),
      },
      body: JSON.stringify({ model: "omni-moderation-latest", input }),
    });
    if (res.ok) {
      const data = await res.json();
      // input 이 배열이면 results 도 항목별 배열 — 하나라도 flagged 면 차단(텍스트/이미지 둘 다 커버).
      if (Array.isArray(data?.results) && data.results.some((r) => r?.flagged)) {
        return { ok: false, status: 400, reason: "안전 정책에 맞지 않는 요청이에요. 다른 묘사나 사진으로 바꿔서 시도해 주세요." };
      }
    }
  } catch {
    // fail-open
  }
  return { ok: true };
}

// FastAPI server.py 와 parity — art_style 별 다른 [Style guidelines].
// 캐릭터 일관성을 위해 클라이언트엔 노출되지 않는 고정 prompt.
const STYLE_SECTIONS = {
  casual: `[Style guidelines]
- Draw the character based on the user's description — appearance, species, and proportions follow the description
- Soft, warm, approachable look with clean, readable shapes that work well as a small icon
- Flat 2D illustration, clean lines, simple shading
- Transparent background — only the character, nothing behind it. Full body visible, character centered
- Keep the same character identity across requests
`,
  pixel: `[Style guidelines]
- 8-bit / 16-bit pixel art sprite
- Retro video game feel, limited palette (8~16 colors)
- Clear pixel boundaries (no anti-aliasing, no smooth gradients)
- Draw the character based on the user's description — appearance and proportions follow the description
- Transparent background — only the character, nothing behind it. Character centered
- Keep the same character identity across requests
`,
};

const COMMON_PROMPT = `You are illustrating a single cute mascot character.

{styleSection}
[Content guidelines]
- Family-friendly, wholesome content only
- No realistic humans, no violence, no inappropriate content
- The image must work as a small icon — keep composition simple
- Do NOT render any text, letters, words, numbers, captions, watermarks, labels, or signatures anywhere in the image

[User request]
`;

function systemPromptFor(artStyle) {
  const styleSection = STYLE_SECTIONS[artStyle] ?? STYLE_SECTIONS.casual;
  return COMMON_PROMPT.replace("{styleSection}", styleSection);
}

// gpt-image-2 는 background=transparent 미지원 — "transparent" 지시를 받으면 가짜 체커보드를
// 그려버린다. v2 요청은 프롬프트의 transparent 표현을 치환하고, 크로마키용 마젠타 단색 배경을
// 지시한다 (클라이언트가 수신 후 #FF00FF 를 제거해 투명 PNG 로 만든다).
function resolveModel(input) {
  return input.model === "gpt-image-2" ? "gpt-image-2" : OPENAI_IMAGE_MODEL;
}

const MAGENTA_BACKGROUND_DIRECTIVE = `

[Background — CRITICAL]
- Fill the ENTIRE background with one solid flat uniform color: pure magenta, exactly #FF00FF (RGB 255, 0, 255)
- Every single background pixel must be that exact color — no gradients, no shadows, no patterns, no checkerboard, no white
- Never use magenta or pink-purple tones anywhere on the character itself
`;

function adaptPromptForModel(prompt, input) {
  if (resolveModel(input) !== "gpt-image-2" || input.kind === "background") {
    return prompt;
  }
  return prompt.replace(/transparent/gi, "plain") + MAGENTA_BACKGROUND_DIRECTIVE;
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // 생성 모니터링 대시보드 (관리자 전용, ADMIN_TOKEN 게이트)
    if (url.pathname === "/admin" || url.pathname === "/admin/") {
      return adminDashboard(request, env);
    }
    if (url.pathname.startsWith("/admin/img/")) {
      return adminImage(request, env, url.pathname.slice("/admin/img/".length));
    }

    if (url.pathname === "/" || url.pathname === "/health") {
      return Response.json({
        ok: true,
        service: "withu-api",
        openai_configured: Boolean(env.OPENAI_API_KEY),
        db_configured: Boolean(env.DB),
        auth_enforced: env.ENFORCE_AUTH === "true",
        ai_gateway: Boolean(env.AI_GATEWAY_BASE)
      });
    }

    // Phase 1 — Sign in with Apple 로그인 핸드셰이크
    if (url.pathname === "/auth/apple") {
      if (request.method !== "POST") return jsonError("Method not allowed", 405);
      return authApple(request, env);
    }

    // Phase 1 — 권리 스냅샷 조회 (앱 시작/포그라운드 동기화)
    //   DELETE → 계정 삭제 (Apple 5.1.1(v))
    if (url.pathname === "/me") {
      if (request.method === "DELETE") return deleteAccountHandler(request, env);
      return meHandler(request, env);
    }

    // Phase 4 — StoreKit 결제 서버 검증/적립
    if (url.pathname === "/iap/verify") {
      if (request.method !== "POST") return jsonError("Method not allowed", 405);
      return iapVerify(request, env);
    }

    // Phase 5 — 할인코드
    if (url.pathname === "/redeem") {
      if (request.method !== "POST") return jsonError("Method not allowed", 405);
      return redeemHandler(request, env);
    }

    // Phase 6 — 친구추천
    if (url.pathname === "/referral/apply") {
      if (request.method !== "POST") return jsonError("Method not allowed", 405);
      return referralHandler(request, env);
    }

    // 갤러리 클라우드 백업 — 계정별 캐릭터 갤러리 (재설치/기기 변경 후 로그인 복원용)
    if (url.pathname === "/gallery") {
      if (request.method !== "GET") return jsonError("Method not allowed", 405);
      return galleryList(request, env);
    }
    if (url.pathname.startsWith("/gallery/")) {
      return galleryItemHandler(request, env, url);
    }

    if (url.pathname === "/generate") {
      if (request.method !== "POST") {
        return jsonError("Method not allowed", 405);
      }

      return generateImage(request, env, ctx);
    }

    return Response.json(
      { detail: "Not found" },
      { status: 404 }
    );
  }
};

// POST /auth/apple { identityToken } → { sessionToken, expiresAt, entitlement }
async function authApple(request, env) {
  if (!env.DB) return jsonError("서버 계정 기능이 아직 설정되지 않았어요.", 503);
  if (!env.SESSION_SECRET) return jsonError("SESSION_SECRET 미설정", 503);

  let body;
  try { body = await request.json(); } catch { return jsonError("JSON 형식 오류", 400); }
  // 클라가 convertToSnakeCase 로 보냄 → identity_token.
  const identityToken = body.identity_token || body.identityToken;
  if (!identityToken) return jsonError("identity_token 필요", 400);

  let claims;
  try {
    claims = await verifyAppleIdentityToken(identityToken, env);
  } catch (e) {
    return jsonError("Apple 토큰 검증 실패: " + e.message, 401);
  }

  await upsertAccount(env, claims.sub, claims.email);
  const sessionToken = await signSession(claims.sub, env);
  const entitlement = await getEntitlement(env, claims.sub);
  const expiresAt = Math.floor(Date.now() / 1000) + 60 * 24 * 60 * 60;
  return Response.json({ session_token: sessionToken, expires_at: expiresAt, entitlement });
}

// GET /me (Bearer) → { entitlement }
async function meHandler(request, env) {
  if (!env.DB) return jsonError("서버 계정 기능이 아직 설정되지 않았어요.", 503);
  const sub = await subFromRequest(request, env);
  if (!sub) return jsonError("Unauthorized", 401);
  const entitlement = await getEntitlement(env, sub);
  if (!entitlement) return jsonError("계정을 찾을 수 없어요.", 404);
  return Response.json({ entitlement });
}

// DELETE /me (Bearer) → { ok: true }. 계정+서버 이용기록 전체 삭제.
async function deleteAccountHandler(request, env) {
  if (!env.DB) return jsonError("서버 계정 기능이 아직 설정되지 않았어요.", 503);
  const sub = await subFromRequest(request, env);
  if (!sub) return jsonError("Unauthorized", 401);
  const result = await deleteAccount(env, sub);
  if (!result.ok) return jsonError("계정 삭제에 실패했어요.", result.status || 500);
  return Response.json({ ok: true });
}

// POST /iap/verify (Bearer) { signed_transaction } → { entitlement }
async function iapVerify(request, env) {
  if (!env.DB) return jsonError("서버 계정 기능이 아직 설정되지 않았어요.", 503);
  const sub = await subFromRequest(request, env);
  if (!sub) return jsonError("Unauthorized", 401);

  let body;
  try { body = await request.json(); } catch { return jsonError("JSON 형식 오류", 400); }
  const jws = body.signed_transaction || body.signedTransaction;
  if (!jws) return jsonError("signed_transaction 필요", 400);

  let payload;
  try { payload = await verifyAppleJws(jws, env); }
  catch { return jsonError("영수증 검증에 실패했어요.", 400); }

  const result = await applyPurchase(env, sub, payload);
  if (!result.ok) return jsonError("적립에 실패했어요.", result.status || 500);

  const entitlement = await getEntitlement(env, sub);
  return Response.json({ entitlement });
}

// POST /redeem (Bearer) { code } → { entitlement } | 409
async function redeemHandler(request, env) {
  if (!env.DB) return jsonError("서버 계정 기능이 아직 설정되지 않았어요.", 503);
  const sub = await subFromRequest(request, env);
  if (!sub) return jsonError("Unauthorized", 401);

  let body;
  try { body = await request.json(); } catch { return jsonError("JSON 형식 오류", 400); }

  const result = await redeemCode(env, sub, body.code);
  if (!result.ok) {
    if (result.status === 409) return jsonError("이미 사용한 코드예요.", 409);
    return jsonError("사용할 수 없는 코드예요.", result.status || 400);
  }

  const entitlement = await getEntitlement(env, sub);
  return Response.json({ entitlement });
}

// POST /referral/apply (Bearer) { code } → { entitlement } | 409
async function referralHandler(request, env) {
  if (!env.DB) return jsonError("서버 계정 기능이 아직 설정되지 않았어요.", 503);
  const sub = await subFromRequest(request, env);
  if (!sub) return jsonError("Unauthorized", 401);

  let body;
  try { body = await request.json(); } catch { return jsonError("JSON 형식 오류", 400); }

  const result = await applyReferral(env, sub, body.code);
  if (!result.ok) {
    if (result.status === 409) return jsonError("이미 추천을 받았어요.", 409);
    if (result.reason === "self") return jsonError("자기 코드는 쓸 수 없어요.", 400);
    return jsonError("사용할 수 없는 코드예요.", result.status || 400);
  }

  const entitlement = await getEntitlement(env, sub);
  return Response.json({ entitlement });
}

// ─────────────────────────────────────────────────────────────────────────────
// 갤러리 클라우드 백업 (계정별 — 재설치/기기 변경 후 로그인하면 복원)
// 로컬(App Group)이 권위, 서버는 백업 — 캔디와 같은 모델(서버가 로컬을 덮어쓰지 않음).
// 이미지는 R2 gallery/<sub>/<id>.png (+<id>_f1.png 애니 프레임), 메타는 D1 gallery_items.
// ─────────────────────────────────────────────────────────────────────────────

const GALLERY_MAX_ITEMS = 400;                    // 계정당 항목 상한
const GALLERY_MAX_IMAGE_BYTES = 6 * 1024 * 1024;  // 이미지 1장 6MB 제한
const GALLERY_DAILY_PUT_LIMIT = 500;              // 계정당 일일 업로드 상한 (반복 업로드 남용/비용 방어 — 400개 전체 첫 백업은 하루에 가능)
const GALLERY_UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function galleryObjectKey(sub, id, frame) {
  return `gallery/${sub}/${id}${frame ? "_f1" : ""}.png`;
}

function galleryB64ToBytes(b64) {
  return Uint8Array.from(atob(b64.includes(",") ? b64.split(",").at(-1) : b64), (c) => c.charCodeAt(0));
}

// GET /gallery (Bearer) → { items: [{ id, source_state, created_at, has_frame1, batch_id, prompt }] }
async function galleryList(request, env) {
  if (!env.DB) return jsonError("서버 계정 기능이 아직 설정되지 않았어요.", 503);
  const sub = await subFromRequest(request, env);
  if (!sub) return jsonError("Unauthorized", 401);
  const { results = [] } = await env.DB.prepare(
    "SELECT id, source_state, created_at, has_frame1, batch_id, prompt FROM gallery_items WHERE sub = ? ORDER BY created_at DESC"
  ).bind(sub).all();
  return Response.json({
    items: results.map((r) => ({
      id: r.id,
      source_state: r.source_state,
      created_at: r.created_at,
      has_frame1: r.has_frame1 === 1,
      batch_id: r.batch_id,
      prompt: r.prompt,
    })),
  });
}

// /gallery/<id> (PUT/DELETE) · /gallery/<id>.png (GET, ?frame=1 이면 애니 프레임)
async function galleryItemHandler(request, env, url) {
  if (!env.DB) return jsonError("서버 계정 기능이 아직 설정되지 않았어요.", 503);
  if (!env.GALLERY_BUCKET) return jsonError("갤러리 백업이 아직 설정되지 않았어요.", 503);
  const sub = await subFromRequest(request, env);
  if (!sub) return jsonError("Unauthorized", 401);

  const raw = url.pathname.slice("/gallery/".length);
  const isPng = raw.toLowerCase().endsWith(".png");
  const id = isPng ? raw.slice(0, -4) : raw;
  if (!GALLERY_UUID_RE.test(id)) return jsonError("잘못된 갤러리 id 예요.", 400);

  if (isPng && request.method === "GET") return galleryImage(env, sub, id, url);
  if (!isPng && request.method === "PUT") return galleryPut(request, env, sub, id);
  if (!isPng && request.method === "DELETE") return galleryDelete(env, sub, id);
  return jsonError("Method not allowed", 405);
}

// 계정(sub) 기준 일일 업로드 상한. 점진 배포: RATE_KV 바인딩이 있을 때만 동작 (checkRateLimit 과 동일 패턴).
async function checkGalleryPutLimit(env, sub) {
  if (!env.RATE_KV) return null;
  const day = new Date().toISOString().slice(0, 10);
  const key = `gput:${sub}:${day}`;
  const used = parseInt((await env.RATE_KV.get(key)) || "0", 10);
  if (used >= GALLERY_DAILY_PUT_LIMIT) {
    return jsonError("오늘 백업 업로드 한도에 도달했어요.", 429);
  }
  await env.RATE_KV.put(key, String(used + 1), { expirationTtl: 60 * 60 * 48 });
  return null;
}

// PUT /gallery/<id> — R2 저장 + D1 upsert. 클라 후처리 완료본 PNG 그대로(재가공 없음).
async function galleryPut(request, env, sub, id) {
  const rateError = await checkGalleryPutLimit(env, sub);
  if (rateError) return rateError;
  let body;
  try { body = await request.json(); } catch { return jsonError("JSON 형식 오류", 400); }
  const imageB64 = body.image_b64 || body.imageB64;
  if (!imageB64) return jsonError("image_b64 필요", 400);

  // 같은 id 가 다른 계정 소유면 충돌 (UUID 라 사실상 없음 — 방어)
  const existing = await env.DB.prepare("SELECT sub FROM gallery_items WHERE id = ?").bind(id).first();
  if (existing && existing.sub !== sub) return jsonError("다른 계정의 항목이에요.", 409);

  // 계정당 상한 — 신규 항목일 때만 검사
  if (!existing) {
    const row = await env.DB.prepare("SELECT COUNT(*) AS n FROM gallery_items WHERE sub = ?").bind(sub).first();
    if ((row?.n ?? 0) >= GALLERY_MAX_ITEMS) {
      return jsonError(`백업 보관함이 가득 찼어요 (${GALLERY_MAX_ITEMS}개). 갤러리에서 안 쓰는 캐릭터를 지워 주세요.`, 409);
    }
  }

  const frame1B64 = body.frame1_b64 || body.frame1B64 || null;
  let bytes, frame1Bytes = null;
  try {
    bytes = galleryB64ToBytes(imageB64);
    if (frame1B64) frame1Bytes = galleryB64ToBytes(frame1B64);
  } catch {
    return jsonError("image_b64 형식 오류", 400);
  }
  if (bytes.byteLength > GALLERY_MAX_IMAGE_BYTES
    || (frame1Bytes && frame1Bytes.byteLength > GALLERY_MAX_IMAGE_BYTES)) {
    return jsonError("이미지가 너무 커요 (장당 6MB 제한).", 413);
  }

  await env.GALLERY_BUCKET.put(galleryObjectKey(sub, id, 0), bytes, { httpMetadata: { contentType: "image/png" } });
  if (frame1Bytes) {
    await env.GALLERY_BUCKET.put(galleryObjectKey(sub, id, 1), frame1Bytes, { httpMetadata: { contentType: "image/png" } });
  } else {
    // 프레임 없는 재업로드면 옛 _f1 고아 객체 정리 (없으면 no-op) — ?frame=1 이 옛 프레임을 서빙하지 않게.
    await env.GALLERY_BUCKET.delete(galleryObjectKey(sub, id, 1));
  }

  const now = Math.floor(Date.now() / 1000);
  await env.DB.prepare(
    `INSERT INTO gallery_items (id, sub, source_state, created_at, has_frame1, batch_id, prompt, bytes, uploaded_at)
     VALUES (?,?,?,?,?,?,?,?,?)
     ON CONFLICT(id) DO UPDATE SET
       source_state = excluded.source_state, created_at = excluded.created_at,
       has_frame1 = excluded.has_frame1, batch_id = excluded.batch_id,
       prompt = excluded.prompt, bytes = excluded.bytes, uploaded_at = excluded.uploaded_at`
  ).bind(
    id, sub, body.source_state ?? null, body.created_at ?? now,
    frame1Bytes ? 1 : 0, body.batch_id ?? null, body.prompt ?? null,
    bytes.byteLength, now
  ).run();

  return Response.json({ ok: true });
}

// GET /gallery/<id>.png — 본인(sub) 소유 확인 후 R2 스트림. ?frame=1 이면 frame1.
async function galleryImage(env, sub, id, url) {
  const row = await env.DB.prepare("SELECT sub FROM gallery_items WHERE id = ?").bind(id).first();
  if (!row || row.sub !== sub) return jsonError("Not found", 404);
  const frame = url.searchParams.get("frame") === "1" ? 1 : 0;
  const obj = await env.GALLERY_BUCKET.get(galleryObjectKey(sub, id, frame));
  if (!obj) return jsonError("Not found", 404);
  return new Response(obj.body, {
    headers: { "Content-Type": "image/png", "Cache-Control": "private, max-age=86400" },
  });
}

// DELETE /gallery/<id> — 본인 소유 확인 후 D1 행 + R2 객체(프레임 포함) 삭제.
// 이미 없으면 ok (멱등 — 클라 pendingDeletes 재시도가 깨끗이 끝나게).
async function galleryDelete(env, sub, id) {
  const row = await env.DB.prepare("SELECT sub FROM gallery_items WHERE id = ?").bind(id).first();
  if (!row) return Response.json({ ok: true });
  if (row.sub !== sub) return jsonError("Not found", 404);
  await env.DB.prepare("DELETE FROM gallery_items WHERE id = ? AND sub = ?").bind(id, sub).run();
  await Promise.all([
    env.GALLERY_BUCKET.delete(galleryObjectKey(sub, id, 0)),
    env.GALLERY_BUCKET.delete(galleryObjectKey(sub, id, 1)),
  ]);
  return Response.json({ ok: true });
}

// 공유 시크릿 토큰 검증. 점진 배포: env.WITHU_API_TOKEN 이 설정돼 있을 때만 강제.
// 설정 전엔 통과시켜 기존 앱 빌드 호환 유지. 설정 후엔 헤더 없는 호출 401.
//   wrangler secret put WITHU_API_TOKEN  (앱 APIConfig.apiToken 과 동일 값)
function checkAuth(request, env) {
  if (!env.WITHU_API_TOKEN) return null;
  const token = request.headers.get("X-Withu-Token");
  if (token !== env.WITHU_API_TOKEN) {
    return jsonError("Unauthorized", 401);
  }
  return null;
}

// IP 기준 일일 생성 상한. 점진 배포: RATE_KV 바인딩이 있을 때만 동작.
//   wrangler kv namespace create RATE_KV  → wrangler.toml 의 id 채우고 deploy
const DAILY_IP_LIMIT = 60;

async function checkRateLimit(request, env) {
  if (!env.RATE_KV) return null;
  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  const day = new Date().toISOString().slice(0, 10); // yyyy-mm-dd (UTC)
  const key = `rl:${ip}:${day}`;
  const used = parseInt((await env.RATE_KV.get(key)) || "0", 10);
  if (used >= DAILY_IP_LIMIT) {
    return jsonError("오늘 만들 수 있는 횟수를 넘었어요. 내일 다시 시도해 주세요.", 429);
  }
  // 카운트 증가 (48시간 후 자동 만료)
  await env.RATE_KV.put(key, String(used + 1), { expirationTtl: 60 * 60 * 48 });
  return null;
}

async function generateImage(request, env, ctx) {
  const authError = checkAuth(request, env);
  if (authError) return authError;

  const rateError = await checkRateLimit(request, env);
  if (rateError) return rateError;

  if (!env.OPENAI_API_KEY) {
    return jsonError("OPENAI_API_KEY secret is not configured.", 503);
  }

  // 로그인 인증 (점진 — ENFORCE_AUTH=true 면 토큰 필수)
  const sub = await subFromRequest(request, env);
  if (env.ENFORCE_AUTH === "true" && !sub) {
    return jsonError("로그인이 필요해요.", 401);
  }

  let input;
  try {
    input = await request.json();
  } catch {
    return jsonError("Request body must be JSON.", 400);
  }

  if (typeof input.prompt !== "string" || input.prompt.trim() === "") {
    return jsonError("prompt is required.", 400);
  }

  // 모니터링 메타 — 헤더에서 세션/상태/플랫폼 수집 (본문은 그대로). logEvent 로 넘긴다.
  const meta = {
    sub,
    sessionId: request.headers.get("X-Withu-Session") || null,
    state: request.headers.get("X-Withu-State") || null,
    platform: request.headers.get("X-Withu-Platform") || null,
    type: eventType(request, input),
    artStyle: input.art_style ?? null,
    model: resolveModel(input),
    prompt: input.prompt,
    userInput: input.user_input ?? null,     // 사용자가 실제 입력한 원문 (표시용)
    inputField: input.input_field ?? null,   // 어떤 입력칸이었는지 라벨
    hadReference: Boolean(input.reference_image_base64),
    referenceB64: input.reference_image_base64 ?? null,  // R2 refs/<id>.png 저장용 (표시용)
  };
  const startedAt = Date.now();

  // 입력 안전 가드 — 부적절한 프롬프트/참고사진은 차감·생성 전에 차단
  const safe = await checkPromptSafe(input.prompt, input.reference_image_base64, env);
  if (!safe.ok) {
    logEvent(env, ctx, { ...meta, status: "blocked", error: safe.reason });
    return jsonError(safe.reason, safe.status);
  }

  // 차감/게이트는 클라이언트(로컬 캔디)가 담당 — 서버는 생성만.
  // 비용 방어는 IP rate limit + OpenAI 월 한도. (서버-권위 차감은 로그인 강제 + 잔액 일원화 후 재도입.)

  let openAIResponse;
  try {
    openAIResponse = input.reference_image_base64
      ? await editImage(input, env)
      : await generateImageFromPrompt(input, env);
  } catch (error) {
    logEvent(env, ctx, { ...meta, status: "error", error: error.message });
    return jsonError(error.message, 400);
  }

  const text = await openAIResponse.text();
  let payload;
  try {
    payload = JSON.parse(text);
  } catch {
    payload = null;
  }

  if (!openAIResponse.ok) {
    const reason = payload?.error?.message ?? text;
    logEvent(env, ctx, { ...meta, status: "error", error: reason });
    return jsonError(reason, openAIResponse.status);
  }

  const image = payload?.data?.[0];
  if (!image?.b64_json) {
    logEvent(env, ctx, { ...meta, status: "error", error: "OpenAI response did not include image data." });
    return jsonError("OpenAI response did not include image data.", 502);
  }

  // 성공 — revised prompt·소요시간·결과 이미지(R2)까지 기록. b64 는 R2 저장용으로 넘긴다.
  logEvent(env, ctx, {
    ...meta,
    status: "ok",
    revisedPrompt: image.revised_prompt ?? null,
    latencyMs: Date.now() - startedAt,
    imageB64: image.b64_json,
  });

  // 계정 무료 1회 — 로그인 사용자의 '처음 만드는 화면' 단건 생성에서만 소진.
  // (기기 재설치와 무관하게 계정당 정확히 1회. 클라는 free_consumed=true 면 캔디 미차감.)
  // 배치(헤더 X-Withu-Kind=batch)·날씨 배경(kind=background)·갤러리 다듬기(kind=refine)는
  // 무료를 먹지 않는다 — 예전엔 body kind 만 봐서 배치/배경 생성이 free_single 을 소진했음.
  let freeConsumed = false;
  let entitlement = null;
  const isSingleCreation = (input.kind == null || input.kind === "character")
    && request.headers.get("X-Withu-Kind") !== "batch";
  if (sub && env.DB && isSingleCreation) {
    try {
      const r = await env.DB.prepare(
        "UPDATE entitlements SET free_single_remaining = free_single_remaining - 1, updated_at = ? WHERE sub = ? AND free_single_remaining > 0"
      ).bind(Math.floor(Date.now() / 1000), sub).run();
      freeConsumed = (r.meta?.changes ?? 0) > 0;
      entitlement = await getEntitlement(env, sub);
    } catch { /* 무료 소진 실패는 생성 자체를 막지 않음 */ }
  } else if (sub && env.DB) {
    try { entitlement = await getEntitlement(env, sub); } catch {}
  }

  return Response.json({
    image_base64: image.b64_json,
    seed: 0,
    revised_prompt: image.revised_prompt ?? null,
    free_consumed: freeConsumed,
    entitlement
  });
}

/// kind 별 prompt 구성:
///   character (default): SYSTEM_PROMPT (style + content guardrails) + 사용자 prompt
///   background:          raw 사용자 prompt (풍경/하늘만, 캐릭터 가드레일 없음)
function buildFullPrompt(input) {
  if (input.kind === "background") {
    return input.prompt;
  }
  return adaptPromptForModel(systemPromptFor(input.art_style) + input.prompt, input);
}

function generateImageFromPrompt(input, env) {
  return fetch(`${openaiBase(env)}/images/generations`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${env.OPENAI_API_KEY}`,
      "Content-Type": "application/json",
      ...gatewayHeaders(env)
    },
    body: JSON.stringify({
      // 클라이언트가 명시한 경우에만 gpt-image-2 (기본 1.5 — 구 빌드 호환)
      model: resolveModel(input),
      prompt: buildFullPrompt(input),
      quality: normalizeQuality(input.quality),
      size: normalizeSize(input.width, input.height),
      // 캐릭터는 투명 배경. 날씨 배경(kind=background)은 풍경. gpt-image-2 는 투명 미지원.
      ...(input.kind === "background" || resolveModel(input) === "gpt-image-2" ? {} : { background: "transparent" }),
      output_format: "png",
      n: 1
    })
  });
}

function editImage(input, env) {
  const form = new FormData();
  form.append("model", resolveModel(input));
  form.append("prompt", buildFullPrompt(input));
  form.append("quality", normalizeQuality(input.quality));
  form.append("size", normalizeSize(input.width, input.height));
  if (resolveModel(input) !== "gpt-image-2") {
    form.append("background", "transparent");
  }
  form.append("output_format", "png");
  form.append("n", "1");
  form.append("image", base64ToBlob(input.reference_image_base64), "reference.png");

  return fetch(`${openaiBase(env)}/images/edits`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${env.OPENAI_API_KEY}`,
      ...gatewayHeaders(env)
    },
    body: form
  });
}

function normalizeQuality(quality) {
  return ["low", "medium", "high", "auto"].includes(quality) ? quality : "medium";
}

function normalizeSize(width, height) {
  const size = `${width}x${height}`;
  return ["1024x1024", "1024x1536", "1536x1024", "auto"].includes(size)
    ? size
    : "1024x1024";
}

function jsonError(detail, status) {
  return Response.json({ detail }, { status });
}

function base64ToBlob(value) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error("reference_image_base64 is invalid.");
  }

  const cleanValue = value.includes(",") ? value.split(",").at(-1) : value;
  try {
    const bytes = Uint8Array.from(atob(cleanValue), (char) => char.charCodeAt(0));
    return new Blob([bytes], { type: "image/png" });
  } catch {
    throw new Error("reference_image_base64 is invalid.");
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 생성 모니터링 (gen_events 로깅 + /admin 대시보드)
// ─────────────────────────────────────────────────────────────────────────────

// 대시보드 썸네일용 — 마젠타(#FF00FF) 배경·투명 배경을 흰색 불투명으로 평탄화.
// gpt-image-2 결과가 핫핑크로 보이는 걸 없앤다. 실패(디코드 등)하면 호출부가 원본을 저장.
function flattenBackgroundToWhite(bytes) {
  const buf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  const img = UPNG.decode(buf);
  const rgba = new Uint8Array(UPNG.toRGBA8(img)[0]);
  for (let i = 0; i < rgba.length; i += 4) {
    const r = rgba[i], g = rgba[i + 1], b = rgba[i + 2], a = rgba[i + 3];
    // 근사 마젠타(배경) 또는 (거의)투명 픽셀 → 흰색 불투명
    if ((r > 180 && g < 90 && b > 180) || a < 24) {
      rgba[i] = 255; rgba[i + 1] = 255; rgba[i + 2] = 255; rgba[i + 3] = 255;
    }
  }
  return new Uint8Array(UPNG.encode([rgba.buffer], img.width, img.height, 0));
}

// 이벤트 타입 한 축으로 정규화: batch(헤더) > refine/background(본문 kind) > single
function eventType(request, input) {
  if (request.headers.get("X-Withu-Kind") === "batch") return "batch";
  if (input.kind === "background") return "background";
  if (input.kind === "refine") return "refine";
  return "single";
}

// 생성 이벤트 기록 — best-effort. 응답을 지연시키지 않게 ctx.waitUntil 로 뒤에서 실행하고,
// DB/버킷 미설정이거나 실패해도 조용히 넘어간다 (관측 실패가 생성 자체를 막지 않는다).
function logEvent(env, ctx, ev) {
  if (!env.DB) return;
  const task = (async () => {
    try {
      const id = crypto.randomUUID();
      // 같은 세션의 기존 행 수 = 이번 시도의 수정 회차 (0 = 원본, 1+ = n번째 수정)
      let refineIndex = 0;
      if (ev.sessionId) {
        const row = await env.DB
          .prepare("SELECT COUNT(*) AS n FROM gen_events WHERE session_id = ?")
          .bind(ev.sessionId).first();
        refineIndex = row?.n ?? 0;
      }
      const b64ToBytes = (b64) => Uint8Array.from(atob(b64.includes(",") ? b64.split(",").at(-1) : b64), (c) => c.charCodeAt(0));
      // 결과 이미지는 R2 에만 (성공 시). gpt-image-2 는 마젠타(#FF00FF) 배경으로 오므로
      // 대시보드용으로 마젠타·투명 배경을 흰색으로 평탄화해 저장 (원본 픽셀은 클라가 따로 크로마키).
      let imageKey = null;
      if (ev.imageB64 && env.LOG_BUCKET) {
        imageKey = `results/${id}.png`;
        let bytes = b64ToBytes(ev.imageB64);
        try { bytes = flattenBackgroundToWhite(bytes); } catch { /* 실패 시 원본(마젠타) 그대로 저장 */ }
        await env.LOG_BUCKET.put(imageKey, bytes, { httpMetadata: { contentType: "image/png" } });
      }
      // 참고사진(첨부)도 R2 에 — refs/<id>.png. had_reference 로 존재 여부를 안다.
      if (ev.referenceB64 && env.LOG_BUCKET) {
        try {
          await env.LOG_BUCKET.put(`refs/${id}.png`, b64ToBytes(ev.referenceB64), { httpMetadata: { contentType: "image/png" } });
        } catch { /* 참고사진 저장 실패는 무시 */ }
      }
      await env.DB.prepare(
        `INSERT INTO gen_events
           (id, at, sub, session_id, refine_index, type, state, art_style, model, platform,
            prompt, revised_prompt, had_reference, status, error, latency_ms, image_key,
            user_input, input_field)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      ).bind(
        id, Date.now(), ev.sub ?? null, ev.sessionId ?? null, refineIndex,
        ev.type, ev.state ?? null, ev.artStyle ?? null, ev.model ?? null, ev.platform ?? null,
        ev.prompt ?? null, ev.revisedPrompt ?? null, ev.hadReference ? 1 : 0,
        ev.status, ev.error ?? null, ev.latencyMs ?? null, imageKey,
        ev.userInput ?? null, ev.inputField ?? null
      ).run();
    } catch (e) {
      console.log("logEvent failed:", e?.message);
    }
  })();
  if (ctx && ctx.waitUntil) ctx.waitUntil(task); else task.catch(() => {});
}

// 관리자 토큰 확인 — ?token= 또는 Authorization: Bearer. 통과면 null, 아니면 에러 Response.
function adminGate(request, env) {
  if (!env.ADMIN_TOKEN) {
    return new Response("ADMIN_TOKEN 미설정 — 대시보드가 비활성화됨.", { status: 503 });
  }
  const url = new URL(request.url);
  const token = url.searchParams.get("token")
    || (request.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (token !== env.ADMIN_TOKEN) {
    return new Response("Unauthorized", { status: 401 });
  }
  return null;
}

// GET /admin/img/<eventId>  — R2 에서 결과 이미지 스트리밍 (토큰 게이트)
async function adminImage(request, env, rawId) {
  const gate = adminGate(request, env);
  if (gate) return gate;
  const id = (rawId || "").replace(/\.png$/i, "").replace(/[^a-f0-9-]/gi, "");
  if (!id || !env.LOG_BUCKET) return new Response("Not found", { status: 404 });
  const prefix = new URL(request.url).searchParams.get("kind") === "ref" ? "refs" : "results";
  const obj = await env.LOG_BUCKET.get(`${prefix}/${id}.png`);
  if (!obj) return new Response("Not found", { status: 404 });
  return new Response(obj.body, {
    headers: { "Content-Type": "image/png", "Cache-Control": "private, max-age=86400" },
  });
}

function esc(s) {
  return String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

// GET /admin  — 생성 로그 대시보드. 세션(수정 체인)별로 묶어서 보여준다.
async function adminDashboard(request, env) {
  const gate = adminGate(request, env);
  if (gate) return gate;
  if (!env.DB) return new Response("DB 미설정", { status: 503 });

  const url = new URL(request.url);
  const token = url.searchParams.get("token") || "";
  const days = Math.max(1, Math.min(90, parseInt(url.searchParams.get("days") || "7", 10) || 7));
  const fType = url.searchParams.get("type") || "";
  const fStatus = url.searchParams.get("status") || "";
  const fPlatform = url.searchParams.get("platform") || "";
  const group = url.searchParams.get("group") === "user" ? "user" : "session";
  const since = Date.now() - days * 24 * 60 * 60 * 1000;

  const where = ["at >= ?"];
  const binds = [since];
  if (fType) { where.push("type = ?"); binds.push(fType); }
  if (fStatus) { where.push("status = ?"); binds.push(fStatus); }
  if (fPlatform) { where.push("platform = ?"); binds.push(fPlatform); }

  const { results = [] } = await env.DB.prepare(
    `SELECT * FROM gen_events WHERE ${where.join(" AND ")} ORDER BY at DESC LIMIT 3000`
  ).bind(...binds).all();

  // 세션으로 그룹핑 (session_id 없는 행은 자기 id 로 단독 세션)
  const groups = new Map();
  for (const r of results) {
    const key = r.session_id || `solo:${r.id}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(r);
  }
  const sessions = [...groups.values()].map((rows) => {
    rows.sort((a, b) => (a.refine_index - b.refine_index) || (a.at - b.at));
    return rows;
  });
  sessions.sort((a, b) => Math.max(...b.map((r) => r.at)) - Math.max(...a.map((r) => r.at)));

  // 요약 집계
  const total = results.length;
  const ok = results.filter((r) => r.status === "ok").length;
  const errored = results.filter((r) => r.status === "error").length;
  const blocked = results.filter((r) => r.status === "blocked").length;
  const edits = sessions.reduce((n, s) => n + Math.max(0, s.length - 1), 0);
  const avgEdits = sessions.length ? (edits / sessions.length).toFixed(2) : "0";
  const stateCounts = {};
  for (const r of results) { const k = r.state || "—"; stateCounts[k] = (stateCounts[k] || 0) + 1; }
  const topStates = Object.entries(stateCounts).sort((a, b) => b[1] - a[1]).slice(0, 12);

  const q = (extra) => {
    const p = new URLSearchParams({ token, days: String(days) });
    if (fType) p.set("type", fType);
    if (fStatus) p.set("status", fStatus);
    if (fPlatform) p.set("platform", fPlatform);
    if (group !== "session") p.set("group", group);
    for (const [k, v] of Object.entries(extra)) { if (v) p.set(k, v); else p.delete(k); }
    return "/admin?" + p.toString();
  };
  const fmtTime = (ms) => new Date(ms).toISOString().slice(0, 16).replace("T", " ");

  const typeBadge = { single: "🆕 단건", refine: "✏️ 다듬기", batch: "📦 배치", background: "🌤 배경" };
  const statusDot = { ok: "🟢", error: "🔴", blocked: "🟠" };

  // 한 스텝(생성 1건) — 왼쪽 썸네일 · 가운데 전송 프롬프트 전체 · 오른쪽 사용자 실제 입력만.
  const renderStep = (r) => {
    const img = r.image_key
      ? `<a href="/admin/img/${esc(r.id)}?token=${esc(token)}" target="_blank"><img loading="lazy" src="/admin/img/${esc(r.id)}?token=${esc(token)}"></a>`
      : `<div class="noimg">${esc(statusDot[r.status] || "")} ${esc(r.status)}</div>`;
    // 참고사진 썸네일 — 저장 전 기록은 404 → onerror 로 조용히 숨김.
    const refImg = r.had_reference
      ? `<a href="/admin/img/${esc(r.id)}?kind=ref&token=${esc(token)}" target="_blank"><img class="refimg" loading="lazy" src="/admin/img/${esc(r.id)}?kind=ref&token=${esc(token)}" title="첨부한 참고사진" onerror="this.closest('a').style.display='none'"></a>`
      : "";
    const err = r.status !== "ok" ? `<div class="err">${esc(statusDot[r.status])} ${esc(r.error || r.status)}</div>` : "";
    const refFlag = r.had_reference ? ' <span class="ref">📎참고</span>' : "";
    const lat = r.latency_ms ? `<span class="lat">${(r.latency_ms / 1000).toFixed(1)}s</span>` : "";
    // 오른쪽: 사용자가 실제 입력한 것만. 없으면(구 기록/자동 프레임) 안내.
    const userField = r.input_field ? `<span class="field">${esc(r.input_field)}</span>` : "";
    const userText = r.user_input != null && r.user_input !== ""
      ? `<div class="uitext">${esc(r.user_input)}</div>`
      : `<div class="uitext none">${r.user_input === "" ? "(입력 없음 · 상태만 선택)" : "(원본 입력 기록 없음)"}</div>`;
    return `<div class="step">
      <div class="thumbs">${img}${refImg}</div>
      <div class="full">
        <div class="stepno">${r.refine_index === 0 ? "원본" : "수정 " + r.refine_index}${refFlag} ${lat}</div>
        <div class="prompt">${esc(r.prompt || "")}</div>
        ${err}
      </div>
      <div class="userin">
        <div class="uihead">✍️ 사용자 입력 ${userField}</div>
        ${userText}
      </div>
    </div>`;
  };

  // 한 세션(캐릭터=수정 체인) 카드.
  const renderSession = (rows) => {
    const head = rows[0];
    const latest = Math.max(...rows.map((r) => r.at));
    const editCount = Math.max(0, rows.length - 1);
    return `<div class="card">
      <div class="chead">
        <span class="state">${esc(head.state || "—")}</span>
        <span class="pill">${typeBadge[head.type] || esc(head.type)}</span>
        ${editCount > 0 ? `<span class="pill edits">✏️ ${editCount}번 수정</span>` : ""}
        <span class="plat">${esc(head.platform || "?")}</span>
        <span class="time">${esc(fmtTime(latest))}</span>
        ${head.sub ? `<span class="sub" title="${esc(head.sub)}">👤 ${esc(String(head.sub).slice(0, 8))}</span>` : `<span class="sub anon">익명</span>`}
      </div>
      <div class="steps">${rows.map(renderStep).join("")}</div>
    </div>`;
  };

  let cards;
  if (group === "user") {
    // 사용자(sub)별로 세션을 묶는다. 로그인 전(sub=null)은 '익명' 한 묶음.
    const users = new Map();
    for (const rows of sessions) {
      const key = rows[0].sub || "__anon__";
      if (!users.has(key)) users.set(key, []);
      users.get(key).push(rows);
    }
    const userBlocks = [...users.entries()].map(([key, sess]) => {
      sess.sort((a, b) => Math.max(...b.map((r) => r.at)) - Math.max(...a.map((r) => r.at)));
      const evCount = sess.reduce((n, s) => n + s.length, 0);
      const editCount = sess.reduce((n, s) => n + Math.max(0, s.length - 1), 0);
      const latest = Math.max(...sess.flatMap((s) => s.map((r) => r.at)));
      const who = key === "__anon__" ? "익명 (로그인 전)" : `👤 ${esc(key)}`;
      return { latest, sess, evCount, editCount, who };
    });
    userBlocks.sort((a, b) => b.latest - a.latest);
    // 사용자마다 접었다 펴는 토글(<details>). 가장 최근 사용자 하나만 기본 펼침.
    cards = userBlocks.map((u, idx) => `<details class="userblock"${idx === 0 ? " open" : ""}>
        <summary class="uhead">
          <span class="caret"></span>
          <span class="uname">${u.who}</span>
          <span class="ucount">캐릭터 ${u.sess.length} · 생성 ${u.evCount} · 수정 ${u.editCount}</span>
          <span class="time">${esc(fmtTime(u.latest))}</span>
        </summary>
        ${u.sess.map(renderSession).join("")}
      </details>`).join("");
  } else {
    cards = sessions.map(renderSession).join("");
  }

  const chip = (label, params, active) =>
    `<a class="chip${active ? " on" : ""}" href="${q(params)}">${esc(label)}</a>`;

  const html = `<!doctype html><html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>withu 생성 로그</title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body { font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 0; background: #f5f5f7; color: #1d1d1f; }
  @media (prefers-color-scheme: dark) { body { background: #000; color: #f5f5f7; } .card, .summary { background: #1c1c1e !important; } .chip { background: #2c2c2e !important; color: #f5f5f7 !important; } }
  header { padding: 16px 20px; position: sticky; top: 0; background: inherit; border-bottom: 1px solid rgba(128,128,128,.2); z-index: 10; }
  h1 { font-size: 18px; margin: 0 0 10px; }
  .filters { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; }
  .chip { text-decoration: none; padding: 4px 10px; border-radius: 999px; background: #e8e8ed; color: #1d1d1f; font-size: 12px; }
  .chip.on { background: #0071e3; color: #fff; }
  .sep { width: 1px; height: 18px; background: rgba(128,128,128,.3); margin: 0 4px; }
  main { padding: 16px 20px; max-width: 1100px; margin: 0 auto; }
  .summary { background: #fff; border-radius: 12px; padding: 14px 16px; margin-bottom: 16px; display: flex; flex-wrap: wrap; gap: 20px; }
  .metric b { font-size: 22px; display: block; }
  .metric span { font-size: 12px; opacity: .6; }
  .states { font-size: 12px; opacity: .8; display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
  .card { background: #fff; border-radius: 12px; padding: 12px 14px; margin-bottom: 12px; box-shadow: 0 1px 3px rgba(0,0,0,.06); }
  .chead { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; margin-bottom: 10px; }
  .state { font-weight: 600; }
  .pill { font-size: 12px; padding: 2px 8px; border-radius: 6px; background: rgba(128,128,128,.15); }
  .pill.edits { background: #ffcc0033; color: #a06a00; }
  .plat { font-size: 12px; opacity: .6; }
  .time { font-size: 12px; opacity: .5; margin-left: auto; }
  .sub { font-size: 11px; opacity: .6; } .sub.anon { opacity: .4; }
  .steps { display: flex; flex-direction: column; gap: 10px; }
  .step { display: flex; gap: 12px; align-items: stretch; border-top: 1px solid rgba(128,128,128,.12); padding-top: 10px; }
  .step:first-child { border-top: 0; padding-top: 0; }
  .thumbs { flex: 0 0 auto; display: flex; gap: 6px; align-items: flex-start; }
  .step img { width: 120px; height: 120px; object-fit: contain; border-radius: 8px; border: 1px solid rgba(128,128,128,.18); background: #fafafa; }
  .refimg { width: 44px !important; height: 44px !important; object-fit: cover; border: 1px solid rgba(128,128,128,.3); }
  .noimg { width: 120px; height: 120px; display: flex; align-items: center; justify-content: center; border-radius: 8px; background: rgba(128,128,128,.1); font-size: 12px; opacity: .7; }
  .full { flex: 1 1 auto; min-width: 0; }
  .stepno { font-size: 11px; opacity: .6; margin-bottom: 4px; }
  /* 가운데: 서버가 실제 보낸 전송 프롬프트 전체 */
  .prompt { font-size: 12px; white-space: pre-wrap; word-break: break-word; opacity: .82; }
  /* 오른쪽: 사용자가 실제 입력한 것만 */
  .userin { flex: 0 0 240px; background: rgba(0,113,227,.06); border-radius: 8px; padding: 8px 10px; }
  .uihead { font-size: 11px; opacity: .7; margin-bottom: 4px; }
  .uitext { font-size: 13px; font-weight: 600; white-space: pre-wrap; word-break: break-word; }
  .uitext.none { font-weight: 400; opacity: .45; font-size: 12px; }
  .field { display: inline-block; font-size: 10px; padding: 1px 5px; border-radius: 4px; background: rgba(0,113,227,.18); color: #0071e3; }
  .err { font-size: 11px; color: #d33; margin-top: 4px; }
  .ref { font-size: 10px; opacity: .7; } .lat { font-size: 10px; opacity: .5; }
  .userblock { margin-bottom: 14px; }
  summary.uhead { display: flex; align-items: center; gap: 10px; padding: 8px 4px; border-bottom: 2px solid rgba(0,113,227,.3); margin-bottom: 8px; cursor: pointer; list-style: none; user-select: none; }
  summary.uhead::-webkit-details-marker { display: none; }
  summary.uhead:hover { background: rgba(0,113,227,.05); }
  .caret { flex: 0 0 auto; width: 0; height: 0; border-left: 6px solid currentColor; border-top: 5px solid transparent; border-bottom: 5px solid transparent; opacity: .45; transition: transform .12s; }
  details[open] > summary.uhead .caret { transform: rotate(90deg); }
  .uname { font-weight: 700; font-size: 15px; word-break: break-all; }
  .ucount { font-size: 12px; opacity: .6; }
  .empty { text-align: center; opacity: .5; padding: 60px; }
  @media (max-width: 720px) { .step { flex-wrap: wrap; } .userin { flex-basis: 100%; } }
</style></head><body>
<header>
  <h1>withu 생성 로그 <span style="opacity:.5;font-weight:400">· 최근 ${days}일</span></h1>
  <div class="filters">
    ${chip("1일", { days: "1" }, days === 1)}${chip("7일", { days: "7" }, days === 7)}${chip("30일", { days: "30" }, days === 30)}
    <span class="sep"></span>
    ${chip("전체", { type: "", status: "" }, !fType && !fStatus)}${chip("단건", { type: "single" }, fType === "single")}${chip("다듬기", { type: "refine" }, fType === "refine")}${chip("배치", { type: "batch" }, fType === "batch")}
    <span class="sep"></span>
    ${chip("성공", { status: "ok" }, fStatus === "ok")}${chip("실패", { status: "error" }, fStatus === "error")}${chip("차단", { status: "blocked" }, fStatus === "blocked")}
    <span class="sep"></span>
    ${chip("iOS", { platform: "ios" }, fPlatform === "ios")}${chip("Android", { platform: "android" }, fPlatform === "android")}
    <span class="sep"></span>
    ${chip("세션별", { group: "" }, group === "session")}${chip("사용자별", { group: "user" }, group === "user")}
  </div>
</header>
<main>
  <div class="summary">
    <div class="metric"><b>${total}</b><span>총 생성</span></div>
    <div class="metric"><b>${sessions.length}</b><span>캐릭터(세션)</span></div>
    <div class="metric"><b>${avgEdits}</b><span>평균 수정 횟수</span></div>
    <div class="metric"><b>${ok}</b><span>성공</span></div>
    <div class="metric"><b>${errored}</b><span>실패</span></div>
    <div class="metric"><b>${blocked}</b><span>차단</span></div>
    <div class="states">${topStates.map(([s, n]) => `<span>${esc(s)} <b>${n}</b></span>`).join("")}</div>
  </div>
  ${sessions.length ? cards : `<div class="empty">이 기간에 생성 기록이 없어요.</div>`}
</main>
</body></html>`;

  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
}
