//
//  CharacterGalleryView.swift
//  withu
//
//  사용자가 만든/첨부한 모든 캐릭터 이미지의 그리드.
//  각 항목 → 다른 state 에 적용 / 삭제 가능.
//

import SwiftUI
import WidgetKit

struct CharacterGalleryView: View {
    @State private var items: [GalleryItem] = []
    @State private var selectedItem: GalleryItem?
    @State private var showApplySheet: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var lastError: String?
    @State private var toastText: String?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        ZStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(items) { item in
                        card(for: item)
                    }
                }
                .padding(12)
            }
            if items.isEmpty {
                emptyState
            }
            if let toast = toastText {
                VStack { Spacer()
                    Text(toast)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 40)
                }
                .transition(.opacity)
            }
        }
        .navigationTitle("캐릭터 갤러리")
        .onAppear { refresh() }
        .confirmationDialog(
            "'\(selectedItem?.sourceState ?? "")' 캐릭터를 어디에 적용할까?",
            isPresented: $showApplySheet,
            presenting: selectedItem
        ) { item in
            ForEach(CharacterState.allCases, id: \.self) { state in
                Button("\(state.symbolEmoji) \(state.rawValue) 자리에") {
                    apply(item, to: state)
                }
            }
            Button("취소", role: .cancel) {}
        }
        .alert("삭제할까요?", isPresented: $showDeleteConfirm, presenting: selectedItem) { item in
            Button("삭제", role: .destructive) {
                CharacterImageStore.deleteGalleryItem(item.id)
                refresh()
                withAnimation { toastText = "삭제됨" }
                hideToastAfter(1.0)
            }
            Button("취소", role: .cancel) {}
        }
    }

    // MARK: - Card

    private func card(for item: GalleryItem) -> some View {
        let img = CharacterImageStore.loadGalleryImage(id: item.id)
        return VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .tertiarySystemBackground))
                if let img {
                    Image(uiImage: img).resizable().scaledToFit().padding(6)
                } else {
                    Image(systemName: "photo")
                        .font(.title2).foregroundStyle(.secondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)

            HStack(spacing: 4) {
                Text(stateEmoji(item.sourceState)).font(.caption2)
                Text(item.sourceState).font(.caption2).lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(item.createdAt, format: .relative(presentation: .named))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                selectedItem = item
                showApplySheet = true
            } label: { Label("다른 자리에 적용", systemImage: "arrow.right.circle") }

            Button(role: .destructive) {
                selectedItem = item
                showDeleteConfirm = true
            } label: { Label("삭제", systemImage: "trash") }
        }
        .onTapGesture {
            selectedItem = item
            showApplySheet = true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.stack")
                .font(.system(size: 50)).foregroundStyle(.secondary)
            Text("아직 만든 캐릭터가 없어요")
                .foregroundStyle(.secondary)
            Text("\"캐릭터 만들기\" 또는 \"여러 상태 한 번에 만들기\" 에서 만든 이미지가 여기에 모여요.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Actions

    private func refresh() {
        items = CharacterImageStore.loadGalleryMetadata()
    }

    private func apply(_ item: GalleryItem, to state: CharacterState) {
        let ok = CharacterImageStore.applyGalleryItem(item.id, to: state)
        if ok {
            WidgetCenter.shared.reloadAllTimelines()
            withAnimation { toastText = "\(state.rawValue) 자리에 적용됨" }
            hideToastAfter(1.6)
        } else {
            withAnimation { toastText = "적용 실패" }
            hideToastAfter(1.6)
        }
    }

    private func hideToastAfter(_ seconds: Double) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            withAnimation { toastText = nil }
        }
    }

    private func stateEmoji(_ raw: String) -> String {
        CharacterState(rawValue: raw)?.symbolEmoji ?? "🙂"
    }
}

#Preview { NavigationStack { CharacterGalleryView() } }
