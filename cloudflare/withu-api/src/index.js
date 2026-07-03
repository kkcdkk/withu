import { verifyAppleIdentityToken, signSession, subFromRequest, verifyAppleJws } from "./auth.js";
import { upsertAccount, getEntitlement, chargeGeneration, refundGeneration, applyPurchase, redeemCode, applyReferral, deleteAccount } from "./db.js";

const OPENAI_IMAGE_MODEL = "gpt-image-1";

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

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

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

    if (url.pathname === "/generate") {
      if (request.method !== "POST") {
        return jsonError("Method not allowed", 405);
      }

      return generateImage(request, env);
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

async function generateImage(request, env) {
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

  // 입력 안전 가드 — 부적절한 프롬프트/참고사진은 차감·생성 전에 차단
  const safe = await checkPromptSafe(input.prompt, input.reference_image_base64, env);
  if (!safe.ok) return jsonError(safe.reason, safe.status);

  // 차감/게이트는 클라이언트(로컬 캔디)가 담당 — 서버는 생성만.
  // 비용 방어는 IP rate limit + OpenAI 월 한도. (서버-권위 차감은 로그인 강제 + 잔액 일원화 후 재도입.)

  let openAIResponse;
  try {
    openAIResponse = input.reference_image_base64
      ? await editImage(input, env)
      : await generateImageFromPrompt(input, env);
  } catch (error) {
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
    return jsonError(payload?.error?.message ?? text, openAIResponse.status);
  }

  const image = payload?.data?.[0];
  if (!image?.b64_json) {
    return jsonError("OpenAI response did not include image data.", 502);
  }

  return Response.json({
    image_base64: image.b64_json,
    seed: 0,
    revised_prompt: image.revised_prompt ?? null,
    entitlement: null
  });
}

/// kind 별 prompt 구성:
///   character (default): SYSTEM_PROMPT (style + content guardrails) + 사용자 prompt
///   background:          raw 사용자 prompt (풍경/하늘만, 캐릭터 가드레일 없음)
function buildFullPrompt(input) {
  if (input.kind === "background") {
    return input.prompt;
  }
  return systemPromptFor(input.art_style) + input.prompt;
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
      model: OPENAI_IMAGE_MODEL,
      prompt: buildFullPrompt(input),
      quality: normalizeQuality(input.quality),
      size: normalizeSize(input.width, input.height),
      // 캐릭터는 투명 배경. 날씨 배경(kind=background)은 풍경이라 불투명 유지.
      ...(input.kind === "background" ? {} : { background: "transparent" }),
      output_format: "png",
      n: 1
    })
  });
}

function editImage(input, env) {
  const form = new FormData();
  form.append("model", OPENAI_IMAGE_MODEL);
  form.append("prompt", buildFullPrompt(input));
  form.append("quality", normalizeQuality(input.quality));
  form.append("size", normalizeSize(input.width, input.height));
  form.append("background", "transparent");
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
