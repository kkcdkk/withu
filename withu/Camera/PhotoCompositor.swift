//
//  PhotoCompositor.swift
//  withu
//

import UIKit
import SwiftUI

/// 촬영된 사진 위에 캐릭터(현재는 SF Symbol)를 합성해서 최종 UIImage를 만드는 유틸.
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

            // 2) 캐릭터 영역 계산 (정규화 좌표 → 픽셀)
            let charRect = CGRect(
                x: normalizedRect.minX * size.width,
                y: normalizedRect.minY * size.height,
                width: normalizedRect.width * size.width,
                height: normalizedRect.height * size.height
            )

            // 3) 배경 원 그리기 (CharacterView 의 느낌 살리기 위해)
            let bgColor = UIColor(state.tint).withAlphaComponent(0.18)
            bgColor.setFill()
            UIBezierPath(ovalIn: charRect).fill()

            // 4) SF Symbol 을 UIImage 로 만들어 가운데 그림
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: charRect.width * 0.55,
                                                            weight: .semibold)
            if let symbol = UIImage(systemName: state.symbolName, withConfiguration: symbolConfig)?
                .withTintColor(UIColor(state.tint), renderingMode: .alwaysOriginal) {
                let symbolSize = symbol.size
                let drawRect = CGRect(
                    x: charRect.midX - symbolSize.width / 2,
                    y: charRect.midY - symbolSize.height / 2,
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                symbol.draw(in: drawRect)
            }
        }
    }
}
