//
//  withuApp.swift
//  withu Watch App
//
//  Created by seoyoung on 5/13/26.
//

import SwiftUI
import WatchKit

/// 앱 실행(백그라운드 launch 포함) 즉시 WCSession 활성화.
/// ContentView.task 는 화면이 떠야 실행되므로, 시스템이 상태·이미지 전달을 위해
/// 앱을 백그라운드로 깨울 때 세션이 아직 활성화 안 돼 전달을 놓치던 것을 방지 →
/// 컴플리케이션/워치 앱이 아이폰 변경을 자동 반영.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in
            ConnectivityManager.shared.activate()
            // 워치 자체 손목 모션으로 운동을 바로 감지 → 폰 왕복 없이 캐릭터 갱신.
            WatchMotionManager.shared.start()
        }
    }
}

@main
struct withu_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
