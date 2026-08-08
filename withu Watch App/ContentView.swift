//
//  ContentView.swift
//  withu Watch App
//

import SwiftUI

struct ContentView: View {
    @State private var connectivity = ConnectivityManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // 실시간 수신(lastMessage)이 아직 없으면 마지막 저장분(SharedAppState)으로 표시 —
                // iPhone 이 근처에 없어도 워치 단독 실행 시 빈 화면 대신 최근 상태를 보여준다.
                if let msg = connectivity.lastMessage ?? SharedAppState.loadMessage() {
                    WatchCharacterView(state: msg.state,
                                       lastReceivedAt: connectivity.lastReceivedAt,
                                       imageReloadKey: connectivity.characterImageVersion,
                                       weatherEmoji: msg.weatherEmoji,
                                       weatherSunrise: msg.weatherSunrise,
                                       weatherSunset: msg.weatherSunset)
                    if let steps = msg.todaySteps {
                        Text("👟 \(Int(steps))보")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 6) {
                        ProgressView()
                        Text("iPhone에서 데이터를\n기다리는 중…")
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }

            }
            .padding(.horizontal, 8)
        }
        .task {
            connectivity.activate()
        }
    }

}

#Preview {
    ContentView()
}
