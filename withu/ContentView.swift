//
//  ContentView.swift
//  withu
//

import SwiftUI
import Combine
import HealthKit
import WidgetKit
import CoreLocation
import WatchConnectivity

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
                    permissionBanner    // 권한 거절돼있을 때만 노출 (이전 layout 위에 얹음)
                    weatherHeader
                    characterHero
                    metricsCard
                    actionButtons
                    watchStatusCard
                    lastUpdateFooter
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
                // 권한 요청은 OnboardingView 에서 단계별로 처리.
                // 여기선 이미 허용된 권한 status 만 갱신 + 데이터 fetch.
                weather.refresh()
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
                // 가장 뒤 — 날씨 배경 (사용자 생성 이미지 있을 때만 표시).
                WeatherBackgroundView(condition: weatherBackgroundCondition)
                    .frame(width: 240, height: 240)
                    .clipShape(Circle())
                // 중간 — 캐릭터 tint 원 (살짝 옅게)
                Circle()
                    .fill(characterState.tint.opacity(0.22))
                    .frame(width: 240, height: 240)
                // 앞 — 캐릭터 (투명 PNG 가정)
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

    /// 현재 시각 + 날씨 → 배경 condition 매핑.
    /// 야간 (프로필 sleep window) 우선 — 날씨 무관하게 .night.
    private var weatherBackgroundCondition: WeatherBackgroundCondition? {
        if isNightByProfile { return .night }
        guard let c = weather.snapshot?.condition else { return nil }
        switch c {
        case .sunny:           return .sunny
        case .cloudy:          return .cloudy
        case .rainy, .thunder: return .rainy
        case .snowy:           return .snowy
        default:               return nil
        }
    }

    /// 현재 시각이 프로필 sleep window (예: 22:00-07:00) 안인지.
    private var isNightByProfile: Bool {
        let cal = Calendar.current
        let now = Date()
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let startMin = profile.sleepStartHour * 60 + profile.sleepStartMinute
        let endMin = profile.sleepEndHour * 60 + profile.sleepEndMinute
        let s = startMin % (24 * 60)
        let e = endMin % (24 * 60)
        return s < e ? (nowMin >= s && nowMin < e) : (nowMin >= s || nowMin < e)
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

    private func metricItem(emoji: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(emoji).font(.subheadline)
            Text(value).font(.callout.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
            "가벼운 산책 어때요 🌿"
        ]
        return lazyMessages.randomElement() ?? ""
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
                       tint: .withuPink) {
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

    // MARK: - Last update footer

    /// 메인 하단 작은 footer — BG refresh 가 정상 작동 중인지 한눈에.
    private var lastUpdateFooter: some View {
        let bgDate = UserDefaults(suiteName: SharedAppState.groupID)?
            .object(forKey: "withu.lastBackgroundRefreshAt") as? Date
        return HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9))
            if let date = bgDate {
                Text("마지막 갱신 \(date.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("백그라운드 갱신 대기 중")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Permission banner

    /// 거절돼있어서 해당 기능이 막힌 권한 목록.
    private var deniedPermissions: [String] {
        var list: [String] = []
        if !health.isAuthorized { list.append("건강") }
        if weather.authorizationStatus == .denied || weather.authorizationStatus == .restricted {
            list.append("위치")
        }
        if notifications.authorizationStatus == .denied { list.append("알림") }
        return list
    }

    @ViewBuilder
    private var permissionBanner: some View {
        if !deniedPermissions.isEmpty {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(deniedPermissions.joined(separator: " · ")) 권한이 꺼져 있어요")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("기능이 제한될 수 있어요. 탭해서 iOS 설정에서 켤 수 있어요.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
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
    @State private var showWidgetGuide: Bool = false
    @State private var showOnboardingConfirm: Bool = false
    @AppStorage("withu.onboarded.v1") private var onboarded: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                watchSection
                healthSection
                notificationsSection
                Section {
                    NavigationLink {
                        AdvancedDiagnosticsView(
                            health: $health,
                            focus: $focus,
                            connectivity: $connectivity,
                            overrideState: $overrideState,
                            characterState: characterState,
                            sendStateToWatch: sendStateToWatch
                        )
                    } label: {
                        Label("고급 / 진단", systemImage: "gauge.with.dots.needle.50percent")
                    }
                } footer: {
                    Text("Focus 모드, HealthKit 수면 데이터, 운동 추론, 백그라운드 새로고침 등의 진단 정보. 일반 사용엔 필요 없어요.")
                        .font(.caption2)
                }
                Section {
                    Button {
                        showWidgetGuide = true
                    } label: {
                        Label("위젯 · 컴플리케이션 추가하기", systemImage: "rectangle.stack.badge.plus")
                    }
                    Button {
                        showOnboardingConfirm = true
                    } label: {
                        Label("온보딩 다시 보기", systemImage: "arrow.counterclockwise.circle")
                    }
                } header: {
                    Text("도움말")
                }
                Section {
                    // ⚠️ 호스팅 후 URL 갱신 — GitHub Pages 등에 legal/ 의 두 markdown 을 HTML 로 배포.
                    Link(destination: URL(string: "https://kkcdkk.github.io/withu/PRIVACY_POLICY.html")!) {
                        Label("개인정보처리방침", systemImage: "lock.shield")
                    }
                    Link(destination: URL(string: "https://kkcdkk.github.io/withu/TERMS_OF_SERVICE.html")!) {
                        Label("이용약관", systemImage: "doc.text")
                    }
                } header: {
                    Text("법적 정보")
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                }
            }
            .sheet(isPresented: $showWidgetGuide) {
                WidgetGuideView()
            }
            .alert("온보딩 다시 보기", isPresented: $showOnboardingConfirm) {
                Button("다시 보기") {
                    onboarded = false
                    dismiss()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("권한 안내 화면을 처음부터 다시 봐요. 거절한 권한도 다시 시도할 수 있어요.")
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

// MARK: - WidgetGuideView

/// 사용자가 위젯 / 컴플리케이션을 어떻게 추가하는지 단계별 안내.
struct WidgetGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    guideSection(
                        icon: "iphone",
                        tint: .pink,
                        title: "iPhone 홈 화면 위젯",
                        steps: [
                            "홈 화면 빈 공간 길게 누르기",
                            "좌상단 [＋] 버튼 탭",
                            "검색에서 \"withu\" 입력",
                            "원하는 크기 (작음/중간/큼) 선택 → 추가",
                        ]
                    )
                    guideSection(
                        icon: "lock.iphone",
                        tint: .indigo,
                        title: "iPhone 잠금 화면 위젯",
                        steps: [
                            "잠금 화면 길게 누르기 → [맞춤 설정] 탭",
                            "잠금 화면 선택 → 위젯 영역 탭",
                            "[위젯 추가] → \"withu\" 검색",
                            "원형 / 사각형 / 인라인 중 선택 → 완료",
                        ]
                    )
                    guideSection(
                        icon: "applewatch",
                        tint: .cyan,
                        title: "Apple Watch 컴플리케이션",
                        steps: [
                            "워치 페이스 길게 누르기 → [편집]",
                            "[컴플리케이션] 화면까지 스와이프",
                            "원하는 자리 탭 → \"withu\" 검색",
                            "선택 → 디지털 크라운 눌러서 완료",
                        ]
                    )
                }
                .padding(20)
            }
            .navigationTitle("위젯 추가하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }

    private func guideSection(icon: String, tint: Color, title: String,
                               steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(tint)
                }
                Text(title).font(.headline)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(i + 1).")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(tint)
                            .frame(width: 20, alignment: .leading)
                        Text(step).font(.callout)
                    }
                }
            }
            .padding(.leading, 50)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - AdvancedDiagnosticsView

/// 일반 사용자에겐 노이즈인 진단 화면들. Settings → "고급 / 진단" 로 격리.
struct AdvancedDiagnosticsView: View {
    @Binding var health: HealthKitManager
    @Binding var focus: FocusModeManager
    @Binding var connectivity: ConnectivityManager
    @Binding var overrideState: CharacterState?
    let characterState: CharacterState
    let sendStateToWatch: (CharacterState) -> Void

    var body: some View {
        Form {
            focusSection
            healthSleepSection
            motionSection
            debugSection
        }
        .navigationTitle("고급 / 진단")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections (옮겨옴)

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
            if let last = focus.lastCheckedAt {
                HStack {
                    Text("마지막 폴링")
                    Spacer()
                    Text(last.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(.secondary)
                }
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
        }
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
        }
    }

    private var debugSection: some View {
        Section {
            HStack {
                Text("마지막 BG refresh")
                Spacer()
                Text(lastBgRefreshLabel)
                    .foregroundStyle(.secondary)
            }
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
            Button {
                ConnectivityManager.shared.sendAllToWatch()
            } label: {
                Label("워치로 모든 이미지 다시 동기화", systemImage: "applewatch.radiowaves.left.and.right")
            }
            HStack {
                Text("워치 전송 대기 중")
                Spacer()
                Text("\(connectivity.outstandingTransfers)개")
                    .foregroundStyle(.secondary)
            }
            if let s = connectivity.lastImageTransferState {
                HStack {
                    Text("워치 마지막 전송")
                    Spacer()
                    Text(s).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2).multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Text("디버그")
        } footer: {
            Text("BG refresh = iOS 가 백그라운드에서 우리 앱을 잠깐 깨운 시각. 30분~수시간 간격으로 iOS 가 결정. 워치 동기화는 앱 첫 실행 / 워치 앱 새로 설치 시 자동으로 한 번 수행돼요.")
                .font(.caption2)
        }
    }

    private var lastBgRefreshLabel: String {
        let defaults = UserDefaults(suiteName: SharedAppState.groupID)
        guard let date = defaults?.object(forKey: "withu.lastBackgroundRefreshAt") as? Date else {
            return "한 번도 없음"
        }
        return date.formatted(date: .omitted, time: .standard)
    }
}
