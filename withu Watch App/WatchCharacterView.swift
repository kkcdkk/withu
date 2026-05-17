//
//  WatchCharacterView.swift
//  withu Watch App
//

import SwiftUI

/// 워치 사이즈에 맞춘 컴팩트한 캐릭터 표시.
struct WatchCharacterView: View {
    let state: CharacterState
    let lastReceivedAt: Date?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(state.tint.opacity(0.20))
                    .frame(width: 80, height: 80)
                CharacterImageView(state: state)
                    .frame(width: 64, height: 64)
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
}

#Preview("Idle")     { WatchCharacterView(state: .idle, lastReceivedAt: .now) }
#Preview("Running")  { WatchCharacterView(state: .running, lastReceivedAt: .now) }
#Preview("Sleeping") { WatchCharacterView(state: .sleeping, lastReceivedAt: .now) }
