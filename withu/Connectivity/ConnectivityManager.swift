//
//  ConnectivityManager.swift  (iOS side — sender)
//  withu
//

import Foundation
import WatchConnectivity
import UIKit

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
    /// 캐릭터 이미지 전송 진행 / 결과 (디버그용)
    private(set) var lastImageTransferState: String?
    /// 큐에 대기 중인 file transfer 개수
    private(set) var outstandingTransfers: Int = 0

    // stored property default 에서 WCSession.default 호출하면 init 시점이 main actor
    // 보장 안 돼서 iOS 26 strict concurrency 가 trap 시킬 가능성. lazy 로 옮김.
    @ObservationIgnored private var session: WCSession?

    // 마지막으로 보낸 메시지를 기억해두고 같으면 안 보냄 (중복 트래픽 방지)
    @ObservationIgnored private var lastSentMessage: WatchMessage?

    /// 캐릭터 이미지 파일 전송 시 metadata 키 — 워치 쪽이 어느 state 의 이미지인지 알 수 있게.
    static let characterImageMetadataKey = "withu.characterImage.state"

    private override init() { super.init() }

    func activate() {
        // main actor 안에서 lazy 초기화 — main actor 보장 = strict concurrency safe.
        if session == nil {
            session = WCSession.isSupported() ? WCSession.default : nil
        }
        guard let session else {
            lastError = "WCSession 미지원 (iPad?)"
            return
        }
        session.delegate = self
        session.activate()
    }

    /// 워치 전송용 다운샘플 크기 (px). 워치 컴플리케이션 + 메인 화면이 모두 작아서
    /// 100 이면 충분. 원본 1024×1024 (~4MB) → 100×100 (~40KB) 로 압축.
    private static let watchImageMaxPixelSize: CGFloat = 100

    /// 사용자가 적용한 캐릭터 이미지를 워치로 전송 (file transfer).
    /// 다운샘플링 후 보내서 워치 메모리 + 네트워크 부담 최소화.
    func sendCharacterImage(_ image: UIImage, for state: CharacterState) {
        guard let session else {
            lastImageTransferState = "❌ WCSession 미지원"
            return
        }
        guard session.activationState == .activated else {
            lastImageTransferState = "❌ WCSession 활성화 안 됨"
            return
        }
        guard session.isPaired else {
            lastImageTransferState = "❌ 워치 페어링 안 됨"
            return
        }
        guard session.isWatchAppInstalled else {
            lastImageTransferState = "❌ 워치 앱 설치 안 됨"
            return
        }
        let resized = Self.downsampled(image, maxPixelSize: Self.watchImageMaxPixelSize)
        guard let data = resized.pngData() else {
            lastImageTransferState = "❌ PNG 인코딩 실패"
            return
        }
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("character_\(state.rawValue)_\(UUID().uuidString).png")
        do {
            try data.write(to: tmpURL, options: .atomic)
            session.transferFile(
                tmpURL,
                metadata: [Self.characterImageMetadataKey: state.rawValue]
            )
            lastImageTransferState = "📤 \(state.rawValue) 전송 시작 (\(data.count / 1024)KB)"
            outstandingTransfers = session.outstandingFileTransfers.count

            // 컴플리케이션이 SharedAppState 메시지로 state 를 결정하니까,
            // 사진 보낼 때 마지막 메시지도 timestamp 만 갱신해서 강제 재전송 →
            // 워치 SharedAppState 가 trigger 되고 WidgetCenter reload 가 효과 봄.
            if let last = lastSentMessage {
                let refreshed = WatchMessage(
                    state: last.state,
                    todaySteps: last.todaySteps,
                    lastSleepHours: last.lastSleepHours,
                    todayActiveMinutes: last.todayActiveMinutes,
                    todayActiveKcal: last.todayActiveKcal,
                    weatherEmoji: last.weatherEmoji,
                    weatherTempC: last.weatherTempC,
                    timestamp: Date()
                )
                if let encoded = try? JSONEncoder().encode(refreshed) {
                    try? session.updateApplicationContext([WatchMessage.payloadKey: encoded])
                    lastSentMessage = refreshed
                }
            }
        } catch {
            lastImageTransferState = "❌ 파일 쓰기 실패: \(error.localizedDescription)"
        }
    }

    /// UIImage 다운샘플링. Apple 의 `preparingThumbnail` API 사용 — iOS 15+,
    /// alpha 채널 유지, 안전. (직접 CGContext 다루는 것보다 crash 위험 낮음)
    private static func downsampled(_ image: UIImage, maxPixelSize: CGFloat) -> UIImage {
        let originalSize = image.size
        let maxDim = max(originalSize.width, originalSize.height)
        guard maxDim > 0, maxDim > maxPixelSize else { return image }

        let scale = maxPixelSize / maxDim
        let targetSize = CGSize(width: originalSize.width * scale,
                                height: originalSize.height * scale)
        return image.preparingThumbnail(of: targetSize) ?? image
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
