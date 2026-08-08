package com.seoyoung.withu.sync

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.seoyoung.withu.WithuApp
import com.seoyoung.withu.health.HealthManager
import com.seoyoung.withu.shared.AppPrefs
import com.seoyoung.withu.weather.WeatherManager
import java.util.concurrent.TimeUnit

/**
 * 주기 백그라운드 갱신 Worker (15분) — iOS BGAppRefreshTask 대응 (00-PLAN §4 Phase I-5).
 * 건강/날씨 신호를 새로고침한 뒤 SyncCoordinator.syncNow() 로 상태·스냅샷 저장 + 위젯 갱신.
 * 개별 매니저 실패는 무시(loadAll 계약) — syncNow 성공 시에만 lastBackgroundRefreshAt 기록.
 */
class BackgroundRefreshWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        return try {
            HealthManager.loadAll()
            runCatching { WeatherManager.refresh() }
            SyncCoordinator.syncNow()
            AppPrefs.lastBackgroundRefreshAt = System.currentTimeMillis()
            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }

    companion object {
        private const val WORK_NAME = "withu.periodicRefresh"

        /** WithuApp.onCreate 에서 1회 — 이미 예약돼 있으면 유지(KEEP). */
        fun schedule() {
            val request = PeriodicWorkRequestBuilder<BackgroundRefreshWorker>(
                15, TimeUnit.MINUTES,
            ).build()
            WorkManager.getInstance(WithuApp.context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
        }
    }
}
