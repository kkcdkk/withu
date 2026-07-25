//
//  PaywallView.swift
//  withu (iOS)
//
//  캔디 팩 구매 화면. 캔디가 부족하거나 설정에서 진입. (구독 없음)
//  홈 디자인 언어(frosted 카드 · withuPink primary)를 따름.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @State private var store = StoreManager.shared
    @State private var auth = AuthManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var redeemInput = ""
    @State private var redeemMessage: String?
    @State private var isRedeeming = false

    @State private var referralInput = ""
    @State private var referralMessage: String?
    @State private var isApplyingReferral = false

    /// 닫힐 때 호출 — 호출 측이 남은 횟수 등을 새로고침하도록.
    var onClose: () -> Void = {}

    /// 배경 톤 — 지금 적용 중인 캐릭터 state (홈과 연속감).
    private var heroState: CharacterState {
        SharedAppState.loadMessage()?.state ?? .idle
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    if !store.creditPacks.isEmpty {
                        creditSection
                    }

                    if !store.didAttemptLoad {
                        ProgressView("불러오는 중…")
                            .padding(.top, 20)
                    } else if store.products.isEmpty {
                        VStack(spacing: 10) {
                            Text("지금은 충전 상품을 불러올 수 없어요.\n아래 코드로 충전하거나 잠시 후 다시 열어 주세요.")
                                .font(.pretendard(12, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button {
                                Task { await store.loadProducts() }
                            } label: {
                                Label("다시 시도", systemImage: "arrow.clockwise")
                                    .font(.pretendard(12, relativeTo: .caption))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.top, 12)
                    }

                    if let err = store.lastError {
                        WarningBanner(text: err)
                    }

                    redeemSection

                    referralSection

                    HStack(spacing: 16) {
                        Link("이용약관", destination: URL(string: "https://kkcdkk.github.io/withu/TERMS_OF_SERVICE.html")!)
                        Link("개인정보처리방침", destination: URL(string: "https://kkcdkk.github.io/withu/PRIVACY_POLICY.html")!)
                    }
                    .font(.pretendard(11, relativeTo: .caption2))
                    .tint(Color.withuPinkText)   // 링크는 글자 — 파스텔은 안 읽혀서 진한 로즈
                    .padding(.top, 4)

                    HelperFooter("충전한 캔디는 만료 없이 계속 쓸 수 있어요.")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(backgroundGradient(for: heroState).ignoresSafeArea())
            .navigationTitle("더 만들기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { onClose(); dismiss() }
                }
            }
            .task { await store.loadProducts() }
        }
    }

    private var redeemSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("할인코드")
            HStack(spacing: 10) {
                TextField("코드 입력", text: $redeemInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button {
                    Task { await redeem() }
                } label: {
                    if isRedeeming {
                        ProgressView()
                    } else {
                        Text("적용")
                    }
                }
                .buttonStyle(WithuCTAButtonStyle())
                .disabled(redeemInput.trimmingCharacters(in: .whitespaces).isEmpty || isRedeeming)
            }
            .plainFrostedCard()
            if let msg = redeemMessage {
                Text(msg)
                    .font(.pretendard(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            if GenerationQuota.allowsTestCandyCode {
                Text("테스트: '\(GenerationQuota.testCandyCode)' 입력하면 캔디 \(GenerationQuota.testCandyAmount)개")
                    .font(.pretendard(11, relativeTo: .caption2))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func redeem() async {
        // TestFlight/샌드박스 전용 캔디 코드 — 로컬 캔디 +20 (운영 빌드에선 무시 → 서버로 보냄).
        let trimmed = redeemInput.trimmingCharacters(in: .whitespaces)
        if trimmed.uppercased() == GenerationQuota.testCandyCode, GenerationQuota.allowsTestCandyCode {
            GenerationQuota.addCredits(GenerationQuota.testCandyAmount)
            redeemMessage = String(localized: "🍬 캔디 \(GenerationQuota.testCandyAmount)개 충전됐어요! (테스트)")
            redeemInput = ""
            return
        }
        isRedeeming = true
        defer { isRedeeming = false }
        do {
            let ent = try await APIClient.shared.redeem(code: trimmed)
            auth.applyEntitlement(ent)
            redeemMessage = String(localized: "적용됐어요! 잔액에 반영됐어요.")
            redeemInput = ""
        } catch {
            redeemMessage = error.koreanizedDescription
        }
    }

    @ViewBuilder
    private var referralSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("친구 초대")

            if let myCode = auth.entitlement?.referralCode {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("내 초대 코드")
                            .font(.pretendard(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                        Text(myCode)
                            .font(.pretendard(20, relativeTo: .title3))
                    }
                    Spacer()
                    ShareLink(item: "Withy 같이 해요! 초대 코드 \(myCode) 를 입력하면 둘 다 보너스를 받아요.") {
                        Image(systemName: "square.and.arrow.up")
                            .font(.pretendard(20, relativeTo: .title3))
                            .foregroundStyle(Color.withuPinkText)
                    }
                }
                .plainFrostedCard()
            }

            HStack(spacing: 10) {
                TextField("받은 초대 코드", text: $referralInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button {
                    Task { await applyReferral() }
                } label: {
                    if isApplyingReferral {
                        ProgressView()
                    } else {
                        Text("적용")
                    }
                }
                .buttonStyle(WithuCTAButtonStyle())
                .disabled(referralInput.trimmingCharacters(in: .whitespaces).isEmpty || isApplyingReferral)
            }
            .plainFrostedCard()

            Text("입력하면 두 사람 모두 캔디 5개를 받아요. 초대 보상은 최대 10명까지예요.")
                .font(.pretendard(11, relativeTo: .caption2))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            if let msg = referralMessage {
                Text(msg)
                    .font(.pretendard(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func applyReferral() async {
        isApplyingReferral = true
        defer { isApplyingReferral = false }
        do {
            let ent = try await APIClient.shared.applyReferral(code: referralInput)
            auth.applyEntitlement(ent)
            referralMessage = String(localized: "초대 코드가 적용됐어요! 보너스를 받았어요.")
            referralInput = ""
        } catch {
            referralMessage = error.koreanizedDescription
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("보유하고 있는 캔디는 \(GenerationQuota.displayedCandy())개예요")
                .font(.pretendard(20, relativeTo: .title3))
            Text("더 만들고 싶다면 캔디를 충전해요.")
                .font(.pretendard(16, relativeTo: .callout))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .plainFrostedCard(cornerRadius: 18)
    }

    private var creditSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("캔디 충전")   // 보유 캔디는 상단 헤더에 이미 표시 — 중복 제거
            ForEach(store.creditPacks, id: \.id) { pack in
                creditRow(pack)
            }
        }
    }

    private func creditRow(_ pack: Product) -> some View {
        let amount = StoreManager.ProductID.creditAmount[pack.id] ?? 0
        let name = StoreManager.ProductID.packName[pack.id] ?? "\(amount)회 충전"
        // 4팩이 다 같아 보이면 고르기 어려움 — 중간 팩 하나만 살짝 강조.
        let isRecommended = pack.id == StoreManager.ProductID.credits50
        return Button {
            // 적립까지 성공했을 때만 닫기 — 취소/실패면 열어 둬 에러 배너를 보여준다.
            Task { if await store.purchase(pack) { onClose() } }
        } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.withuPink.opacity(0.18))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "wand.and.stars")
                            .font(.pretendard(20, relativeTo: .title3))
                            .foregroundStyle(Color.withuPinkText)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.pretendard(16, relativeTo: .callout))
                            .foregroundStyle(.primary)
                        if isRecommended {
                            Text("가장 인기")
                                .font(.pretendard(11, relativeTo: .caption2))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.withuPink.opacity(0.18), in: Capsule())
                                .foregroundStyle(Color.withuPinkText)
                        }
                    }
                    Text("캔디 \(amount)개 · 만료 없이 사용할 수 있어요")
                        .font(.pretendard(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(pack.displayPrice)
                    .font(.pretendard(16, relativeTo: .callout))
                    .foregroundStyle(.primary)
            }
            .plainFrostedCard()
            .overlay {
                if isRecommended {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.withuPink.opacity(0.45), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(store.isPurchasing)
    }
}
