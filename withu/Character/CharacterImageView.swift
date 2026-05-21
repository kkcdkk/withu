//
//  CharacterImageView.swift
//  withu (Shared)
//
//  Asset Catalog 에 `character_<state>` PNG 가 있으면 그걸 띄우고,
//  없으면 SF Symbol 로 fallback.
//
//  Target Membership: iOS app + Watch app + 두 위젯 extension (4개).
//

import SwiftUI
import WidgetKit

#if canImport(UIKit)
import UIKit
#endif

struct CharacterImageView: View {
    let state: CharacterState

    /// SF Symbol fallback 의 padding 비율. 컨테이너 크기 대비.
    /// 0.2 정도면 적당히 동그란 배경 가운데에 들어감.
    var symbolPaddingRatio: CGFloat = 0.2

    /// 위젯에서 메모리 절약용 다운샘플 픽셀 크기. nil 이면 풀 사이즈 로드.
    /// 위젯 프로세스는 ~30MB 메모리 한도라 1024×1024 PNG 를 그대로 올리면
    /// 시스템이 위젯을 죽이고 회색 박스로 대체. 위젯에선 256/512 정도로 지정.
    var maxPixelSize: CGFloat? = nil

    /// true 면 alpha 외곽선만 추출해 그림 (속이 빈 윤곽선). accessoryCircular
    /// 같은 단색 강제 환경에서 캐릭터 디테일 살리는 트릭. 다른 워치 앱들도 동일 패턴.
    var outlineOnly: Bool = false

    var body: some View {
        #if canImport(UIKit)
        if let userImage = loadUserImage() {
            // 1순위: 사용자가 AI 로 만들어 적용한 이미지 (App Group)
            // outlineOnly 면 .template + widgetAccentable — 시계 face accent 색 따라감
            if outlineOnly {
                Image(uiImage: Self.outlineImage(from: userImage))
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .widgetAccentable()
            } else {
                Image(uiImage: userImage)
                    .resizable()
                    .scaledToFit()
            }
        } else if UIImage(named: state.imageAssetName) != nil {
            // 2순위: Asset Catalog 의 placeholder (Step 9 의 9컷)
            Image(state.imageAssetName)
                .resizable()
                .scaledToFit()
        } else {
            sfSymbolFallback
        }
        #else
        sfSymbolFallback
        #endif
    }

    #if canImport(UIKit)
    private func loadUserImage() -> UIImage? {
        if let maxPixelSize {
            return CharacterImageStore.loadThumbnail(state, maxPixelSize: maxPixelSize)
        }
        return CharacterImageStore.load(state)
    }

    /// PNG 의 alpha mask 외곽선만 추출 (manual pixel processing — CoreImage 의존성 X).
    /// 각 픽셀의 주변을 봐서 alpha 경계면 흰색, 아니면 투명. 단색 강제 컴플리케이션
    /// 환경에서 캐릭터 윤곽선만 깔끔하게 보이게 하는 트릭.
    static func outlineImage(from image: UIImage, lineWidth: Int = 3) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let width = cg.width
        let height = cg.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        // 1) 원본 디코드 → pixel buffer
        guard let inCtx = CGContext(data: nil,
                                    width: width, height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: colorSpace,
                                    bitmapInfo: bitmapInfo),
              let inData = inCtx.data else { return image }
        inCtx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let inBuf = inData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // 2) outline buffer 생성
        guard let outCtx = CGContext(data: nil,
                                     width: width, height: height,
                                     bitsPerComponent: 8,
                                     bytesPerRow: bytesPerRow,
                                     space: colorSpace,
                                     bitmapInfo: bitmapInfo),
              let outData = outCtx.data else { return image }
        let outBuf = outData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        let alphaThreshold: UInt8 = 64   // 투명/불투명 기준
        let darkThreshold: Int = 90      // 이보다 어두운 픽셀 = 디테일 (눈코입)
        let w = lineWidth
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let alpha = inBuf[idx + 3]
                guard alpha >= alphaThreshold else {
                    outBuf[idx] = 0; outBuf[idx+1] = 0; outBuf[idx+2] = 0; outBuf[idx+3] = 0
                    continue
                }
                // 1) alpha 외곽선
                var isEdge = false
                outer: for dy in -w...w {
                    for dx in -w...w {
                        let nx = x + dx, ny = y + dy
                        if nx < 0 || nx >= width || ny < 0 || ny >= height {
                            isEdge = true; break outer
                        }
                        if inBuf[(ny * width + nx) * 4 + 3] < alphaThreshold {
                            isEdge = true; break outer
                        }
                    }
                }
                // 2) 어두운 픽셀 (눈코입 등 내부 디테일)
                let r = Int(inBuf[idx]), g = Int(inBuf[idx+1]), b = Int(inBuf[idx+2])
                let luminance = (r * 299 + g * 587 + b * 114) / 1000
                let isDarkDetail = luminance < darkThreshold

                if isEdge || isDarkDetail {
                    outBuf[idx] = 255; outBuf[idx+1] = 255
                    outBuf[idx+2] = 255; outBuf[idx+3] = 255
                } else {
                    outBuf[idx] = 0; outBuf[idx+1] = 0
                    outBuf[idx+2] = 0; outBuf[idx+3] = 0
                }
            }
        }

        guard let outCG = outCtx.makeImage() else { return image }
        return UIImage(cgImage: outCG)
    }
    #endif

    private var sfSymbolFallback: some View {
        GeometryReader { geo in
            Image(systemName: state.symbolName)
                .resizable()
                .scaledToFit()
                .padding(geo.size.width * symbolPaddingRatio)
                .foregroundStyle(state.tint)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

#Preview("Idle (SF fallback)") {
    CharacterImageView(state: .idle)
        .frame(width: 120, height: 120)
        .background(Circle().fill(CharacterState.idle.tint.opacity(0.18)))
}

#Preview("Beach (SF fallback)") {
    CharacterImageView(state: .beach)
        .frame(width: 120, height: 120)
        .background(Circle().fill(CharacterState.beach.tint.opacity(0.18)))
}
