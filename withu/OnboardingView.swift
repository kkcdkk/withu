//
//  OnboardingView.swift
//  withu
//
//  첫 실행 시 1번만 보이는 환영/안내 화면 — multi-step.
//  권한 4종을 한 번에 우르르 요청하지 않고 각자 한 페이지씩, 거절해도 흐름 막히지 않게.
//

import SwiftUI
import CoreLocation

private enum OnboardingStep: Int, CaseIterable, Equatable {
    case welcome
    case health
    case location
    case notification
    case focus
    case done

    var progressIndex: Int { rawValue }
    var totalSteps: Int { OnboardingStep.allCases.count - 1 }  // welcome 은 진척도 0으로
}

/// 각 권한 요청의 결과 표시.
private enum PermissionResult: Equatable {
    case pending      // 아직 요청 안 함
    case requesting   // 시트 띄우는 중
    case granted
    case denied
    case skipped

    var label: String {
        switch self {
        case .pending, .requesting: return ""
        case .granted: return "✅ 허용됨"
        case .denied:  return "⚠️ 거절됨 — 설정에서 켤 수 있어요"
        case .skipped: return "건너뜀 — 나중에 설정에서 켤 수 있어요"
        }
    }

    var color: Color {
        switch self {
        case .granted: return .green
        case .denied:  return .orange
        case .skipped: return .secondary
        default:       return .clear
        }
    }
}

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var healthResult: PermissionResult = .pending
    @State private var locationResult: PermissionResult = .pending
    @State private var notificationResult: PermissionResult = .pending
    @State private var focusResult: PermissionResult = .pending

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                progressBar
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }
            ZStack {
                content
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
            .frame(maxHeight: .infinity)
            bottomBar
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(backgroundGradient.ignoresSafeArea())
        .animation(.snappy, value: step)
    }

    // MARK: - Progress

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(1..<OnboardingStep.allCases.count, id: \.self) { i in
                Capsule()
                    .fill(i <= step.progressIndex ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(height: 4)
            }
        }
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:      welcomeContent
        case .health:       healthContent
        case .location:     locationContent
        case .notification: notificationContent
        case .focus:        focusContent
        case .done:         doneContent
        }
    }

    // MARK: - Welcome

    private var welcomeContent: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                Text("🐰")
                    .font(.system(size: 100))
                    .frame(width: 160, height: 160)
                    .background(Circle().fill(Color.withuPinkSoft))
                VStack(spacing: 8) {
                    Text("with U")
                        .font(.largeTitle.weight(.bold))
                    Text("내 캐릭터가 일상에 함께해요")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "wand.and.stars", tint: .withuPink,
                           title: "AI 캐릭터 생성",
                           description: "원하는 외형 / 성격으로 내 캐릭터 만들기")
                featureRow(icon: "heart.text.square.fill", tint: .mint,
                           title: "건강 데이터 연동",
                           description: "운동 / 수면 / 걸음에 맞춰 캐릭터 상태 변화")
                featureRow(icon: "applewatch", tint: .cyan,
                           title: "워치 동기화",
                           description: "Apple Watch 컴플리케이션 / 메인 화면에도 표시")
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Health

    private var healthContent: some View {
        permissionPage(
            icon: "heart.text.square.fill",
            tint: .mint,
            title: "건강 데이터",
            body: "걸음 · 운동 · 수면 데이터를 캐릭터 상태에 반영해요.",
            details: [
                "운동 시작 → 캐릭터가 같이 움직여요",
                "수면 시간 → 캐릭터도 자요",
                "허용 안 하면 시간대만 보고 캐릭터가 움직여요"
            ],
            result: healthResult,
            skipNote: "허용해도 데이터는 기기 안에서만 처리돼요."
        )
    }

    private func requestHealth() async {
        healthResult = .requesting
        do {
            try await HealthKitManager.shared.requestAuthorization()
            healthResult = .granted
        } catch {
            healthResult = .denied
        }
        await Task.sleep(seconds: 0.5)
        advance()
    }

    // MARK: - Location

    private var locationContent: some View {
        permissionPage(
            icon: "location.fill",
            tint: .blue,
            title: "위치 (날씨)",
            body: "현재 위치의 날씨를 받아 배경에 반영해요.",
            details: [
                "비 / 눈 / 맑음 / 야간 → 캐릭터 뒤 배경 자동 변경",
                "위치는 기기 안에서만 처리 · 서버에 저장 X",
                "허용 안 하면 배경이 없어요 (캐릭터만 표시)"
            ],
            result: locationResult,
            skipNote: nil
        )
    }

    private func requestLocation() async {
        locationResult = .requesting
        // WeatherManager.refresh 가 권한 시트 띄움. status 변화 0.5초 폴링.
        WeatherManager.shared.refresh(force: true)
        for _ in 0..<20 {  // 최대 10초 대기
            await Task.sleep(seconds: 0.5)
            let status = WeatherManager.shared.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                locationResult = .granted
                break
            } else if status == .denied || status == .restricted {
                locationResult = .denied
                break
            }
        }
        if locationResult == .requesting { locationResult = .skipped }
        await Task.sleep(seconds: 0.5)
        advance()
    }

    // MARK: - Notification

    private var notificationContent: some View {
        permissionPage(
            icon: "bell.badge.fill",
            tint: .orange,
            title: "알림",
            body: "걸음 목표 달성 · 잠 리마인더 · 운동 종료를 알려드려요.",
            details: [
                "방해 적게 — 하루 몇 번 이내",
                "허용 안 해도 메인 기능은 다 작동"
            ],
            result: notificationResult,
            skipNote: nil
        )
    }

    private func requestNotification() async {
        notificationResult = .requesting
        await NotificationManager.shared.requestAuthorization()
        let status = NotificationManager.shared.authorizationStatus
        notificationResult = (status == .authorized || status == .provisional)
            ? .granted : .denied
        await Task.sleep(seconds: 0.5)
        advance()
    }

    // MARK: - Focus

    private var focusContent: some View {
        permissionPage(
            icon: "moon.stars.fill",
            tint: .indigo,
            title: "수면 / 집중 모드",
            body: "iOS 의 수면 집중 모드 (Sleep Focus) 를 감지해 캐릭터를 자게 해요.",
            details: [
                "권한 + 설정 → 집중 → 수면 → 필터 → withu 연결도 권장",
                "(필터 연결 가이드는 메인 화면 설정에서 다시 볼 수 있어요)",
                "허용 안 하면 자동 감지 없음, 프로필 수면 시간만 사용"
            ],
            result: focusResult,
            skipNote: nil
        )
    }

    private func requestFocus() async {
        focusResult = .requesting
        await FocusModeManager.shared.requestAuthorization()
        focusResult = FocusModeManager.shared.isAuthorized ? .granted : .denied
        await Task.sleep(seconds: 0.5)
        advance()
    }

    // MARK: - Done

    private var doneContent: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 140, height: 140)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(spacing: 8) {
                Text("준비 완료!")
                    .font(.largeTitle.weight(.bold))
                Text("이제 내 캐릭터를 만들어 봐요")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                summaryRow("건강 데이터", healthResult)
                summaryRow("위치 (날씨)", locationResult)
                summaryRow("알림", notificationResult)
                summaryRow("수면 모드", focusResult)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24)
            Spacer()
            Text("거절한 권한은 메인 화면 → 설정 에서 다시 켤 수 있어요.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func summaryRow(_ label: String, _ result: PermissionResult) -> some View {
        HStack {
            Image(systemName: iconFor(result))
                .foregroundStyle(result.color == .clear ? .secondary : result.color)
            Text(label).font(.callout)
            Spacer()
            Text(shortLabel(result))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func iconFor(_ r: PermissionResult) -> String {
        switch r {
        case .granted: return "checkmark.circle.fill"
        case .denied:  return "exclamationmark.triangle.fill"
        case .skipped, .pending, .requesting: return "circle"
        }
    }

    private func shortLabel(_ r: PermissionResult) -> String {
        switch r {
        case .granted: return "허용됨"
        case .denied:  return "거절됨"
        case .skipped: return "건너뜀"
        case .pending, .requesting: return "—"
        }
    }

    // MARK: - Permission page template

    private func permissionPage(icon: String, tint: Color, title: String,
                                 body bodyText: String,
                                 details: [String],
                                 result: PermissionResult,
                                 skipNote: String?) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(tint.opacity(0.2))
                        .frame(width: 110, height: 110)
                    Image(systemName: icon)
                        .font(.system(size: 50))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.title.weight(.bold))
                Text(bodyText)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 28)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                ForEach(details, id: \.self) { d in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(d).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 32)
            if let skipNote {
                Text(skipNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
                    .padding(.top, 4)
            }
            if result != .pending && result != .requesting {
                Text(result.label)
                    .font(.caption)
                    .foregroundStyle(result.color)
                    .padding(.top, 12)
            }
            Spacer()
        }
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        switch step {
        case .welcome:
            primaryButton("시작하기") { advance() }
        case .health, .location, .notification, .focus:
            VStack(spacing: 8) {
                primaryButton(currentRequestButtonLabel) {
                    Task { await currentRequest() }
                }
                .disabled(currentResult == .requesting)
                if currentResult == .pending {
                    Button("건너뛰기") {
                        markSkippedAndAdvance()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        case .done:
            primaryButton("메인 화면으로") { onComplete() }
        }
    }

    private var currentResult: PermissionResult {
        switch step {
        case .health:       return healthResult
        case .location:     return locationResult
        case .notification: return notificationResult
        case .focus:        return focusResult
        default:            return .pending
        }
    }

    private var currentRequestButtonLabel: String {
        if currentResult == .requesting { return "요청 중…" }
        return "허용 요청"
    }

    private func currentRequest() async {
        switch step {
        case .health:       await requestHealth()
        case .location:     await requestLocation()
        case .notification: await requestNotification()
        case .focus:        await requestFocus()
        default: break
        }
    }

    private func markSkippedAndAdvance() {
        switch step {
        case .health:       healthResult = .skipped
        case .location:     locationResult = .skipped
        case .notification: notificationResult = .skipped
        case .focus:        focusResult = .skipped
        default: break
        }
        advance()
    }

    private func advance() {
        let all = OnboardingStep.allCases
        if let idx = all.firstIndex(of: step), idx < all.count - 1 {
            step = all[idx + 1]
        } else {
            onComplete()
        }
    }

    // MARK: - Common

    private func featureRow(icon: String, tint: Color, title: String, description: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.25))
                    .frame(width: 40, height: 40)
                Image(systemName: icon).font(.callout).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.withuPink)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color.withuPinkBackground, Color(.systemBackground)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

// MARK: - Helpers

private extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: Double) async {
        try? await Task<Never, Never>.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

#Preview {
    OnboardingView(onComplete: {})
}

// MARK: - withu Theme colors (light/dark adaptive)

extension Color {
    /// withu 의 메인 핑크. 라이트 = 파스텔, 다크 = 채도 낮은 와인.
    static let withuPink = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.55, green: 0.32, blue: 0.42, alpha: 1.0)
            : UIColor(red: 1.0,  green: 0.78, blue: 0.85, alpha: 1.0)
    })

    /// 캐릭터 원 배경, soft chip 배경 등 더 옅은 톤.
    static let withuPinkSoft = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.45, green: 0.28, blue: 0.36, alpha: 1.0)
            : UIColor(red: 1.0,  green: 0.85, blue: 0.92, alpha: 1.0)
    })

    /// 온보딩 배경 gradient 의 상단 — 거의 흰색-핑크 / 다크 모드 매우 어두운 와인.
    static let withuPinkBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.08, blue: 0.10, alpha: 1.0)
            : UIColor(red: 1.0,  green: 0.95, blue: 0.97, alpha: 1.0)
    })
}
