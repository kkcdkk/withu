//
//  NotificationManager.swift
//  withu (iOS)
//

import Foundation
import UserNotifications

/// 캐릭터 앱의 로컬 알림 매니저.
/// iOS 가 발송한 알림은 페어드 워치에도 자동 전달됨 (Apple 의 기본 동작).
@Observable
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var lastError: String?

    /// 생성 완료/기준 모습 알림을 탭함 — ContentView 가 관찰해 배치 화면으로 이동 후 false 로 리셋.
    var wantsOpenGenerationScreen: Bool = false

    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    // 같은 종류의 알림이 도배되지 않게 식별자를 고정
    private enum ID {
        static let stepGoal = "withu.notification.stepGoal"
        static let bedtime  = "withu.notification.bedtime"
        static let workoutEnded = "withu.notification.workoutEnded"
        static let generationDone = "withu.notification.generationDone"
        static let generationAnchor = "withu.notification.generationAnchor"
    }

    /// 걸음 수 목표 (이 값 이상이면 한 번 축하 알림)
    @ObservationIgnored private let stepGoal: Double = 8000

    private init() {}

    // MARK: - 권한

    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            if !granted { lastError = String(localized: "사용자가 알림을 허용하지 않았어요.") }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    // MARK: - 트리거들

    /// 오늘 걸음이 목표를 넘었으면 축하 알림 (당일 1회만).
    /// 이미 오늘 보냈으면 무시.
    // MARK: - 캐릭터 호칭

    /// 알림에서 '캐릭터' 대신 쓸 이름 — '내 캐릭터 설정'의 이름 기준.
    /// 기본값("내 캐릭터")이면 이름을 안 지은 것으로 보고 nil.
    private var characterName: String? {
        let n = CharacterProfileStore.load().name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (n.isEmpty || n == "내 캐릭터") ? nil : n
    }

    /// 이름 끝 받침 유무에 따라 조사를 붙인다.
    ///   받침 있음: 하늘 → 하늘이가 / 하늘이도
    ///   받침 없음: 코코 → 코코가 / 코코도
    /// 이름이 없으면 "캐릭터가" / "캐릭터도".
    private func subject(_ particle: NameParticle) -> String {
        guard let name = characterName else {
            return particle == .subject ? String(localized: "캐릭터가") : String(localized: "캐릭터도")
        }
        let hasFinalConsonant: Bool = {
            guard let u = name.unicodeScalars.last?.value,
                  (0xAC00...0xD7A3).contains(u) else { return false }   // 한글 음절만 판정
            return (u - 0xAC00) % 28 != 0
        }()
        switch particle {
        case .subject: return name + (hasFinalConsonant ? "이가" : "가")
        case .also:    return name + (hasFinalConsonant ? "이도" : "도")
        }
    }

    private enum NameParticle { case subject, also }

    func scheduleStepGoalIfNeeded(steps: Double) async {
        guard steps >= stepGoal else { return }
        guard !alreadySentToday(key: ID.stepGoal) else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "🎉 \(Int(stepGoal))보 달성!")
        content.body = String(localized: "오늘 \(Int(steps))보 걸었어요. \(subject(.also)) 신났어요 ✨")
        content.sound = .default

        await schedule(id: ID.stepGoal, content: content, in: 1)
        markSentToday(key: ID.stepGoal)
    }

    /// 매일 정해진 시각에 취침 리마인더 (반복).
    /// 같은 식별자로 add 하면 OS 가 알아서 교체.
    func scheduleBedtimeReminder(hour: Int = 22, minute: Int = 30) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "💤 잘 시간이에요")
        content.body = String(localized: "오늘도 수고했어요. \(subject(.subject)) 같이 잘 준비 중이에요.")
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(identifier: ID.bedtime, content: content, trigger: trigger)
        do {
            try await center.add(request)
            lastError = nil   // 성공 — 설정 화면이 lastError 로 성공/실패를 구분한다
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 최근 워크아웃이 방금 끝났으면 격려 알림.
    func scheduleWorkoutEndedIfNeeded(latest: WorkoutSummary?) async {
        guard let w = latest else { return }
        let endedAt = w.start.addingTimeInterval(w.duration)
        guard Date().timeIntervalSince(endedAt) < 10 * 60 else { return }  // 끝난 지 10분 이내
        guard !alreadySent(key: ID.workoutEnded + ".\(w.start.timeIntervalSince1970)") else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(w.activity.displayName) 끝!")
        content.body = String(localized: "\(formatDuration(w.duration)) 동안 잘 움직였어요. \(subject(.also)) 함께 뛰었어요.")
        content.sound = .default

        await schedule(id: ID.workoutEnded, content: content, in: 1)
        markSent(key: ID.workoutEnded + ".\(w.start.timeIntervalSince1970)")
    }

    /// 백그라운드 배치 생성이 다 끝났을 때 (BackgroundGenerationManager 가 호출).
    func notifyGenerationFinished(done: Int, failed: Int) async {
        let content = UNMutableNotificationContent()
        if failed == 0 {
            content.title = String(localized: "캐릭터를 다 만들었어요")
            content.body = String(localized: "\(done)개 모습이 완성돼 바로 적용됐어요. 열어서 확인해 보세요.")
        } else {
            content.title = String(localized: "캐릭터 생성이 끝났어요")
            content.body = String(localized: "\(done)개 완성, \(failed)개는 못 만들었어요. 앱에서 다시 시도할 수 있어요.")
        }
        content.sound = .default
        await schedule(id: ID.generationDone, content: content, in: 1)
    }

    /// 기준(idle) 모습이 완성돼 승인을 기다릴 때.
    func notifyAnchorReady() async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "기준 모습이 준비됐어요")
        content.body = String(localized: "마음에 드는지 확인하고 나머지 모습을 이어서 만들어 보세요.")
        content.sound = .default
        await schedule(id: ID.generationAnchor, content: content, in: 1)
    }

    /// 등록된 보류 중 알림 다 취소.
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - 내부

    private func schedule(id: String, content: UNMutableNotificationContent, in seconds: TimeInterval) async {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        return String(localized: "\(m)분")
    }

    // MARK: - 중복 방지 (간단한 UserDefaults 마커)

    private func alreadySentToday(key: String) -> Bool {
        let day = Calendar.current.startOfDay(for: Date())
        let saved = UserDefaults.standard.double(forKey: key)
        return saved == day.timeIntervalSince1970
    }

    private func markSentToday(key: String) {
        let day = Calendar.current.startOfDay(for: Date())
        UserDefaults.standard.set(day.timeIntervalSince1970, forKey: key)
    }

    private func alreadySent(key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    private func markSent(key: String) {
        UserDefaults.standard.set(true, forKey: key)
    }
}

/// 알림 탭/표시 처리 delegate — AppDelegate 가 launch 직후 등록 (cold start 탭도 받기 위해).
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// 생성 관련 알림을 탭하면 만들어진 화면(배치)으로 이동.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        if id == "withu.notification.generationDone" || id == "withu.notification.generationAnchor" {
            await MainActor.run {
                NotificationManager.shared.wantsOpenGenerationScreen = true
            }
        }
    }

    /// 앱이 켜져 있는 동안에도 배너로 표시 (기본은 무표시라 완료를 놓침).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
