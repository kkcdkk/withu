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
}

struct GenerateImageResponse: Codable {
    let imageBase64: String
    let seed: Int
    let revisedPrompt: String?
}

struct APIErrorDetail: Codable {
    let detail: String
}
