package com.seoyoung.withu.watch

import android.graphics.Bitmap
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Asset
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import com.seoyoung.withu.WithuApp
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.shared.CharacterImageStore
import com.seoyoung.withu.shared.SharedAppState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

/**
 * 폰 → 워치 push (Wearable Data Layer) — iOS ConnectivityManager 대응.
 * 폰이 두뇌: 상태를 계산해 스냅샷 + 캐릭터 PNG(다운샘플)를 워치로 보낸다.
 * 워치는 받은 걸 표시하고, 손목 움직임 감지 시 그 상태 이미지로 바꾼다.
 *
 * 이미지는 '모든 상태'를 보낸다 — 워치가 걷기를 감지하면 그 상태(산책 등)의 캐릭터가
 * 워치에 미리 있어야 하므로. 내용이 같으면 Data Layer 가 재전송을 생략(효율적).
 */
object WearSyncManager {

    private const val PATH_STATE = "/withu/state"
    private const val PATH_IMAGE_PREFIX = "/withu/image/"
    // iOS watchImageMaxPixelSize = 100 — 워치 RAM/전송 한계. 원본을 그대로 보내면 안 됨.
    private const val WATCH_IMAGE_MAX_PX = 100

    /**
     * 최신 스냅샷 + 활성 캐릭터 이미지(전 상태)를 워치로 push. 워치 미연결/실패는 삼킨다(무해).
     * @param force true 면 이미지도 변화필드를 넣어 무조건 재전달(수동 '지금 동기화' / 워치 새 설치 대비).
     */
    suspend fun push(force: Boolean = false) = withContext(Dispatchers.IO) {
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

            // 2) 활성 캐릭터 이미지 — 모든 상태. 워치가 손목 움직임으로 상태를 바꿀 때
            //    그 상태의 캐릭터가 워치에 있어야 하므로 전부 보낸다.
            //    hash 필드로 내용이 바뀔 때만 실제 전송(효율). force 면 무조건 재전송.
            for (state in CharacterState.entries) {
                if (!CharacterImageStore.hasImage(state)) continue
                val bmp = CharacterImageStore.loadThumbnail(state, WATCH_IMAGE_MAX_PX) ?: continue
                val bytes = ByteArrayOutputStream().use { out ->
                    bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
                    out.toByteArray()
                }
                val req = PutDataMapRequest.create(PATH_IMAGE_PREFIX + state.raw).apply {
                    dataMap.putString("state", state.raw)
                    dataMap.putInt("frame", 0)
                    dataMap.putAsset("image", Asset.createFromBytes(bytes))
                    dataMap.putInt("hash", bytes.contentHashCode())
                    if (force) dataMap.putLong("forcedAt", msg.timestamp)
                }.asPutDataRequest()
                Tasks.await(client.putDataItem(req))
            }
            WatchStatus.markSynced()
        }
    }
}
