//
//  ContentView.swift
//  withu
//

import SwiftUI
import HealthKit
import WidgetKit

struct ContentView: View {
    // HealthKit (Step 2)
    @State private var health = HealthKitManager.shared
    @State private var healthMessage: String = "권한 요청 안 함"
    @State private var healthLoading: Bool = false

    // 캐릭터 (Step 3)
    @State private var overrideState: CharacterState? = nil   // 디버그용 강제 변경

    private var characterState: CharacterState {
        overrideState ?? CharacterStateResolver.resolve(
            sleep: health.sleep,
            workouts: health.recentWorkouts,
            todaySteps: health.todaySteps,
            weather: weather.snapshot
        )
    }

    @State private var connectivity = ConnectivityManager.shared
    @State private var notifications = NotificationManager.shared
    @State private var weather = WeatherManager.shared

    var body: some View {
        NavigationStack {
            Form {
                characterSection
                weatherSection
                watchSection
                notificationsSection
                cameraSection
                healthSection
                debugSection
            }
            .navigationTitle("withu")
            .scrollDismissesKeyboard(.interactively)
            .task {
                connectivity.activate()
                await notifications.refreshAuthorizationStatus()
                weather.refresh()
            }
            .onChange(of: characterState) { _, newValue in
                sendStateToWatch(newValue)
            }
            .onChange(of: health.todaySteps) { _, newSteps in
                sendStateToWatch(characterState)
                if let s = newSteps {
                    Task { await notifications.scheduleStepGoalIfNeeded(steps: s) }
                }
            }
            .onChange(of: health.recentWorkouts) { _, newWorkouts in
                Task { await notifications.scheduleWorkoutEndedIfNeeded(latest: newWorkouts.first) }
            }
            .onChange(of: weather.snapshot) { _, _ in
                // 날씨 바뀌면 캐릭터 재계산 → 워치/위젯에 새 메시지 푸시
                sendStateToWatch(characterState)
            }
        }
    }

    private func sendStateToWatch(_ state: CharacterState) {
        let msg = WatchMessage(
            state: state,
            todaySteps: health.todaySteps,
            lastSleepHours: health.sleep.map { $0.totalAsleep / 3600 },
            timestamp: Date()
        )
        // 1) iOS 위젯이 읽을 수 있게 App Group 에 저장 + 위젯 타임라인 리로드
        SharedAppState.save(msg)
        WidgetCenter.shared.reloadAllTimelines()
        // 2) 워치로도 전송
        connectivity.send(msg)
    }

    // MARK: - Weather section

    private var weatherSection: some View {
        Section("날씨") {
            if let snap = weather.snapshot {
                HStack {
                    Text("\(snap.condition.emoji) \(snap.condition.caption)")
                        .font(.headline)
                    Spacer()
                    Text("\(snap.temperatureC, specifier: "%.1f")°C")
                        .foregroundStyle(.secondary)
                }
                Text("측정: \(snap.timestamp.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("날씨 정보 없음")
                    Spacer()
                    if weather.isFetching {
                        ProgressView()
                    }
                }
            }
            Button {
                weather.refresh(force: true)
            } label: {
                Text(weather.isFetching ? "가져오는 중…" : "날씨 새로고침")
            }
            .disabled(weather.isFetching)

            if let err = weather.lastError {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Notifications section

    private var notificationsSection: some View {
        Section("알림") {
            HStack {
                Text("권한 상태")
                Spacer()
                Text(authStatusLabel)
                    .foregroundStyle(.secondary)
            }
            if notifications.authorizationStatus != .authorized {
                Button("알림 권한 요청") {
                    Task { await notifications.requestAuthorization() }
                }
            }
            Button("매일 22:30 취침 리마인더 설정") {
                Task { await notifications.scheduleBedtimeReminder() }
            }
            Button("등록된 알림 모두 취소", role: .destructive) {
                notifications.cancelAll()
            }
            if let err = notifications.lastError {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var authStatusLabel: String {
        switch notifications.authorizationStatus {
        case .notDetermined:    return "❓ 미요청"
        case .denied:           return "❌ 거부됨"
        case .authorized:       return "✅ 허용됨"
        case .provisional:      return "🤖 자동 허용"
        case .ephemeral:        return "🕐 일시 허용"
        @unknown default:       return "?"
        }
    }

    // MARK: - Watch status section

    private var watchSection: some View {
        Section("Apple Watch 연결") {
            HStack {
                Text("페어링")
                Spacer()
                Text(connectivity.isPaired ? "✅" : "❌")
            }
            HStack {
                Text("워치 앱 설치")
                Spacer()
                Text(connectivity.isWatchAppInstalled ? "✅" : "❌")
            }
            HStack {
                Text("Reachable")
                Spacer()
                Text(connectivity.isReachable ? "✅" : "—")
            }
            if let last = connectivity.lastSentAt {
                HStack {
                    Text("마지막 전송")
                    Spacer()
                    Text(last.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(.secondary)
                }
            }
            if let err = connectivity.lastError {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
            Button("지금 보내기") {
                sendStateToWatch(characterState)
            }
        }
    }

    // MARK: - Character

    private var characterSection: some View {
        Section {
            CharacterView(state: characterState)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Camera

    private var cameraSection: some View {
        Section("카메라") {
            NavigationLink {
                CameraView()
            } label: {
                Label("캐릭터랑 사진 찍기", systemImage: "camera.fill")
            }
            NavigationLink {
                CharacterGenView()
            } label: {
                Label("캐릭터 만들기", systemImage: "wand.and.stars")
            }
            NavigationLink {
                BatchCharacterGenView()
            } label: {
                Label("여러 상태 한 번에 만들기", systemImage: "square.grid.3x3.fill")
            }
        }
    }

    // MARK: - HealthKit

    private var healthSection: some View {
        Section("HealthKit") {
            HStack {
                Text("데이터 접근")
                Spacer()
                Text(health.isAuthorized ? "✅ 가능" : "❓ 확인 안 됨")
                    .foregroundStyle(.secondary)
            }

            Button("권한 요청") {
                Task { await requestAuth() }
            }
            .disabled(healthLoading)

            Button("데이터 불러오기") {
                Task { await loadAll() }
            }
            .disabled(healthLoading)

            Text(healthMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let s = health.sleep {
                VStack(alignment: .leading, spacing: 4) {
                    Text("💤 수면 (지난 7일)").font(.subheadline).bold()
                    Text("총 수면: \(formatDuration(s.totalAsleep))")
                    Text("기록 수: \(s.sampleCount)건")
                    if let last = s.lastNight {
                        Text("마지막: \(last.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                .font(.footnote)
            }

            if let steps = health.todaySteps {
                Text("👟 오늘 걸음: \(Int(steps))보").font(.subheadline)
            }

            if !health.recentWorkouts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("🏋️ 최근 운동").font(.subheadline).bold()
                    ForEach(Array(health.recentWorkouts.prefix(5).enumerated()), id: \.offset) { _, w in
                        HStack {
                            Text(w.activity.displayName)
                            Spacer()
                            Text(formatDuration(w.duration))
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                    }
                }
            }
        }
    }

    private func requestAuth() async {
        healthLoading = true
        defer { healthLoading = false }
        do {
            try await health.requestAuthorization()
            healthMessage = "권한 요청 완료"
        } catch {
            healthMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func loadAll() async {
        healthLoading = true
        defer { healthLoading = false }

        var errors: [String] = []
        do { _ = try await health.fetchSleep(days: 7) }
        catch { errors.append("수면: \(error.localizedDescription)") }
        do { _ = try await health.fetchWorkouts(days: 7) }
        catch { errors.append("운동: \(error.localizedDescription)") }
        do { _ = try await health.fetchTodaySteps() }
        catch { errors.append("걸음: \(error.localizedDescription)") }

        healthMessage = errors.isEmpty
            ? "✅ 데이터 로드 완료"
            : "⚠️ 일부 실패\n" + errors.joined(separator: "\n")
    }

    // MARK: - Debug

    private var debugSection: some View {
        Section("디버그 (상태 강제)") {
            Picker("상태 강제", selection: $overrideState) {
                Text("자동").tag(CharacterState?.none)
                ForEach(CharacterState.allCases, id: \.self) { state in
                    Text(state.rawValue).tag(CharacterState?.some(state))
                }
            }
            .pickerStyle(.menu)

            Text("자동 모드는 HealthKit 데이터 + 현재 시각으로 결정")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return "\(h)시간 \(m)분"
    }
}

#Preview {
    ContentView()
}
