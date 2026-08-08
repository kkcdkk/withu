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
    /// 이미지 모델 — "gpt-image-2" 명시 시 서버가 v2 사용 (마젠타 배경 → 클라 크로마키 제거).
    /// nil 이면 서버 기본(gpt-image-1.5, 진짜 투명 배경).
    var model: String? = nil
    /// 생성 모니터링 표시용 — 사용자가 실제 입력한 원문. OpenAI 로는 안 감(서버가 로깅만).
    var userInput: String? = nil
    /// 그 입력이 어떤 칸이었는지 라벨 ("설명"/"다듬기"/"참고사진 수정" 등).
    var inputField: String? = nil
}

struct GenerateImageResponse: Codable {
    let imageBase64: String
    let seed: Int
    let revisedPrompt: String?
    /// 차감 후 갱신된 잔액(로그인 시). 앱 캐시 갱신용.
    var entitlement: Entitlement? = nil
    /// 서버가 이번 생성을 '계정 무료 1회'로 소진했는지 — true 면 클라는 캔디 미차감.
    var freeConsumed: Bool? = nil
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

/// POST /iap/verify 요청 (convertToSnakeCase → signed_transaction).
struct IapVerifyRequest: Codable {
    let signedTransaction: String
}

/// POST /redeem 요청.
struct RedeemRequest: Codable {
    let code: String
}

// MARK: - 갤러리 클라우드 백업

/// GET /gallery 응답의 항목 (서버 gallery_items 메타 — snake_case → camelCase).
struct GalleryBackupItem: Codable {
    let id: String
    let sourceState: String?
    let createdAt: Int?      // epoch 초 (클라 업로드 값 그대로)
    let hasFrame1: Bool?
    let batchId: String?
    let prompt: String?
}

/// GET /gallery 응답.
struct GalleryListResponse: Codable {
    let items: [GalleryBackupItem]
}

/// PUT /gallery/<id> 요청 (convertToSnakeCase → image_b64 / frame1_b64 …).
struct GalleryUploadRequest: Codable {
    let imageB64: String
    let frame1B64: String?
    let sourceState: String
    let createdAt: Int       // epoch 초
    let hasFrame1: Bool
    let batchId: String?
    let prompt: String?
}

/// POST /referral/apply 요청.
struct ReferralRequest: Codable {
    let code: String
}
