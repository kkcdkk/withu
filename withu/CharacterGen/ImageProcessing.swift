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

    /// CIContext 는 생성 비용이 큰 객체 — 1개를 공유 재사용 (immutable, thread-safe).
    private static let sharedCIContext = CIContext()

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
    /// Vision 이 전경을 못 잡거나 15초 안에 안 끝나면 원본을 그대로 반환.
    /// (일부 이미지에서 Vision 이 매우 느리거나 hang 하는 케이스 안전망.)
    static func bestEffortTransparent(_ image: UIImage, timeoutSeconds: Double = 15) async -> UIImage {
        await withTaskGroup(of: UIImage?.self) { group in
            group.addTask {
                do { return try await removeBackground(from: image) }
                catch { return nil }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                return nil   // timeout → 원본 fallback
            }
            // 먼저 끝난 결과를 채택, 나머지 task 는 cancel
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? image
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
        guard let cgOutput = sharedCIContext.createCGImage(ciImage, from: ciImage.extent) else {
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

    /// 알파(투명)가 있으면 흰 배경에 합성해 평탄화.
    /// frame0 은 생성(흰배경)인데 frame1 은 edit 라 모델이 가끔 알파를 만들어 배경이 어긋남 → 통일용.
    /// 알파 없으면 원본 그대로 반환(no-op).
    static func flattenedOnWhite(_ image: UIImage) -> UIImage {
        if let cg = image.cgImage {
            switch cg.alphaInfo {
            case .none, .noneSkipLast, .noneSkipFirst:
                return image   // 알파 없음 — 평탄화 불필요
            default:
                break
            }
        }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: image.size))
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    // MARK: - frame 1 정규화 (크기 · 위치 · 배경 강제)

    /// 전경(알파 > 임계)이 차지하는 bounding box (좌상단 원점, 픽셀). 전경 없으면 nil.
    /// 표준 비트맵 컨텍스트 — 변환 없이 draw 하면 buffer row 0 = 이미지 상단.
    private static func alphaBoundingBox(_ image: UIImage, threshold: UInt8 = 10) -> CGRect? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * w * 4
            for x in 0..<w where buf[row + x * 4 + 3] > threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// removeBackground + 타임아웃. 실패/타임아웃 → nil (폴백은 호출부가 결정).
    private static func removeBackgroundTimed(_ image: UIImage, timeout: Double = 12) async -> UIImage? {
        await withTaskGroup(of: UIImage?.self) { group in
            group.addTask { try? await removeBackground(from: image) }
            group.addTask { try? await Task.sleep(for: .seconds(timeout)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// 애니메이션 2번째 장면(image)을 reference(1번째)와 같은 크기·위치·흰배경으로 강제.
    /// 전경(Vision)을 잘라 reference 전경 bbox 의 위치·크기에 aspect-fit 으로 흰 캔버스에 재배치.
    /// → 모델이 크기/배경을 바꿔도 결과는 1번째와 동일한 프레이밍·흰배경으로 고정.
    /// Vision 실패·타임아웃 시 흰배경 평탄화로 폴백(기존 동작 — 더 나빠지지 않음).
    static func matchedToReference(_ image: UIImage, reference: UIImage, canvas target: CGFloat = 1024) async -> UIImage {
        guard let imgCut = await removeBackgroundTimed(image),
              let imgBox = alphaBoundingBox(imgCut),
              let croppedCG = imgCut.cgImage?.cropping(to: imgBox),
              let refCut = await removeBackgroundTimed(reference),
              let refBox = alphaBoundingBox(refCut),
              let refCG = refCut.cgImage, refCG.width > 0, refCG.height > 0 else {
            return flattenedOnWhite(image)
        }
        // Vision 이 캐릭터를 아주 작은 조각으로만 잡았을 때(부분 실패) — 그 조각을 확대하면
        // 망가진 frame1 이 되므로, 신뢰도 낮다고 보고 흰배경 평탄화 폴백.
        if let imgW = imgCut.cgImage?.width, let imgH = imgCut.cgImage?.height,
           imgW > 0, imgH > 0,
           imgBox.width / CGFloat(imgW) < 0.35, imgBox.height / CGFloat(imgH) < 0.35 {
            return flattenedOnWhite(image)
        }
        let refW = CGFloat(refCG.width), refH = CGFloat(refCG.height)
        // reference 전경 bbox 를 캔버스 비율로 환산 → 목표 위치/크기
        let dst = CGRect(x: refBox.minX / refW * target,
                         y: refBox.minY / refH * target,
                         width:  refBox.width  / refW * target,
                         height: refBox.height / refH * target)
        // image 전경을 dst 안에 aspect-fit (비율 유지), dst 중앙 정렬
        let fit = min(dst.width / imgBox.width, dst.height / imgBox.height)
        let dw = imgBox.width * fit, dh = imgBox.height * fit
        let drawRect = CGRect(x: dst.midX - dw / 2, y: dst.midY - dh / 2, width: dw, height: dh)

        let canvasSize = CGSize(width: target, height: target)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvasSize))
            UIImage(cgImage: croppedCG).draw(in: drawRect)
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
