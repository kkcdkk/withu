package com.seoyoung.withu.watch

import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.Wearable
import com.seoyoung.withu.WithuApp
import com.seoyoung.withu.shared.SharedAppState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 폰이 보는 워치 연동 상태 — iOS ConnectivityManager 의 isPaired/isWatchAppInstalled/isReachable 대응.
 * 설정 화면의 '갤럭시 워치' 섹션에서 표시.
 */
object WatchStatus {

    // wear 모듈 res/values/wear.xml 의 capability 와 문자열 일치해야 함.
    const val CAPABILITY = "withu_wear_app"
    private const val KEY_LAST_SYNC = "withu.wear.lastSyncAt.v1"

    data class State(
        val paired: Boolean,       // 연결된 워치 노드 존재
        val appInstalled: Boolean, // 워치에 우리 앱(capability) 있음
        val reachable: Boolean,    // 지금 가까이(BT) 연결됨
        val lastSyncAt: Long,      // 마지막 push 시각 (0 = 없음)
    )

    /** push 성공 시 호출 — 마지막 전송 시각 기록. */
    fun markSynced() {
        SharedAppState.prefs().edit().putLong(KEY_LAST_SYNC, System.currentTimeMillis()).apply()
    }

    suspend fun query(): State = withContext(Dispatchers.IO) {
        val ctx = WithuApp.context
        val nodes = runCatching {
            Tasks.await(Wearable.getNodeClient(ctx).connectedNodes)
        }.getOrNull().orEmpty()
        val appInstalled = runCatching {
            val cap = Tasks.await(
                Wearable.getCapabilityClient(ctx).getCapability(CAPABILITY, CapabilityClient.FILTER_ALL),
            )
            cap.nodes.isNotEmpty()
        }.getOrDefault(false)
        State(
            paired = nodes.isNotEmpty(),
            appInstalled = appInstalled,
            reachable = nodes.any { it.isNearby },
            lastSyncAt = SharedAppState.prefs().getLong(KEY_LAST_SYNC, 0L),
        )
    }
}
