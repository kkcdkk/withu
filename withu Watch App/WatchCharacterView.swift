//
//  WatchCharacterView.swift
//  withu Watch App
//

import SwiftUI

/// 워치 사이즈에 맞춘 컴팩트한 캐릭터 표시.
/// 다마고치 느낌 — TimelineView 로 매 frame 캐릭터에 미세한 모션
/// (호흡/점프/흔들기 등) 부여. state 별로 패턴 다름.
struct WatchCharacterView: View {
    let state: CharacterState
    let lastReceivedAt: Date?
    /// 새 이미지 도착 시 부모가 ++ 해서 전달. 같은 state 의 이미지만 바뀌어도
    /// .id() 가 강제 재생성을 트리거해 disk 에서 새 PNG 를 다시 읽음.
    var imageReloadKey: Int = 0

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(state.tint.opacity(0.20))
                    .frame(width: 80, height: 80)
                animatedCharacter
                    .id(imageReloadKey)
            }
            Text(state.caption)
                .font(.caption)
                .multilineTextAlignment(.center)
                .id(state)
                .transition(.opacity)
            if let last = lastReceivedAt {
                Text(last.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.snappy, value: state)
    }

    /// 매 ~30fps 마다 갱신. sine 파로 위치/스케일을 부드럽게 흔듦.
    /// (배터리 절약: 화면 active 일 때만 동작. dim/잠금 상태선 Timeline 정지)
    private var animatedCharacter: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let m = motion(for: state, at: ctx.date)
            CharacterImageView(state: state)
                .frame(width: 64, height: 64)
                .scaleEffect(m.scale)
                .offset(x: m.offsetX, y: m.offsetY)
                .rotationEffect(.degrees(m.rotation))
        }
    }
}

// MARK: - Motion model

/// 한 frame 의 변환 파라미터 — view 가 그대로 적용.
private struct MotionFrame {
    var scale: CGFloat = 1.0
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var rotation: Double = 0
}

/// state 별 다마고치 모션. 한 주기 period 와 진폭만 다름.
/// sine 파라 부드럽고, 멈춤 지점 (0 위치) 가 시각적으로 자연스러움.
private func motion(for state: CharacterState, at date: Date) -> MotionFrame {
    let t = date.timeIntervalSinceReferenceDate
    // 사이클 진행도 (-1 ~ 1)
    func phase(period: Double) -> Double {
        sin(t * 2 * .pi / period)
    }
    // 점프형(0~1, 빠르게 올랐다 떨어짐)
    func bounce(period: Double) -> Double {
        let s = sin(t * 2 * .pi / period)
        return max(0, s)   // 음수 구간은 바닥 — 진짜 점프처럼
    }

    switch state {
    case .sleeping:
        // 느린 호흡
        let p = phase(period: 3.2)
        return MotionFrame(scale: 1.0 + 0.025 * p)

    case .wakingUp:
        // 졸린 듯 느리게 살짝 휘청 — 호흡 + 좌우 살짝
        let p1 = phase(period: 2.8)
        let p2 = phase(period: 4.0)
        return MotionFrame(scale: 1.0 + 0.02 * p1,
                           offsetX: 1.5 * p2,
                           rotation: 1.0 * p2)

    case .eating:
        // 모션 없음 — 가만히 밥 먹는 모습
        return MotionFrame()

    case .idle:
        // 평범한 호흡 + 살짝 까닥
        let p = phase(period: 2.4)
        return MotionFrame(scale: 1.0 + 0.035 * p,
                           rotation: 1.5 * p)

    case .running, .energetic:
        // 빠른 점프
        let b = bounce(period: 0.5)
        return MotionFrame(offsetY: -6 * b)

    case .walking:
        // 천천히 위아래 + 살짝 까닥
        let b = bounce(period: 0.9)
        let p = phase(period: 0.9)
        return MotionFrame(offsetY: -3 * b,
                           rotation: 2 * p)

    case .cycling:
        // 살짝 위아래 + 좌우 흔들
        let p = phase(period: 0.7)
        return MotionFrame(offsetX: 2 * p,
                           offsetY: -2 * abs(p),
                           rotation: 3 * p)

    case .beach:
        // 손 흔드는 느낌 — 좌우 회전
        let p = phase(period: 1.1)
        return MotionFrame(rotation: 5 * p)

    case .cloudy:
        // 잔잔한 호흡 — 구름 위에 있는 듯 부드럽게
        let p = phase(period: 2.6)
        return MotionFrame(scale: 1.0 + 0.025 * p,
                           offsetY: -1.2 * p)

    case .snowPlay:
        // 발랄한 좌우 점프
        let b = bounce(period: 0.7)
        let p = phase(period: 0.7)
        return MotionFrame(offsetX: 3 * p,
                           offsetY: -4 * b)

    case .rainyShelter:
        // 처마 밑에서 빗소리 듣는 평온함 — 느린 호흡 + 살짝 까닥
        let p = phase(period: 3.0)
        return MotionFrame(scale: 1.0 + 0.025 * p,
                           rotation: 1.0 * p)
    }
}

#Preview("Idle")     { WatchCharacterView(state: .idle, lastReceivedAt: .now) }
#Preview("Running")  { WatchCharacterView(state: .running, lastReceivedAt: .now) }
#Preview("Sleeping") { WatchCharacterView(state: .sleeping, lastReceivedAt: .now) }
