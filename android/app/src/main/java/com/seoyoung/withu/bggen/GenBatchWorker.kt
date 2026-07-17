package com.seoyoung.withu.bggen

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import com.seoyoung.withu.BuildConfig
import com.seoyoung.withu.notify.NotificationHelper
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.Response
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * 배치 생성 Worker — unique work "bggen", 큐 전체를 순차(1개씩) 소비 (스펙 11 §6.2).
 * setForeground(dataSync) 로 화면 꺼짐/앱 전환에도 진행 — 생성이 잡당 1–5분이라
 * expedited 로는 부족 (iOS background URLSession 대응).
 * 재시도 정책은 큐 내부 재큐잉(attempts)으로 대체 — Result.retry() 사용 안 함.
 */
class GenBatchWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        // Android 12+ 백그라운드에서 FGS 시작이 거부될 수 있음 — 실패해도 Worker 는 계속.
        runCatching { setForeground(getForegroundInfo()) }
        try {
            while (true) {
                val job = BackgroundGenQueue.nextQueuedAndMarkRunning() ?: break
                runJob(job)
            }
        } catch (e: CancellationException) {
            // cancelAll() → WorkManager 취소. 잡 상태는 cancelAll 이 이미 failed 로 정리.
            throw e
        }
        BackgroundGenQueue.finishRun()
        return Result.success()
    }

    override suspend fun getForegroundInfo(): ForegroundInfo =
        NotificationHelper.genProgressForegroundInfo(applicationContext)

    /** 한 잡 실행 — body 파일 업로드 → process 콜백 (헤더는 스펙 11 §3.2). */
    private suspend fun runJob(job: BgGenJob) {
        val bodyFile = BackgroundGenQueue.bodyFileFor(job.id)
        if (!bodyFile.exists()) {
            BackgroundGenQueue.failMissingBody(job.id)
            return
        }
        val builder = Request.Builder()
            .url("$BASE_URL/generate")
            .post(bodyFile.asRequestBody(JSON_TYPE))
            .header("Content-Type", "application/json")
            .header("Idempotency-Key", job.id)          // 잡 id 고정 — 재전송 이중차감 방지
            .header("X-Withu-Kind", "batch")
            .header("X-Withu-Batch", job.batchId)
            // 생성 모니터링 메타 — 배치 항목은 서로 다른 상태(수정 체인 아님)라 세션은 안 붙인다.
            .header("X-Withu-Platform", "android")
            .header("X-Withu-State", job.stateRaw)
        val token = BuildConfig.WITHU_API_TOKEN
        if (token.isNotEmpty()) builder.header("X-Withu-Token", token)

        try {
            executeCall(builder.build()).use { resp ->
                val bytes = runCatching { resp.body?.bytes() }.getOrNull()
                BackgroundGenQueue.process(job.id, resp.code, bytes, null)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            BackgroundGenQueue.process(job.id, null, null, e)
        }
    }

    /** OkHttp enqueue 를 코루틴으로 — Worker 취소 시 진행 중 요청도 함께 취소. */
    private suspend fun executeCall(request: Request): Response =
        suspendCancellableCoroutine { cont ->
            val call = client.newCall(request)
            cont.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (cont.isActive) cont.resumeWithException(e)
                }

                override fun onResponse(call: Call, response: Response) {
                    if (cont.isActive) cont.resume(response) else response.close()
                }
            })
        }

    private companion object {
        const val BASE_URL = "https://withu-api.ysy1398.workers.dev"
        val JSON_TYPE = "application/json".toMediaType()

        // 이미지 생성 medium 1–3분/high 2–5분 — read 30분/전체 60분 (ApiClient 와 동일 정책).
        val client: OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.MINUTES)
            .callTimeout(60, TimeUnit.MINUTES)
            .build()
    }
}
