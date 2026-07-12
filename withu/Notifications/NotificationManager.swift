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
            if !granted { lastError = "사용자가 알림을 허용하지 않았어요." }
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
    func scheduleStepGoalIfNeeded(steps: Double) async {
        guard steps >= stepGoal else { return }
        guard !alreadySentToday(key: ID.stepGoal) else { return }

        let content = UNMutableNotificationContent()
        content.title = "🎉 \(Int(stepGoal))보 달성!"
        content.body = "오늘 \(Int(steps))보 걸었어요. 캐릭터도 신났어요 ✨"
        content.sound = .default

        await schedule(id: ID.stepGoal, content: content, in: 1)
        markSentToday(key: ID.stepGoal)
    }

    /// 매일 정해진 시각에 취침 리마인더 (반복).
    /// 같은 식별자로 add 하면 OS 가 알아서 교체.
    func scheduleBedtimeReminder(hour: Int = 22, minute: Int = 30) async {
        let content = UNMutableNotificationContent()
        content.title = "💤 잘 시간이에요"
        content.body = "오늘도 수고했어요. 캐릭터가 같이 잘 준비 중이에요."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(identifier: ID.bedtime, content: content, trigger: trigger)
        do {
            try await center.add(request)
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
        content.title = "\(w.activity.displayName) 끝!"
        content.body = "\(formatDuration(w.duration)) 동안 잘 움직였어요. 캐릭터도 함께 뛰었어요."
        content.sound = .default

        await schedule(id: ID.workoutEnded, content: content, in: 1)
        markSent(key: ID.workoutEnded + ".\(w.start.timeIntervalSince1970)")
    }

    /// 백그라운드 배치 생성이 다 끝났을 때 (BackgroundGenerationManager 가 호출).
    func notifyGenerationFinished(done: Int, failed: Int) async {
        let content = UNMutableNotificationContent()
        if failed == 0 {
            content.title = "캐릭터를 다 만들었어요"
            content.body = "\(done)개 모습이 완성돼 바로 적용됐어요. 열어서 확인해 보세요."
        } else {
            content.title = "캐릭터 생성이 끝났어요"
            content.body = "\(done)개 완성, \(failed)개는 못 만들었어요. 앱에서 다시 시도할 수 있어요."
        }
        content.sound = .default
        await schedule(id: ID.generationDone, content: content, in: 1)
    }

    /// 기준(idle) 모습이 완성돼 승인을 기다릴 때.
    func notifyAnchorReady() async {
        let content = UNMutableNotificationContent()
        content.title = "기준 모습이 준비됐어요"
        content.body = "마음에 드는지 확인하고 나머지 모습을 이어서 만들어 보세요."
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
        return "\(m)분"
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
