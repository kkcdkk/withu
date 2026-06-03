//
//  CharacterGalleryView.swift
//  withu
//
//  사용자가 만든/첨부한 모든 캐릭터 이미지의 그리드.
//  각 항목 → 다른 state 에 적용 / 삭제 가능.
//

import SwiftUI
import Photos
import WidgetKit

struct CharacterGalleryView: View {
    @State private var items: [GalleryItem] = []
    @State private var selectedItem: GalleryItem?
    @State private var showApplySheet: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var lastError: String?
    @State private var toastText: String?
    @State private var saveResultMessage: String?
    @State private var showSaveAlert: Bool = false

    // 다중 선택 모드
    @State private var isSelectionMode: Bool = false
    @State private var selectedIDs: Set<String> = []
    @State private var showBulkDeleteConfirm: Bool = false

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSelectionMode {
                    Button("취소") {
                        isSelectionMode = false
                        selectedIDs = []
                    }
                } else {
                    Button("선택") {
                        isSelectionMode = true
                    }
                    .disabled(items.isEmpty)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelectionMode {
                selectionBottomBar
            }
        }
        .onAppear { refresh() }
        .confirmationDialog(
            "'\(selectedItem?.sourceState ?? "")' 캐릭터를 어디에 적용할까?",
            isPresented: $showApplySheet,
            presenting: selectedItem
        ) { item in
            ForEach(CharacterState.userFacing, id: \.self) { state in
                Button("\(state.symbolEmoji) \(state.rawValue) 자리에") {
                    apply(item, to: state)
                }
            }
            Button("취소", role: .cancel) {}
        }
        .alert("캐릭터 삭제", isPresented: $showDeleteConfirm, presenting: selectedItem) { item in
            Button("삭제", role: .destructive) {
                CharacterImageStore.deleteGalleryItem(item.id)
                selectedItem = nil
                refresh()
                withAnimation { toastText = "삭제됨" }
                hideToastAfter(1.0)
            }
            Button("취소", role: .cancel) {}
        }
        .alert("사진 저장", isPresented: $showSaveAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(saveResultMessage ?? "")
        }
        .alert("\(selectedIDs.count)개 캐릭터 삭제", isPresented: $showBulkDeleteConfirm) {
            Button("삭제", role: .destructive) { deleteSelected() }
            Button("취소", role: .cancel) {}
        }
        .sheet(item: $selectedItem) { item in
            galleryDetailSheet(item: item)
        }
    }

    private var selectionBottomBar: some View {
        HStack(spacing: 16) {
            Button {
                Task { await saveSelected() }
            } label: {
                Label("저장", systemImage: "square.and.arrow.down")
            }
            .disabled(selectedIDs.isEmpty)
            Spacer()
            Text("\(selectedIDs.count)개 선택")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) {
                showBulkDeleteConfirm = true
            } label: {
                Label("삭제", systemImage: "trash")
            }
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    // MARK: - Bulk actions

    private func saveSelected() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveResultMessage = "사진 추가 권한이 거부됐어요. 설정 → withu 에서 허용해 주세요."
            showSaveAlert = true
            return
        }
        let imgs = selectedIDs.compactMap { CharacterImageStore.loadGalleryImage(id: $0) }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for img in imgs {
                    PHAssetChangeRequest.creationRequestForAsset(from: img)
                }
            }
            saveResultMessage = "\(imgs.count)장 사진 앱에 저장됐어요."
        } catch {
            saveResultMessage = "저장 실패: \(error.localizedDescription)"
        }
        showSaveAlert = true
        isSelectionMode = false
        selectedIDs = []
    }

    private func deleteSelected() {
        for id in selectedIDs {
            CharacterImageStore.deleteGalleryItem(id)
        }
        let count = selectedIDs.count
        selectedIDs = []
        isSelectionMode = false
        refresh()
        withAnimation { toastText = "\(count)개 삭제됨" }
        hideToastAfter(1.2)
    }

    // MARK: - Detail sheet

    @ViewBuilder
    private func galleryDetailSheet(item: GalleryItem) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let img = CharacterImageStore.loadGalleryImage(id: item.id) {
                        // frame 1 있으면 frame 1/2 나란히, 없으면 단일
                        if let f1 = CharacterImageStore.loadGalleryFrame1(id: item.id) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(spacing: 4) {
                                    Image(uiImage: img).resizable().scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    Text("frame 1").font(.caption2).foregroundStyle(.secondary)
                                }
                                VStack(spacing: 4) {
                                    Image(uiImage: f1).resizable().scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    Text("frame 2").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal)
                        } else {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 320)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        HStack {
                            Text(stateEmoji(item.sourceState))
                            Text(item.sourceState).font(.subheadline.weight(.medium))
                            if item.hasFrame1 ?? false {
                                Text("· 🎬 연속")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.createdAt, format: .relative(presentation: .named))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

                        HStack(spacing: 12) {
                            Button {
                                Task { await saveOneToPhotos(img) }
                            } label: {
                                Label("저장", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                showApplySheet = true
                            } label: {
                                Label("적용", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.horizontal)

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("삭제", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal)
                    } else {
                        Image(systemName: "photo")
                            .font(.largeTitle).foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("캐릭터")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { selectedItem = nil }
                }
            }
        }
    }

    /// 단일 이미지를 사진 앱에 저장.
    private func saveOneToPhotos(_ image: UIImage) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveResultMessage = "사진 추가 권한이 거부됐어요. 설정 → withu 에서 허용해 주세요."
            showSaveAlert = true
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            saveResultMessage = "사진 앱에 저장됐어요."
        } catch {
            saveResultMessage = "저장 실패: \(error.localizedDescription)"
        }
        showSaveAlert = true
    }

    // MARK: - Card

    private func card(for item: GalleryItem) -> some View {
        let img = CharacterImageStore.loadGalleryImage(id: item.id)
        let isSelected = selectedIDs.contains(item.id)
        let hasFrame1 = item.hasFrame1 ?? false
        return VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .tertiarySystemBackground))
                if let img {
                    Image(uiImage: img).resizable().scaledToFit().padding(6)
                } else {
                    Image(systemName: "photo")
                        .font(.title2).foregroundStyle(.secondary)
                }
                // 선택 모드 + 선택됨 → 체크. 모드만 켜져있고 미선택 → 빈 원
                if isSelectionMode {
                    Image(systemName: isSelected
                          ? "checkmark.circle.fill"
                          : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .background(Circle().fill(.regularMaterial))
                        .padding(6)
                }
                // 연속 이미지 (frame 1 있음) 배지 — 우상단
                if hasFrame1 {
                    Text("🎬")
                        .font(.caption)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            )

            HStack(spacing: 4) {
                Text(stateEmoji(item.sourceState)).font(.caption2)
                Text(item.sourceState).font(.caption2).lineLimit(1)
                Spacer(minLength: 0)
            }
            // 이 갤러리 항목이 현재 활성으로 적용된 state 들의 이모지 chip
            let activeStates = CharacterImageStore.statesUsingGalleryItem(item.id)
            if !activeStates.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                    ForEach(activeStates, id: \.self) { s in
                        Text(s.symbolEmoji).font(.system(size: 11))
                    }
                    Spacer(minLength: 0)
                }
            }
            Text(item.createdAt, format: .relative(presentation: .named))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if !isSelectionMode {
                Button {
                    selectedItem = item
                    showApplySheet = true
                } label: { Label("다른 자리에 적용", systemImage: "arrow.right.circle") }

                Button(role: .destructive) {
                    selectedItem = item
                    showDeleteConfirm = true
                } label: { Label("삭제", systemImage: "trash") }
            }
        }
        .onTapGesture {
            if isSelectionMode {
                if isSelected { selectedIDs.remove(item.id) }
                else { selectedIDs.insert(item.id) }
            } else {
                selectedItem = item  // sheet 자동 열림
            }
        }
        .onLongPressGesture {
            if !isSelectionMode {
                isSelectionMode = true
                selectedIDs = [item.id]
            }
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
            // 워치도 같은 이미지로 갱신 — frame 0 + (있으면) frame 1
            if let img = CharacterImageStore.loadGalleryImage(id: item.id) {
                ConnectivityManager.shared.sendCharacterImage(img, for: state, frame: 0)
            }
            if let f1 = CharacterImageStore.loadGalleryFrame1(id: item.id) {
                ConnectivityManager.shared.sendCharacterImage(f1, for: state, frame: 1)
            }
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
