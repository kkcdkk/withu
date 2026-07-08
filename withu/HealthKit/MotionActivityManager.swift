//
//  MotionActivityManager.swift
//  withu (iOS)
//
//  폰 전용 운동 추정 — CoreMotion 활동 분류(CMMotionActivityManager).
//  워치(심박) 없이도 아이폰의 모션 코프로세서가 가속도계+자이로 패턴으로
//  걷기/달리기/자전거를 온디바이스 분류해준다.
//  캐주얼 걸음 오탐 방지: 최근 10분 창에서 지배 활동이 70%+ 지속일 때만 보고.
//

import Foundation
import CoreMotion

@MainActor
@Observable
final class MotionActivityManager {
    static let shared = MotionActivityManager()

    enum Activity { case walking, running, cycling }

    /// 최근 refresh() 기준 "지속 중인 운동" 추정. 없으면 nil.
    /// 첫 조회 시 iOS 가 '동작 및 피트니스' 권한을 1회 묻는다. 거부 시 항상 nil (무해).
    private(set) var sustainedActivity: Activity?

    @ObservationIgnored private let manager = CMMotionActivityManager()
    private init() {}

    /// 최근 10분 활동 이력 조회 → 지배 활동 채택. 폴링(30초 캐치업 등)에서 호출.
    func refresh() async {
        guard CMMotionActivityManager.isActivityAvailable() else {
            sustainedActivity = nil
            return
        }
        let now = Date()
        let start = now.addingTimeInterval(-10 * 60)
        let acts: [CMMotionActivity] = await withCheckedContinuation { cont in
            manager.queryActivityStarting(from: start, to: now, to: .main) { list, _ in
                cont.resume(returning: list ?? [])   // 권한 거부/오류 → 빈 배열
            }
        }
        sustainedActivity = Self.dominantActivity(in: acts, windowStart: start, windowEnd: now)
    }

    /// 활동 엔트리는 (startDate, 플래그) 시퀀스 — 각 엔트리가 다음 엔트리 전까지 지속.
    /// confidence low 는 무시. 지배 활동이 창의 70% 미만이면 nil (일상 이동 오탐 방지).
    static func dominantActivity(in acts: [CMMotionActivity],
                                 windowStart: Date, windowEnd: Date) -> Activity? {
        guard !acts.isEmpty else { return nil }
        var durations: [Activity: TimeInterval] = [:]
        for (i, a) in acts.enumerated() {
            guard a.confidence != .low else { continue }
            let s = max(a.startDate, windowStart)
            let e = i + 1 < acts.count ? acts[i + 1].startDate : windowEnd
            let dur = e.timeIntervalSince(s)
            guard dur > 0 else { continue }
            // running/cycling 이 walking 과 동시에 true 인 엔트리도 있어 우선순위로 분류.
            if a.running { durations[.running, default: 0] += dur }
            else if a.cycling { durations[.cycling, default: 0] += dur }
            else if a.walking { durations[.walking, default: 0] += dur }
        }
        let window = windowEnd.timeIntervalSince(windowStart)
        guard window > 0,
              let best = durations.max(by: { $0.value < $1.value }),
              best.value >= window * 0.7 else { return nil }
        return best.key
    }
}
