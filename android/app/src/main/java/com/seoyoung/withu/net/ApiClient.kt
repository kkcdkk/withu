package com.seoyoung.withu.net

import com.seoyoung.withu.BuildConfig
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.UUID
import java.util.concurrent.TimeUnit

/**
 * withu API 클라이언트 — iOS APIClient.swift 포팅 (스펙 11).
 * 같은 Cloudflare Worker 사용. 인증은 X-Withu-Token 경로만 (로그인은 SCOPE 제외 — Bearer 미전송).
 * 이미지 생성이 medium 1–3분/high 2–5분 — read timeout 30분/전체 60분.
 * 짧게 줄이면 진행 중 생성이 잘못된 "offline" 으로 죽는다 (iOS 교훈).
 */
object ApiClient {
    private const val BASE_URL = "https://withu-api.ysy1398.workers.dev"

    /** preflight 재시도 — iOS APIClient.preflight 와 동일 (2회 시도 · 0.7초 간격). */
    private const val PREFLIGHT_ATTEMPTS = 2
    private const val PREFLIGHT_RETRY_DELAY_MS = 700L

    // encodeDefaults: steps/width/height/quality/style/model 기본값도 서버로 전송 (iOS 파리티).
    // explicitNulls=false: null 필드는 본문에서 생략 (iOS JSONEncoder 의 nil 생략과 동일).
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true; explicitNulls = false }

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.MINUTES)     // iOS timeout=1800
        .callTimeout(60, TimeUnit.MINUTES)     // iOS resourceTimeout=3600
        .build()

    /**
     * preflight 전용 8초 클라이언트 — 본 세션은 30분 timeout 이라 연결이 끊겼을 때
     * 한참 매달림. generate 직전 이걸로 즉시 실패 판정 (iOS ephemeral 세션 대응).
     * 5초는 화면 재진입 직후 등 일시적 지연에서 오탐이 나서 8초로 완화 (iOS 파리티).
     */
    private val preflightClient = client.newBuilder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(8, TimeUnit.SECONDS)
        .callTimeout(8, TimeUnit.SECONDS)
        .build()

    private val jsonMediaType = "application/json".toMediaType()

    /**
     * 이미지 생성. 402 → ApiError.PaymentRequired 로 분류.
     * @param kind X-Withu-Kind — "single"|"batch" (서버 무료 버킷 구분)
     * @param batchId X-Withu-Batch — 일괄 세션 묶음 (배치일 때만)
     * @param idempotencyKey 재시도 이중차감 방지 — 배치는 job.id 고정 전달
     */
    suspend fun generateImage(
        req: GenerateImageRequest,
        kind: String = "single",
        batchId: String? = null,
        sessionId: String? = null,
        state: String? = null,
        idempotencyKey: String = UUID.randomUUID().toString(),
    ): GenerateImageResponse = withContext(Dispatchers.IO) {
        val body = json.encodeToString(GenerateImageRequest.serializer(), req)
            .toRequestBody(jsonMediaType)
        val builder = Request.Builder()
            .url("$BASE_URL/generate")
            .post(body)
            .header("Content-Type", "application/json")
            .header("Idempotency-Key", idempotencyKey)
            .header("X-Withu-Kind", kind)
            // 생성 모니터링 메타 (서버 gen_events 로깅용 — 수정 체인/상태/플랫폼)
            .header("X-Withu-Platform", "android")
        val token = BuildConfig.WITHU_API_TOKEN
        if (token.isNotEmpty()) builder.header("X-Withu-Token", token)
        if (batchId != null) builder.header("X-Withu-Batch", batchId)
        if (sessionId != null) builder.header("X-Withu-Session", sessionId)
        if (state != null) builder.header("X-Withu-State", state)

        try {
            client.newCall(builder.build()).execute().use { resp ->
                val text = resp.body?.string() ?: ""
                // 402 — 무료/크레딧 소진
                if (resp.code == 402) {
                    val balance = runCatching {
                        json.decodeFromString<PaymentRequiredResponse>(text)
                    }.getOrNull()?.balance
                    throw ApiError.PaymentRequired(balance)
                }
                if (!resp.isSuccessful) {
                    throw ApiError.Server(resp.code, detailOf(text))
                }
                try {
                    json.decodeFromString<GenerateImageResponse>(text)
                } catch (e: Exception) {
                    throw ApiError.Decoding(e.message ?: "unknown")
                }
            }
        } catch (e: ApiError) {
            throw e   // ApiError 는 그대로 재던지기 — Transport 로 이중 래핑 금지 (스펙 11 §4.1)
        } catch (e: Exception) {
            throw ApiError.Transport(e)
        }
    }

    /**
     * 빠른 reachability 체크 — /health, 8초 × 2회 (실패 후 0.7초 대기). 2xx 아니면 ApiError throw.
     * 1회 시도는 화면 재진입 직후의 일시적 실패에서 "연결이 어려워요" 오탐이 났다 (iOS 파리티).
     */
    suspend fun preflightPing(): Unit = withContext(Dispatchers.IO) {
        var last: Exception = ApiError.InvalidResponse()
        repeat(PREFLIGHT_ATTEMPTS) { attempt ->
            try {
                val req = Request.Builder().url("$BASE_URL/health").build()
                preflightClient.newCall(req).execute().use { resp ->
                    if (!resp.isSuccessful) throw ApiError.InvalidResponse()
                }
                return@withContext
            } catch (e: CancellationException) {
                throw e   // 취소는 재시도 대상이 아니다 — 호출부가 취소를 따로 처리한다
            } catch (e: Exception) {
                last = e
                if (attempt < PREFLIGHT_ATTEMPTS - 1) delay(PREFLIGHT_RETRY_DELAY_MS)
            }
        }
        throw if (last is ApiError) last else ApiError.Transport(last)
    }

    /** /health — 기본 세션으로 Bool 반환 (실패는 false). */
    suspend fun health(): Boolean = withContext(Dispatchers.IO) {
        runCatching {
            val req = Request.Builder().url("$BASE_URL/health").build()
            client.newCall(req).execute().use { it.isSuccessful }
        }.getOrDefault(false)
    }

    /**
     * Google 로그인 핸드셰이크 — POST /auth/google { id_token } → 세션 토큰 + entitlement.
     * (iOS /auth/apple 대응. 서버가 계정 키를 "google:<sub>" 로 네임스페이스.)
     */
    suspend fun authGoogle(idToken: String): AuthResponse = withContext(Dispatchers.IO) {
        val bodyJson = json.encodeToString(AuthGoogleRequest.serializer(), AuthGoogleRequest(idToken))
        try {
            val req = Request.Builder()
                .url("$BASE_URL/auth/google")
                .post(bodyJson.toRequestBody(jsonMediaType))
                .header("Content-Type", "application/json")
                .build()
            client.newCall(req).execute().use { resp ->
                val text = resp.body?.string() ?: ""
                if (!resp.isSuccessful) throw ApiError.Server(resp.code, detailOf(text))
                try {
                    json.decodeFromString<AuthResponse>(text)
                } catch (e: Exception) {
                    throw ApiError.Decoding(e.message ?: "unknown")
                }
            }
        } catch (e: ApiError) {
            throw e
        } catch (e: Exception) {
            throw ApiError.Transport(e)
        }
    }

    /**
     * 할인코드 적용 — POST /redeem.
     * 로그인 제외 범위라 서버가 401 을 줄 수 있음 — 에러는 그대로 throw (caller 가 koreanized).
     */
    suspend fun redeem(code: String): Entitlement =
        postCode("/redeem", json.encodeToString(RedeemRequest.serializer(), RedeemRequest(code)))

    /** 친구 초대 코드 적용 — POST /referral/apply. */
    suspend fun applyReferral(code: String): Entitlement =
        postCode("/referral/apply", json.encodeToString(ReferralRequest.serializer(), ReferralRequest(code)))

    private suspend fun postCode(path: String, bodyJson: String): Entitlement =
        withContext(Dispatchers.IO) {
            try {
                val req = Request.Builder()
                    .url("$BASE_URL$path")
                    .post(bodyJson.toRequestBody(jsonMediaType))
                    .header("Content-Type", "application/json")
                    .build()
                client.newCall(req).execute().use { resp ->
                    val text = resp.body?.string() ?: ""
                    if (!resp.isSuccessful) {
                        throw ApiError.Server(resp.code, detailOf(text))
                    }
                    try {
                        json.decodeFromString<MeResponse>(text).entitlement
                    } catch (e: Exception) {
                        throw ApiError.Decoding(e.message ?: "unknown")
                    }
                }
            } catch (e: ApiError) {
                throw e
            } catch (e: Exception) {
                throw ApiError.Transport(e)
            }
        }

    /** 비 2xx 본문 → detail 필드 우선, 실패 시 raw body (앞부분만). */
    private fun detailOf(text: String): String =
        runCatching { json.decodeFromString<ApiErrorDetail>(text).detail }
            .getOrElse { text.take(300) }
}
