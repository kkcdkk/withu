package com.seoyoung.withu.health

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionResult
import com.seoyoung.withu.sync.SyncCoordinator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Activity Recognition 전환 이벤트 수신 — ENTER/EXIT 를 MotionActivityManager 에 반영하고
 * 즉시 상태 동기화(홈/위젯 갱신). iOS 는 폰 모션이 push 없어 폴링이지만, Android 는 이벤트라 즉시.
 */
class MotionTransitionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION || !ActivityTransitionResult.hasResult(intent)) return
        val result = ActivityTransitionResult.extractResult(intent) ?: return
        for (event in result.transitionEvents) {
            MotionActivityManager.onTransition(
                activityType = event.activityType,
                isEnter = event.transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER,
            )
        }
        // 감지 변화 → 캐릭터/위젯 즉시 갱신. onReceive 는 코루틴이 아니라 goAsync 로 생명주기 연장.
        val pending = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                SyncCoordinator.syncNow()
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        const val ACTION = "com.seoyoung.withu.ACTIVITY_TRANSITION"
    }
}
