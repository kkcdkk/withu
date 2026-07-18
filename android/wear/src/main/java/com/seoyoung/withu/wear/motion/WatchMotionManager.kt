package com.seoyoung.withu.wear.motion

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.DetectedActivity
import com.seoyoung.withu.wear.WearStore

/**
 * 워치 손목 활동 감지 — 애플워치 파리티의 핵심.
 * 폰이 없어도 워치가 스스로 걷기/달리기/자전거를 감지해 캐릭터를 바꾼다.
 * (Play Services Activity Recognition Transition API — 폰 MotionActivityManager 와 동일 방식.)
 *
 * 감지 결과는 WearStore 에 저장되고, effectiveStateRaw 가 폰 push 보다 우선한다.
 */
object WatchMotionManager {

    fun hasPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACTIVITY_RECOGNITION,
        ) == PackageManager.PERMISSION_GRANTED

    fun start(context: Context) {
        if (!hasPermission(context)) return
        val activities = listOf(
            DetectedActivity.WALKING, DetectedActivity.RUNNING, DetectedActivity.ON_BICYCLE,
        )
        val directions = listOf(
            ActivityTransition.ACTIVITY_TRANSITION_ENTER, ActivityTransition.ACTIVITY_TRANSITION_EXIT,
        )
        val transitions = ArrayList<ActivityTransition>()
        for (act in activities) for (dir in directions) {
            transitions.add(
                ActivityTransition.Builder().setActivityType(act).setActivityTransition(dir).build(),
            )
        }
        val request = ActivityTransitionRequest(transitions)
        runCatching {
            ActivityRecognition.getClient(context)
                .requestActivityTransitionUpdates(request, pendingIntent(context))
        }
    }

    /** 전환 수신 — ENTER 면 상태 저장, EXIT(현재와 일치)면 해제. */
    fun onTransition(context: Context, activityType: Int, isEnter: Boolean) {
        val raw = mapActivity(activityType) ?: return
        if (isEnter) {
            WearStore.saveWatchActivity(context, raw)
        } else if (WearStore.currentWatchActivityRaw(context) == raw) {
            WearStore.saveWatchActivity(context, null)
        }
    }

    // CharacterState.raw 와 동일 문자열 (walking/running/cycling).
    private fun mapActivity(type: Int): String? = when (type) {
        DetectedActivity.WALKING -> "walking"
        DetectedActivity.RUNNING -> "running"
        DetectedActivity.ON_BICYCLE -> "cycling"
        else -> null
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, WatchMotionReceiver::class.java)
            .setAction(WatchMotionReceiver.ACTION)
        return PendingIntent.getBroadcast(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
    }
}
