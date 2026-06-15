// withu Phase 1 — D1 헬퍼. env.DB 가 없으면(미설정) null 반환해 graceful.

import { makeReferralCode } from "./auth.js";

/// 신규면 계정 + 무료체험(일괄1/단건5) 시드, 기존이면 last_seen 갱신.
/// 무료는 INSERT 시에만 — 재설치해도 재시드 안 됨(평생 1회 보장).
export async function upsertAccount(env, sub, email) {
  if (!env.DB) return;
  const now = Math.floor(Date.now() / 1000);
  const existing = await env.DB.prepare("SELECT sub FROM accounts WHERE sub = ?").bind(sub).first();
  if (existing) {
    await env.DB.prepare("UPDATE accounts SET last_seen_at = ? WHERE sub = ?").bind(now, sub).run();
    return;
  }
  // 신규: 계정 + entitlement 시드 (추천 코드 충돌 시 재시도)
  let code = makeReferralCode();
  for (let i = 0; i < 5; i++) {
    const clash = await env.DB.prepare("SELECT 1 FROM accounts WHERE my_referral_code = ?").bind(code).first();
    if (!clash) break;
    code = makeReferralCode();
  }
  await env.DB.batch([
    env.DB.prepare(
      "INSERT INTO accounts (sub, email, my_referral_code, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?)"
    ).bind(sub, email, code, now, now),
    env.DB.prepare(
      "INSERT INTO entitlements (sub, free_batch_remaining, free_single_remaining, credits, sub_active, updated_at) VALUES (?, 1, 5, 0, 0, ?)"
    ).bind(sub, now),
  ]);
}

/// 사용자 권리 스냅샷 (앱이 캐시할 형태). 없으면 null.
export async function getEntitlement(env, sub) {
  if (!env.DB) return null;
  const ent = await env.DB.prepare(
    "SELECT free_batch_remaining, free_single_remaining, credits, sub_active, sub_expires_at FROM entitlements WHERE sub = ?"
  ).bind(sub).first();
  const acc = await env.DB.prepare("SELECT my_referral_code FROM accounts WHERE sub = ?").bind(sub).first();
  if (!ent) return null;
  // snake_case — 클라가 convertFromSnakeCase 로 디코드.
  return {
    free_batch_remaining: ent.free_batch_remaining,
    free_single_remaining: ent.free_single_remaining,
    credits: ent.credits,
    sub_active: ent.sub_active === 1,
    sub_expires_at: ent.sub_expires_at || null,
    referral_code: acc?.my_referral_code || null,
  };
}
