//
//  ConnectivityManager.swift  (iOS side — sender)
//  withu
//

import Foundation
import WatchConnectivity

/// iPhone 에서 watch 로 캐릭터 상태를 보내는 매니저.
/// `updateApplicationContext` 를 써서 "마지막 값" 동기화. 두 디바이스가 동시에
/// reachable 하지 않아도 다음에 워치가 켜질 때 최신 상태가 적용됨.
@Observable
@MainActor
final class ConnectivityManager: NSObject {
    static let shared = ConnectivityManager()

    private(set) var isPaired: Bool = false
    private(set) var isWatchAppInstalled: Bool = false
    private(set) var isReachable: Bool = false
    private(set) var lastSentAt: Date?
    private(set) var lastError: String?
    private(set) var activationState: WCSessionActivationState = .notActivated

    @ObservationIgnored private let session: WCSession? =
        WCSession.isSupported() ? WCSession.default : nil

    // 마지막으로 보낸 메시지를 기억해두고 같으면 안 보냄 (중복 트래픽 방지)
    @ObservationIgnored private var lastSentMessage: WatchMessage?

    private override init() { super.init() }

    func activate() {
        guard let session else {
            lastError = "WCSession 미지원 (iPad?)"
            return
        }
        session.delegate = self
        session.activate()
    }

    /// 캐릭터 상태 메시지를 워치로 전송.
    /// 이전과 동일한 메시지면 skip.
    func send(_ message: WatchMessage) {
        guard let session, session.activationState == .activated else {
            lastError = "WCSession 활성화 안 됨"
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else {
            // 페어링/설치 안 돼 있어도 에러 아님 — 그냥 받을 사람이 없을 뿐
            return
        }
        if lastSentMessage == message { return }

        do {
            let data = try JSONEncoder().encode(message)
            try session.updateApplicationContext([WatchMessage.payloadKey: data])
            lastSentMessage = message
            lastSentAt = Date()
            lastError = nil
        } catch {
            lastError = "전송 실패: \(error.localizedDescription)"
        }
    }
}

// MARK: - WCSessionDelegate

extension ConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            self.activationState = activationState
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable
            if let error { self.lastError = error.localizedDescription }
        }
    }

    // iOS 전용 콜백 (watchOS 엔 없음)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // 새 워치로 페어링 가능성 → 재활성화
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }
}
