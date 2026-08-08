//
//  FocusSignalLog.swift
//  withu (iOS 앱 타깃 전용)
//
//  수면/집중 모드 신호 모니터 — "수동으로 켤 땐 되는데 예약(자동)으로 켜지면 안 잔다" 를
//  기기에서 밤새 찍어서 확정하기 위한 기록.
//
//  iOS 시뮬레이터에는 집중 모드 자체가 없어(설정 화면·데몬 없음) 재현이 불가능하다.
//  그래서 실기기에서 아래 3가지를 시각과 함께 남기고, 진단 화면에서 복사해 비교한다:
//    · 수면 필터 intent 가 실제로 불렸는지 (예약 전환 때도 불리는지)
//    · 그 시점 INFocusStatusCenter 가 뭐라고 답했는지
//    · HealthKit inBed(수면 일정) 신호가 있었는지
//

import Foundation

enum FocusSignalLog {
    /// 한 시점의 신호 스냅샷.
    struct Entry: Codable, Identifiable {
        var id: Date { t }
        let t: Date
        /// 이 기록을 남긴 계기 (앱 실행 / 앱 열림 / 백그라운드 갱신 / 폴링 / 수면필터)
        let src: String
        /// INFocusStatusCenter: 1 = 켜짐, 0 = 꺼짐, -1 = 공유 꺼짐/권한 없음(nil)
        let focusRaw: Int
        /// 수면 필터 intent 가 마지막으로 남긴 플래그
        let filter: Bool
        /// HealthKit inBed/asleep 샘플이 '지금'을 덮고 있는지
        let inBed: Bool

        var focusLabel: String {
            switch focusRaw {
            case 1:  return "켜짐"
            case 0:  return "꺼짐"
            default: return "공유꺼짐"
            }
        }
    }

    private static let key = "withu.focusSignalLog.v1"
    private static let limit = 300

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedAppState.groupID)
    }

    /// 신호 스냅샷 기록.
    /// 3초 폴링이 로그를 덮지 않게, **값이 바뀐 순간**과 push 성 이벤트(수면필터)만 남긴다.
    /// (값이 그대로여도 1시간에 한 번은 '살아있음' 기록을 남겨 공백 구간과 구분)
    static func record(source src: String, focusRaw: Bool?, filter: Bool, inBed: Bool,
                       now: Date = Date()) {
        let raw = focusRaw.map { $0 ? 1 : 0 } ?? -1
        var all = load()
        if let last = all.last {
            let sameSignals = last.focusRaw == raw && last.filter == filter && last.inBed == inBed
            let isPush = src.hasPrefix("수면필터")
            if sameSignals, !isPush, now.timeIntervalSince(last.t) < 3600 { return }
        }
        all.append(Entry(t: now, src: src, focusRaw: raw, filter: filter, inBed: inBed))
        if all.count > limit { all.removeFirst(all.count - limit) }
        if let data = try? JSONEncoder().encode(all) {
            defaults?.set(data, forKey: key)
        }
    }

    static func load() -> [Entry] {
        guard let data = defaults?.data(forKey: key),
              let items = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return items
    }

    static func clear() { defaults?.removeObject(forKey: key) }

    /// 사람이 읽고 그대로 붙여넣을 수 있는 텍스트 (최신이 아래).
    static func exportText() -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm:ss"
        let rows = load().map { e in
            "\(f.string(from: e.t))  \(e.src)  집중=\(e.focusLabel)  필터=\(e.filter ? "수면" : "-")  inBed=\(e.inBed ? "O" : "-")"
        }
        return rows.isEmpty ? "기록 없음" : rows.joined(separator: "\n")
    }
}
