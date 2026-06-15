//
//  LoginGateView.swift
//  withu (iOS)
//
//  로그인 게이트 — 온보딩 후, 메인 진입 전. Sign in with Apple.
//

import SwiftUI
import AuthenticationServices

struct LoginGateView: View {
    @State private var auth = AuthManager.shared

    var body: some View {
        ZStack {
            backgroundGradient(for: .idle).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.withuPink.opacity(0.22))
                        .frame(width: 200, height: 200)
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(Color.withuPink)
                }

                VStack(spacing: 8) {
                    Text("withu 시작하기")
                        .font(.title3.weight(.semibold))
                    Text("로그인하면 내 캐릭터와 무료 체험이\n어느 기기에서나 이어져요.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                if auth.isAuthenticating {
                    ProgressView("로그인 중…")
                }

                if let err = auth.lastError {
                    WarningBanner(text: err)
                        .padding(.horizontal, 20)
                }

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    auth.handleAuthorization(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .padding(.horizontal, 32)
                .disabled(auth.isAuthenticating)

                Text("로그인하면 개인정보처리방침과 이용약관에 동의하는 것으로 봐요.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                #if DEBUG
                Button("로그인 없이 둘러보기 (개발용)") {
                    auth.skipForDebug()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
                #else
                Spacer().frame(height: 16)
                #endif
            }
        }
    }
}
