package com.seoyoung.withu

import android.app.Application
import android.content.Context
import com.seoyoung.withu.bggen.BackgroundGenQueue
import com.seoyoung.withu.gen.SingleGenQueue
import com.seoyoung.withu.notify.NotificationHelper
import com.seoyoung.withu.sync.BackgroundRefreshWorker

/**
 * Application — 공유 싱글턴들의 Context 홀더.
 * 계약(00-PLAN §0-2): 공유 API 는 Context 파라미터를 받지 않고 `WithuApp.context` 를 내부에서 쓴다.
 */
class WithuApp : Application() {

    override fun onCreate() {
        super.onCreate()
        context = applicationContext
        // Phase I 배선 (이 순서 유지) — 시작 부수효과라 각각 best-effort:
        // WorkManager 미초기화 등(테스트/드문 런타임)에도 앱 시작이 죽지 않게 개별 runCatching.
        //  1) NotificationHelper.ensureChannels() — 알림 채널 생성
        //  2) BackgroundGenQueue.resumeIfNeeded() — 프로세스 사망 후 배치 큐 재개
        //  3) BackgroundRefreshWorker.schedule() — 15분 주기 상태/위젯 갱신 (§4 Phase I-5)
        runCatching { NotificationHelper.ensureChannels() }
        runCatching { BackgroundGenQueue.resumeIfNeeded() }
        // 2-b) SingleGenQueue.resumeIfNeeded() — 프로세스 사망 후 단건 생성 재개
        runCatching { SingleGenQueue.resumeIfNeeded() }
        runCatching { BackgroundRefreshWorker.schedule() }
        // 4) 폰 모션 감지 시작 — 권한 있으면 워치 없이 산책/달리기/자전거 반영 (권한 없으면 no-op)
        runCatching { com.seoyoung.withu.health.MotionActivityManager.start(this) }
    }

    companion object {
        /** 앱 전역 Context. Application.onCreate 에서 세팅 — 공유 저장소/네트워크 계층이 사용. */
        lateinit var context: Context
            private set
    }
}
