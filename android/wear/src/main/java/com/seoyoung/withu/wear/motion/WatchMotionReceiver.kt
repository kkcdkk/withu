package com.seoyoung.withu.wear.motion

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionResult
import com.seoyoung.withu.wear.complication.CharacterComplicationService
import com.seoyoung.withu.wear.tile.CharacterTileService

/**
 * 손목 활동 전환 수신 → 상태 반영 + Tile·컴플리케이션 즉시 갱신.
 * 폰 없이도 워치가 스스로 캐릭터를 바꾸는 경로.
 */
class WatchMotionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION || !ActivityTransitionResult.hasResult(intent)) return
        val result = ActivityTransitionResult.extractResult(intent) ?: return
        for (event in result.transitionEvents) {
            WatchMotionManager.onTransition(
                context = context,
                activityType = event.activityType,
                isEnter = event.transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER,
            )
        }
        runCatching {
            TileService.getUpdater(context).requestUpdate(CharacterTileService::class.java)
        }
        runCatching {
            ComplicationDataSourceUpdateRequester.create(
                context,
                ComponentName(context, CharacterComplicationService::class.java),
            ).requestUpdateAll()
        }
    }

    companion object {
        const val ACTION = "com.seoyoung.withu.wear.ACTIVITY_TRANSITION"
    }
}
