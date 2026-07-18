package com.seoyoung.withu.watch

import android.graphics.Bitmap
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Asset
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import com.seoyoung.withu.WithuApp
import com.seoyoung.withu.shared.CharacterImageStore
import com.seoyoung.withu.shared.SharedAppState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

/**
 * 폰 → 워치 push (Wearable Data Layer) — iOS ConnectivityManager 대응.
 * 폰이 두뇌: 상태를 계산해 스냅샷 + 현재 상태의 캐릭터 PNG(다운샘플)를 워치로 보낸다.
 * 워치는 받은 걸 Tile/화면에 표시만 한다(재계산 없음).
 *
 * 경로/키는 :wear 모듈의 WearContract 와 바이트 동일해야 한다.
 */
object WearSyncManager {

    private const val PATH_STATE = "/withu/state"
    private const val PATH_IMAGE = "/withu/image"
    // iOS watchImageMaxPixelSize = 100 — 워치 RAM/전송 한계. 원본을 그대로 보내면 안 됨.
    private const val WATCH_IMAGE_MAX_PX = 100

    /** 최신 스냅샷 + 현재 상태 이미지를 워치로 push. 워치 미연결/실패는 삼킨다(무해). */
    suspend fun push() = withContext(Dispatchers.IO) {
        val msg = SharedAppState.loadMessage() ?: return@withContext
        val client = Wearable.getDataClient(WithuApp.context)
        runCatching {
            // 1) 상태 스냅샷 — 자주 바뀜. updatedAt 으로 항상 최신 전달(urgent).
            val stateReq = PutDataMapRequest.create(PATH_STATE).apply {
                dataMap.putString("state", msg.state)
                msg.todaySteps?.let { dataMap.putDouble("steps", it) }
                msg.lastSleepHours?.let { dataMap.putDouble("sleepHours", it) }
                msg.weatherEmoji?.let { dataMap.putString("weatherEmoji", it) }
                msg.weatherTempC?.let { dataMap.putDouble("tempC", it) }
                dataMap.putLong("updatedAt", msg.timestamp)
            }.asPutDataRequest().setUrgent()
            Tasks.await(client.putDataItem(stateReq))

            // 2) 현재 상태의 활성 캐릭터 이미지 — 다운샘플 PNG.
            //    바이트가 같으면 Data Layer 가 재전송하지 않으므로(타임스탬프 미포함) 매번 보내도 안전.
            val state = msg.characterState
            val bmp = CharacterImageStore.loadThumbnail(state, WATCH_IMAGE_MAX_PX)
            if (bmp != null) {
                val bytes = ByteArrayOutputStream().use { out ->
                    bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
                    out.toByteArray()
                }
                val imgReq = PutDataMapRequest.create(PATH_IMAGE).apply {
                    dataMap.putString("state", state.raw)
                    dataMap.putInt("frame", 0)
                    dataMap.putAsset("image", Asset.createFromBytes(bytes))
                    // 워치가 새로 설치돼도 확실히 재전달되게 변화 필드 포함 (dedupe 로 전달 누락 방지).
                    dataMap.putLong("updatedAt", msg.timestamp)
                }.asPutDataRequest().setUrgent()
                Tasks.await(client.putDataItem(imgReq))
            }
            WatchStatus.markSynced()
        }
    }
}
