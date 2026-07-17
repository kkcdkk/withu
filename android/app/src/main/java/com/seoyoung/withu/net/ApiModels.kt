package com.seoyoung.withu.net

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * 서버 DTO — iOS APIModels.swift 포팅 (스펙 11 §3).
 * 서버는 snake_case ↔ 클라 camelCase — @SerialName 명시가 안전.
 */

@Serializable
data class GenerateImageRequest(
    val prompt: String,
    @SerialName("reference_image_base64") val referenceImageBase64: String? = null,
    val steps: Int = 30,
    val width: Int = 1024,
    val height: Int = 1024,
    val quality: String? = "low",              // "low" | "medium" | "high" | "auto"
    @SerialName("art_style") val artStyle: String? = null,   // "casual" | "pixel"
    val style: String? = "auto",               // legacy
    val kind: String? = null,                  // null|"character" → 서버 SYSTEM_PROMPT, "background" → raw
    // gpt-image-2 명시 시 마젠타 배경 → 클라 크로마키. null = gpt-image-1.5 (진짜 투명)
    val model: String? = "gpt-image-2",
)

@Serializable
data class GenerateImageResponse(
    @SerialName("image_base64") val imageBase64: String,
    val seed: Int = 0,
    @SerialName("revised_prompt") val revisedPrompt: String? = null,
    /** 차감 후 갱신 잔액 (로그인 시). Android 파리티 범위에선 파싱만. */
    val entitlement: Entitlement? = null,
    /** true 면 서버가 '계정 무료 1회' 소진 → 클라 캔디 미차감. */
    @SerialName("free_consumed") val freeConsumed: Boolean? = null,
)

@Serializable
data class Entitlement(
    @SerialName("free_batch_remaining") val freeBatchRemaining: Int = 0,
    @SerialName("free_single_remaining") val freeSingleRemaining: Int = 0,
    val credits: Int = 0,
    @SerialName("sub_active") val subActive: Boolean = false,
    @SerialName("sub_expires_at") val subExpiresAt: Long? = null,
    @SerialName("referral_code") val referralCode: String? = null,
)

@Serializable
data class RedeemRequest(val code: String)

@Serializable
data class ReferralRequest(val code: String)

/** /redeem·/referral/apply·/me·/iap/verify 공통 응답 래퍼. */
@Serializable
data class MeResponse(val entitlement: Entitlement)

/** 402 응답 본문 — balance 는 갱신된 잔액(있으면). */
@Serializable
data class PaymentRequiredResponse(
    val detail: String? = null,
    val balance: Entitlement? = null,
)

/** 비 2xx 공통 에러 본문. */
@Serializable
data class ApiErrorDetail(val detail: String)
