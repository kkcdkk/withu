//
//  SharedAppState.swift
//  withu (Shared: iOS app + Watch app + Widget extension)
//
//  Target Membership 을 세 타겟 모두 (withu, withu Watch App, withuComplication)
//  체크해야 함.
//

import Foundation

/// App Group UserDefaults 를 감싸는 얇은 헬퍼.
/// 메인 앱과 위젯 extension 이 같은 컨테이너를 통해 캐릭터 상태를 공유.
enum SharedAppState {
    /// Xcode 의 Capabilities → App Groups 에서 등록한 그룹 ID 와 일치해야 함.
    static let groupID = "group.com.seoyoung.withu"

    private static let messageKey = "withu.currentMessage.v1"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: groupID)
    }

    /// 받은 WatchMessage 를 App Group 에 저장.
    /// 저장 후 위젯에 timeline reload 알리는 책임은 caller 가 짐.
    static func save(_ message: WatchMessage) {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(message) {
            defaults.set(data, forKey: messageKey)
        }
    }

    /// 위젯이 호출. 저장된 마지막 메시지 (없으면 nil).
    static func loadMessage() -> WatchMessage? {
        guard let defaults,
              let data = defaults.data(forKey: messageKey) else { return nil }
        return try? JSONDecoder().decode(WatchMessage.self, from: data)
    }
}
