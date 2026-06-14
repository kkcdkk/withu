//
//  ConnectivityManager.swift  (watchOS side — receiver)
//  withu Watch App
//

import Foundation
import WatchConnectivity
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

/// 워치 쪽 WCSession 매니저. iPhone 에서 보낸 캐릭터 메시지를 받음.
@Observable
@MainActor
final class ConnectivityManager: NSObject {
    static let shared = ConnectivityManager()

    private(set) var lastMessage: WatchMessage?
    private(set) var lastReceivedAt: Date?
    private(set) var lastError: String?
    private(set) var activationState: WCSessionActivationState = .notActivated

    /// 마지막으로 받은 캐릭터 이미지의 state — 단순 UI 표시용
    private(set) var lastReceivedImageState: String?
    /// 캐릭터 이미지가 새로 도착할 때마다 +1. SwiftUI view 가 .id() 또는
    /// .onChange 로 의존하면, 같은 state 의 이미지만 바뀌어도 강제 재로드됨.
    private(set) var characterImageVersion: Int = 0
    /// 마지막으로 컴플리케이션 reload 를 trigger 한 시각 (디버그)
    private(set) var lastComplicationReloadAt: Date?

    @ObservationIgnored private let session: WCSession? =
        WCSession.isSupported() ? WCSession.default : nil

    private override init() { super.init() }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// applicationContext / receivedApplicationContext 에서 메시지 추출.
    /// 받은 메시지는 App Group 에 저장하고 위젯 timeline 도 리로드.
    private func ingest(_ context: [String: Any]) {
        guard let data = context[WatchMessage.payloadKey] as? Data else { return }
        do {
            let msg = try JSONDecoder().decode(WatchMessage.self, from: data)
            self.lastMessage = msg
            self.lastReceivedAt = Date()
            self.lastError = nil

            // 위젯/컴플리케이션이 읽을 수 있게 공유 컨테이너에 저장
            SharedAppState.save(msg)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            self.lastError = "디코드 실패: \(error.localizedDescription)"
        }
    }
}

extension ConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        // 활성화 시점에 이미 도착해 있던 마지막 context 도 한 번 처리
        let context = session.receivedApplicationContext
        Task { @MainActor in
            self.activationState = activationState
            if let error { self.lastError = error.localizedDescription }
            self.ingest(context)
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.ingest(applicationContext)
        }
    }

    /// iPhone 이 보낸 PNG 파일 수신. metadata 키에 따라:
    ///   - withu.characterImage.state → 캐릭터 active slot 저장
    ///   - withu.weatherBackground.condition → 배경 저장
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        let characterKey = "withu.characterImage.state"
        let frameKey = "withu.characterImage.frame"
        let backgroundKey = "withu.weatherBackground.condition"
        let decorationKey = "withu.weatherDecoration.condition"

        // 1) 날씨 배경 파일?
        #if canImport(UIKit)
        if let condRaw = metadata[backgroundKey] as? String,
           let cond = WeatherBackgroundCondition(rawValue: condRaw),
           let data = try? Data(contentsOf: file.fileURL),
           let img = UIImage(data: data) {
            Task { @MainActor in
                CharacterImageStore.saveBackground(img, for: cond)
                WidgetCenter.shared.reloadAllTimelines()
                WidgetCenter.shared.reloadTimelines(ofKind: "withuComplication")
                self.lastComplicationReloadAt = Date()
            }
            return
        }
        // 2) 날씨 표현 (작은 아이콘) 파일?
        if let condRaw = metadata[decorationKey] as? String,
           let cond = WeatherBackgroundCondition(rawValue: condRaw),
           let data = try? Data(contentsOf: file.fileURL),
           let img = UIImage(data: data) {
            Task { @MainActor in
                CharacterImageStore.saveDecoration(img, for: cond)
                WidgetCenter.shared.reloadAllTimelines()
                WidgetCenter.shared.reloadTimelines(ofKind: "withuComplication")
                self.lastComplicationReloadAt = Date()
            }
            return
        }
        #endif

        // 2) 캐릭터 이미지 (기존)
        guard let stateRaw = metadata[characterKey] as? String,
              let state = CharacterState(rawValue: stateRaw) else {
            Task { @MainActor in self.lastError = "수신 파일 metadata 누락" }
            return
        }
        let frame = (metadata[frameKey] as? Int) ?? 0

        #if canImport(UIKit)
        if let data = try? Data(contentsOf: file.fileURL),
           let img = UIImage(data: data) {
            Task { @MainActor in
                CharacterImageStore.save(img, for: state, frame: frame)
                self.lastReceivedImageState = stateRaw
                self.characterImageVersion &+= 1

                // 컴플리케이션이 SharedAppState 메시지에 의존하니까, 사진 받자마자
                // 마지막 메시지의 timestamp 만 새로 써서 강제로 trigger.
                // 이게 없으면 iOS 의 force resend (applicationContext) 가 file transfer
                // 와 다른 채널이라 타이밍 차이로 컴플리케이션이 옛 state 그대로일 수 있음.
                if let last = SharedAppState.loadMessage() {
                    let refreshed = WatchMessage(
                        state: last.state,
                        todaySteps: last.todaySteps,
                        lastSleepHours: last.lastSleepHours,
                        todayActiveMinutes: last.todayActiveMinutes,
                        todayActiveKcal: last.todayActiveKcal,
                        weatherEmoji: last.weatherEmoji,
                        weatherTempC: last.weatherTempC,
                        weatherSunrise: last.weatherSunrise,
                        weatherSunset: last.weatherSunset,
                        timestamp: Date()
                    )
                    SharedAppState.save(refreshed)
                }

                WidgetCenter.shared.reloadAllTimelines()
                // kind 별 명시적 reload — 시스템이 reloadAllTimelines 무시하는 케이스 대비
                WidgetCenter.shared.reloadTimelines(ofKind: "withuComplication")
                self.lastComplicationReloadAt = Date()
            }
        } else {
            Task { @MainActor in self.lastError = "수신 파일 디코드 실패" }
        }
        #endif
    }
}
