//
//  withuApp.swift
//  withu
//
//  Created by seoyoung on 5/12/26.
//

import SwiftUI
import UIKit
import BackgroundTasks

@main
struct withuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    /// BGTaskScheduler identifier — Info.plist BGTaskSchedulerPermittedIdentifiers 와 일치해야 함.
    static let backgroundRefreshTaskID = "com.seoyoung.withu.refresh"

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // 포그라운드 복귀 시 Apple 로그인 권한 철회/계정 삭제 감지
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await AuthManager.shared.checkCredentialState() }
            }
        }
        // iOS 가 ~30분 ~ 수 시간 마다 깨워서 호출. 사용자 습관 따라 자동 조정.
        .backgroundTask(.appRefresh(Self.backgroundRefreshTaskID)) {
            await Self.handleBackgroundRefresh()
        }
    }

    /// 다음 background refresh 를 예약. handler 끝에 + 앱 background 진입 시 호출.
    /// earliestBeginDate 는 iOS 에 대한 "이때 이후 깨워줘" 힌트 — 실제 시점은 iOS 가 결정.
    static func scheduleNextRefresh(after: TimeInterval = 30 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: backgroundRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: after)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// iOS 가 우리 앱 잠깐 깨워서 호출 — 30초 이내에 끝내야 함.
    /// 날씨 + HealthKit fetch + SyncCoordinator → 다음 task 재예약.
    @MainActor
    static func handleBackgroundRefresh() async {
        let health = HealthKitManager.shared
        let weather = WeatherManager.shared

        // 1) 날씨 갱신 (가장 시각적, 위젯에 즉시 반영)
        weather.refresh(force: true)

        // 2) HealthKit 데이터 force-fetch — observer 가 미스해도 catchup
        _ = try? await health.fetchTodaySteps()
        _ = try? await health.fetchTodayActiveMinutes()
        _ = try? await health.fetchTodayActiveKcal()
        _ = await health.fetchInBedSchedule()

        // 3) 모든 신호 모아 sync (SharedAppState + 위젯 reload + 워치 push)
        SyncCoordinator.syncNow()

        // 4) 진단 — 마지막 실행 시각 기록
        let defaults = UserDefaults(suiteName: SharedAppState.groupID)
        defaults?.set(Date(), forKey: "withu.lastBackgroundRefreshAt")

        // 5) 다음 깨움 예약 — chain 끊기면 iOS 가 더 안 깨움
        scheduleNextRefresh()
    }
}

/// 앱이 background launch (HealthKit observer wake-up 등) 되어도 살아있는
/// 진입점. ContentView.task 는 첫 화면 onAppear 후에야 동작하므로,
/// 워치 sync / HealthKit observer / Focus 권한 활성화는 여기서 launch 직후 한 번 시작.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task { @MainActor in
            ConnectivityManager.shared.activate()
            HealthKitManager.shared.startObservingChanges()
            // 인앱 결제 — 상품 로드 + 구독 상태 동기화 + 트랜잭션 감시
            StoreManager.shared.start()
            // Focus 권한 — 처음이면 시스템 시트, 이후엔 즉시 status 갱신.
            await FocusModeManager.shared.requestAuthorization()
            // 권한 결과 반영해서 즉시 한 번 sync.
            SyncCoordinator.syncNow()
            // BG refresh 첫 예약 — 이후는 handler 가 자기 끝에 재예약 (chain).
            withuApp.scheduleNextRefresh()
        }
        return true
    }
}
