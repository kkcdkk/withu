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

                if let err = connectivity.lastError {
                    Text(err)
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                debugSection
            }
            .padding(.horizontal, 8)
        }
        .task {
            connectivity.activate()
        }
    }

    /// 컴플리케이션 갱신 진단용. 사용자가 워치 앱 켜서 직접 확인 가능.
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Divider().padding(.vertical, 4)
            Text("🔍 디버그").font(.system(size: 10)).bold()

            if let rawState = connectivity.lastReceivedImageState {
                Text("📸 마지막 사진: \(rawState)").font(.system(size: 9))
            } else {
                Text("📸 사진 미수신").font(.system(size: 9)).foregroundStyle(.secondary)
            }

            Text("🔢 이미지 버전: \(connectivity.characterImageVersion)")
                .font(.system(size: 9))

            if let rt = connectivity.lastComplicationReloadAt {
                Text("🔄 마지막 reload: \(rt.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 9))
            } else {
                Text("🔄 reload 미호출").font(.system(size: 9)).foregroundStyle(.secondary)
            }

            if let msg = SharedAppState.loadMessage() {
                Text("💾 SharedAppState: \(msg.state.rawValue)")
                    .font(.system(size: 9))
                Text("⏰ msg ts: \(msg.timestamp.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 9))
                // 현재 state 의 PNG alpha 진단
                if let alphaDesc = CharacterImageStore.alphaInfoDescription(for: msg.state) {
                    Text("🖼️ PNG: \(alphaDesc)")
                        .font(.system(size: 9))
                } else {
                    Text("🖼️ PNG 파일 없음")
                        .font(.system(size: 9)).foregroundStyle(.orange)
                }
            } else {
                Text("💾 SharedAppState 비어 있음").font(.system(size: 9)).foregroundStyle(.red)
            }
        }
        .foregroundStyle(.secondary)
    }
}

#Preview {
    ContentView()
}
