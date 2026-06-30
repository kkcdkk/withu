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
        // Vision 전에 다운샘플 — 폰 카메라 원본(수천 px)에 그대로 Vision 돌리면 몇 초씩 걸림.
        let maxDim = max(image.size.width, image.size.height)
        let downsized: UIImage
        if maxDim > target {
            let s = target / maxDim
            let fitted = CGSize(width: image.size.width * s, height: image.size.height * s)
            downsized = image.preparingThumbnail(of: fitted) ?? image
        } else {
            downsized = image
        }
        let cutout = try await removeBackground(from: downsized)
        return normalizeSquare(cutout, target: target)
    }

    /// AI 생성 결과처럼 가짜 체커보드 배경이 박혀 있을 수 있는 이미지를
    /// 베스트-에포트로 진짜 alpha PNG 로 변환.
    /// Vision 이 전경을 못 잡거나 15초 안에 안 끝나면 원본을 그대로 반환.
    /// (일부 이미지에서 Vision 이 매우 느리거나 hang 하는 케이스 안전망.)
    static func bestEffortTransparent(_ image: UIImage, timeoutSeconds: Double = 15) async -> UIImage {
        let cutout: UIImage? = await withTaskGroup(of: UIImage?.self) { group in
            group.addTask { try? await removeBackground(from: image) }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                return nil   // timeout → 원본 fallback
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        // Vision 실패/타임아웃 → 원본
        guard let cutout else { return image }

        // 과다 제거 가드 — 흰배경에 밝은 캐릭터면 Vision 이 전경을 거의 다 날려버림.
        // 남은 전경이 거의 없으면 배경 빼기를 포기하고 원본 유지(빈 화면 방지).
        guard let box = alphaBoundingBox(cutout),
              let cg = cutout.cgImage, cg.width > 0, cg.height > 0 else {
            return image
        }
        if box.width / CGFloat(cg.width) < 0.2, box.height / CGFloat(cg.height) < 0.2 {
            return image
        }

        // 크기·스케일을 원본과 동일하게 고정(투명 유지) — '배경 빼면 크기 달라짐' 방지.
        if cutout.size == image.size, cutout.scale == image.scale { return cutout }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            cutout.draw(in: CGRect(origin: .zero, size: image.size))
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

    /// 애니메이션 2번째 장면(image)을 reference(1번째)와 같은 크기·위치로 정규화.
    /// 모델이 투명 배경으로 주므로 alpha bbox 로 직접 잘라(Vision 불필요) reference 전경 bbox 위치·크기에
    /// aspect-fit 으로 투명 캔버스에 재배치. → 크기/위치만 1번째에 맞추고 투명은 유지.
    /// 전경을 못 찾으면 원본(투명) 그대로 반환.
    static func matchedToReference(_ image: UIImage, reference: UIImage, canvas target: CGFloat = 1024) async -> UIImage {
        guard let imgCG = image.cgImage, imgCG.width > 0, imgCG.height > 0,
              let imgBox = alphaBoundingBox(image),
              let croppedCG = imgCG.cropping(to: imgBox),
              let refBox = alphaBoundingBox(reference),
              let refCG = reference.cgImage, refCG.width > 0, refCG.height > 0 else {
            return image
        }
        // 전경이 거의 안 잡히면(이상치) 원본 유지 — 조각 확대 방지.
        if imgBox.width / CGFloat(imgCG.width) < 0.1, imgBox.height / CGFloat(imgCG.height) < 0.1 {
            return image
        }
        let refW = CGFloat(refCG.width), refH = CGFloat(refCG.height)
        let dst = CGRect(x: refBox.minX / refW * target,
                         y: refBox.minY / refH * target,
                         width:  refBox.width  / refW * target,
                         height: refBox.height / refH * target)
        let fit = min(dst.width / imgBox.width, dst.height / imgBox.height)
        let dw = imgBox.width * fit, dh = imgBox.height * fit
        let drawRect = CGRect(x: dst.midX - dw / 2, y: dst.midY - dh / 2, width: dw, height: dh)

        let canvasSize = CGSize(width: target, height: target)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false   // 투명 캔버스
        format.scale = 1
        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { _ in
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
