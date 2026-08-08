package com.seoyoung.withu.gen

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import com.seoyoung.withu.BuildConfig
import com.seoyoung.withu.net.ApiClient
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
 * 단건 생성 Worker — unique work "singlegen", 잡 1개(최대 2프레임)를 순차 실행.
 * `setForeground(dataSync)` 로 화면 이탈/화면 꺼짐/앱 전환에도 진행된다 — 생성이 1~3분이라
 * expedited 로는 부족하다 (iOS 는 `beginBackgroundTask(withName:expirationHandler:)` 로 버틴다).
 *
 * 배치 Worker(`bggen/GenBatchWorker`)와 같은 패턴이지만 **별도 unique work** 라
 * 배치 큐의 동작에는 영향을 주지 않는다.
 */
class GenSingleWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        // Android 12+ 백그라운드에서 FGS 시작이 거부될 수 있음 — 실패해도 Worker 는 계속.
        runCatching { setForeground(getForegroundInfo()) }
        try {
            if (!preflightOk()) {
                // 오프라인 — 30분 timeout 세션에 매달리지 않고 즉시 안내 (iOS preflightPing 동일).
                SingleGenQueue.failOffline()
            } else {
                while (true) {
                    val job = SingleGenQueue.nextQueuedAndMarkRunning() ?: break
                    runJob(job)
                }
            }
        } catch (e: CancellationException) {
            // 사용자 취소 → WorkManager 취소. 잡 정리는 SingleGenQueue.cancel() 이 이미 했다.
            throw e
        }
        SingleGenQueue.finishRun()
        return Result.success()
    }

    override suspend fun getForegroundInfo(): ForegroundInfo =
        NotificationHelper.singleGenProgressForegroundInfo(applicationContext)

    private suspend fun preflightOk(): Boolean = try {
        ApiClient.preflightPing()
        true
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        false
    }

    /** 한 프레임 실행 — body 파일 업로드 → process 콜백. */
    private suspend fun runJob(job: SingleGenJob) {
        val bodyFile = SingleGenQueue.bodyFileFor(job.id)
        if (!bodyFile.exists()) {
            SingleGenQueue.failMissingBody(job.id)
            return
        }
        val builder = Request.Builder()
            .url("$BASE_URL/generate")
            .post(bodyFile.asRequestBody(JSON_TYPE))
            .header("Content-Type", "application/json")
            .header("Idempotency-Key", job.idempotencyKey)   // 프레임별 고정 — 재전송 이중차감 방지
            .header("X-Withu-Kind", "single")
            // 생성 모니터링 메타 — 수정 체인(session)은 frame 0 만 (움직임 프레임은 수정 횟수 제외).
            .header("X-Withu-Platform", "android")
            .header("X-Withu-State", job.stateRaw)
        if (job.frame == 0) builder.header("X-Withu-Session", job.sessionId)
        val token = BuildConfig.WITHU_API_TOKEN
        if (token.isNotEmpty()) builder.header("X-Withu-Token", token)

        try {
            executeCall(builder.build()).use { resp ->
                val bytes = runCatching { resp.body?.bytes() }.getOrNull()
                SingleGenQueue.process(job.id, resp.code, bytes, null)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            SingleGenQueue.process(job.id, null, null, e)
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
