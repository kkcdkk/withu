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

    /// StatusPill 종류로 매핑. nil 이면 표시하지 않음 (아직 요청 전).
    var statusKind: StatusKind? {
        switch self {
        case .pending, .requesting: return nil
        case .granted: return .ok
        case .denied:  return .warning
        case .skipped: return .off
        }
    }

    /// 권한 결과 한 줄 안내. 평서형.
    var statusLabel: String {
        switch self {
        case .pending, .requesting: return ""
        case .granted: return String(localized: "연결되었어요")
        case .denied:  return String(localized: "나중에 설정에서 켤 수 있어요")
        case .skipped: return String(localized: "나중에 설정에서 켤 수 있어요")
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
                    .transition(.opacity)
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
                    .fill(i <= step.progressIndex ? Color.withuPink : Color.secondary.opacity(0.2))
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
                ZStack {
                    Circle()
                        .fill(Color.withuPink.opacity(0.22))
                        .frame(width: 240, height: 240)
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(Color.withuPinkText)
                }
                VStack(spacing: 8) {
                    Text("Withy")
                        .font(.title3.weight(.semibold))
                    Text("내 캐릭터가 일상에 함께해요")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "wand.and.stars", tint: .withuPink,
                           title: "내 캐릭터 만들기",
                           description: "원하는 외형과 성격으로 캐릭터를 만들어요")
                featureRow(icon: "heart.text.square.fill", tint: .mint,
                           title: "건강 데이터 연동",
                           description: "운동·수면·걸음에 맞춰 캐릭터 상태가 바뀌어요")
                featureRow(icon: "applewatch", tint: .cyan,
                           title: "워치 동기화",
                           description: "애플워치 시계 화면과 메인 화면에도 함께해요")
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
            body: "걸음·운동·수면 데이터를 캐릭터 상태에 반영해요.",
            details: [
                (symbol: "figure.run", text: "운동을 시작하면 캐릭터도 같이 운동해요"),
                (symbol: "moon.fill", text: "잠든 시간에는 캐릭터도 잠들어요"),
                (symbol: "clock", text: "허용하지 않으면 시간대만 보고 움직여요")
            ],
            result: healthResult,
            skipNote: "허용해도 데이터는 기기 안에서만 처리돼요."
        )
    }

    private func requestHealth() async {
        healthResult = .requesting
        do {
            try await HealthKitManager.shared.requestAuthorization()
            // 요청 절차 성공 ≠ 허용 (거부해도 에러 없음). 걸음 probe 는 새 기기/거부 구분이
            // 안 되므로(0 걸음), 시트에서 결정을 마쳤으면(.notRequested 아님) 연결로 표시 —
            // 허용했는데 '허용 안 됨'이 뜨는 오판(항목 7) 방지. 진짜 거부는 이후 화면들이 보정.
            healthResult = HealthKitManager.shared.authStatus == .notRequested ? .denied : .granted
        } catch {
            healthResult = .denied
        }
        await Task.sleep(seconds: 0.5)
        advance()
    }

    // MARK: - Location

    private var locationContent: some View {
        permissionPage(
            icon: "cloud.sun.fill",
            tint: .cyan,
            title: "지금 날씨를 받아올게요",
            body: "현재 위치의 날씨를 받아 배경에 반영해요.",
            details: [
                (symbol: "cloud.rain.fill", text: "비·눈·맑음·밤에 따라 배경이 바뀌어요"),
                (symbol: "lock.shield.fill", text: "위치는 기기 안에서만 쓰고 서버에 저장하지 않아요"),
                (symbol: "person.fill", text: "허용하지 않으면 배경 없이 캐릭터만 보여요")
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
            body: "걸음 목표 달성·잠잘 시간·운동 종료를 알려드려요.",
            details: [
                (symbol: "hand.raised.fill", text: "방해되지 않게 하루 몇 번만 보내요"),
                (symbol: "checkmark.circle", text: "허용하지 않아도 주요 기능은 모두 작동해요")
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
            icon: "moon.zzz.fill",
            tint: .indigo,
            title: "캐릭터와 함께 수면",
            body: "수면 집중 모드를 감지해 캐릭터를 재워줘요.",
            details: [
                (symbol: "moon.zzz", text: "설정에서 집중·수면 필터에 Withy 를 연결하면 더 정확해요"),
                (symbol: "gearshape", text: "연결 방법은 메인 화면 설정에서 다시 볼 수 있어요"),
                (symbol: "bed.double.fill", text: "허용하지 않으면 프로필에 적은 수면 시간만 써요")
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
                    .fill(Color.withuPink.opacity(0.22))
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.withuPinkText)
            }
            VStack(spacing: 8) {
                Text("준비가 끝났어요")
                    .font(.title3.weight(.semibold))
                Text("이제 내 캐릭터를 만들어 봐요")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                summaryRow("건강 데이터", healthResult)
                summaryRow("날씨", locationResult)
                summaryRow("알림", notificationResult)
                summaryRow("수면 감지", focusResult)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .pixelCardSurface()
            .padding(.horizontal, 24)
            Spacer()
            Text("켜지 않은 권한은 메인 화면 설정에서 다시 켤 수 있어요.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func summaryRow(_ label: String, _ result: PermissionResult) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            StatusPill(kind: result.statusKind ?? .off, label: LocalizedStringKey(summaryShortLabel(result)))
        }
    }

    private func summaryShortLabel(_ r: PermissionResult) -> String {
        switch r {
        case .granted: return String(localized: "연결됨")
        case .denied:  return String(localized: "나중에")
        case .skipped: return String(localized: "나중에")
        case .pending, .requesting: return String(localized: "아직")
        }
    }

    // MARK: - Permission page template

    private func permissionPage(icon: String, tint: Color, title: String,
                                 body bodyText: String,
                                 details: [(symbol: String, text: String)],
                                 result: PermissionResult,
                                 skipNote: String?) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(tint.opacity(0.22))
                        .frame(width: 120, height: 120)
                    Image(systemName: icon)
                        .font(.system(size: 48))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(bodyText)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 28)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                ForEach(details, id: \.text) { d in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: d.symbol)
                            .font(.caption)
                            .foregroundStyle(tint)
                            .frame(width: 18)
                        Text(d.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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
            if let kind = result.statusKind {
                StatusPill(kind: kind, label: LocalizedStringKey(result.statusLabel))
                    .padding(.top, 12)
            }
            Spacer()
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            switch step {
            case .welcome:
                primaryButton("시작할게요") { advance() }
            case .health, .location, .notification, .focus:
                primaryButton(currentRequestButtonLabel) {
                    Task { await currentRequest() }
                }
                .disabled(currentResult == .requesting)
            case .done:
                primaryButton("캐릭터 만들러 가기") { onComplete() }
            }
            // 건너뛰기 슬롯 — 높이를 항상 예약해 CTA 버튼 위치를 모든 스텝에서 고정.
            // (예전엔 pending 일 때만 노출돼서, 허용을 누르면 슬롯이 사라지며 버튼이
            //  아래로 점프해 헷갈리던 문제. Android OnboardingScreen 과 동일 처리.)
            ZStack {
                if step != .welcome && step != .done && currentResult == .pending {
                    Button("건너뛰기") {
                        markSkippedAndAdvance()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(height: 28)
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
        if currentResult == .requesting { return String(localized: "요청 중…") }
        return String(localized: "허용하고 다음으로")
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
            Text(title).frame(maxWidth: .infinity)
        }
        // 다른 초록 CTA 와 동일한 픽셀 테두리 스타일 (Galmuri 폰트 + 계단 윤곽).
        .buttonStyle(WithuCTAButtonStyle())
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
    // 2026-07: 브랜드 색 전환 — 연핑크 → 그린(기존 withuGreen 새싹 톤 기준).
    // 프로퍼티 이름은 사용처가 많아 호환을 위해 유지 (withuPink* = 그린 계열 값).
    /// withu 의 메인 액센트 (구 핑크 자리). 라이트 = 새싹 그린(withuGreen 과 동일 톤), 다크 = 딥그린.
    static let withuPink = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.48, blue: 0.36, alpha: 1.0)
            : UIColor(red: 0.55, green: 0.80, blue: 0.58, alpha: 1.0)
    })

    /// 캐릭터 원 배경, soft chip 배경 등 더 옅은 톤.
    static let withuPinkSoft = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.26, green: 0.40, blue: 0.31, alpha: 1.0)
            : UIColor(red: 0.72, green: 0.89, blue: 0.74, alpha: 1.0)
    })

    /// 글자·링크·배지 텍스트용 진한 그린 — 파스텔 withuPink 는 글자로 쓰면
    /// 대비가 낮아 안 읽힘. 면적(버튼 배경 등)은 withuPink, 텍스트는 이걸 사용.
    static let withuPinkText = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.62, green: 0.86, blue: 0.66, alpha: 1.0)
            : UIColor(red: 0.20, green: 0.50, blue: 0.28, alpha: 1.0)
    })

    /// CTA 버튼용 그린 — 새싹 톤의 연한 초록(귀여운 파스텔). 테두리(withuCTABorder)와 짝.
    static let withuCTAGreen = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.22, green: 0.66, blue: 0.34, alpha: 1.0)
            : UIColor(red: 0.34, green: 0.80, blue: 0.46, alpha: 1.0)
    })

    /// CTA 버튼 테두리 — 채운 초록보다 진한 딥그린(사용자 선호: 이 버전 유지).
    static let withuCTABorder = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.42, blue: 0.22, alpha: 1.0)
            : UIColor(red: 0.16, green: 0.52, blue: 0.28, alpha: 1.0)
    })

    /// 카드/홈 항목 픽셀 테두리 — 따뜻한 먹빛(까망에 갈색기). 동물의 숲/레트로 카툰 윤곽.
    static let withuPixelOutline = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.09, blue: 0.08, alpha: 1.0)
            : UIColor(red: 0.20, green: 0.16, blue: 0.12, alpha: 1.0)
    })

    /// 카드 표면 — 따뜻한 크림. 먹빛 테두리와 짝. 어두운 글자(.primary)와 대비 충분.
    static let withuCardFill = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.17, green: 0.15, blue: 0.13, alpha: 1.0)
            : UIColor(red: 0.99, green: 0.97, blue: 0.91, alpha: 1.0)
    })

    /// 화면 배경 — 카드보다 살짝 진한 따뜻한 베이지(동물의 숲 톤).
    static let withuWarmBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.11, green: 0.10, blue: 0.09, alpha: 1.0)
            : UIColor(red: 0.96, green: 0.91, blue: 0.80, alpha: 1.0)
    })

    /// 보조 액센트 — 채도 낮춘 세이지 그린. 핑크(포인트)와 짝을 이루는 2색 체계의 '보조'.
    /// withuGreen(배경 기조)보다 차분해 카드 아이콘 tint 로 써도 배경과 뭉개지지 않음.
    static let withuSage = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.45, green: 0.55, blue: 0.44, alpha: 1.0)
            : UIColor(red: 0.55, green: 0.66, blue: 0.50, alpha: 1.0)
    })

    /// withu 의 브랜드 그린 — 새싹 캐릭터 색. 배경 그라데이션 기조에 사용.
    /// 라이트 = 연한 새싹색, 다크 = 채도 낮은 딥그린.
    static let withuGreen = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.48, blue: 0.36, alpha: 1.0)
            : UIColor(red: 0.55, green: 0.80, blue: 0.58, alpha: 1.0)
    })

    /// 홈 '함께할 캐릭터 생성하기' 버튼 전용 — 브랜드 그린 전환 후에도 이 버튼만
    /// 원래 연핑크 유지 (사용자 지정). 라이트 = 파스텔, 다크 = 채도 낮은 와인.
    static let withuHeroPink = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.55, green: 0.32, blue: 0.42, alpha: 1.0)
            : UIColor(red: 1.0,  green: 0.78, blue: 0.85, alpha: 1.0)
    })

    /// 온보딩 배경 gradient 의 상단 — 거의 흰색-그린 / 다크 모드 매우 어두운 딥그린.
    static let withuPinkBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.08, green: 0.11, blue: 0.09, alpha: 1.0)
            : UIColor(red: 0.95, green: 0.99, blue: 0.96, alpha: 1.0)
    })
}
