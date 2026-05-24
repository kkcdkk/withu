//
//  withuApp.swift
//  withu
//
//  Created by seoyoung on 5/12/26.
//

import SwiftUI
import UIKit

@main
struct withuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
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
            // Focus 권한 — 처음이면 시스템 시트, 이후엔 즉시 status 갱신.
            await FocusModeManager.shared.requestAuthorization()
            // CoreMotion 권한 시트는 startActivityUpdates 첫 호출 시 자동.
            MotionActivityManager.shared.start()
            // 권한 결과 반영해서 즉시 한 번 sync.
            SyncCoordinator.syncNow()
        }
        return true
    }
}
