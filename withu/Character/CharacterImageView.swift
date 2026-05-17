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

#if canImport(UIKit)
import UIKit
#endif

struct CharacterImageView: View {
    let state: CharacterState

    /// SF Symbol fallback 의 padding 비율. 컨테이너 크기 대비.
    /// 0.2 정도면 적당히 동그란 배경 가운데에 들어감.
    var symbolPaddingRatio: CGFloat = 0.2

    var body: some View {
        if assetExists {
            Image(state.imageAssetName)
                .resizable()
                .scaledToFit()
        } else {
            // SF Symbol fallback
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

    private var assetExists: Bool {
        #if canImport(UIKit)
        return UIImage(named: state.imageAssetName) != nil
        #else
        return false
        #endif
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
