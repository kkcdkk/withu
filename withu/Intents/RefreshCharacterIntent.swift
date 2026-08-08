//
//  RefreshCharacterIntent.swift
//  withu (iOS)
//
//  단축어/자동화용 백그라운드 새로고침 인텐트.
//  iOS 는 '운동 시작'을 앱에 직접 push 해주지 않는다 — HKWorkout 은 운동이 끝나야
//  저장되고, CoreMotion 은 앱이 살아있어야 한다. 그래서 개인 자동화(운동/수면 모드
//  트리거)에 이 인텐트를 연결하는 게 즉시 반영의 최선 경로다.
//  '앱 열기' 방식과 달리 openAppWhenRun=false 라 화면 전환 없이 조용히 실행된다.
//

import AppIntents
import WidgetKit

struct RefreshCharacterIntent: AppIntent {
    static let title: LocalizedStringResource = "캐릭터 새로고침"
    static let description = IntentDescription("지금 상태(운동·수면·날씨)에 맞춰 캐릭터와 위젯을 조용히 새로 맞춰요.")
    /// 백그라운드 실행 — 앱을 화면에 띄우지 않는다.
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let health = HealthKitManager.shared
        // 운동 시작 직후엔 HKWorkout 이 아직 없으므로 실시간 신호(심박 스트림·페이스)로 추정.
        await health.refreshWorkoutInference()
        _ = try? await health.fetchTodaySteps()
        _ = await health.fetchInBedSchedule()
        WeatherManager.shared.refresh()
        // SharedAppState 기록 + 위젯 reload + 워치 push 까지 한 번에.
        SyncCoordinator.syncNow()
        return .result()
    }
}

/// 단축어 앱 노출 — 자동화에서 "Withy 캐릭터 새로고침" 으로 검색/추가.
struct WithyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RefreshCharacterIntent(),
            phrases: ["\(.applicationName) 캐릭터 새로고침"],
            shortTitle: "캐릭터 새로고침",
            systemImageName: "arrow.clockwise"
        )
    }
}
