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
}

struct GenerateImageResponse: Codable {
    let imageBase64: String
    let seed: Int
}

struct APIErrorDetail: Codable {
    let detail: String
}
