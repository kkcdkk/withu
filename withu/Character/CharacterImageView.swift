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

    /// true 면 사용자 이미지를 건너뛰고 번들 기본 일러스트부터 사용.
    /// 잠금화면(vibrant)에서 배경이 불투명한 사용자 그림이 통짜 사각형으로 보일 때의 대체 경로.
    var preferBundled: Bool = false

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
        guard !CharacterImageStore.isAnimationDisabled(for: state) else { return false }
        return CharacterImageStore.animationEnabled
    }

    #if canImport(UIKit)
    @ViewBuilder
    private func singleFrameView(frameIndex: Int) -> some View {
        if !preferBundled, let userImage = loadFrameWithFallback(frameIndex) {
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
            if outlineOnly, let assetImage = UIImage(named: assetName) {
                // 단색 강제 환경 — 번들 에셋도 사용자 이미지와 동일하게 외곽선만.
                // (풀컬러로 그리면 잠금화면/컴플리케이션에서 알파 실루엣 덩어리로 보임)
                Image(uiImage: Self.outlineImage(from: downsampledForOutline(assetImage)))
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .widgetAccentable()
            } else {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
            }
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
    /// 마지막으로, 공통 placeholder 이미지("character_placeholder")가 있으면 그걸 씀
    /// → 첫 캐릭터 생성 전 SF Symbol 대신 사용자가 지정한 사진을 보여줌.
    private func assetNameWithFallback() -> String? {
        if UIImage(named: state.imageAssetName) != nil {
            return state.imageAssetName
        }
        if let base = state.baseFallback,
           UIImage(named: base.imageAssetName) != nil {
            return base.imageAssetName
        }
        if UIImage(named: "character_placeholder") != nil {
            return "character_placeholder"
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

    /// outlineImage 는 픽셀 전수 순회라 원본 크기로 돌리면 위젯 메모리/CPU 초과 위험 —
    /// maxPixelSize 지정 시 (위젯/컴플리케이션) 그 크기로 먼저 축소한 뒤 외곽선 추출.
    private func downsampledForOutline(_ image: UIImage) -> UIImage {
        guard let maxPixelSize else { return image }
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxPixelSize else { return image }
        let ratio = maxPixelSize / longest
        let newSize = CGSize(width: pixelWidth * ratio, height: pixelHeight * ratio)
        // UIGraphicsImageRenderer 는 watchOS 미지원 — CGContext 로 직접 축소 (4개 타깃 공용).
        guard let cg = image.cgImage,
              let ctx = CGContext(data: nil,
                                  width: Int(newSize.width), height: Int(newSize.height),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(origin: .zero, size: newSize))
        guard let scaled = ctx.makeImage() else { return image }
        return UIImage(cgImage: scaled)
    }

    private func maybeDownsample(_ image: UIImage) -> UIImage {
        guard let maxPixelSize else { return image }
        // 단순화: frame 1 은 작은 PNG 가정. downsampling 없어도 OK.
        // 메모리 위험 시 maxPixelSize 적용은 loadThumbnail 만 가능 — 따로 안 함.
        _ = maxPixelSize
        return image
    }

    /// 잠금화면(vibrant) accessory 렌더 전략. vibrant 는 불투명 픽셀 전체를 밝기 패널로
    /// 그리므로, 배경까지 꽉 찬(불투명) 그림은 통짜 사각형이 된다.
    ///   1) 사용자 이미지가 투명 배경 → 그대로 (밝기 디테일로 눈코입까지 보임 — 최선)
    ///   2) 사용자 이미지가 불투명 배경 → 번들 기본 일러스트로 대체 (사각형 방지)
    ///   3) 번들 일러스트마저 불투명(기본 eating 식탁) → 외곽선 모드
    /// 반환: (preferBundled: 사용자 이미지 건너뛸지, outline: 외곽선 모드일지)
    static func accessoryPlan(for state: CharacterState) -> (preferBundled: Bool, outline: Bool) {
        if CharacterImageStore.hasImage(for: state),
           let user = CharacterImageStore.loadThumbnail(state, maxPixelSize: 16),
           !imageHasOpaqueCorners(user) {
            return (preferBundled: false, outline: false)   // 투명 사용자 그림 — 그대로
        }
        // 사용자 그림이 없거나 불투명 → 번들 기준으로 판단
        let bundledOpaque = imageHasOpaqueCorners(UIImage(named: state.imageAssetName))
        return (preferBundled: true, outline: bundledOpaque)
    }

    /// 네 모서리 중 불투명한 곳이 있으면 true (배경이 있는 그림으로 간주).
    private static func imageHasOpaqueCorners(_ image: UIImage?) -> Bool {
        guard let cg = image?.cgImage else { return false }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return false }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let corners = [0, (w - 1) * 4, (h - 1) * w * 4, ((h - 1) * w + w - 1) * 4]
        return corners.contains { pixels[$0 + 3] > 24 }
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
                    // 중간 톤은 반투명 '잉크'로 — 어두울수록 진하게, 밝을수록 투명하게.
                    // 이진 처리(외곽선+진한 디테일만)로는 연한 눈코입/음영이 통째로 사라져
                    // 틴트 페이스에서 빈 실루엣만 보이던 문제 보완.
                    // 하한 64(25%): 흰 이불 등 아주 밝은 그림도 최소한의 몸통 실루엣은 보이게
                    // (하한 없인 워치 틴트에서 수면 캐릭터가 '빈 원'으로 보였음).
                    // premultipliedLast: 흰색 × alpha 프리멀티플라이 = 네 채널 동일 값.
                    let ink = max((255 - luminance) * Int(alpha) / 255, 64)
                    let a = UInt8(min(255, ink))
                    outBuf[idx] = a; outBuf[idx+1] = a
                    outBuf[idx+2] = a; outBuf[idx+3] = a
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
