package com.seoyoung.withu.wear.sync

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import androidx.wear.tiles.TileService
import com.google.android.gms.tasks.Tasks
import com.seoyoung.withu.wear.WearStore
import com.seoyoung.withu.wear.tile.CharacterTileService

/**
 * 폰 Data Layer 수신 — 상태 스냅샷(/withu/state)·캐릭터 이미지(/withu/image)를 저장하고
 * Tile 을 갱신한다. iOS 워치 ConnectivityManager 의 didReceiveApplicationContext / didReceive(file) 대응.
 */
class WearDataListenerService : WearableListenerService() {

    override fun onDataChanged(events: DataEventBuffer) {
        var changed = false
        for (event in events) {
            if (event.type != DataEvent.TYPE_CHANGED) continue
            val item = event.dataItem
            when (item.uri.path) {
                WearStore.PATH_STATE -> {
                    val map = DataMapItem.fromDataItem(item).dataMap
                    WearStore.saveState(
                        context = this,
                        stateRaw = map.getString("state") ?: "idle",
                        steps = if (map.containsKey("steps")) map.getDouble("steps") else null,
                        sleepHours = if (map.containsKey("sleepHours")) map.getDouble("sleepHours") else null,
                        weatherEmoji = map.getString("weatherEmoji"),
                        tempC = if (map.containsKey("tempC")) map.getDouble("tempC") else null,
                        updatedAt = map.getLong("updatedAt"),
                    )
                    changed = true
                }
                WearStore.PATH_IMAGE -> {
                    val map = DataMapItem.fromDataItem(item).dataMap
                    val stateRaw = map.getString("state") ?: continue
                    val asset = map.getAsset("image") ?: continue
                    // Asset → 바이트: getFdForAsset 는 blocking Task 라 서비스 스레드에서 await.
                    val png = runCatching {
                        val client = Wearable.getDataClient(this)
                        val resp = Tasks.await(client.getFdForAsset(asset))
                        resp.inputStream.use { it.readBytes() }
                    }.getOrNull()
                    if (png != null) {
                        WearStore.saveImage(this, stateRaw, png)
                        changed = true
                    }
                }
            }
        }
        if (changed) {
            // Tile 즉시 갱신 — iOS 의 WidgetCenter reload 대응.
            runCatching {
                TileService.getUpdater(this).requestUpdate(CharacterTileService::class.java)
            }
        }
    }
}
