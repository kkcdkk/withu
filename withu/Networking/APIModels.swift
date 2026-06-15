//
//  APIModels.swift
//  withu
//

import Foundation

struct GenerateImageRequest: Codable {
    let prompt: String
    let referenceImageBase64: String?
    let steps: Int
    let width: Int
    let height: Int
    let quality: String?   // "low" | "medium" | "high" | "auto"
    let artStyle: String?  // "casual" | "pixel"
    let style: String?     // legacy
    /// 요청 종류 — nil 또는 "character" 면 서버 SYSTEM_PROMPT 적용 (캐릭터 가드레일).
    /// "background" 이면 raw prompt 그대로 → 풍경/배경 생성용.
    /// var + default → 기존 caller 그대로, 새 caller 만 명시.
    var kind: String? = nil
}

struct GenerateImageResponse: Codable {
    let imageBase64: String
    let seed: Int
    let revisedPrompt: String?
    /// 차감 후 갱신된 잔액(로그인 시). 앱 캐시 갱신용.
    var entitlement: Entitlement? = nil
}

/// 402 응답 — 무료/크레딧 소진.
struct PaymentRequiredResponse: Codable {
    let detail: String?
    let balance: Entitlement?
}

struct APIErrorDetail: Codable {
    let detail: String
}

// MARK: - 계정 / 권리 (Phase 2)

/// 서버가 보유한 사용자 권리 스냅샷. 표시용 캐시.
/// 서버는 snake_case 로 반환 → convertFromSnakeCase 로 디코드.
struct Entitlement: Codable, Equatable {
    let freeBatchRemaining: Int
    let freeSingleRemaining: Int
    let credits: Int
    let subActive: Bool
    let subExpiresAt: Int?
    let referralCode: String?
}

/// POST /auth/apple 요청 (convertToSnakeCase → identity_token).
struct AppleAuthRequest: Codable {
    let identityToken: String
}

/// POST /auth/apple 응답.
struct AppleAuthResponse: Codable {
    let sessionToken: String
    let expiresAt: Int
    let entitlement: Entitlement?
}

/// GET /me 응답.
struct MeResponse: Codable {
    let entitlement: Entitlement
}
