//
//  PhotoCompositor.swift
//  withu
//

import UIKit
import SwiftUI

/// 촬영된 사진 위에 여러 캐릭터를 합성해서 최종 UIImage를 만드는 유틸.
/// 우선순위: 1) App Group 의 사용자 적용 이미지 2) Asset Catalog 3) SF Symbol fallback
enum PhotoCompositor {

    static func compose(
        photo: UIImage,
        placed: [PlacedCharacter]
    ) -> UIImage {
        let size = photo.size
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { _ in
            photo.draw(in: CGRect(origin: .zero, size: size))

            for character in placed {
                let rect = character.rect(in: size)
                drawCharacter(state: character.state, in: rect)
            }
        }
    }

    /// 한 캐릭터 합성. 사용자 이미지 → Asset → SF Symbol fallback.
    private static func drawCharacter(state: CharacterState, in rect: CGRect) {
        if let userImage = CharacterImageStore.load(state) {
            drawAspectFit(userImage, in: rect)
        } else if let asset = UIImage(named: state.imageAssetName) {
            drawAspectFit(asset, in: rect)
        } else {
            drawSymbolFallback(state: state, in: rect)
        }
    }

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

    private static func drawSymbolFallback(state: CharacterState, in charRect: CGRect) {
        let bgColor = UIColor(state.tint).withAlphaComponent(0.18)
        bgColor.setFill()
        UIBezierPath(ovalIn: charRect).fill()

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
