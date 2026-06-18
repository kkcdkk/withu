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
    /// 캐릭터 옆 날씨 그림(해/달/구름/비/눈) 표시 여부. App Group 저장.
    @AppStorage("withu.showWeatherDecoration.v1",
                store: UserDefaults(suiteName: SharedAppState.groupID))
    private var showWeather: Bool = true
    @State private var auth = AuthManager.shared

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
        .fullScreenCover(isPresented: Binding(
            get: { onboarded && auth.state == .signedOut },
            set: { _ in }
        )) {
            LoginGateView()
        }
        .task { await auth.restore() }
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
            Toggle("날씨 표시", isOn: $showWeather)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
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
                // 캐릭터 tint 원
                Circle()
                    .fill(characterState.tint.opacity(0.22))
                    .frame(width: 240, height: 240)
                // 캐릭터 (투명 PNG)
                CharacterImageView(state: characterState, animated: true)
                    .frame(width: 200, height: 200)
                    .id("\(characterState.rawValue)-\(imageRefreshKey)")
                // 날씨 표현 — 해/달/구름은 우상단 고정, 비/눈은 영역 전체 떨어짐.
                // 메인 스위치(showWeather)로 켜고 끌 수 있음.
                if showWeather {
                    WeatherDecorationView(condition: weatherBackgroundCondition, size: 44)
                        .frame(width: 240, height: 240)
                        .allowsHitTesting(false)
                }
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
        // 야간 판정: 날씨에서 받은 sunrise/sunset 1순위, 없으면 프로필의 fallback 시간.
        let isNight = CharacterImageStore.isCurrentlyNight(
            sunrise: weather.snapshot?.sunrise,
            sunset: weather.snapshot?.sunset,
            fallbackStartMinute: profile.effectiveNightFallbackStart,
            fallbackEndMinute: profile.effectiveNightFallbackEnd
        )
        if isNight { return .night }
        guard let c = weather.snapshot?.condition else { return nil }
        switch c {
        case .sunny:           return .sunny
        case .cloudy:          return .cloudy
        case .rainy, .thunder: return .rainy
        case .snowy:           return .snowy
        default:               return nil
        }
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
                       subtitle: "함께할 캐릭터를 만들어요",
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
                        Text("기능이 제한될 수 있어요. iOS 설정에서 켤 수 있어요.")
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
    @State private var auth = AuthManager.shared

    @Binding var overrideState: CharacterState?
    let characterState: CharacterState
    let sendStateToWatch: (CharacterState) -> Void

    @State private var healthMessage: String = ""
    @State private var healthLoading: Bool = false
    @State private var showWidgetGuide: Bool = false
    @State private var showOnboardingConfirm: Bool = false
    @State private var showPaywall: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var isDeletingAccount: Bool = false
    @State private var deleteError: String?
    @AppStorage("withu.onboarded.v1") private var onboarded: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient(for: .idle).ignoresSafeArea()
                Form {
                    Section {
                        Button {
                            showPaywall = true
                        } label: {
                            Label("구독 · 횟수 충전", systemImage: "sparkles")
                        }
                    } header: {
                        Text("더 만들기")
                    } footer: {
                        Text("오늘 \(GenerationQuota.remainingToday())번 생성할 수 있어요.")
                            .font(.caption2)
                    }
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
                            Label("캐릭터 상태 살펴보기", systemImage: "gauge.with.dots.needle.50percent")
                        }
                    } footer: {
                        Text("집중 모드, 건강 앱 수면 기록, 운동 감지, 백그라운드 갱신 같은 자세한 정보예요. 평소엔 보지 않아도 돼요.")
                            .font(.caption2)
                    }
                    Section {
                        Button {
                            showWidgetGuide = true
                        } label: {
                            Label("홈 화면·시계 화면에 두기", systemImage: "rectangle.stack.badge.plus")
                        }
                        Button {
                            showOnboardingConfirm = true
                        } label: {
                            Label("처음 안내 다시 보기", systemImage: "arrow.counterclockwise.circle")
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
                    if KeychainStore.sessionToken() != nil {
                        Section {
                            Button {
                                auth.signOut()
                                dismiss()
                            } label: {
                                Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                if isDeletingAccount {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        Text("삭제 중…")
                                    }
                                } else {
                                    Label("계정 삭제", systemImage: "trash")
                                }
                            }
                            .disabled(isDeletingAccount)
                        } header: {
                            Text("계정")
                        } footer: {
                            Text("계정과 서버에 저장된 이용 기록을 삭제해요. 충전한 횟수·무료 혜택도 함께 사라지고 되돌릴 수 없어요.")
                                .font(.caption2)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .sheet(isPresented: $showWidgetGuide) {
                WidgetGuideView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(onClose: { showPaywall = false })
            }
            .alert("처음 안내 다시 보기", isPresented: $showOnboardingConfirm) {
                Button("다시 보기") {
                    onboarded = false
                    dismiss()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("권한 안내 화면을 처음부터 다시 봐요. 거절한 권한도 다시 한 번 물어볼 수 있어요.")
            }
            .alert("계정을 삭제할까요?", isPresented: $showDeleteConfirm) {
                Button("삭제", role: .destructive) {
                    Task {
                        isDeletingAccount = true
                        let ok = await auth.deleteAccount()
                        isDeletingAccount = false
                        if ok {
                            dismiss()
                        } else {
                            deleteError = auth.lastError ?? "삭제에 실패했어요. 잠시 후 다시 시도해 주세요."
                        }
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("계정과 서버 이용 기록이 모두 삭제돼요. 충전한 횟수·무료 혜택도 사라지며 되돌릴 수 없어요.")
            }
            .alert("계정 삭제 실패", isPresented: Binding(get: { deleteError != nil },
                                                  set: { if !$0 { deleteError = nil } })) {
                Button("확인", role: .cancel) { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    private var watchSection: some View {
        Section("애플 워치") {
            HStack {
                Text("페어링")
                Spacer()
                StatusPill(kind: connectivity.isPaired ? .ok : .off,
                           label: connectivity.isPaired ? "연결됨" : "안 됨")
            }
            HStack {
                Text("앱 설치")
                Spacer()
                StatusPill(kind: connectivity.isWatchAppInstalled ? .ok : .off,
                           label: connectivity.isWatchAppInstalled ? "설치됨" : "안 됨")
            }
            HStack {
                Text("연결 상태")
                Spacer()
                StatusPill(kind: connectivity.isReachable ? .ok : .off,
                           label: connectivity.isReachable ? "연결됨" : "대기 중")
            }
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
            Button("지금 바로 동기화") { sendStateToWatch(characterState) }
        }
    }

    private var healthSection: some View {
        Section {
            HStack {
                Text("권한")
                Spacer()
                StatusPill(kind: health.isAuthorized ? .ok : .off,
                           label: health.isAuthorized ? "허용됨" : "허용 안 됨")
            }
            Button("건강 권한 다시 묻기") {
                Task {
                    try? await health.requestAuthorization()
                }
            }
            Button("오늘 데이터 새로고침") {
                Task { await reloadHealth() }
            }
            .disabled(healthLoading)
            if !healthMessage.isEmpty {
                Text(healthMessage).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("건강 데이터")
        } footer: {
            Text("운동이나 수면을 시작하는 순간 바로 캐릭터를 바꾸고 싶다면, '단축어' 앱의 자동화에서 '운동' 또는 '수면 모드' 트리거에 'withu 앱 열기' 동작을 더해주세요.")
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
        case .notDetermined: return "아직 요청 안 했어요"
        case .denied: return "거부됨"
        case .authorized, .provisional, .ephemeral: return "허용됨"
        @unknown default: return "—"
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
            ZStack {
                backgroundGradient(for: .idle).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        guideSection(
                            icon: "iphone",
                            tint: .cyan,
                            title: "홈 화면 위젯",
                            steps: [
                                "홈 화면 빈 곳을 길게 눌러주세요",
                                "왼쪽 위 더하기 버튼을 눌러주세요",
                                "검색창에 \"withu\" 라고 입력해주세요",
                                "원하는 크기를 골라 추가해주세요",
                            ]
                        )
                        guideSection(
                            icon: "lock.iphone",
                            tint: .mint,
                            title: "잠금 화면 위젯",
                            steps: [
                                "잠금 화면을 길게 누른 뒤 '맞춤 설정'을 눌러주세요",
                                "꾸밀 잠금 화면을 고르고 위젯 영역을 눌러주세요",
                                "'위젯 추가'를 누르고 \"withu\"를 검색해주세요",
                                "원형·사각형·한 줄 중에서 골라주세요",
                            ]
                        )
                        guideSection(
                            icon: "applewatch",
                            tint: .brown,
                            title: "시계 화면에 올리기",
                            steps: [
                                "워치 화면을 길게 누른 뒤 '편집'을 눌러주세요",
                                "위젯을 올리는 화면까지 옆으로 넘겨주세요",
                                "원하는 자리를 누르고 \"withu\"를 찾아주세요",
                                "고른 다음 크라운을 눌러 마무리해주세요",
                            ]
                        )
                    }
                    .padding(20)
                }
            }
            .navigationTitle("홈 화면에 withu 두기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
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
                Text(title).font(.callout.weight(.semibold))
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
        .frostedCard(cornerRadius: 16)
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
        ZStack {
            backgroundGradient(for: .idle).ignoresSafeArea()
            Form {
                focusSection
                healthSleepSection
                motionSection
                debugSection
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("캐릭터 상태 살펴보기")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections (옮겨옴)

    private var focusSection: some View {
        Section {
            HStack { Text("권한"); Spacer(); Text(focus.authorizationStatusLabel).foregroundStyle(.secondary) }
            HStack { Text("현재 집중 모드"); Spacer(); Text(focus.focusStateLabel).foregroundStyle(.secondary) }
            HStack {
                Text("수면 집중 모드 신호")
                Spacer()
                StatusPill(kind: focus.isFocusFilterSleeping ? .ok : .off,
                           label: focus.isFocusFilterSleeping ? "받는 중" : "꺼짐")
            }
            HStack {
                Text("마지막으로 받은 시각")
                Spacer()
                Text(focus.focusFilterLastPerformAt.map { $0.formatted(date: .omitted, time: .standard) }
                     ?? "아직 없어요")
                    .foregroundStyle(.secondary)
            }
            if let last = focus.lastCheckedAt {
                HStack {
                    Text("마지막 확인")
                    Spacer()
                    Text(last.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(.secondary)
                }
            }
            if !focus.focusFilterPerformLog.isEmpty {
                DisclosureGroup("집중 모드 신호 기록 (최근 \(focus.focusFilterPerformLog.count)번)") {
                    ForEach(Array(focus.focusFilterPerformLog.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Text(entry.date.formatted(date: .omitted, time: .standard))
                                .font(.caption.monospaced())
                            Spacer()
                            Text(entry.sleeping ? "수면 켜짐" : "수면 꺼짐")
                                .font(.caption)
                                .foregroundStyle(entry.sleeping ? .indigo : .secondary)
                        }
                    }
                }
            }
            if !focus.isAuthorized {
                Button("집중 모드 권한 요청") {
                    Task { await focus.requestAuthorization() }
                }
            }
            Button {
                focus.refresh()
                sendStateToWatch(characterState)
            } label: {
                Label("지금 다시 확인", systemImage: "arrow.clockwise.circle.fill")
            }
            if focus.isAuthorized && focus.rawFocusedValue == nil {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("설정 앱 열기", systemImage: "gear")
                }
            }
        } header: {
            Text("수면·집중 모드")
        }
    }

    private var healthSleepSection: some View {
        Section {
            HStack {
                Text("최근 48시간 잠자리 기록")
                Spacer()
                Text("\(health.inBedSampleCount24h)개")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("지금 잠자리 시간대")
                Spacer()
                StatusPill(kind: health.isInBedSchedule ? .ok : .off,
                           label: health.isInBedSchedule ? "맞아요" : "아니에요")
            }
            if let start = health.lastInBedSampleStart {
                HStack {
                    Text("마지막 잠자리 시작")
                    Spacer()
                    Text(start.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("최근 7일 수면 기록")
                Spacer()
                Text("\(health.sleep?.sampleCount ?? 0)개")
                    .foregroundStyle(.secondary)
            }
            if let last = health.sleep?.lastNight {
                HStack {
                    Text("마지막 수면 시작")
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
                Label("수면 기록 다시 가져오기", systemImage: "arrow.clockwise.circle.fill")
            }
        } header: {
            Text("건강 앱 수면 정보")
        }
    }

    private var motionSection: some View {
        Section {
            HStack {
                Text("운동 중으로 보이나요")
                Spacer()
                StatusPill(kind: health.isLikelyInWorkout ? .ok : .off,
                           label: health.isLikelyInWorkout ? "그런 것 같아요" : "아니에요")
            }
            HStack {
                Text("최근 90초 심박 기록")
                Spacer()
                Text("\(health.recentHRSampleCount)개")
                    .foregroundStyle(.secondary)
            }
            if health.recentHRAverage > 0 {
                HStack {
                    Text("평균 심박수")
                    Spacer()
                    Text("분당 \(Int(health.recentHRAverage))회")
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                Task {
                    await health.refreshWorkoutInference()
                    sendStateToWatch(characterState)
                }
            } label: {
                Label("심박으로 다시 확인", systemImage: "arrow.clockwise.circle.fill")
            }
        } header: {
            Text("운동 감지")
        }
    }

    private var debugSection: some View {
        Section {
            HStack {
                Text("마지막 백그라운드 갱신")
                Spacer()
                Text(lastBgRefreshLabel)
                    .foregroundStyle(.secondary)
            }
            Picker("상태 직접 고르기", selection: $overrideState) {
                Text("자동으로 맡기기 (추천)").tag(CharacterState?.none)
                ForEach(CharacterState.allCases, id: \.self) { state in
                    Text(state.koreanShortLabel).tag(CharacterState?.some(state))
                }
            }
            .pickerStyle(.menu)
            Button {
                sendStateToWatch(characterState)
                WidgetCenter.shared.reloadAllTimelines()
                WidgetCenter.shared.reloadTimelines(ofKind: "withuWidget")
                WidgetCenter.shared.reloadTimelines(ofKind: "withuComplication")
            } label: {
                Label("위젯 지금 새로고침", systemImage: "arrow.clockwise.circle.fill")
            }
            Button {
                ConnectivityManager.shared.sendAllToWatch()
            } label: {
                Label("워치로 모든 그림 다시 동기화", systemImage: "applewatch.radiowaves.left.and.right")
            }
            HStack {
                Text("워치로 보내는 중")
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
            Text("위젯·워치 다시 맞추기")
        } footer: {
            Text("백그라운드 갱신은 폰이 앱을 잠깐 깨워 화면을 새로 맞춘 시각이에요. 30분에서 몇 시간 간격으로 폰이 알아서 정해요. 워치 동기화는 앱을 처음 켜거나 워치 앱을 새로 설치하면 한 번 자동으로 이뤄져요.")
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
