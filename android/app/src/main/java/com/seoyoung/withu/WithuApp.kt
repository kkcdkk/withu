package com.seoyoung.withu

import android.app.Application
import android.content.Context

/**
 * Application — 공유 싱글턴들의 Context 홀더.
 * 계약(00-PLAN §0-2): 공유 API 는 Context 파라미터를 받지 않고 `WithuApp.context` 를 내부에서 쓴다.
 */
class WithuApp : Application() {

    override fun onCreate() {
        super.onCreate()
        context = applicationContext
        // F2 훅 지점 (이 순서 유지):
        //  1) NotificationHelper.ensureChannels() — 알림 채널 생성
        //  2) BackgroundGenQueue.resumeIfNeeded() — 프로세스 사망 후 배치 큐 재개
        // F1 시점엔 해당 모듈이 아직 없으므로 호출하지 않는다 (00-PLAN §4 Phase F).
    }

    companion object {
        /** 앱 전역 Context. Application.onCreate 에서 세팅 — 공유 저장소/네트워크 계층이 사용. */
        lateinit var context: Context
            private set
    }
}
