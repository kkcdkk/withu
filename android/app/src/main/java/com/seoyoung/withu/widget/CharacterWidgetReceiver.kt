package com.seoyoung.withu.widget

import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver

/**
 * 홈 위젯 브로드캐스트 리시버 — Manifest 에 등록되는 진입점 (Phase I 배선).
 * iOS 는 WidgetKit 이 자동 등록하지만 Android 는 receiver 를 명시해야 함.
 */
class CharacterWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = CharacterWidget()
}
