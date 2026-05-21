//
//  OnboardingView.swift
//  withu
//
//  첫 실행 시 1번만 보이는 환영/안내 화면.
//

import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Text("🐰")
                    .font(.system(size: 100))
                    .frame(width: 160, height: 160)
                    .background(
                        Circle().fill(Color(red: 1.0, green: 0.85, blue: 0.92))
                    )

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
                featureRow(icon: "wand.and.stars",
                           tint: Color(red: 1.0, green: 0.78, blue: 0.85),
                           title: "AI 캐릭터 생성",
                           description: "원하는 외형 / 성격으로 내 캐릭터 만들기")
                featureRow(icon: "heart.text.square.fill",
                           tint: .mint,
                           title: "건강 데이터 연동",
                           description: "운동 / 수면 / 걸음에 맞춰 캐릭터 상태 변화")
                featureRow(icon: "applewatch",
                           tint: .cyan,
                           title: "워치 동기화",
                           description: "Apple Watch 컴플리케이션 / 메인 화면에도 표시")
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 8) {
                Button {
                    onComplete()
                } label: {
                    Text("시작하기")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 1.0, green: 0.78, blue: 0.85))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Text("건강 / 알림 / 위치 권한을 차례로 요청해요.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.95, blue: 0.97),
                    Color(.systemBackground)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private func featureRow(icon: String, tint: Color,
                            title: String, description: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.25))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
