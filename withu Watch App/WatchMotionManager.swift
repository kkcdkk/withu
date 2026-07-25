//
//  WatchMotionManager.swift
//  withu Watch App
//
//  ②단계 — 워치가 자기 손목 CoreMotion 활동 분류로 산책/달리기/자전거를 직접 감지해
//  폰 왕복 없이 캐릭터 상태를 바로 갱신(컴플리케이션 reload). 폰이 백그라운드에서
//  운동을 늦게 잡아 "앱 열어야만 바뀌던" 지연을 줄인다.
//
//  ⚠️ watchOS 는 백그라운드 실행/컴플리케이션 갱신을 제한하므로, 주로 워치 앱이
//     떠 있거나 시스템이 준 짧은 런타임 동안 반영된다(완전 즉시는 OS 한계).
//

import Foundation
import CoreMotion
import WidgetKit

@MainActor
final class WatchMotionManager {
    static let shared = WatchMotionManager()

    private let manager = CMMotionActivityManager()
    private var started = false
    /// 워치가 로컬로 운동 상태를 덮어쓰는 중이면 그 state (아니면 nil).
    private var localOverride: CharacterState?

    private init() {}

    func start() {
        guard !started, CMMotionActivityManager.isActivityAvailable() else { return }
        started = true
        manager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            Task { @MainActor in self?.handle(activity) }
        }
    }

    private func handle(_ a: CMMotionActivity) {
        // confidence 낮은 추정은 무시 (오탐 방지).
        guard a.confidence != .low else { return }

        let detected: CharacterState? =
            a.running ? .running :
            a.cycling ? .cycling :
            a.walking ? .walking : nil

        if let detected {
            if localOverride != detected {
                localOverride = detected
                writeState(detected)
            }
        } else if localOverride != nil {
            // 운동 종료(정지/차량/불명) — 폰이 준 마지막 '비운동' 상태로 복귀, 없으면 느긋.
            localOverride = nil
            let base = ConnectivityManager.shared.lastMessage
            let fallback = (base.map { !Self.isWorkout($0.state) } ?? false) ? base!.state : .idle
            writeState(fallback)
        }
    }

    private static func isWorkout(_ s: CharacterState) -> Bool {
        switch s {
        case .walking, .running, .cycling, .energetic: return true
        default: return false
        }
    }

    /// 마지막 메시지의 다른 값은 유지한 채 state 만 바꿔 SharedAppState 저장 + 컴플리케이션 즉시 reload.
    private func writeState(_ state: CharacterState) {
        let base = SharedAppState.loadMessage()
        let msg = WatchMessage(
            state: state,
            todaySteps: base?.todaySteps,
            lastSleepHours: base?.lastSleepHours,
            todayActiveMinutes: base?.todayActiveMinutes,
            todayActiveKcal: base?.todayActiveKcal,
            weatherEmoji: base?.weatherEmoji,
            weatherTempC: base?.weatherTempC,
            weatherSunrise: base?.weatherSunrise,
            weatherSunset: base?.weatherSunset,
            timestamp: Date()
        )
        SharedAppState.save(msg)
        WidgetCenter.shared.reloadAllTimelines()
        WidgetCenter.shared.reloadTimelines(ofKind: "withuComplication")
    }
}
