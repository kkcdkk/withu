package com.seoyoung.withu.net

import com.seoyoung.withu.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.UUID
import java.util.concurrent.TimeUnit

/**
 * withu API 클라이언트 — iOS APIClient.swift 포팅.
 * 같은 Cloudflare Worker (/generate, /health) 를 사용. 서버는 snake_case.
 * 이미지 생성이 low 기준 20~40초 — read timeout 을 넉넉히 잡는다.
 */
object ApiClient {
    private const val BASE_URL = "https://withu-api.ysy1398.workers.dev"

    private val json = Json { ignoreUnknownKeys = true }

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.MINUTES)   // iOS timeout=1800 과 동일 정책
        .build()

    @Serializable
    data class GenerateImageRequest(
        val prompt: String,
        @SerialName("reference_image_base64") val referenceImageBase64: String? = null,
        val steps: Int = 30,
        val width: Int = 1024,
        val height: Int = 1024,
        val quality: String = "low",
        @SerialName("art_style") val artStyle: String = "casual",
        val style: String = "auto",
        val kind: String? = null,
        // gpt-image-2: 서버가 마젠타 배경 지시 → 클라 크로마키 (iOS 와 동일 파이프라인)
        val model: String = "gpt-image-2",
    )

    @Serializable
    data class GenerateImageResponse(
        @SerialName("image_base64") val imageBase64: String,
        val seed: Int = 0,
        @SerialName("revised_prompt") val revisedPrompt: String? = null,
        @SerialName("free_consumed") val freeConsumed: Boolean? = null,
    )

    class ApiException(val status: Int, message: String) : Exception(message)

    suspend fun generateImage(req: GenerateImageRequest): GenerateImageResponse =
        withContext(Dispatchers.IO) {
            val body = json.encodeToString(GenerateImageRequest.serializer(), req)
                .toRequestBody("application/json".toMediaType())
            val request = Request.Builder()
                .url("$BASE_URL/generate")
                .post(body)
                .header("X-Withu-Token", BuildConfig.WITHU_API_TOKEN)
                .header("X-Withu-Kind", "single")
                .header("Idempotency-Key", UUID.randomUUID().toString())
                .build()
            client.newCall(request).execute().use { resp ->
                val text = resp.body?.string() ?: ""
                if (!resp.isSuccessful) throw ApiException(resp.code, text.take(300))
                json.decodeFromString(GenerateImageResponse.serializer(), text)
            }
        }

    suspend fun health(): Boolean = withContext(Dispatchers.IO) {
        runCatching {
            val request = Request.Builder().url("$BASE_URL/health").build()
            client.newCall(request).execute().use { it.isSuccessful }
        }.getOrDefault(false)
    }
}
