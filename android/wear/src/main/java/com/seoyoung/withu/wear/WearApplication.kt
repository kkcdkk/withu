package com.seoyoung.withu.wear

import android.app.Application
import com.seoyoung.withu.wear.motion.WatchMotionManager

/**
 * 워치 앱 프로세스 시작 시 손목 활동 감지 재시작 (권한 이미 허용된 경우 — 재부팅/프로세스 재생성 대비).
 * 권한이 없으면 no-op (WearMainActivity 가 권한 요청).
 */
class WearApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        runCatching { WatchMotionManager.start(this) }
    }
}
