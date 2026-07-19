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
import WidgetKit

enum ImageProcessing {

    /// CIContext 는 생성 비용이 큰 객체 — 1개를 공유 재사용 (immutable, thread-safe).
    private static let sharedCIContext = CIContext()

    enum ProcessingError: LocalizedError {
        case invalidImage
        case noForeground
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .invalidImage:  return String(localized: "이미지가 유효하지 않아요.")
            case .noForeground:  return String(localized: "이미지에서 대상을 찾지 못했어요. 더 또렷한 사진을 시도해보세요.")
            case .renderFailed:  return String(localized: "이미지 변환 실패.")
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
        // Vision 이 일부 이미지에서 hang/초장시간 걸리는 케이스 → timeout 가드.
        // 실패/타임아웃이면 원본(다운샘플)로 진행 — 무한 로딩("멈춤") 방지.
        let cutout = await bestEffortTransparent(downsized)
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

        // 내부 흰색 구멍 복원 — 완전 흰색(눈·하이라이트 등)이 흰 배경으로 오인돼 뚫린 곳을
        // 원본 색으로 되돌림. 가장자리와 연결된 투명(진짜 배경)만 투명 유지.
        let repaired = fillInteriorHoles(cutout, original: image)

        // 크기·스케일을 원본과 동일하게 고정(투명 유지) — '배경 빼면 크기 달라짐' 방지.
        if repaired.size == image.size, repaired.scale == image.scale { return repaired }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            repaired.draw(in: CGRect(origin: .zero, size: image.size))
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

    /// 전체를 정사각(target) 안에 aspect-fit + 중앙 정렬. 투명 배경 유지(잘리지 않음).
    /// (이전엔 cg 픽셀과 image.size 포인트를 섞어 center-crop 해서 고배율 기기에서 1/4만 잘리는 버그가 있었음.)
    static func normalizeSquare(_ image: UIImage, target: CGFloat = 1024) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false   // 알파 채널 유지
        format.scale = 1
        let canvas = CGSize(width: target, height: target)
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { _ in
            let w = image.size.width, h = image.size.height
            guard w > 0, h > 0 else {
                image.draw(in: CGRect(origin: .zero, size: canvas)); return
            }
            // 긴 변을 target 에 맞춰 비율 유지(aspect-fit), 중앙 정렬 — image.draw 는 포인트 단위라 단위 일관.
            let s = Swift.min(target / w, target / h)
            let dw = w * s, dh = h * s
            image.draw(in: CGRect(x: (target - dw) / 2, y: (target - dh) / 2, width: dw, height: dh))
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

    // MARK: - 내부 구멍 복원 (배경 빼기 후)

    /// Vision 배경 제거 결과에서 '캐릭터 안에 갇힌 투명 구멍'을 원본 색으로 복원.
    /// 완전 흰색 부분(눈·하이라이트·흰옷)이 흰 배경으로 오인돼 뚫린 경우를 되살린다.
    ///   - 가장자리에서 투명으로 이어지는 영역 = 진짜 배경 → 투명 유지.
    ///   - 그 외 투명(=캐릭터에 둘러싸인 구멍)이면서 원본이 불투명이던 곳만 복원.
    /// (원본이 원래 투명이던 진짜 구멍은 건드리지 않음 — 검은 얼룩 방지.)
    static func fillInteriorHoles(_ cutout: UIImage, original: UIImage,
                                  alphaThreshold: UInt8 = 20) -> UIImage {
        guard let cutCG = cutout.cgImage, cutCG.width > 0, cutCG.height > 0,
              let origCG = original.cgImage else { return cutout }
        let w = cutCG.width, h = cutCG.height
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let cutCtx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                     bytesPerRow: w * 4, space: cs, bitmapInfo: info) else { return cutout }
        cutCtx.draw(cutCG, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let cutData = cutCtx.data else { return cutout }
        let cut = cutData.bindMemory(to: UInt8.self, capacity: w * h * 4)

        // 원본을 cutout 과 같은 픽셀 격자로 그려 색 참조(크기 달라도 맞춤).
        guard let origCtx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: cs, bitmapInfo: info) else { return cutout }
        origCtx.draw(origCG, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let origData = origCtx.data else { return cutout }
        let orig = origData.bindMemory(to: UInt8.self, capacity: w * h * 4)

        // 가장자리에서 4-연결된 투명 픽셀 = 진짜 배경. BFS 로 표시.
        var reached = [Bool](repeating: false, count: w * h)
        var stack = [Int]()
        func seedIfBg(_ p: Int) {
            if cut[p * 4 + 3] < alphaThreshold, !reached[p] { reached[p] = true; stack.append(p) }
        }
        for x in 0..<w { seedIfBg(x); seedIfBg((h - 1) * w + x) }
        for y in 0..<h { seedIfBg(y * w); seedIfBg(y * w + (w - 1)) }
        while let p = stack.popLast() {
            let x = p % w, y = p / w
            if x > 0 { seedIfBg(p - 1) }
            if x < w - 1 { seedIfBg(p + 1) }
            if y > 0 { seedIfBg(p - w) }
            if y < h - 1 { seedIfBg(p + w) }
        }

        // 투명이지만 가장자리와 연결 안 됨(내부 구멍) + 원본이 불투명이던 곳 → 원본 색 복원.
        var filled = 0
        for p in 0..<(w * h) {
            let i = p * 4
            if cut[i + 3] < alphaThreshold, !reached[p], orig[i + 3] > 200 {
                cut[i] = orig[i]; cut[i + 1] = orig[i + 1]; cut[i + 2] = orig[i + 2]; cut[i + 3] = 255
                filled += 1
            }
        }
        guard filled > 0, let outCG = cutCtx.makeImage() else { return cutout }
        return UIImage(cgImage: outCG, scale: cutout.scale, orientation: .up)
    }

    // MARK: - 투명화 공용 후처리 (크로마키 → Vision 폴백)

    /// 생성 수신 공용 후처리: 크로마키(마젠타)로 투명화하고, 그래도 배경이 남아 있으면
    /// (모서리 불투명 = 모델이 마젠타 지시를 무시하고 실제 배경을 그린 케이스) Vision 으로
    /// 한 번 더 배경을 제거한다. 불투명 그림은 잠금화면(vibrant)에서 통짜 사각형이 되고
    /// 워치 틴트 페이스에서도 뭉개지므로, 저장 전에 반드시 투명화한다. Vision 실패 시 크로마키 결과 유지.
    static func transparentized(_ image: UIImage) async -> UIImage {
        let keyed = chromaKeyRemoved(image)
        guard hasOpaqueCorners(keyed) else { return keyed }
        guard let cut = try? await removeBackground(from: keyed),
              CharacterImageView.alphaCoverage(cut) >= 0.02 else {
            // Vision 이 전경을 못 찾아 사실상 빈 결과를 주면 원본 유지 (빈 그림 저장 방지)
            return keyed
        }
        return cut
    }

    /// 네 모서리 중 불투명한 곳이 있으면 true — 배경 잔존 판정 (16px 축소본으로 검사).
    static func hasOpaqueCorners(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let w = 16, h = 16
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let corners = [0, (w - 1) * 4, (h - 1) * w * 4, ((h - 1) * w + w - 1) * 4]
        return corners.contains { pixels[$0 + 3] > 24 }
    }

    /// 저장돼 있는 '배경 안 지워진' 그림 일괄 보정 — 활성 슬롯 전체 + 갤러리.
    /// 이전 버전에서 크로마키가 실패한 채 저장된 그림을 Vision 으로 투명화해,
    /// 사용자가 만든 캐릭터가 잠금화면/워치에서도 그대로 보이게 한다.
    /// 멱등: 이미 투명이면 건너뜀. 실패한 항목은 다음 실행 때 재시도. 앱 시작 시 백그라운드 실행.
    static func backfillTransparency() async {
        var changed = false
        for state in CharacterState.allCases {
            for frame in 0...1 {
                guard let data = CharacterImageStore.activeImageData(for: state, frame: frame),
                      let img = UIImage(data: data) else { continue }
                // 사실상 빈 그림(잘못된 배경 제거 결과가 저장된 경우) → 갤러리 원본으로 복원,
                // 원본이 없거나 그것도 비었으면 슬롯 삭제(번들 일러스트 fallback — 빈 위젯 방지).
                if CharacterImageView.alphaCoverage(img) < 0.02 {
                    if let id = CharacterImageStore.currentGalleryItemId(for: state),
                       let galleryData = CharacterImageStore.galleryImageData(id: id, frame: frame),
                       let galleryImg = UIImage(data: galleryData),
                       CharacterImageView.alphaCoverage(galleryImg) >= 0.02 {
                        CharacterImageStore.rewriteActiveImage(galleryData, for: state, frame: frame)
                    } else {
                        CharacterImageStore.removeActiveImage(for: state, frame: frame)
                    }
                    changed = true
                    continue
                }
                guard hasOpaqueCorners(img),
                      let fixed = try? await removeBackground(from: img),
                      CharacterImageView.alphaCoverage(fixed) >= 0.02,   // 빈 결과로 덮어쓰기 금지
                      let out = fixed.pngData() else { continue }
                CharacterImageStore.rewriteActiveImage(out, for: state, frame: frame)
                changed = true
            }
        }
        for item in CharacterImageStore.loadGalleryMetadata() {
            let frames = (item.hasFrame1 ?? false) ? [0, 1] : [0]
            for frame in frames {
                guard let data = CharacterImageStore.galleryImageData(id: item.id, frame: frame),
                      let img = UIImage(data: data), hasOpaqueCorners(img),
                      let fixed = try? await removeBackground(from: img),
                      CharacterImageView.alphaCoverage(fixed) >= 0.02 else { continue }
                CharacterImageStore.replaceGalleryImage(item.id, with: fixed, frame: frame)
                changed = true
            }
        }
        if changed {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - 마젠타 크로마키 (gpt-image-2 배경 제거)

    /// gpt-image-2 는 투명 배경 미지원 → 서버가 순수 마젠타(#FF00FF) 단색 배경을 지시하고,
    /// 여기서 가장자리에서 4-연결된 마젠타 영역만 투명으로 바꾼다.
    /// - 가장자리 연결 BFS: 캐릭터 안(볼터치·핑크 옷)은 배경과 연결돼도 마젠타 판정이 아니면 안 지움.
    /// - 마젠타가 거의 없으면(이미 투명이거나 1.5 결과) 원본 그대로 반환 — 어디에 끼워도 안전한 no-op.
    static func chromaKeyRemoved(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage, cg.width > 0, cg.height > 0 else { return image }
        let w = cg.width, h = cg.height
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs, bitmapInfo: info) else { return image }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return image }
        let buf = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        // 마젠타 판정 — 압축/경계 블렌딩 여유를 두되 볼터치 핑크(G≈180)는 통과 못 하게.
        func isMagenta(_ p: Int) -> Bool {
            let i = p * 4
            let r = Int(buf[i]), g = Int(buf[i + 1]), b = Int(buf[i + 2])
            return buf[i + 3] > 0 && r >= 160 && b >= 160 && g <= 120 && r - g >= 70 && b - g >= 70
        }

        // 가장자리에서 4-연결된 마젠타 = 진짜 배경. (fillInteriorHoles 와 같은 BFS 패턴)
        var reached = [Bool](repeating: false, count: w * h)
        var stack = [Int]()
        func seed(_ p: Int) {
            if !reached[p], isMagenta(p) { reached[p] = true; stack.append(p) }
        }
        for x in 0..<w { seed(x); seed((h - 1) * w + x) }
        for y in 0..<h { seed(y * w); seed(y * w + (w - 1)) }
        while let p = stack.popLast() {
            let x = p % w, y = p / w
            if x > 0 { seed(p - 1) }
            if x < w - 1 { seed(p + 1) }
            if y > 0 { seed(p - w) }
            if y < h - 1 { seed(p + w) }
        }

        var removed = 0
        for p in 0..<(w * h) where reached[p] {
            let i = p * 4
            buf[i] = 0; buf[i + 1] = 0; buf[i + 2] = 0; buf[i + 3] = 0
            removed += 1
        }
        // 마젠타 배경이 사실상 없으면(오검출 방지) 원본 유지 — 1.5 투명 결과 등에 안전.
        guard removed > (w * h) / 100, let outCG = ctx.makeImage() else { return image }

        // 경계 마젠타 번짐(halo) 정리 — 배경에 인접한 픽셀의 마젠타 끼를 중화.
        let out = UIImage(cgImage: outCG, scale: image.scale, orientation: .up)
        return defringeMagenta(out)
    }

    /// 크로마키 후 외곽선에 남는 마젠타 halo 를 중화 — 투명 픽셀에 4-인접하면서
    /// 마젠타 끼(r,b 가 g 보다 두드러짐)가 있는 픽셀의 r/b 를 g 쪽으로 당긴다.
    private static func defringeMagenta(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage, cg.width > 0, cg.height > 0 else { return image }
        let w = cg.width, h = cg.height
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs, bitmapInfo: info) else { return image }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return image }
        let buf = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        var touched = 0
        for p in 0..<(w * h) {
            let i = p * 4
            guard buf[i + 3] > 0 else { continue }
            let x = p % w, y = p / w
            let nearBG = (x > 0 && buf[(p - 1) * 4 + 3] == 0) || (x < w - 1 && buf[(p + 1) * 4 + 3] == 0)
                || (y > 0 && buf[(p - w) * 4 + 3] == 0) || (y < h - 1 && buf[(p + w) * 4 + 3] == 0)
            guard nearBG else { continue }
            let r = Int(buf[i]), g = Int(buf[i + 1]), b = Int(buf[i + 2])
            if r - g >= 40 && b - g >= 40 {   // 마젠타 끼 잔여
                let m = UInt8(min(255, g + 30))
                buf[i] = min(buf[i], m); buf[i + 2] = min(buf[i + 2], m)
                touched += 1
            }
        }
        guard touched > 0, let outCG = ctx.makeImage() else { return image }
        return UIImage(cgImage: outCG, scale: image.scale, orientation: .up)
    }

    // MARK: - 색 맞추기 (프레임2 → 프레임0)

    /// 프레임2의 색을 프레임0(reference)에 맞춰 2프레임 스왑 시 미묘한 색 드리프트 제거.
    /// 전경(알파>200) 픽셀의 채널별 평균/표준편차를 reference 에 맞추는 Reinhard 색 전이.
    /// 의도된 국소 변화(입·다리)는 전체 통계를 거의 안 바꾸므로 보존됨. 알파는 그대로 유지.
    /// 128px 썸네일에 적용하는 전제(저비용). 통계가 불안정하면 원본 반환.
    static func colorMatched(_ image: UIImage, reference: UIImage) -> UIImage {
        guard let src = channelStats(image), let ref = channelStats(reference),
              let cg = image.cgImage else { return image }
        // 표준편차가 너무 작으면(거의 단색) 나눗셈 불안정 → 스킵
        if src.std.contains(where: { $0 < 0.5 }) { return image }

        let w = cg.width, h = cg.height
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs, bitmapInfo: info) else { return image }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return image }
        let buf = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        // out = (in - sMean) * (rStd/sStd) + rMean  = in*gain + off
        var gain = [Double](repeating: 1, count: 3), off = [Double](repeating: 0, count: 3)
        for c in 0..<3 {
            gain[c] = ref.std[c] / src.std[c]
            off[c] = ref.mean[c] - gain[c] * src.mean[c]
        }
        var i = 0
        while i < w * h * 4 {
            if buf[i + 3] > 200 {   // 전경만
                for c in 0..<3 {
                    let v = Double(buf[i + c]) * gain[c] + off[c]
                    buf[i + c] = UInt8(max(0, min(255, v.rounded())))
                }
            }
            i += 4
        }
        guard let outCG = ctx.makeImage() else { return image }
        return UIImage(cgImage: outCG, scale: image.scale, orientation: .up)
    }

    private struct ChannelStats { let mean: [Double]; let std: [Double] }

    /// 전경(알파>200) 픽셀의 RGB 채널별 평균/표준편차. 전경이 너무 적으면 nil.
    private static func channelStats(_ image: UIImage) -> ChannelStats? {
        guard let cg = image.cgImage, cg.width > 0, cg.height > 0 else { return nil }
        let w = cg.width, h = cg.height
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs, bitmapInfo: info) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let buf = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var sum = [Double](repeating: 0, count: 3), sumSq = [Double](repeating: 0, count: 3)
        var n = 0, i = 0
        while i < w * h * 4 {
            if buf[i + 3] > 200 {
                n += 1
                for c in 0..<3 {
                    let v = Double(buf[i + c])
                    sum[c] += v; sumSq[c] += v * v
                }
            }
            i += 4
        }
        guard n > 100 else { return nil }
        let nd = Double(n)
        var mean = [Double](repeating: 0, count: 3), std = [Double](repeating: 0, count: 3)
        for c in 0..<3 {
            mean[c] = sum[c] / nd
            std[c] = max(0, sumSq[c] / nd - mean[c] * mean[c]).squareRoot()
        }
        return ChannelStats(mean: mean, std: std)
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
