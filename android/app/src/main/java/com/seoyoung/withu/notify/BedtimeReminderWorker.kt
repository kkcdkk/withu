package com.seoyoung.withu.notify

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

/**
 * 취침 리마인더 Worker — 알림 발사 후 다음 날 같은 시각으로 자체 재예약.
 * PeriodicWorkRequest 는 정각 실행을 보장하지 못해(15분 flex) 매일 22:30 고정에는
 * initialDelay 재예약 방식이 더 정확하다.
 */
class BedtimeReminderWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        NotificationHelper.postBedtimeReminder()
        NotificationHelper.scheduleNextBedtime()
        return Result.success()
    }
}
