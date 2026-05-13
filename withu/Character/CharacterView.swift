//
//  CharacterView.swift
//  withu
//

import SwiftUI

struct CharacterView: View {
    let state: CharacterState

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(state.tint.opacity(0.15))
                    .frame(width: 200, height: 200)

                Image(systemName: state.symbolName)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(state.tint)
                    .frame(width: 110, height: 110)
                    .symbolEffect(.bounce, value: state)
            }

            Text(state.caption)
                .font(.headline)
                .foregroundStyle(.primary)
                .transition(.opacity)
                .id(state)   // 상태 바뀌면 텍스트 fade 새로 트리거
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .animation(.snappy, value: state)
    }
}

#Preview("Idle")      { CharacterView(state: .idle) }
#Preview("Sleeping")  { CharacterView(state: .sleeping) }
#Preview("Running")   { CharacterView(state: .running) }
#Preview("Cycling")   { CharacterView(state: .cycling) }
#Preview("Walking")   { CharacterView(state: .walking) }
#Preview("Energetic") { CharacterView(state: .energetic) }
