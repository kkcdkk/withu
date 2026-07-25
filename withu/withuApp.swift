//
//  withuApp.swift
//  withu
//
//  Created by seoyoung on 5/12/26.
//

import SwiftUI
import UIKit
import BackgroundTasks
import UserNotifications

@main
struct withuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    /// BGTaskScheduler identifier — Info.plist BGTaskSchedulerPermittedIdentifiers 와 일치해야 함.
    static let backgroundRefreshTaskID = "com.seoyoung.withu.refresh"

    init() {
        // 전 페이지 네비게이션 타이틀을 Galmuri 픽셀 폰트로 — 앱 전체 헤더 톤 통일.
        // 배경은 투명(각 화면의 따뜻한 그라데이션이 그대로 비치게).
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        if let title = UIFont(name: "DungGeunMo", size: 17) {
            appearance.titleTextAttributes = [.font: title, .foregroundColor: UIColor.label]
        }
        if let large = UIFont(name: "DungGeunMo", size: 26) {
            appearance.largeTitleTextAttributes = [.font: large, .foregroundColor: UIColor.label]
        }
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // 다크모드에서 캐릭터/카드 대비가 어긋나 항상 밝은 화면으로 고정.
                .preferredColorScheme(.light)
                // 앱 전체 토글을 픽셀 스타일로 (iOS 초록 스위치 제거). sheet/네비도 상속.
                .toggleStyle(PixelToggleStyle())
        }
        // 포그라운드 복귀 시 Apple 로그인 권한 철회/계정 삭제 감지
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await AuthManager.shared.checkCredentialState() }
                // 갤러리 클라우드 백업 동기화 (로그인 상태일 때만 내부에서 동작)
                GallerySyncManager.shared.kick()
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
        // 알림 탭 라우팅 — launch 완료 전에 등록해야 종료 상태에서 탭한 알림도 전달받음.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        Task { @MainActor in
            ConnectivityManager.shared.activate()
            HealthKitManager.shared.startObservingChanges()
            // 인앱 결제 — 상품 로드 + 구독 상태 동기화 + 트랜잭션 감시
            StoreManager.shared.start()
            // Focus 권한 — 온보딩 완료 후에만 (첫 설치에서 Welcome 화면보다 먼저
            // 맥락 없는 시스템 시트가 뜨는 것 방지 — 첫 요청은 온보딩 focus 단계가 담당).
            // 진단/스크린샷 실행(simctl 자동화, `--` 인자)에선 팝업이 화면을 가리므로 건너뜀.
            if UserDefaults.standard.bool(forKey: "withu.onboarded.v1"),
               !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--") }) {
                await FocusModeManager.shared.requestAuthorization()
            }
            // 권한 결과 반영해서 즉시 한 번 sync.
            SyncCoordinator.syncNow()
            // BG refresh 첫 예약 — 이후는 handler 가 자기 끝에 재예약 (chain).
            withuApp.scheduleNextRefresh()
            // 백그라운드 캐릭터 생성 — 앱이 죽었다 다시 켜져도 미완료 작업 이어가기.
            BackgroundGenerationManager.shared.resumeIfNeeded()
            // 갤러리 클라우드 백업 — 저장/삭제 알림 구독 시작 (실제 동기화는 로그인 시).
            GallerySyncManager.shared.start()
        }
        // 저장 파일 일회성 보정 (멱등, 백그라운드):
        //  1) 보호 등급 완화 — 재부팅 후 첫 잠금해제 전 잠금화면 렌더에서도 그림이 읽히게
        //  2) 배경 안 지워진 그림 Vision 투명화 — 잠금화면 통짜 사각형 방지. 완료 시 위젯 reload.
        Task.detached(priority: .utility) {
            CharacterImageStore.relaxFileProtection()
            await ImageProcessing.backfillTransparency()
        }
        return true
    }

    /// 백그라운드 URLSession 이벤트로 앱이 깨어났을 때 — completion handler 를 매니저에
    /// 넘겨 두고, 이벤트 소진 후 매니저가 호출한다 (iOS 요구사항).
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == BackgroundGenerationManager.sessionIdentifier else {
            completionHandler()
            return
        }
        // 동기로 저장해야 함 — Task 로 미루면 세션 이벤트 소진이 먼저 와서
        // handler 가 nil 인 채 지나가고, iOS 가 백그라운드 실행을 제한할 수 있다.
        BackgroundGenerationManager.shared.backgroundCompletionHandler = completionHandler
    }
}
