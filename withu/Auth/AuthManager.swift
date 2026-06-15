//
//  AuthManager.swift
//  withu (iOS)
//
//  Sign in with Apple 로그인 상태 관리.
//  서버 권위: 무료/크레딧/구독 잔액은 서버(entitlement)가 보유, 여기선 캐시.
//

import Foundation
import AuthenticationServices

@MainActor
@Observable
final class AuthManager {
    static let shared = AuthManager()

    enum State {
        case unknown    // 앱 시작 직후 — 복원 시도 중
        case signedOut
        case signedIn
    }

    private(set) var state: State = .unknown
    private(set) var entitlement: Entitlement?
    private(set) var lastError: String?
    private(set) var isAuthenticating = false

    private init() {}

    /// 앱 시작 — Keychain 토큰 있으면 복원 + 서버 검증.
    func restore() async {
        guard KeychainStore.sessionToken() != nil else {
            state = .signedOut
            return
        }
        state = .signedIn            // 낙관적 — 캐시된 토큰 신뢰, 백그라운드 검증
        await refreshEntitlement()
        await checkCredentialState()
    }

    /// SignInWithAppleButton 의 onCompletion 핸들러.
    func handleAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            lastError = "로그인에 실패했어요. 다시 시도해 주세요."
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                lastError = "Apple 로그인 정보를 읽지 못했어요."
                return
            }
            let appleUserId = credential.user
            Task { await completeSignIn(identityToken: identityToken, appleUserId: appleUserId) }
        }
    }

    private func completeSignIn(identityToken: String, appleUserId: String) async {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let resp = try await APIClient.shared.authenticateApple(identityToken: identityToken)
            KeychainStore.saveSessionToken(resp.sessionToken)
            KeychainStore.saveAppleUserId(appleUserId)
            entitlement = resp.entitlement
            state = .signedIn
            lastError = nil
        } catch {
            lastError = "로그인 처리에 실패했어요. 잠시 후 다시 시도해 주세요."
        }
    }

    /// 서버 권리 스냅샷 갱신. 401 이면 토큰 만료로 보고 로그아웃.
    func refreshEntitlement() async {
        do {
            entitlement = try await APIClient.shared.fetchMe()
        } catch {
            if case APIError.server(let status, _) = error, status == 401 {
                signOut()
            }
        }
    }

    func signOut() {
        KeychainStore.clear()
        entitlement = nil
        state = .signedOut
    }

    #if DEBUG
    /// 개발용 — 로그인 없이 메인 둘러보기. capability 추가 전이나 시뮬레이터 테스트에.
    /// 세션 토큰이 없어 서버는 ENFORCE_AUTH=false 경로로 통과(생성 가능).
    func skipForDebug() { state = .signedIn }
    #endif

    /// 포그라운드 진입 시 Apple 권한 철회/계정 삭제 감지.
    func checkCredentialState() async {
        guard let userId = KeychainStore.appleUserId() else { return }
        let provider = ASAuthorizationAppleIDProvider()
        let credState = try? await provider.credentialState(forUserID: userId)
        if credState == .revoked || credState == .notFound {
            signOut()
        }
    }
}
