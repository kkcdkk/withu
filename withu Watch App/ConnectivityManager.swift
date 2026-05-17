//
//  ConnectivityManager.swift  (watchOS side — receiver)
//  withu Watch App
//

import Foundation
import WatchConnectivity
import WidgetKit

/// 워치 쪽 WCSession 매니저. iPhone 에서 보낸 캐릭터 메시지를 받음.
@Observable
@MainActor
final class ConnectivityManager: NSObject {
    static let shared = ConnectivityManager()

    private(set) var lastMessage: WatchMessage?
    private(set) var lastReceivedAt: Date?
    private(set) var lastError: String?
    private(set) var activationState: WCSessionActivationState = .notActivated

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
}
