//
//  ConnectivityManager.swift  (iOS side — sender)
//  withu
//

import Foundation
import WatchConnectivity
import UIKit
import WidgetKit
import Intents
import AppIntents

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
    /// 이번 앱 launch 동안 초기 sync (모든 캐릭터/배경 일괄 전송) 한 적 있는지.
    /// 워치 앱이 새로 설치된 직후 / iPhone 앱 첫 실행 시 1회만 수행.
    @ObservationIgnored private var hasInitialSyncedThisLaunch: Bool = false

    /// 캐릭터 이미지 파일 전송 시 metadata 키 — 워치 쪽이 어느 state 의 이미지인지 알 수 있게.
    static let characterImageMetadataKey = "withu.characterImage.state"
    /// 애니메이션 frame index metadata (0/1)
    static let characterFrameMetadataKey = "withu.characterImage.frame"
    /// 날씨 배경 이미지 파일 transfer 시 metadata 키 — 워치 쪽이 어느 condition 인지 알 수 있게.
    static let weatherBackgroundMetadataKey = "withu.weatherBackground.condition"

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

    /// 모든 캐릭터 이미지 + 날씨 배경을 워치로 일괄 전송.
    /// 사용 시점:
    ///   1) 워치 앱이 새로 설치된 시점 (sessionWatchStateDidChange — 자동)
    ///   2) iPhone 앱 첫 실행 시 워치가 이미 연결돼 있으면 (activate — 자동)
    ///   3) Settings → 고급/진단 → "워치로 다시 동기화" (수동)
    func sendAllToWatch() {
        for state in CharacterState.userFacing {
            if let img = CharacterImageStore.load(state) {
                sendCharacterImage(img, for: state, frame: 0)
            }
            if CharacterImageStore.hasAnimationFrames(for: state),
               let img1 = CharacterImageStore.loadFrame(state, frame: 1) {
                sendCharacterImage(img1, for: state, frame: 1)
            }
        }
        for cond in WeatherBackgroundCondition.allCases {
            if let img = CharacterImageStore.loadBackground(cond) {
                sendWeatherBackground(img, for: cond)
            }
        }
    }

    /// 한 launch 당 1회만 자동 sync. 자동 트리거 (activate / state change) 에서 사용.
    func triggerInitialSyncIfNeeded() {
        guard !hasInitialSyncedThisLaunch,
              let session,
              session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else { return }
        hasInitialSyncedThisLaunch = true
        sendAllToWatch()
    }

    /// 사용자가 적용한 캐릭터 이미지를 워치로 전송 (file transfer).
    /// 다운샘플링 후 보내서 워치 메모리 + 네트워크 부담 최소화.
    /// frame 0 = 기본 / frame 1 = 애니메이션 frame.
    func sendCharacterImage(_ image: UIImage, for state: CharacterState, frame: Int = 0) {
        guard let session else {
            lastImageTransferState = "이 기기에선 Apple Watch 연동을 쓸 수 없어요."
            return
        }
        guard session.activationState == .activated else {
            lastImageTransferState = "Apple Watch 연결을 준비 중이에요. 잠시 후 다시 시도해 주세요."
            return
        }
        guard session.isPaired else {
            lastImageTransferState = "Apple Watch 가 페어링돼 있지 않아요."
            return
        }
        guard session.isWatchAppInstalled else {
            lastImageTransferState = "Apple Watch 에 withu 앱이 설치돼 있지 않아요."
            return
        }
        let resized = Self.downsampled(image, maxPixelSize: Self.watchImageMaxPixelSize)
        guard let data = resized.pngData() else {
            lastImageTransferState = "이미지 변환에 실패했어요. 다시 시도해 주세요."
            return
        }
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("character_\(state.rawValue)_\(UUID().uuidString).png")
        do {
            try data.write(to: tmpURL, options: .atomic)
            session.transferFile(
                tmpURL,
                metadata: [
                    Self.characterImageMetadataKey: state.rawValue,
                    Self.characterFrameMetadataKey: frame
                ]
            )
            lastImageTransferState = "워치로 \(state.rawValue) 전송 중 (\(data.count / 1024)KB)"
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
            lastImageTransferState = "워치 전송 준비에 실패했어요. 다시 시도해 주세요."
        }
    }

    /// 날씨 배경 이미지를 워치로 전송 (file transfer). 캐릭터와 별도 metadata key.
    /// 워치 쪽 background storage 에 저장됨.
    func sendWeatherBackground(_ image: UIImage, for cond: WeatherBackgroundCondition) {
        guard let session,
              session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else { return }
        // 워치 화면 ~ 410px 이내라 256 정도면 충분. 더 작게 200 으로 다운샘플.
        let resized = Self.downsampled(image, maxPixelSize: 200)
        guard let data = resized.pngData() else {
            lastImageTransferState = "배경 이미지 변환에 실패했어요."
            return
        }
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bg_\(cond.rawValue)_\(UUID().uuidString).png")
        do {
            try data.write(to: tmpURL, options: .atomic)
            session.transferFile(
                tmpURL,
                metadata: [Self.weatherBackgroundMetadataKey: cond.rawValue]
            )
            lastImageTransferState = "워치로 \(cond.rawValue) 배경 전송 중 (\(data.count / 1024)KB)"
            outstandingTransfers = session.outstandingFileTransfers.count
        } catch {
            lastImageTransferState = "배경 전송 준비에 실패했어요. 다시 시도해 주세요."
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
            // 활성화 직후 워치가 이미 연결돼 있으면 초기 sync (앱 launch 당 1회).
            self.triggerInitialSyncIfNeeded()
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
            let wasInstalled = self.isWatchAppInstalled
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            // 워치 앱이 새로 설치됨 → 모든 캐릭터/배경 자동 전송.
            // hasInitialSyncedThisLaunch flag 가 있으니 중복 호출 안전.
            if !wasInstalled && session.isWatchAppInstalled {
                // 신규 설치 케이스는 무조건 한 번 더 — 위 flag 가 이미 true 라도.
                self.hasInitialSyncedThisLaunch = false
                self.triggerInitialSyncIfNeeded()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }
}

// MARK: - FocusModeManager

/// iOS Focus (수면 모드 / 업무 모드 등) 활성 여부 감지.
///
/// ⚠️ API 제약:
/// - `INFocusStatusCenter.focusStatus.isFocused` 는 **Bool 만 반환**.
///   Sleep Focus 와 다른 Focus 를 구별 못 함.
/// - iOS 가 Focus 변화를 push 알림으로 안 줌 → polling. App launch /
///   foreground 진입 / HealthKit observer fire 시점에 `refresh()` 호출.
/// - 권한이 필요 (`NSFocusStatusUsageDescription` + 사용자 허용).
@Observable
@MainActor
final class FocusModeManager {
    static let shared = FocusModeManager()

    /// App Group UserDefaults 의 Focus Filter 강제 sleeping 플래그 키.
    /// SleepFocusFilterIntent.perform() 이 set, 우리가 read.
    static let focusFilterSleepingKey = "withu.focusFilter.forceSleeping"
    /// 진단용 — perform() 이 마지막 호출된 시각.
    static let focusFilterLastPerformKey = "withu.focusFilter.lastPerformAt"
    /// 진단용 — perform() 호출 이력 (최근 10번). iOS throttling 진단에 사용.
    /// 저장 포맷: "1731234567.0|true,1731234580.0|false,..." 의 string.
    static let focusFilterPerformLogKey = "withu.focusFilter.performLog"
    static let focusFilterPerformLogLimit = 10

    private(set) var isAuthorized: Bool = false
    /// 사용 가능한 actionable bool — resolver 가 보는 값. nil 일 땐 false 로 fallback.
    private(set) var isFocused: Bool = false
    /// iOS 가 진짜로 돌려준 raw 값. nil 의 의미가 중요해서 (= 공유 OFF) 따로 보관.
    private(set) var rawFocusedValue: Bool?
    /// SetFocusFilterIntent 이 iOS 가 푸시한 신호 — Focus 상태 공유 권한 무관.
    /// 사용자가 Settings → Focus → Sleep → 필터 추가 → withu 연결해야 동작.
    private(set) var isFocusFilterSleeping: Bool = false
    /// perform() 이 마지막으로 호출된 시각 — manual setup 이 됐는지 / Focus 가 토글된 적 있는지 진단.
    private(set) var focusFilterLastPerformAt: Date?
    /// perform() 호출 이력 (최근 N번, 최신 우선). iOS throttling 진단용.
    private(set) var focusFilterPerformLog: [(date: Date, sleeping: Bool)] = []
    private(set) var lastCheckedAt: Date?

    private init() {}

    /// 권한 요청. 처음 호출하면 시스템 시트 1회 노출. 이후 호출은 즉시 status 갱신.
    func requestAuthorization() async {
        let status = await INFocusStatusCenter.default.requestAuthorization()
        isAuthorized = (status == .authorized)
        refresh()
    }

    /// 현재 Focus 상태 즉시 폴링. INFocusStatusCenter + App Group 의 Focus Filter 플래그 둘 다 갱신.
    func refresh() {
        // 1) INFocusStatusCenter (제약 많음 — "Focus 상태 공유" 토글 필요)
        let status = INFocusStatusCenter.default.authorizationStatus
        isAuthorized = (status == .authorized)
        if isAuthorized {
            let raw = INFocusStatusCenter.default.focusStatus.isFocused
            rawFocusedValue = raw
            isFocused = raw ?? false
        } else {
            rawFocusedValue = nil
            isFocused = false
        }

        // 2) SetFocusFilterIntent 가 저장한 App Group 플래그 (신뢰성 ↑, 사용자가 한 번 연결 필요)
        let defaults = UserDefaults(suiteName: SharedAppState.groupID)
        isFocusFilterSleeping = defaults?.bool(forKey: Self.focusFilterSleepingKey) ?? false
        focusFilterLastPerformAt = defaults?.object(forKey: Self.focusFilterLastPerformKey) as? Date
        // perform 로그 디코드 (newest first)
        let logString = defaults?.string(forKey: Self.focusFilterPerformLogKey) ?? ""
        focusFilterPerformLog = logString.split(separator: ",").compactMap { entry in
            let parts = entry.split(separator: "|")
            guard parts.count == 2,
                  let ts = Double(parts[0]) else { return nil }
            return (date: Date(timeIntervalSince1970: ts), sleeping: parts[1] == "true")
        }

        lastCheckedAt = Date()
    }

    /// SleepFocusFilterIntent.perform() 가 호출. 로그에 1줄 추가 (최신 우선, 10개 제한).
    /// UserDefaults 만 건드려서 thread-safe — main actor 격리 불필요.
    nonisolated static func appendPerformLog(sleeping: Bool, date: Date = Date()) {
        let defaults = UserDefaults(suiteName: SharedAppState.groupID)
        let existing = defaults?.string(forKey: focusFilterPerformLogKey) ?? ""
        let newEntry = "\(date.timeIntervalSince1970)|\(sleeping)"
        let combined: String
        if existing.isEmpty {
            combined = newEntry
        } else {
            let parts = ([newEntry] + existing.split(separator: ",").map(String.init))
                .prefix(focusFilterPerformLogLimit)
            combined = parts.joined(separator: ",")
        }
        defaults?.set(combined, forKey: focusFilterPerformLogKey)
    }

    /// 현재 권한 상태 한국어 라벨 (디버그 UI 용).
    var authorizationStatusLabel: String {
        switch INFocusStatusCenter.default.authorizationStatus {
        case .notDetermined: return "미요청"
        case .restricted:    return "제한됨"
        case .denied:        return "거부됨"
        case .authorized:    return "허용됨"
        @unknown default:    return "?"
        }
    }

    /// 현재 Focus 상태를 사용자 친화적으로 표현. nil/true/false 세 케이스 구별.
    var focusStateLabel: String {
        guard isAuthorized else { return "— (권한 없음)" }
        switch rawFocusedValue {
        case .none:          return "❓ 공유 OFF"   // 권한 O 이지만 iOS 가 nil 반환 = Focus 별 "공유" 토글 OFF
        case .some(true):    return "✅ 활성"
        case .some(false):   return "— 비활성"
        }
    }
}

// MARK: - SyncCoordinator

/// 현재 HealthKit / Weather / Profile / Focus 상태로 WatchMessage 하나 만들어
/// 세 군데로 동시 push:
///   1) SharedAppState — 위젯/컴플리케이션이 읽는 App Group UserDefaults
///   2) WidgetCenter.reloadAllTimelines — iOS 위젯 즉시 갱신
///   3) ConnectivityManager.send — 워치로 push
///
/// HealthKit observer 가 background 에서 fetch 한 뒤 이 함수만 부르면 됨.
/// 이게 없을 때는 observer 가 WidgetCenter.reload 만 호출해서 SharedAppState
/// 옛 데이터로 위젯이 reload → 화면 그대로인 버그.
@MainActor
enum SyncCoordinator {
    static func syncNow(override: CharacterState? = nil) {
        let health = HealthKitManager.shared
        let weather = WeatherManager.shared
        let focus = FocusModeManager.shared
        let profile = CharacterProfileStore.load()

        // Focus 는 push 알림이 안 와서 매번 폴링.
        focus.refresh()

        // 프로필이 "자동 감지 끔" 이면 Focus + HealthKit inBed 무시,
        // 프로필 sleepStart/End 시간만 fallback 으로 사용.
        let manualOnly = profile.manualSleepOnly ?? false
        // INFocusStatusCenter (제약多) OR Focus Filter Intent (신뢰성↑) — 둘 중 하나라도 활성이면 sleeping.
        let focusEither = focus.isFocused || focus.isFocusFilterSleeping
        let isFocusActive = manualOnly ? false : focusEither
        let inSleepSchedule = manualOnly ? false : health.isInBedSchedule
        let hasSleepSchedule = manualOnly ? false : health.hasSleepSchedule

        let state = override ?? CharacterStateResolver.resolve(
            sleep: health.sleep,
            workouts: health.recentWorkouts,
            todaySteps: health.todaySteps,
            weather: weather.snapshot,
            inSleepSchedule: inSleepSchedule,
            hasSleepSchedule: hasSleepSchedule,
            isFocusActive: isFocusActive,
            isLikelyInWorkout: health.isLikelyInWorkout,
            profile: profile
        )

        let msg = WatchMessage(
            state: state,
            todaySteps: health.todaySteps,
            lastSleepHours: health.sleep.map { $0.totalAsleep / 3600 },
            todayActiveMinutes: health.todayActiveMinutes,
            todayActiveKcal: health.todayActiveKcal,
            weatherEmoji: weather.snapshot?.condition.emoji,
            weatherTempC: weather.snapshot?.temperatureC,
            timestamp: Date()
        )

        SharedAppState.save(msg)
        WidgetCenter.shared.reloadAllTimelines()
        ConnectivityManager.shared.send(msg)
    }
}

// MARK: - SleepFocusFilterIntent (iOS 16+ SetFocusFilterIntent)

/// iOS 가 Focus 모드 on/off 시점에 우리 앱의 perform() 을 직접 호출.
/// INFocusStatusCenter 폴링과 달리 push 방식이라 누락/지연 없음.
///
/// 사용자 manual setup 필요 (한 번):
///   iOS 설정 → 집중 모드 → 수면 → "필터 추가" → withu 선택
///   → "캐릭터를 자게 하기" 토글 ON → 완료
///
/// 이후 Sleep Focus on/off 마다 iOS 가 백그라운드에서 perform() 호출.
@available(iOS 16.0, *)
struct SleepFocusFilterIntent: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "withu 캐릭터 상태 변경"
    static var description: IntentDescription? = IntentDescription(
        "집중 모드가 켜질 때 withu 캐릭터를 자는 모습으로 바꿔요."
    )

    /// ⚠ Default 는 반드시 false — Focus OFF 시 iOS 가 perform() 을 default 값으로 다시 호출함.
    /// default=true 면 OFF 후에도 sleeping push 가 영원히 유지되는 버그.
    /// 사용자가 필터 설정 화면에서 toggle 을 켜야 ON 시 true 가 전달됨.
    @Parameter(title: "캐릭터를 자게 하기", default: false)
    var setSleeping: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("집중 모드일 때 캐릭터를 자게 하기: \(\.$setSleeping)")
    }

    /// 사용자가 설정 화면에서 이 필터 인스턴스를 봤을 때 표시될 라벨.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: setSleeping ? "캐릭터를 자게 하기" : "그대로 두기")
    }

    func perform() async throws -> some IntentResult {
        // App Group 에 플래그 + 호출 시각 + 호출 로그 저장 — FocusModeManager 가 refresh() 시 읽음.
        let now = Date()
        let defaults = UserDefaults(suiteName: SharedAppState.groupID)
        defaults?.set(setSleeping, forKey: FocusModeManager.focusFilterSleepingKey)
        defaults?.set(now, forKey: FocusModeManager.focusFilterLastPerformKey)
        FocusModeManager.appendPerformLog(sleeping: setSleeping, date: now)

        // 위젯/워치 즉시 갱신. 메인 앱이 잠들어 있어도 SyncCoordinator 가 깨워 처리.
        await MainActor.run {
            FocusModeManager.shared.refresh()
            SyncCoordinator.syncNow()
        }

        return .result()
    }
}
