//
//  ImageProcessing.swift
//  withu
//
//  사용자가 직접 첨부한 이미지를 캐릭터 슬롯에 쓰기 좋게 가공.
//  - 배경 제거 (iOS 17+ Vision Framework)
//  - 정사각형 1024x1024 정규화 (center crop + resize)
//

import Foundation
import UIKit
import Vision
import CoreImage

enum ImageProcessing {

    enum ProcessingError: LocalizedError {
        case invalidImage
        case noForeground
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .invalidImage:  return "이미지가 유효하지 않아요."
            case .noForeground:  return "이미지에서 대상을 찾지 못했어요. 더 또렷한 사진을 시도해보세요."
            case .renderFailed:  return "이미지 변환 실패."
            }
        }
    }

    /// 사진 첨부 흐름의 한 번 호출: 배경 제거 → 정사각형 정규화.
    static func prepareForCharacter(_ image: UIImage, target: CGFloat = 1024) async throws -> UIImage {
        let cutout = try await removeBackground(from: image)
        return normalizeSquare(cutout, target: target)
    }

    /// AI 생성 결과처럼 가짜 체커보드 배경이 박혀 있을 수 있는 이미지를
    /// 베스트-에포트로 진짜 alpha PNG 로 변환.
    /// Vision 이 전경을 못 잡으면 원본을 그대로 반환 (사용자 노출 안 함).
    static func bestEffortTransparent(_ image: UIImage) async -> UIImage {
        do {
            return try await removeBackground(from: image)
        } catch {
            return image
        }
    }

    // MARK: - 배경 제거 (Vision)

    /// iOS 17+ 의 VNGenerateForegroundInstanceMaskRequest 로 전경 추출.
    static func removeBackground(from image: UIImage) async throws -> UIImage {
        guard let cgImage = image.cgImage else { throw ProcessingError.invalidImage }

        let handler = VNImageRequestHandler(cgImage: cgImage,
                                            orientation: cgOrientation(image.imageOrientation))
        let request = VNGenerateForegroundInstanceMaskRequest()

        try handler.perform([request])
        guard let result = request.results?.first else {
            throw ProcessingError.noForeground
        }

        let pixelBuffer = try result.generateMaskedImage(
            ofInstances: result.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgOutput = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw ProcessingError.renderFailed
        }
        return UIImage(cgImage: cgOutput, scale: image.scale, orientation: .up)
    }

    // MARK: - 정사각형 정규화

    /// center crop → 1024x1024 (또는 target) 으로 리사이즈. 투명 배경 유지.
    static func normalizeSquare(_ image: UIImage, target: CGFloat = 1024) -> UIImage {
        let size = image.size
        let side = Swift.min(size.width, size.height)
        let crop = CGRect(
            x: (size.width - side) / 2,
            y: (size.height - side) / 2,
            width: side,
            height: side
        )

        // crop 한 다음 target 크기로 그림
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false   // 알파 채널 유지
        format.scale = 1
        let canvas = CGSize(width: target, height: target)
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)

        return renderer.image { _ in
            // cgImage 가 있으면 직접 crop
            if let cg = image.cgImage, let croppedCG = cg.cropping(to: crop) {
                UIImage(cgImage: croppedCG).draw(in: CGRect(origin: .zero, size: canvas))
            } else {
                // fallback: 원본 그대로 그려도 일단 동작
                image.draw(in: CGRect(origin: .zero, size: canvas))
            }
        }
    }

    // MARK: - Helpers

    private static func cgOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up:            return .up
        case .upMirrored:    return .upMirrored
        case .down:          return .down
        case .downMirrored:  return .downMirrored
        case .left:          return .left
        case .leftMirrored:  return .leftMirrored
        case .right:         return .right
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }
}
