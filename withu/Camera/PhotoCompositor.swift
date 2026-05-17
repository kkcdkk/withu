//
//  PhotoCompositor.swift
//  withu
//

import UIKit
import SwiftUI

/// 촬영된 사진 위에 캐릭터를 합성해서 최종 UIImage를 만드는 유틸.
/// 우선순위: 1) App Group 의 사용자 적용 이미지 2) Asset Catalog 3) SF Symbol fallback
enum PhotoCompositor {

    /// - Parameters:
    ///   - photo: 원본 카메라 사진
    ///   - state: 현재 캐릭터 상태
    ///   - normalizedRect: 사진 좌표계에서 캐릭터가 들어갈 위치/크기 (0~1 비율)
    static func compose(
        photo: UIImage,
        state: CharacterState,
        normalizedRect: CGRect
    ) -> UIImage {
        let size = photo.size
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { _ in
            // 1) 원본 사진을 가득 채워서 그림
            photo.draw(in: CGRect(origin: .zero, size: size))

            // 2) 캐릭터 영역 (정규화 좌표 → 픽셀)
            let charRect = CGRect(
                x: normalizedRect.minX * size.width,
                y: normalizedRect.minY * size.height,
                width: normalizedRect.width * size.width,
                height: normalizedRect.height * size.height
            )

            // 3) 캐릭터 이미지 결정 (사용자 이미지 → asset → SF Symbol)
            if let userImage = CharacterImageStore.load(state) {
                drawAspectFit(userImage, in: charRect)
            } else if let asset = UIImage(named: state.imageAssetName) {
                drawAspectFit(asset, in: charRect)
            } else {
                drawSymbolFallback(state: state, in: charRect)
            }
        }
    }

    /// aspectFit 으로 이미지를 charRect 안에 그림.
    private static func drawAspectFit(_ image: UIImage, in rect: CGRect) {
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return }
        let scale = min(rect.width / imgSize.width, rect.height / imgSize.height)
        let w = imgSize.width * scale
        let h = imgSize.height * scale
        let drawRect = CGRect(
            x: rect.midX - w / 2,
            y: rect.midY - h / 2,
            width: w,
            height: h
        )
        image.draw(in: drawRect)
    }

    /// 이미지 없을 때 SF Symbol + 배경 원.
    private static func drawSymbolFallback(state: CharacterState, in charRect: CGRect) {
        // 배경 원
        let bgColor = UIColor(state.tint).withAlphaComponent(0.18)
        bgColor.setFill()
        UIBezierPath(ovalIn: charRect).fill()

        // SF Symbol
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: charRect.width * 0.55,
                                                       weight: .semibold)
        guard let symbol = UIImage(systemName: state.symbolName, withConfiguration: symbolConfig)?
            .withTintColor(UIColor(state.tint), renderingMode: .alwaysOriginal) else { return }
        let s = symbol.size
        let drawRect = CGRect(
            x: charRect.midX - s.width / 2,
            y: charRect.midY - s.height / 2,
            width: s.width,
            height: s.height
        )
        symbol.draw(in: drawRect)
    }
}
