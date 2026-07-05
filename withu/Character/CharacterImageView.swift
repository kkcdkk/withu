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
                let frame = Int(Int64(ctx.date.timeIntervalSinceReferenceDate / 0.7) % 2)
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

// MARK: - WeatherDecorationView (4 타깃 공유)

/// 캐릭터 옆에 띄우는 작은 날씨 표현.
///   - 해/달/구름: 우상단에 정적 emoji (고정, 모션 X)
///   - 비/눈: 영역 전체에 진짜 떨어지는 입자
struct WeatherDecorationView: View {
    let condition: WeatherBackgroundCondition?
    /// emoji 기본 크기. 메인 = 44, 워치 = 18, 위젯 medium = 18.
    var size: CGFloat = 44

    var body: some View {
        if let condition {
            decoration(for: condition)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func decoration(for cond: WeatherBackgroundCondition) -> some View {
        #if canImport(UIKit)
        // Asset Catalog 에 박아둔 고정 PNG → 없으면 emoji fallback.
        let assetExists = UIImage(named: cond.decorationAssetName) != nil
        switch cond {
        case .sunny, .cloudy, .night:
            cornerElement(assetName: assetExists ? cond.decorationAssetName : nil,
                          fallback: cond.fallbackEmoji)
        case .rainy:
            FallingParticles(assetName: assetExists ? cond.decorationAssetName : nil,
                             fallbackSymbol: "💧",
                             count: 7,
                             particleSize: size * 0.35,
                             fallPeriod: 1.0, drift: false)
        case .snowy:
            FallingParticles(assetName: assetExists ? cond.decorationAssetName : nil,
                             fallbackSymbol: "❄️",
                             count: 7,
                             particleSize: size * 0.38,
                             fallPeriod: 2.6, drift: true)
        }
        #else
        EmptyView()
        #endif
    }

    #if canImport(UIKit)
    /// 해/달/구름 아이콘은 캐릭터 대비 작게 — size 의 일부만 사용 (캐릭터의 ~1/4.5).
    private var cornerScale: CGFloat { 0.66 }

    /// 우상단 정적 — Asset Catalog 이미지 있으면 그걸, 없으면 emoji.
    @ViewBuilder
    private func cornerElement(assetName: String?, fallback: String) -> some View {
        let elementSize = size * cornerScale
        VStack {
            HStack {
                Spacer()
                Group {
                    if let assetName {
                        Image(assetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: elementSize, height: elementSize)
                    } else {
                        Text(fallback)
                            .font(.system(size: elementSize))
                    }
                }
                .padding(.top, size * 0.08)
                .padding(.trailing, size * 0.08)
            }
            Spacer()
        }
    }
    #endif
}

/// 영역 전체에 떨어지는 입자 — 비/눈.
/// Asset Catalog 이미지 있으면 그게 입자, 없으면 emoji symbol.
/// `count` 개 입자가 staggered phase 로 위→아래 반복. drift=true 면 수평 sine 흔들림.
private struct FallingParticles: View {
    let assetName: String?
    let fallbackSymbol: String
    let count: Int
    let particleSize: CGFloat
    let fallPeriod: Double
    var drift: Bool = false

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<count, id: \.self) { i in
                        particle(i: i, t: t, size: geo.size)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func particleContent() -> some View {
        if let assetName {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: particleSize, height: particleSize)
        } else {
            Text(fallbackSymbol).font(.system(size: particleSize))
        }
    }

    private func particle(i: Int, t: TimeInterval, size: CGSize) -> some View {
        let startOffset = Double(i) / Double(count)
        let phase = (t / fallPeriod + startOffset)
            .truncatingRemainder(dividingBy: 1.0)
        let baseX = size.width * CGFloat((Double(i) + 0.5) / Double(count))
        let jitter = CGFloat(sin(Double(i) * 7.31) * 12)
        let driftX: CGFloat = drift
            ? CGFloat(sin(t * 1.2 + Double(i) * 1.7) * 10)
            : 0
        let yStart: CGFloat = -particleSize
        let yEnd: CGFloat = size.height + particleSize
        let y = yStart + CGFloat(phase) * (yEnd - yStart)
        let opacity: Double
        if phase < 0.08 {
            opacity = phase / 0.08
        } else if phase > 0.92 {
            opacity = (1 - phase) / 0.08
        } else {
            opacity = 1
        }
        return particleContent()
            .position(x: baseX + jitter + driftX, y: y)
            .opacity(opacity)
    }
}

// MARK: - WeatherBackgroundView (legacy, AI 풀배경 — 현재 entry 숨김)

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
