package com.seoyoung.withu.wear.complication

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.SmallImage
import androidx.wear.watchface.complications.data.SmallImageComplicationData
import androidx.wear.watchface.complications.data.SmallImageType
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import com.seoyoung.withu.wear.WearCharacter
import com.seoyoung.withu.wear.WearStore

/**
 * 시계 페이스 컴플리케이션 — iOS withuComplicationExtension 대응.
 * 폰이 push 해 WearStore 에 저장된 현재 상태의 캐릭터를 SMALL_IMAGE(PHOTO, 풀컬러)로 제공.
 * 워치 페이스의 컴플리케이션 칸에 캐릭터가 뜬다.
 */
class CharacterComplicationService : SuspendingComplicationDataSourceService() {

    // 컴플리케이션 선택기 미리보기.
    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        if (type == ComplicationType.SMALL_IMAGE) build("idle") else null

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        if (request.complicationType != ComplicationType.SMALL_IMAGE) return null
        return build(WearStore.loadSnapshot(this).stateRaw)
    }

    private fun build(stateRaw: String?): ComplicationData? {
        val bmp = characterBitmap(stateRaw) ?: return null
        return SmallImageComplicationData.Builder(
            smallImage = SmallImage.Builder(Icon.createWithBitmap(bmp), SmallImageType.PHOTO).build(),
            contentDescription = PlainComplicationText.Builder(WearCharacter.shortLabel(stateRaw)).build(),
        ).build()
    }

    private fun characterBitmap(stateRaw: String?): Bitmap? {
        val raw = stateRaw ?: "idle"
        WearStore.loadImage(this, raw)?.let { return it }
        val id = resources.getIdentifier(WearCharacter.fallbackDrawableName(raw), "drawable", packageName)
        if (id == 0) return null
        return runCatching { BitmapFactory.decodeResource(resources, id) }.getOrNull()
    }
}
