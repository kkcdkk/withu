//
//  ContentView.swift
//  withu
//

import SwiftUI
import Combine
import HealthKit
import WidgetKit

struct ContentView: View {
    @State private var health = HealthKitManager.shared
    @State private var connectivity = ConnectivityManager.shared
    @State private var notifications = NotificationManager.shared
    @State private var weather = WeatherManager.shared
    @State private var focus = FocusModeManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var overrideState: CharacterState? = nil
    @State private var showSettings: Bool = false
    @State private var profile: CharacterProfile = CharacterProfileStore.load()
    /// 캐릭터 이미지 변경 시 ++. CharacterImageView 의 .id 에 들어가 강제 재생성.
    @State private var imageRefreshKey: Int = 0
    /// 활동 종합 메시지 — task / 새로고침 시 갱신
    @State private var activityMessage: String = ""
    @AppStorage("withu.onboarded.v1") private var onboarded: Bool = false

    private var characterState: CharacterState {
        // SyncCoordinator 와 동일 정책 — manualSleepOnly 면 자동 감지 끔.
        let manualOnly = profile.manualSleepOnly ?? false
        return overrideState ?? CharacterStateResolver.resolve(
            sleep: health.sleep,
            workouts: health.recentWorkouts,
            todaySteps: health.todaySteps,
            weather: weather.snapshot,
            inSleepSchedule: manualOnly ? false : health.isInBedSchedule,
            hasSleepSchedule: manualOnly ? false : health.hasSleepSchedule,
            isFocusActive: manualOnly ? false : (focus.isFocused || focus.isFocusFilterSleeping),
            isLikelyInWorkout: health.isLikelyInWorkout,
            profile: profile
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    weatherHeader
                    characterHero
                    metricsCard
                    actionButtons
                    watchStatusCard
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .background(backgroundGradient.ignoresSafeArea())
            .navigationTitle("with U")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(overrideState: $overrideState,
                             characterState: characterState,
                             sendStateToWatch: sendStateToWatch)
            }
            .task {
                connectivity.activate()
                await notifications.refreshAuthorizationStatus()
                weather.refresh()
                if !health.isAuthorized {
                    try? await health.requestAuthorization()
                }
                await loadAll()
                activityMessage = computeActivityMessage()
                health.startObservingChanges()
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
                sendStateToWatch(characterState)
            }
            .onChange(of: health.isInBedSchedule) { _, _ in
                sendStateToWatch(characterState)
            }
            .onReceive(NotificationCenter.default.publisher(for: .characterProfileChanged)) { _ in
                profile = CharacterProfileStore.load()
                sendStateToWatch(characterState)
            }
            .onReceive(NotificationCenter.default.publisher(for: .characterImageChanged)) { _ in
                imageRefreshKey &+= 1
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Foreground 진입 시 Focus 폴링 + 즉시 sync (iOS 가 Focus 변화를 push 안 함).
                guard newPhase == .active else { return }
                focus.refresh()
                SyncCoordinator.syncNow(override: overrideState)
            }
            .onChange(of: focus.isFocused) { _, _ in
                // Focus 토글이 반영되면 워치/위젯도 즉시 갱신.
                sendStateToWatch(characterState)
            }
            // Control Center 로 Focus 토글하면 scenePhase 가 안 바뀌어서
            // .onChange 도 안 옴 → 3초마다 직접 폴링. iOS background 진입 시 Timer
            // 도 자동으로 멈춰서 배터리 영향 작음.
            .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
                guard scenePhase == .active else { return }
                focus.refresh()
            }
            // Focus API 가 Sleep Focus 를 false 로 거짓말하는 경우 대비 — HealthKit
            // inBed 샘플도 30초 주기로 catchup 폴링 (HKObserverQuery 가 미스해도 안전).
            // fetch 자체는 store query 라 3초 폴링은 부담. 30초가 균형.
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
                guard scenePhase == .active else { return }
                Task {
                    _ = await health.fetchInBedSchedule()
                    SyncCoordinator.syncNow(override: overrideState)
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !onboarded },
            set: { _ in }
        )) {
            OnboardingView(onComplete: { onboarded = true })
        }
    }

    // MARK: - Sections

    private var backgroundGradient: LinearGradient {
        // 더 옅은 파스텔 톤 — 캐릭터 색 따라 살짝 톤만 변경
        LinearGradient(
            colors: [
                characterState.tint.opacity(0.12),
                characterState.tint.opacity(0.04),
                Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var weatherHeader: some View {
        HStack(spacing: 8) {
            if let snap = weather.snapshot {
                Text("\(snap.condition.emoji) \(snap.condition.caption)")
                    .font(.subheadline.weight(.medium))
                Text("·")
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f°", snap.temperatureC))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("날씨 가져오는 중…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                weather.refresh(force: true)
            } label: {
                Image(systemName: weather.isFetching ? "arrow.clockwise.circle" : "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(weather.isFetching)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private var characterHero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(characterState.tint.opacity(0.22))
                    .frame(width: 240, height: 240)
                CharacterImageView(state: characterState, animated: true)
                    .frame(width: 200, height: 200)
                    .id("\(characterState.rawValue)-\(imageRefreshKey)")  // 이미지 갱신 강제
            }
            Text(characterState.caption)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .id(characterState)
                .transition(.opacity)
        }
        .animation(.snappy, value: characterState)
    }

    private var metricsCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("오늘 활동")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await loadAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)

            HStack(spacing: 0) {
                metricItem(emoji: "👟",
                           value: health.todaySteps.map { "\(Int($0))" } ?? "-",
                           label: "걸음")
                Divider().frame(height: 32)
                metricItem(emoji: "🏃",
                           value: health.todayActiveMinutes.map { "\(Int($0))" } ?? "-",
                           label: "활동분")
                Divider().frame(height: 32)
                metricItem(emoji: "🔥",
                           value: health.todayActiveKcal.map { "\(Int($0))" } ?? "-",
                           label: "kcal")
                Divider().frame(height: 32)
                metricItem(emoji: "💤",
                           value: sleepHoursText,
                           label: "수면")
            }

            if !activityMessage.isEmpty {
                Text(activityMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Slack 새로고침 메시지 같은 가벼운 격려/안내. 시간대 + 활동량 기반.
    /// 메시지 문구 수정: 이 함수 안 morningMessages / lazyMessages / 활동량 분기 메시지.
    private func computeActivityMessage() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let kcal = Int(health.todayActiveKcal ?? 0)
        let steps = Int(health.todaySteps ?? 0)
        let minutes = Int(health.todayActiveMinutes ?? 0)

        // 아침 (11시 전) — 활동 적을 때 랜덤 인사
        if hour < 11 && kcal < 100 {
            let morningMessages = [
                "좋은 아침! 오늘도 함께해요 ☀️",
                "새 하루 시작이에요 🌱",
                "기지개 펴고 시작해봐요 🧘",
                "물 한 잔 마시는 거 잊지 마세요 💧"
            ]
            return morningMessages.randomElement() ?? ""
        }
        // 활발한 날
        if kcal >= 400 || minutes >= 60 || steps >= 10000 {
            return "오늘 알찬 하루였네요! 평소보다 많이 움직였어요"
        }
        // 보통
        if kcal >= 150 || steps >= 4000 {
            return "오늘 \(steps)보 걸었어요 🌿"
        }
        // 잔잔한 날
        let lazyMessages = [
            "가벼운 산책 할까요?"
        ]
        return lazyMessages.randomElement() ?? ""
    }

    private func metricItem(emoji: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(emoji).font(.subheadline)
            Text(value).font(.callout.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var sleepHoursText: String {
        guard let sleep = health.sleep, sleep.totalAsleep > 0 else { return "-" }
        let h = sleep.totalAsleep / 3600
        return String(format: "%.1fh", h)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            actionLink(title: "함께할 캐릭터 생성하기",
                       subtitle: "AI/사진 첨부로 함께할 캐릭터를 만들어요",
                       icon: "wand.and.stars",
                       tint: Color(red: 1.0, green: 0.78, blue: 0.85)) {  // soft pastel pink
                CharacterGenView()
            }
            actionLink(title: "함께 사진 찍기",
                       subtitle: "캐릭터와 함께 사진 찍어요",
                       icon: "camera.fill",
                       tint: .cyan) {
                CameraView()
            }
            actionLink(title: "캐릭터 갤러리",
                       subtitle: "만든 캐릭터를 모아봐요",
                       icon: "photo.stack",
                       tint: .brown) {
                CharacterGalleryView()
            }
            actionLink(title: "내 캐릭터 설정하기",
                       subtitle: "이름 · 수면 · 식사 시간",
                       icon: "person.crop.circle.fill",
                       tint: .mint) {
                CharacterProfileView()
            }
        }
    }

    @ViewBuilder
    private func actionLink<Dest: View>(title: String, subtitle: String,
                                         icon: String, tint: Color,
                                         @ViewBuilder destination: () -> Dest) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var watchStatusCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "applewatch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Apple Watch").font(.subheadline.weight(.semibold))
                Spacer()
                if let last = connectivity.lastSentAt {
                    Text(last.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button {
                    sendStateToWatch(characterState)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 0) {
                statusItem(label: "페어링", ok: connectivity.isPaired)
                Divider().frame(height: 28)
                statusItem(label: "앱 설치", ok: connectivity.isWatchAppInstalled)
                Divider().frame(height: 28)
                statusItem(label: "연결", ok: connectivity.isReachable)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statusItem(label: String, ok: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: ok ? "checkmark.circle.fill" : "minus.circle.fill")
                .foregroundStyle(ok ? .green : .secondary)
                .font(.callout)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Logic

    private func sendStateToWatch(_ state: CharacterState) {
        // override 가 살아있을 때만 명시. nil 이면 resolver 가 다시 계산해도 같은 값.
        SyncCoordinator.syncNow(override: overrideState)
    }

    private func loadAll() async {
        do { _ = try await health.fetchSleep(days: 7) } catch {}
        do { _ = try await health.fetchWorkouts(days: 7) } catch {}
        do { _ = try await health.fetchTodaySteps() } catch {}
        do { _ = try await health.fetchTodayActiveMinutes() } catch {}
        do { _ = try await health.fetchTodayActiveKcal() } catch {}
        _ = await health.fetchInBedSchedule()
        sendStateToWatch(characterState)
        activityMessage = computeActivityMessage()
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var health = HealthKitManager.shared
    @State private var connectivity = ConnectivityManager.shared
    @State private var notifications = NotificationManager.shared
    @State private var focus = FocusModeManager.shared

    @Binding var overrideState: CharacterState?
    let characterState: CharacterState
    let sendStateToWatch: (CharacterState) -> Void

    @State private var healthMessage: String = ""
    @State private var healthLoading: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                watchSection
                healthSection
                notificationsSection
                focusSection
                healthSleepSection
                motionSection
                debugSection
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }

    private var watchSection: some View {
        Section("Apple Watch") {
            HStack { Text("페어링"); Spacer(); Text(connectivity.isPaired ? "✅" : "❌") }
            HStack { Text("앱 설치"); Spacer(); Text(connectivity.isWatchAppInstalled ? "✅" : "❌") }
            HStack { Text("연결"); Spacer(); Text(connectivity.isReachable ? "✅" : "—") }
            if let last = connectivity.lastSentAt {
                HStack {
                    Text("마지막 전송")
                    Spacer()
                    Text(last.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(.secondary)
                }
            }
            if let imgState = connectivity.lastImageTransferState {
                Text(imgState).font(.footnote).foregroundStyle(.secondary)
            }
            Button("지금 보내기") { sendStateToWatch(characterState) }
        }
    }

    private var healthSection: some View {
        Section {
            HStack {
                Text("권한")
                Spacer()
                Text(health.isAuthorized ? "허용" : "미허용")
                    .foregroundStyle(.secondary)
            }
            Button("권한 다시 요청") {
                Task {
                    try? await health.requestAuthorization()
                }
            }
            Button("데이터 새로고침") {
                Task { await reloadHealth() }
            }
            .disabled(healthLoading)
            if !healthMessage.isEmpty {
                Text(healthMessage).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("건강 데이터")
        } footer: {
            Text("💡 운동/수면 *시작* 시 즉시 캐릭터 바꾸려면 — iOS '단축어' 앱 → 자동화 → '운동' / '수면 모드' 트리거에 'withu 앱 열기' 액션 추가.")
                .font(.caption2)
        }
    }

    private var notificationsSection: some View {
        Section("알림") {
            HStack {
                Text("권한 상태")
                Spacer()
                Text(authStatusLabel).foregroundStyle(.secondary)
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
        }
    }

    private var authStatusLabel: String {
        switch notifications.authorizationStatus {
        case .notDetermined: return "미요청"
        case .denied: return "거부됨"
        case .authorized: return "허용됨"
        case .provisional: return "자동 허용"
        case .ephemeral: return "일시 허용"
        @unknown default: return "?"
        }
    }

    private var focusSection: some View {
        Section {
            HStack { Text("권한"); Spacer(); Text(focus.authorizationStatusLabel).foregroundStyle(.secondary) }
            HStack { Text("현재 Focus"); Spacer(); Text(focus.focusStateLabel).foregroundStyle(.secondary) }
            HStack {
                Text("Focus Filter")
                Spacer()
                Text(focus.isFocusFilterSleeping ? "✅ sleeping push" : "— 비활성/미연결")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Filter 마지막 호출")
                Spacer()
                Text(focus.focusFilterLastPerformAt.map { $0.formatted(date: .omitted, time: .standard) }
                     ?? "한 번도 없음")
                    .foregroundStyle(.secondary)
            }
            if !focus.focusFilterPerformLog.isEmpty {
                DisclosureGroup("perform() 호출 로그 (최근 \(focus.focusFilterPerformLog.count)번)") {
                    ForEach(Array(focus.focusFilterPerformLog.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Text(entry.date.formatted(date: .omitted, time: .standard))
                                .font(.caption.monospaced())
                            Spacer()
                            Text(entry.sleeping ? "→ sleeping ON" : "→ sleeping OFF")
                                .font(.caption)
                                .foregroundStyle(entry.sleeping ? .indigo : .secondary)
                        }
                    }
                }
            }
            if let last = focus.lastCheckedAt {
                HStack {
                    Text("마지막 폴링")
                    Spacer()
                    Text(last.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack { Text("마지막 폴링"); Spacer(); Text("아직 없음").foregroundStyle(.secondary) }
            }
            if !focus.isAuthorized {
                Button("Focus 권한 요청") {
                    Task { await focus.requestAuthorization() }
                }
            }
            Button {
                focus.refresh()
                sendStateToWatch(characterState)
            } label: {
                Label("지금 다시 폴링", systemImage: "arrow.clockwise.circle.fill")
            }
            if focus.isAuthorized && focus.rawFocusedValue == nil {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("iOS 설정 열기", systemImage: "gear")
                }
            }
        } header: {
            Text("수면/집중 모드")
        } footer: {
            Text(focusFooterText).font(.caption2)
        }
    }

    /// 현재 진단 상태에 따라 사용자에게 다음 액션을 안내.
    private var focusFooterText: String {
        if focus.isFocusFilterSleeping {
            return "✅ Focus Filter 가 sleeping 을 push 해줬어요. iOS 가 우리 앱을 직접 깨워 호출한 가장 신뢰성 높은 경로."
        }
        // Filter 가 한 번도 호출된 적 없다 = manual setup 미완료
        if focus.focusFilterLastPerformAt == nil {
            return """
                Focus Filter 연결 필요 (한 번만):
                  1) iOS 설정 → 집중 모드 → 수면
                  2) 화면 아래쪽 "필터" 섹션 → "필터 추가"
                  3) 앱 목록에서 withu 선택
                  4) "캐릭터를 자게 하기" 토글 ON → 완료
                  5) Sleep Focus 한 번 OFF → ON
                위 "Filter 마지막 호출" 에 시각이 찍히면 연결 성공.
                """
        }
        // Filter 가 한 번이라도 호출됐는데 지금 false → Focus 가 OFF 상태 (정상)
        return "Focus Filter 연결됨. 마지막 호출 후 sleeping=false 상태 (Sleep Focus OFF 상태). Sleep Focus 켜면 perform() 다시 호출되어 sleeping push."
    }

    private var healthSleepSection: some View {
        Section {
            HStack {
                Text("최근 48h inBed 샘플")
                Spacer()
                Text("\(health.inBedSampleCount24h)개")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("지금 inBed 시간대")
                Spacer()
                Text(health.isInBedSchedule ? "✅ 안" : "— 밖")
                    .foregroundStyle(.secondary)
            }
            if let start = health.lastInBedSampleStart {
                HStack {
                    Text("마지막 inBed 시작")
                    Spacer()
                    Text(start.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("최근 7d asleep 샘플")
                Spacer()
                Text("\(health.sleep?.sampleCount ?? 0)개")
                    .foregroundStyle(.secondary)
            }
            if let last = health.sleep?.lastNight {
                HStack {
                    Text("마지막 asleep 시작")
                    Spacer()
                    Text(last.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                Task {
                    _ = try? await health.fetchSleep(days: 7)
                    _ = await health.fetchInBedSchedule()
                    sendStateToWatch(characterState)
                }
            } label: {
                Label("수면 데이터 다시 가져오기", systemImage: "arrow.clockwise.circle.fill")
            }
        } header: {
            Text("HealthKit 수면 진단")
        } footer: {
            Text("""
                • inBed = "침대에 있음" sample. 건강 앱 수면 일정 + Apple Watch 가 만들어요. iPhone 만 쓰면 자동 생성 안 될 수 있음.
                • asleep = Watch 가 실제 잠든 걸 감지한 sample. Watch 착용하고 자야 생김.
                • 둘 다 0이어도 캐릭터는 너의 \"내 캐릭터 설정 → 수면 시간\" 으로 잘 자.
                """)
                .font(.caption2)
        }
    }

    private var motionSection: some View {
        Section {
            HStack {
                Text("워치 운동 추론")
                Spacer()
                Text(health.isLikelyInWorkout ? "✅ 운동중일 가능성" : "—")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("최근 90s HR sample")
                Spacer()
                Text("\(health.recentHRSampleCount)개")
                    .foregroundStyle(.secondary)
            }
            if health.recentHRAverage > 0 {
                HStack {
                    Text("평균 BPM")
                    Spacer()
                    Text("\(Int(health.recentHRAverage))")
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                Task {
                    await health.refreshWorkoutInference()
                    sendStateToWatch(characterState)
                }
            } label: {
                Label("HR 추론 다시 계산", systemImage: "arrow.clockwise.circle.fill")
            }
        } header: {
            Text("운동 감지")
        } footer: {
            Text("Apple 워치 운동 앱 시작 시 HR sample 이 1-5초 간격으로 stream — 빈도 + 평균 BPM 으로 운동중 여부 추정 (5+ samples / 90s & ≥95bpm). 운동 종료 후엔 HKWorkout sample 로 정식 타입 매핑. 캐주얼한 걷기는 감지 안 함 (운동 = 명시적 시작).")
                .font(.caption2)
        }
    }

    private var debugSection: some View {
        Section("디버그") {
            Picker("상태 강제", selection: $overrideState) {
                Text("자동").tag(CharacterState?.none)
                ForEach(CharacterState.allCases, id: \.self) { state in
                    Text(state.rawValue).tag(CharacterState?.some(state))
                }
            }
            .pickerStyle(.menu)
            Button {
                sendStateToWatch(characterState)
                WidgetCenter.shared.reloadAllTimelines()
                WidgetCenter.shared.reloadTimelines(ofKind: "withuWidget")
                WidgetCenter.shared.reloadTimelines(ofKind: "withuComplication")
            } label: {
                Label("위젯 강제 새로고침", systemImage: "arrow.clockwise.circle.fill")
            }
        }
    }

    private func reloadHealth() async {
        healthLoading = true
        defer { healthLoading = false }
        var errors: [String] = []
        do { _ = try await health.fetchSleep(days: 7) } catch { errors.append("수면") }
        do { _ = try await health.fetchWorkouts(days: 7) } catch { errors.append("운동") }
        do { _ = try await health.fetchTodaySteps() } catch { errors.append("걸음") }
        do { _ = try await health.fetchTodayActiveMinutes() } catch { errors.append("활동") }
        do { _ = try await health.fetchTodayActiveKcal() } catch { errors.append("칼로리") }
        _ = await health.fetchInBedSchedule()
        sendStateToWatch(characterState)
        healthMessage = errors.isEmpty ? "최신화 완료" : "실패: \(errors.joined(separator: ", "))"
    }
}

#Preview {
    ContentView()
}
