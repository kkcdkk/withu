//
//  PaywallView.swift
//  withu (iOS)
//
//  구독 + 횟수 팩 구매 화면. 한도를 다 썼거나 설정에서 진입.
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

                    if store.isSubscriber {
                        subscribedCard
                    } else if let sub = store.subscription {
                        subscriptionCard(sub)
                    }

                    if !store.creditPacks.isEmpty {
                        creditSection
                    }

                    if store.products.isEmpty {
                        ProgressView("불러오는 중…")
                            .padding(.top, 20)
                    }

                    if let err = store.lastError {
                        WarningBanner(text: err)
                    }

                    redeemSection

                    referralSection

                    Button("구매 복원") {
                        Task { await store.restore(); onClose() }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                    HelperFooter("구독은 언제든 설정 > Apple ID 에서 해지할 수 있어요. 충전한 횟수는 사라지지 않아요.")
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
                        Text("적용").font(.callout.weight(.semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.withuPink)
                .disabled(redeemInput.trimmingCharacters(in: .whitespaces).isEmpty || isRedeeming)
            }
            .frostedCard()
            if let msg = redeemMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func redeem() async {
        isRedeeming = true
        defer { isRedeeming = false }
        do {
            let ent = try await APIClient.shared.redeem(code: redeemInput)
            auth.applyEntitlement(ent)
            redeemMessage = "적용됐어요! 잔액에 반영됐어요."
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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(myCode)
                            .font(.title3.weight(.semibold))
                    }
                    Spacer()
                    ShareLink(item: "withu 같이 해요! 초대 코드 \(myCode) 를 입력하면 둘 다 보너스를 받아요.") {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                            .foregroundStyle(Color.withuPink)
                    }
                }
                .frostedCard()
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
                        Text("적용").font(.callout.weight(.semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.withuPink)
                .disabled(referralInput.trimmingCharacters(in: .whitespaces).isEmpty || isApplyingReferral)
            }
            .frostedCard()

            if let msg = referralMessage {
                Text(msg)
                    .font(.caption)
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
            referralMessage = "초대 코드가 적용됐어요! 보너스를 받았어요."
            referralInput = ""
        } catch {
            referralMessage = error.koreanizedDescription
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("오늘 \(GenerationQuota.remainingToday())번 만들 수 있어요")
                .font(.title3.weight(.semibold))
            Text(store.isSubscriber
                 ? "구독 중이에요. 매일 넉넉하게 만들 수 있어요."
                 : "더 만들고 싶다면 구독하거나 횟수를 충전해요.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frostedCard(cornerRadius: 18)
    }

    private var subscribedCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("구독 중")
                    .font(.callout.weight(.semibold))
                Text("하루 \(GenerationQuota.subscriberDailyLimit)번까지 만들 수 있어요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frostedCard()
    }

    private func subscriptionCard(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("withu 구독")
                        .font(.callout.weight(.semibold))
                    Text("매일 \(GenerationQuota.subscriberDailyLimit)번씩 만들 수 있어요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.callout.weight(.semibold))
            }
            Button {
                Task { await store.purchase(product); onClose() }
            } label: {
                Text("구독하기")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.withuPink)
            .disabled(store.isPurchasing)
        }
        .frostedCard()
    }

    private var creditSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("횟수 충전") {
                Text("지금 \(auth.entitlement?.credits ?? GenerationQuota.credits())회 보유")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            ForEach(store.creditPacks, id: \.id) { pack in
                creditRow(pack)
            }
        }
    }

    private func creditRow(_ pack: Product) -> some View {
        let amount = StoreManager.ProductID.creditAmount[pack.id] ?? 0
        return Button {
            Task { await store.purchase(pack); onClose() }
        } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.withuPink.opacity(0.18))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "wand.and.stars")
                            .font(.title3)
                            .foregroundStyle(Color.withuPink)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(amount)회 충전")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("만료 없이 계속 쓸 수 있어요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(pack.displayPrice)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frostedCard()
        }
        .buttonStyle(.plain)
        .disabled(store.isPurchasing)
    }
}
