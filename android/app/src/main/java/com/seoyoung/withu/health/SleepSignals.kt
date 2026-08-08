package com.seoyoung.withu.health

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import com.seoyoung.withu.WithuApp
import com.seoyoung.withu.shared.SharedAppState
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId

/**
 * 수면 신호 근사 — iOS FocusModeManager(집중 모드 필터) 의 Android 대체 (스펙 05 §5, 08 §5).
 * Android 엔 Sleep Focus 확정 신호가 없어 방해 금지(DND) 로 근사:
 *  - isGenericFocusActive ≈ DND on (읽기는 권한 불필요)
 *  - focusWokeAt ≈ DND 가 꺼진 전환 시각 (ACTION_INTERRUPTION_FILTER_CHANGED 관측)
 * 리졸버의 수면 3단 판정(수면 세션 → DND+수면창 → 수면창 fallback)이 그대로 살아남는다.
 */
object SleepSignals {
    /** DND 해제 전환 시각 (epoch millis) — 프로세스 재시작에도 유지되게 공유 prefs. */
    private const val DND_OFF_AT_KEY = "withu.dndOffAt.v1"

    private var receiverRegistered = false
    private var lastKnownDndOn: Boolean? = null

    /** 지금 방해 금지(DND)가 켜져 있는지. 알 수 없으면 false (오탐으로 수면 처리하지 않게). */
    fun isDndOn(): Boolean {
        val nm = WithuApp.context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return false
        return when (nm.currentInterruptionFilter) {
            NotificationManager.INTERRUPTION_FILTER_ALL,
            NotificationManager.INTERRUPTION_FILTER_UNKNOWN,
            -> false
            else -> true
        }
    }

    /**
     * 마지막으로 DND 가 꺼진 시각 — 리졸버 focusWokeAt 입력.
     * "이번 밤 창에서 수면 모드를 껐으면 기상으로 존중" 판정에 쓰인다 (스펙 08 §3.2).
     */
    fun lastDndOffAt(): LocalDateTime? {
        val prefs = SharedAppState.prefs()
        if (!prefs.contains(DND_OFF_AT_KEY)) return null
        val ms = prefs.getLong(DND_OFF_AT_KEY, 0L)
        if (ms <= 0L) return null
        return Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault()).toLocalDateTime()
    }

    /**
     * DND 전환 모니터 시작 — Application.onCreate 에서 1회.
     * ACTION_INTERRUPTION_FILTER_CHANGED 는 manifest 등록이 안 되는 implicit broadcast 라
     * 프로세스 수명의 context-registered receiver 로 관측 (프로세스가 죽은 사이 전환은 놓치지만,
     * 그 경우 focusWokeAt 없음 = 수면 창 fallback 유지 — 안전한 방향으로 실패).
     */
    fun startMonitoring() {
        if (receiverRegistered) return
        lastKnownDndOn = isDndOn()
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val on = isDndOn()
                // on → off 전환만 기록 (수면 모드를 '껐다' 신호)
                if (lastKnownDndOn == true && !on) {
                    SharedAppState.prefs().edit()
                        .putLong(DND_OFF_AT_KEY, System.currentTimeMillis())
                        .apply()
                }
                lastKnownDndOn = on
            }
        }
        WithuApp.context.registerReceiver(
            receiver,
            IntentFilter(NotificationManager.ACTION_INTERRUPTION_FILTER_CHANGED),
        )
        receiverRegistered = true
    }
}
