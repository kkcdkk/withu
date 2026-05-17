//
//  ContentView.swift
//  withu Watch App
//

import SwiftUI

struct ContentView: View {
    @State private var connectivity = ConnectivityManager.shared

    var body: some View {
        VStack(spacing: 8) {
            if let msg = connectivity.lastMessage {
                WatchCharacterView(state: msg.state, lastReceivedAt: connectivity.lastReceivedAt)
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

            if let err = connectivity.lastError {
                Text(err)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 8)
        .task {
            connectivity.activate()
        }
    }
}

#Preview {
    ContentView()
}
