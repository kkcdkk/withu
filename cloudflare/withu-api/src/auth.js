// withu — 인증 모듈
//
// 토큰 2종 (절대 혼용 금지):
//   (A) Apple identityToken — Apple 서명 RS256 JWT. 로그인 시 1회만 검증.
//   (B) sessionToken        — withu 자체 HS256 JWT. 매 API 호출 인증용.
// + StoreKit2 JWS 트랜잭션 검증 (x5c 인증서 체인 → Apple Root CA G3).
//   대부분 WebCrypto. 인증서 체인 검증만 @peculiar/x509 사용.

import "reflect-metadata";
import * as x509 from "@peculiar/x509";

x509.cryptoProvider.set(crypto);

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

const APPLE_ROOT_CA_G3_URL = "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer";

/// Apple Root CA - G3 (신뢰 앵커) 로드. RATE_KV 있으면 30일 캐시(없으면 매번 fetch).
async function fetchAppleRootG3(env) {
  if (env.RATE_KV) {
    const cached = await env.RATE_KV.get("apple_root_g3", "arrayBuffer");
    if (cached) return new x509.X509Certificate(new Uint8Array(cached));
  }
  const res = await fetch(APPLE_ROOT_CA_G3_URL);
  if (!res.ok) throw new Error("Apple Root CA fetch 실패");
  const der = new Uint8Array(await res.arrayBuffer());
  if (env.RATE_KV) {
    await env.RATE_KV.put("apple_root_g3", der, { expirationTtl: 60 * 60 * 24 * 30 });
  }
  return new x509.X509Certificate(der);
}

/// 두 인증서의 DER 이 같은지 (상수시간 비교).
function certsEqual(a, b) {
  const x = new Uint8Array(a.rawData), y = new Uint8Array(b.rawData);
  if (x.length !== y.length) return false;
  let d = 0;
  for (let i = 0; i < x.length; i++) d |= x[i] ^ y[i];
  return d === 0;
}

/// StoreKit2 JWS 트랜잭션 검증 — ES256 서명 + x5c 인증서 체인을 Apple Root CA G3 까지.
/// 통과 시 payload(JSON) 반환, 실패 시 throw. (위조 영수증으로 크레딧 적립되는 것을 차단)
export async function verifyAppleJws(jws, env) {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("JWS 형식 오류");
  const header = JSON.parse(b64urlToString(parts[0]));
  if (header.alg !== "ES256") throw new Error("alg 불일치");
  const x5c = header.x5c;
  if (!Array.isArray(x5c) || x5c.length < 2) throw new Error("x5c 없음");

  const certs = x5c.map((b) => new x509.X509Certificate(b));   // base64 DER
  const now = new Date();
  for (const c of certs) {
    if (now < c.notBefore || now > c.notAfter) throw new Error("인증서 유효기간 벗어남");
  }
  // 인접 인증서 서명 검증 (leaf ← intermediate ← ...)
  for (let i = 0; i < certs.length - 1; i++) {
    const ok = await certs[i].verify({ publicKey: certs[i + 1].publicKey, signatureOnly: true });
    if (!ok) throw new Error("체인 서명 검증 실패");
  }
  // 신뢰 앵커 — 체인 최상단이 진짜 Apple Root CA G3 인지 (위조 self-signed 체인 차단)
  const trustedRoot = await fetchAppleRootG3(env);
  if (now < trustedRoot.notBefore || now > trustedRoot.notAfter) throw new Error("Apple root 유효기간 벗어남");
  const top = certs[certs.length - 1];
  if (!certsEqual(top, trustedRoot)) {
    const ok = await top.verify({ publicKey: trustedRoot.publicKey, signatureOnly: true });
    if (!ok) throw new Error("신뢰할 수 없는 root");
  }
  // JWS 서명 검증 — leaf 공개키로 header.payload
  const leafKey = await certs[0].publicKey.export();
  const sigOk = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    leafKey,
    b64urlToBytes(parts[2]),
    new TextEncoder().encode(parts[0] + "." + parts[1])
  );
  if (!sigOk) throw new Error("JWS 서명 검증 실패");

  return JSON.parse(b64urlToString(parts[1]));
}

/// 짧은 추천 코드 생성 (혼동 문자 제외).
export function makeReferralCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(6));
  let code = "";
  for (const b of bytes) code += alphabet[b % alphabet.length];
  return code;
}
