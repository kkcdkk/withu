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
}

struct APIErrorDetail: Codable {
    let detail: String
}
