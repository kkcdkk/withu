// withu Phase 1 — 인증 모듈 (외부 의존성 0, WebCrypto 만)
//
// 토큰 2종 (절대 혼용 금지):
//   (A) Apple identityToken — Apple 서명 RS256 JWT. 로그인 시 1회만 검증.
//   (B) sessionToken        — withu 자체 HS256 JWT. 매 API 호출 인증용.

const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";
const APPLE_ISSUER = "https://appleid.apple.com";

// ---- base64url ----

function b64urlToBytes(s) {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  const bin = atob(s);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function bytesToB64url(bytes) {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64urlToString(s) {
  return new TextDecoder().decode(b64urlToBytes(s));
}

function jsonToB64url(obj) {
  return bytesToB64url(new TextEncoder().encode(JSON.stringify(obj)));
}

// ---- Apple identityToken 검증 ----

// JWKS 를 KV(있으면) 로 24h 캐시. 없으면 매번 fetch.
async function fetchAppleKeys(env) {
  if (env.RATE_KV) {
    const cached = await env.RATE_KV.get("apple_jwks", "json");
    if (cached) return cached;
  }
  const res = await fetch(APPLE_JWKS_URL);
  if (!res.ok) throw new Error("Apple JWKS fetch 실패");
  const data = await res.json();
  if (env.RATE_KV) {
    await env.RATE_KV.put("apple_jwks", JSON.stringify(data), { expirationTtl: 60 * 60 * 24 });
  }
  return data;
}

/// identityToken(JWT) 을 검증하고 { sub, email } 반환. 실패 시 throw.
export async function verifyAppleIdentityToken(identityToken, env) {
  const parts = identityToken.split(".");
  if (parts.length !== 3) throw new Error("토큰 형식 오류");
  const header = JSON.parse(b64urlToString(parts[0]));
  const payload = JSON.parse(b64urlToString(parts[1]));

  // 1) claims 1차 검증
  const now = Math.floor(Date.now() / 1000);
  if (payload.iss !== APPLE_ISSUER) throw new Error("iss 불일치");
  const expectedAud = env.APPLE_BUNDLE_ID || "sy.withu";
  if (payload.aud !== expectedAud) throw new Error("aud 불일치");
  if (typeof payload.exp !== "number" || payload.exp < now) throw new Error("토큰 만료");
  if (!payload.sub) throw new Error("sub 없음");

  // 2) 서명 검증 — kid 매칭되는 Apple 공개키
  const jwks = await fetchAppleKeys(env);
  const jwk = (jwks.keys || []).find((k) => k.kid === header.kid && k.alg === "RS256");
  if (!jwk) throw new Error("서명 키 매칭 실패");

  const key = await crypto.subtle.importKey(
    "jwk",
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"]
  );
  const signingInput = new TextEncoder().encode(parts[0] + "." + parts[1]);
  const signature = b64urlToBytes(parts[2]);
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, signature, signingInput);
  if (!ok) throw new Error("서명 검증 실패");

  return { sub: payload.sub, email: payload.email || null };
}

// ---- sessionToken (withu 자체 HS256 JWT) ----

async function hmacKey(secret) {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"]
  );
}

/// sub 로 sessionToken 발급. 기본 60일.
export async function signSession(sub, env, ttlSeconds = 60 * 24 * 60 * 60) {
  if (!env.SESSION_SECRET) throw new Error("SESSION_SECRET 미설정");
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "HS256", typ: "JWT" };
  const payload = { iss: "withu-api", sub, iat: now, exp: now + ttlSeconds };
  const signingInput = jsonToB64url(header) + "." + jsonToB64url(payload);
  const key = await hmacKey(env.SESSION_SECRET);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signingInput));
  return signingInput + "." + bytesToB64url(new Uint8Array(sig));
}

/// sessionToken 검증 → sub 반환. 실패 시 null.
export async function verifySession(token, env) {
  if (!token || !env.SESSION_SECRET) return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const key = await hmacKey(env.SESSION_SECRET);
    const signingInput = new TextEncoder().encode(parts[0] + "." + parts[1]);
    const ok = await crypto.subtle.verify("HMAC", key, b64urlToBytes(parts[2]), signingInput);
    if (!ok) return null;
    const payload = JSON.parse(b64urlToString(parts[1]));
    const now = Math.floor(Date.now() / 1000);
    if (payload.iss !== "withu-api" || !payload.sub) return null;
    if (typeof payload.exp !== "number" || payload.exp < now) return null;
    return payload.sub;
  } catch {
    return null;
  }
}

/// Authorization: Bearer <token> 에서 sub 추출. 실패 시 null.
export async function subFromRequest(request, env) {
  const auth = request.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ")) return null;
  return verifySession(auth.slice(7), env);
}

/// 짧은 추천 코드 생성 (혼동 문자 제외).
export function makeReferralCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(6));
  let code = "";
  for (const b of bytes) code += alphabet[b % alphabet.length];
  return code;
}
