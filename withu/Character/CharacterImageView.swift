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
    var symbolPaddingRatio: CGFloat = 0.2

    /// 위젯에서 메모리 절약용 다운샘플 픽셀 크기. nil 이면 풀 사이즈.
    var maxPixelSize: CGFloat? = nil

    /// true 면 alpha 외곽선만 추출. 단색 강제 환경 (컴플리케이션 등) 용.
    var outlineOnly: Bool = false

    /// 애니메이션 모드 — frame 0/1 를 0.7초 간격 swap.
    var animated: Bool = false

    var body: some View {
        #if canImport(UIKit)
        if shouldAnimate {
            TimelineView(.periodic(from: .now, by: 0.7)) { ctx in
                let frame = Int(ctx.date.timeIntervalSinceReferenceDate / 0.7) % 2
                singleFrameView(frameIndex: frame)
            }
        } else {
            singleFrameView(frameIndex: 0)
        }
        #else
        sfSymbolFallback
        #endif
    }

    /// 세 조건 모두 만족해야 swap 애니메이션:
    ///   1) caller 가 animated: true 로 호출
    ///   2) frame 1 파일이 활성 슬롯에 존재
    ///   3) 사용자 토글 (CharacterImageStore.animationEnabled, default true)
    private var shouldAnimate: Bool {
        guard animated else { return false }
        guard CharacterImageStore.hasAnimationFrames(for: state) else { return false }
        return CharacterImageStore.animationEnabled
    }

    #if canImport(UIKit)
    @ViewBuilder
    private func singleFrameView(frameIndex: Int) -> some View {
        if let userImage = loadFrameWithFallback(frameIndex) {
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
        } else if let assetName = assetNameWithFallback() {
            Image(assetName)
                .resizable()
                .scaledToFit()
        } else {
            sfSymbolFallback
        }
    }

    /// 사용자 PNG 로드. 현재 state 에 없으면 baseFallback state (조합 → 운동 base) 도 시도.
    private func loadFrameWithFallback(_ frameIndex: Int) -> UIImage? {
        if let img = loadFrame(frameIndex, state: state) {
            return img
        }
        // 조합 state (예: walkingRainy) 이미지 없으면 base (walking) 시도
        if let base = state.baseFallback,
           let img = loadFrame(frameIndex, state: base) {
            return img
        }
        return nil
    }

    /// Asset Catalog 이름 결정. 현재 state asset 없으면 baseFallback asset 시도.
    private func assetNameWithFallback() -> String? {
        if UIImage(named: state.imageAssetName) != nil {
            return state.imageAssetName
        }
        if let base = state.baseFallback,
           UIImage(named: base.imageAssetName) != nil {
            return base.imageAssetName
        }
        return nil
    }

    private func loadFrame(_ frameIndex: Int, state: CharacterState) -> UIImage? {
        if frameIndex == 0 {
            return loadFrame0(state: state)
        }
        if let img = CharacterImageStore.loadFrame(state, frame: frameIndex) {
            return maybeDownsample(img)
        }
        return loadFrame0(state: state)
    }

    private func loadFrame0(state: CharacterState) -> UIImage? {
        if let maxPixelSize {
            return CharacterImageStore.loadThumbnail(state, maxPixelSize: maxPixelSize)
        }
        return CharacterImageStore.load(state)
    }

    /// 지정 frame 로드. 다운샘플 옵션 + frame 0 fallback.
    private func loadFrame(_ frameIndex: Int) -> UIImage? {
        if frameIndex == 0 {
            return loadFrame0()
        }
        // frame >= 1 — 없으면 frame 0 fallback
        if let img = CharacterImageStore.loadFrame(state, frame: frameIndex) {
            return maybeDownsample(img)
        }
        return loadFrame0()
    }

    private func loadFrame0() -> UIImage? {
        if let maxPixelSize {
            return CharacterImageStore.loadThumbnail(state, maxPixelSize: maxPixelSize)
        }
        return CharacterImageStore.load(state)
    }

    private func maybeDownsample(_ image: UIImage) -> UIImage {
        guard let maxPixelSize else { return image }
        // 단순화: frame 1 은 작은 PNG 가정. downsampling 없어도 OK.
        // 메모리 위험 시 maxPixelSize 적용은 loadThumbnail 만 가능 — 따로 안 함.
        _ = maxPixelSize
        return image
    }

    /// PNG 의 alpha mask 외곽선 추출 (CoreImage 의존성 X).
    static func outlineImage(from image: UIImage, lineWidth: Int = 3) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let width = cg.width
        let height = cg.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let inCtx = CGContext(data: nil, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                    space: colorSpace, bitmapInfo: bitmapInfo),
              let inData = inCtx.data else { return image }
        inCtx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let inBuf = inData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        guard let outCtx = CGContext(data: nil, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                     space: colorSpace, bitmapInfo: bitmapInfo),
              let outData = outCtx.data else { return image }
        let outBuf = outData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        let alphaThreshold: UInt8 = 64
        let darkThreshold: Int = 90
        let w = lineWidth
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let alpha = inBuf[idx + 3]
                guard alpha >= alphaThreshold else {
                    outBuf[idx] = 0; outBuf[idx+1] = 0; outBuf[idx+2] = 0; outBuf[idx+3] = 0
                    continue
                }
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

// MARK: - WeatherBackgroundView (4 타깃 공유)

/// 현재 날씨에 맞는 배경 이미지 표시. 사용자 생성 PNG → Asset Catalog → Color.clear 순.
/// 호출자는 condition 직접 (iOS app) 또는 emoji (watch/widget) 로 전달.
struct WeatherBackgroundView: View {
    let condition: WeatherBackgroundCondition?

    /// emoji 로 초기화 — 워치 / 위젯에서 사용 (WatchMessage.weatherEmoji).
    init(emoji: String?) {
        self.condition = WeatherBackgroundCondition.from(emoji: emoji)
    }

    /// condition 으로 직접 초기화 — iOS app 에서 WeatherCondition 매핑 후 사용.
    init(condition: WeatherBackgroundCondition?) {
        self.condition = condition
    }

    var body: some View {
        #if canImport(UIKit)
        if let condition, let img = CharacterImageStore.loadBackground(condition) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
        } else if let condition, UIImage(named: "background_\(condition.rawValue)") != nil {
            Image("background_\(condition.rawValue)")
                .resizable()
                .scaledToFill()
        } else {
            Color.clear
        }
        #else
        Color.clear
        #endif
    }
}
