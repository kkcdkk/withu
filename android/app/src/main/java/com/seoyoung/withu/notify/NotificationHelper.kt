package com.seoyoung.withu.notify

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.seoyoung.withu.MainActivity
import com.seoyoung.withu.R
import com.seoyoung.withu.WithuApp
import com.seoyoung.withu.bggen.BgGenPhase
import com.seoyoung.withu.health.WorkoutSummary
import java.time.Duration
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.util.concurrent.TimeUnit

/**
 * 로컬 알림 헬퍼 — iOS NotificationManager.swift 포팅 (00-PLAN §2-9).
 * 채널 3종: reminder(취침 등) / gen_done(생성 완료) / gen_progress(배치 FGS 진행).
 * 같은 종류의 알림이 도배되지 않게 알림 id 는 종류별로 고정 (iOS 식별자 고정과 동일 의도).
 */
object NotificationHelper {
    /** 알림 탭 → MainActivity 로 배치 화면 열기 요청 extra (Phase I 가 소비). */
    const val EXTRA_OPEN_BATCH = "withu.openBatch"

    const val CHANNEL_REMINDER = "reminder"
    const val CHANNEL_GEN_DONE = "gen_done"
    const val CHANNEL_GEN_PROGRESS = "gen_progress"

    // 종류별 고정 알림 id
    private const val NOTIF_ID_GEN_DONE = 1001
    private const val NOTIF_ID_GEN_ANCHOR = 1002
    private const val NOTIF_ID_BEDTIME = 1003
    private const val NOTIF_ID_STEP_GOAL = 1004
    private const val NOTIF_ID_WORKOUT_ENDED = 1005
    internal const val NOTIF_ID_GEN_PROGRESS = 1006

    /** 걸음 수 목표 (이 값 이상이면 하루 1회 축하) — iOS stepGoal 동일. */
    private const val STEP_GOAL = 8000.0

    // 중복 방지 마커 — iOS UserDefaults.standard 대응 (표준 prefs, 키 문자열 iOS 원문)
    private const val MARKER_PREFS = "withu_prefs"
    private const val MARKER_STEP_GOAL = "withu.notification.stepGoal"
    private const val MARKER_WORKOUT_ENDED = "withu.notification.workoutEnded"
    /** '권한을 한 번이라도 요청했는지' — authorizationLabel 의 '아직 요청 안 했어요' 판정. */
    private const val MARKER_PERMISSION_REQUESTED = "withu.notification.permissionRequested"

    private const val BEDTIME_WORK_NAME = "withu.bedtimeReminder"
    /** 취침 리마인더 시각 (자정 기준 분) — iOS @AppStorage 키와 바이트 동일. */
    private const val BEDTIME_MINUTES_KEY = "withu.bedtimeReminderMinutes.v1"
    private const val BEDTIME_MINUTES_DEFAULT = 22 * 60 + 30

    private val ctx: Context get() = WithuApp.context

    /** 채널 생성 — Application.onCreate 에서 1회 (재호출 무해). */
    fun ensureChannels() {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_REMINDER,
                ctx.getString(R.string.notify_channel_reminder),
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_GEN_DONE,
                ctx.getString(R.string.notify_channel_gen_done),
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_GEN_PROGRESS,
                ctx.getString(R.string.notify_channel_gen_progress),
                NotificationManager.IMPORTANCE_LOW,   // 진행 FGS — 소리/배너 없이 조용히
            ),
        )
    }

    fun hasPermission(): Boolean =
        if (Build.VERSION.SDK_INT >= 33) {
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            NotificationManagerCompat.from(ctx).areNotificationsEnabled()
        }

    /**
     * 설정 화면 표시용 라벨. Android 는 iOS 의 notDetermined 를 직접 알 수 없어
     * '요청한 적 있음' 마커로 근사 — 권한 요청 launcher 를 띄운 화면이 markPermissionRequested() 호출.
     */
    fun authorizationLabel(): String = when {
        hasPermission() -> ctx.getString(R.string.notify_auth_granted)
        markerPrefs().getBoolean(MARKER_PERMISSION_REQUESTED, false) ->
            ctx.getString(R.string.notify_auth_denied)
        else -> ctx.getString(R.string.notify_auth_not_asked)
    }

    /** 권한 요청 직후 화면이 호출 — authorizationLabel 의 '거부됨' 판정 근거. */
    fun markPermissionRequested() {
        markerPrefs().edit().putBoolean(MARKER_PERMISSION_REQUESTED, true).apply()
    }

    /** 권한을 한 번이라도 요청했는지 — 재요청이 무반응인 상태(iOS .denied 대응) 판정용. */
    fun permissionRequested(): Boolean =
        markerPrefs().getBoolean(MARKER_PERMISSION_REQUESTED, false)

    /**
     * 배치 생성 완료 알림 (스펙 11 §2.4 문구 전량).
     * anchor: done > 0 일 때만 '기준 모습' 알림 / rest: 완료·부분완료 / retry: 알림 없음.
     * 탭 → MainActivity + EXTRA_OPEN_BATCH (배치 화면 딥링크).
     */
    fun notifyBatchFinished(done: Int, failed: Int, phase: BgGenPhase) {
        when (phase) {
            BgGenPhase.RETRY -> return   // 한 장 재시도 — 배치 완료 알림을 다시 보내지 않음
            BgGenPhase.ANCHOR -> {
                if (done <= 0) return
                post(
                    id = NOTIF_ID_GEN_ANCHOR,
                    channel = CHANNEL_GEN_DONE,
                    title = ctx.getString(R.string.notify_anchor_title),
                    body = ctx.getString(R.string.notify_anchor_body),
                    openBatch = true,
                )
            }
            BgGenPhase.REST -> {
                val (title, body) = if (failed == 0) {
                    ctx.getString(R.string.notify_gen_done_title) to
                        ctx.getString(R.string.notify_gen_done_body, done)
                } else {
                    ctx.getString(R.string.notify_gen_partial_title) to
                        ctx.getString(R.string.notify_gen_partial_body, done, failed)
                }
                post(
                    id = NOTIF_ID_GEN_DONE,
                    channel = CHANNEL_GEN_DONE,
                    title = title,
                    body = body,
                    openBatch = true,
                )
            }
        }
    }

    /** 저장된 취침 리마인더 시각 (자정 기준 분) — 설정 화면 피커 초기값. */
    fun bedtimeReminderMinutes(): Int =
        markerPrefs().getInt(BEDTIME_MINUTES_KEY, BEDTIME_MINUTES_DEFAULT)

    /** 매일 선택 시각 취침 리마인더 — 자체 재예약 Worker (iOS UNCalendarNotificationTrigger 대응). */
    fun scheduleBedtimeReminder(hour: Int = 22, minute: Int = 30) {
        markerPrefs().edit().putInt(BEDTIME_MINUTES_KEY, hour * 60 + minute).apply()
        scheduleNextBedtime()
    }

    internal fun scheduleNextBedtime() {
        val minutes = bedtimeReminderMinutes()
        val hour = minutes / 60
        val minute = minutes % 60
        val now = LocalDateTime.now()
        var next = LocalDateTime.of(LocalDate.now(), LocalTime.of(hour, minute))
        if (!next.isAfter(now)) next = next.plusDays(1)
        val delayMs = Duration.between(
            now.atZone(ZoneId.systemDefault()).toInstant(),
            next.atZone(ZoneId.systemDefault()).toInstant(),
        ).toMillis()
        val request = OneTimeWorkRequestBuilder<BedtimeReminderWorker>()
            .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
            .build()
        WorkManager.getInstance(ctx)
            .enqueueUniqueWork(BEDTIME_WORK_NAME, ExistingWorkPolicy.REPLACE, request)
    }

    /** 예약된 리마인더 전부 취소 — iOS removeAllPendingNotificationRequests 대응. */
    fun cancelAllScheduled() {
        WorkManager.getInstance(ctx).cancelUniqueWork(BEDTIME_WORK_NAME)
    }

    internal fun postBedtimeReminder() {
        post(
            id = NOTIF_ID_BEDTIME,
            channel = CHANNEL_REMINDER,
            title = ctx.getString(R.string.notify_bedtime_title),
            body = ctx.getString(R.string.notify_bedtime_body),
        )
    }

    /** 오늘 걸음이 목표(8000)를 넘었으면 축하 — 당일 1회만 (iOS 동형). */
    fun scheduleStepGoalIfNeeded(steps: Double) {
        if (steps < STEP_GOAL) return
        val todayEpochDay = LocalDate.now().toEpochDay()
        if (markerPrefs().getLong(MARKER_STEP_GOAL, -1L) == todayEpochDay) return
        post(
            id = NOTIF_ID_STEP_GOAL,
            channel = CHANNEL_REMINDER,
            title = ctx.getString(R.string.notify_step_goal_title, STEP_GOAL.toInt()),
            body = ctx.getString(R.string.notify_step_goal_body, steps.toInt()),
        )
        markerPrefs().edit().putLong(MARKER_STEP_GOAL, todayEpochDay).apply()
    }

    /** 최근 워크아웃이 방금(10분 이내) 끝났으면 격려 — 세션당 1회 (iOS 동형). */
    fun scheduleWorkoutEndedIfNeeded(latest: WorkoutSummary?) {
        val w = latest ?: return
        val endedAt = w.start + (w.durationSeconds * 1000).toLong()
        if (System.currentTimeMillis() - endedAt >= 10 * 60 * 1000) return
        val markerKey = "$MARKER_WORKOUT_ENDED.${w.start}"
        if (markerPrefs().getBoolean(markerKey, false)) return
        val minutes = (w.durationSeconds / 60).toInt()
        post(
            id = NOTIF_ID_WORKOUT_ENDED,
            channel = CHANNEL_REMINDER,
            title = ctx.getString(R.string.notify_workout_ended_title, w.activity.displayName),
            body = ctx.getString(R.string.notify_workout_ended_body, minutes),
        )
        markerPrefs().edit().putBoolean(markerKey, true).apply()
    }

    /** 배치 Worker 의 FGS(dataSync) 진행 알림 — GenBatchWorker.getForegroundInfo 가 사용. */
    fun genProgressForegroundInfo(context: Context): ForegroundInfo {
        val notification = NotificationCompat.Builder(context, CHANNEL_GEN_PROGRESS)
            .setSmallIcon(R.drawable.ic_stat_withu)
            .setContentTitle(context.getString(R.string.notify_gen_progress))
            .setOngoing(true)
            .setContentIntent(openAppIntent(openBatch = true))
            .build()
        return if (Build.VERSION.SDK_INT >= 29) {
            ForegroundInfo(
                NOTIF_ID_GEN_PROGRESS, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(NOTIF_ID_GEN_PROGRESS, notification)
        }
    }

    // MARK: - 내부

    private fun markerPrefs() = ctx.getSharedPreferences(MARKER_PREFS, Context.MODE_PRIVATE)

    private fun openAppIntent(openBatch: Boolean = false): PendingIntent {
        val intent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (openBatch) putExtra(EXTRA_OPEN_BATCH, true)
        }
        return PendingIntent.getActivity(
            ctx,
            if (openBatch) 1 else 0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun post(id: Int, channel: String, title: String, body: String, openBatch: Boolean = false) {
        if (!hasPermission()) return
        val notification = NotificationCompat.Builder(ctx, channel)
            .setSmallIcon(R.drawable.ic_stat_withu)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(openAppIntent(openBatch))
            .build()
        // POST_NOTIFICATIONS 미허용 등 — 알림 실패가 생성 플로우를 깨지 않게 삼킴
        runCatching { NotificationManagerCompat.from(ctx).notify(id, notification) }
    }
}
