//
//  GalleryReferencePicker.swift
//  withu
//
//  참고사진을 '내 캐릭터 갤러리'에서 고르는 sheet.
//  단건/배치 생성의 참고사진 선택에서 사진 앱 대신 쓸 수 있는 경로.
//

import SwiftUI

struct GalleryReferencePicker: View {
    /// 선택된 갤러리 이미지 (원본 로드본).
    var onPick: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [GalleryItem] = []

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(CharacterState.idle.imageAssetName)
                            .resizable().scaledToFit().frame(width: 56, height: 56)
                        Text("아직 만든 캐릭터가 없어요")
                            .font(.pretendard(16, relativeTo: .callout))
                        Text("캐릭터를 만들면 여기서 참고사진으로 고를 수 있어요.")
                            .font(.pretendard(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(items) { item in
                                cell(for: item)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("내 캐릭터에서 고르기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .onAppear { items = CharacterImageStore.loadGalleryMetadata() }
        }
    }

    @ViewBuilder
    private func cell(for item: GalleryItem) -> some View {
        if let img = CharacterImageStore.loadGalleryImage(id: item.id) {
            Button {
                onPick(img)
                dismiss()
            } label: {
                VStack(spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.regularMaterial)
                        Image(uiImage: img).resizable().scaledToFit().padding(5)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    Text(CharacterState(rawValue: item.sourceState)?.koreanShortLabel ?? "기타")
                        .font(.pretendard(10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview { GalleryReferencePicker { _ in } }
