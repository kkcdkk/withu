//
//  SquareCropView.swift
//  withu
//
//  사진 첨부 시 정사각으로 자르는 편집 화면.
//  핀치로 확대 · 드래그로 위치 맞춤 → 보이는 정사각 영역을 1024px 로 잘라 반환.
//

import SwiftUI
import UIKit

/// crop 시트를 띄울 대상 — 선택한 이미지 + 자른 뒤 처리 콜백.
struct CropTarget: Identifiable {
    let id = UUID()
    let image: UIImage
    let onDone: (UIImage) -> Void
}

struct SquareCropView: View {
    let image: UIImage
    var onDone: (UIImage) -> Void
    var onCancel: () -> Void

    @State private var scale: CGFloat = 1
    @GestureState private var gestureScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var gestureOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) - 48
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {
                    // 상단 바 — 취소(좌) / 선택(우)
                    HStack {
                        Button("취소") { onCancel() }
                            .foregroundStyle(.white)
                        Spacer()
                        Button {
                            if let cropped = renderCrop(side: side) {
                                onDone(cropped)
                            } else {
                                onCancel()
                            }
                        } label: {
                            Text("선택")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 22).padding(.vertical, 9)
                                .background(Color.withuPink, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                    Spacer()

                    cropWindow(side: side)

                    Text("두 손가락으로 확대 · 드래그로 위치를 맞춰요")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()
                }
            }
        }
    }

    private func cropWindow(side: CGFloat) -> some View {
        croppedImage(side: side)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white, lineWidth: 2)
            )
            .gesture(
                DragGesture()
                    .updating($gestureOffset) { v, state, _ in state = v.translation }
                    .onEnded { v in
                        offset.width += v.translation.width
                        offset.height += v.translation.height
                    }
                    .simultaneously(with:
                        MagnifyGesture()
                            .updating($gestureScale) { v, state, _ in state = v.magnification }
                            .onEnded { v in scale = max(1, scale * v.magnification) }
                    )
            )
    }

    /// 정사각 윈도우 안에 변형된 이미지 (표시 + 렌더 공용).
    private func croppedImage(side: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .scaleEffect(scale * gestureScale)
            .offset(x: offset.width + gestureOffset.width,
                    y: offset.height + gestureOffset.height)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 현재 보이는 정사각을 1024px UIImage 로 렌더.
    @MainActor
    private func renderCrop(side: CGFloat) -> UIImage? {
        let content = croppedImage(side: side)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1024 / side
        return renderer.uiImage
    }
}
