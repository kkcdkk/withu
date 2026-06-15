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

/// 생성 1회 차감 (서버 권위). 우선순위:
///   single: free_single → 구독 → credits
///   batch:  같은 batch_id 세션이면 무료, 아니면 free_batch → 구독 → credits
/// idempotencyKey 로 재시도 이중차감 방지. 잔액 없으면 402.
/// 반환: { ok, chargedFrom?, status?, balance? }
export async function chargeGeneration(env, sub, kind, batchId, idemKey) {
  if (!env.DB) return { ok: true, chargedFrom: null };   // DB 없으면 차감 생략(개발)
  const now = Math.floor(Date.now() / 1000);

  // 멱등성 — 이미 처리된 키면 재차감 안 함
  const existing = await env.DB
    .prepare("SELECT charged_from FROM generation_log WHERE id = ?")
    .bind(idemKey).first();
  if (existing) return { ok: true, chargedFrom: existing.charged_from };

  const ent = await env.DB
    .prepare("SELECT free_batch_remaining, free_single_remaining, credits, sub_active FROM entitlements WHERE sub = ?")
    .bind(sub).first();
  if (!ent) return { ok: false, status: 404 };

  let chargedFrom = null;

  // 일괄 세션 무료 — 같은 batch_id 가 이미 free_batch 로 시작됐으면 그 세션은 전부 무료
  if (kind === "batch" && batchId) {
    const sessionFree = await env.DB
      .prepare("SELECT 1 FROM generation_log WHERE batch_id = ? AND charged_from = 'free_batch' LIMIT 1")
      .bind(batchId).first();
    if (sessionFree) chargedFrom = "free_batch_session";
  }

  if (!chargedFrom) {
    if (kind === "batch" && ent.free_batch_remaining > 0) {
      const r = await env.DB.prepare(
        "UPDATE entitlements SET free_batch_remaining = free_batch_remaining - 1, updated_at = ? WHERE sub = ? AND free_batch_remaining > 0"
      ).bind(now, sub).run();
      if (r.meta.changes > 0) chargedFrom = "free_batch";
    } else if (kind === "single" && ent.free_single_remaining > 0) {
      const r = await env.DB.prepare(
        "UPDATE entitlements SET free_single_remaining = free_single_remaining - 1, updated_at = ? WHERE sub = ? AND free_single_remaining > 0"
      ).bind(now, sub).run();
      if (r.meta.changes > 0) chargedFrom = "free_single";
    }
    // 무료 소진 → 구독 → 크레딧
    if (!chargedFrom && ent.sub_active === 1) {
      chargedFrom = "subscription";   // 구독은 잔액 무차감(일일상한은 추후)
    }
    if (!chargedFrom && ent.credits > 0) {
      const r = await env.DB.prepare(
        "UPDATE entitlements SET credits = credits - 1, updated_at = ? WHERE sub = ? AND credits > 0"
      ).bind(now, sub).run();
      if (r.meta.changes > 0) chargedFrom = "credits";
    }
  }

  if (!chargedFrom) {
    return { ok: false, status: 402, balance: await getEntitlement(env, sub) };
  }

  await env.DB.prepare(
    "INSERT INTO generation_log (id, sub, kind, charged_from, batch_id, at) VALUES (?, ?, ?, ?, ?, ?)"
  ).bind(idemKey, sub, kind, chargedFrom, batchId || null, now).run();

  return { ok: true, chargedFrom };
}

/// OpenAI 호출 실패 시 차감 되돌림.
export async function refundGeneration(env, sub, chargedFrom, idemKey) {
  if (!env.DB || !chargedFrom) return;
  await env.DB.prepare("DELETE FROM generation_log WHERE id = ?").bind(idemKey).run();
  const col = chargedFrom === "free_batch" ? "free_batch_remaining"
    : chargedFrom === "free_single" ? "free_single_remaining"
    : chargedFrom === "credits" ? "credits"
    : null;
  if (col) {
    await env.DB.prepare(
      `UPDATE entitlements SET ${col} = ${col} + 1 WHERE sub = ?`
    ).bind(sub).run();
  }
  // subscription / free_batch_session 은 무차감이라 복원 불필요
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
