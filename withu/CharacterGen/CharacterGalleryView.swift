//
//  CharacterGalleryView.swift
//  withu
//
//  내가 만든/첨부한 캐릭터를 상태별 폴더로 모아보는 화면.
//  landing(폴더 목록) → StateFolderView(폴더 안 그리드) drill-down.
//  그리드·적용·삭제·저장 로직은 GalleryGrid 한 곳에 모아 재사용.
//

import SwiftUI
import Photos
import WidgetKit

// MARK: - Landing: 상태별 폴더 목록

struct CharacterGalleryView: View {
    @State private var grouped: [CharacterState: [GalleryItem]] = [:]
    @State private var legacy: [GalleryItem] = []

    private var totalCount: Int {
        grouped.values.reduce(0) { $0 + $1.count } + legacy.count
    }

    /// landing 배경 톤 — 지금 적용 중인 캐릭터 state (없으면 느긋).
    private var heroState: CharacterState {
        SharedAppState.loadMessage()?.state ?? .idle
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SectionHeader("상태별 폴더") {
                    Text("\(totalCount)개")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 2)

                ForEach(sortedFolders, id: \.self) { state in
                    NavigationLink {
                        StateFolderView(state: state, onChange: refresh)
                    } label: {
                        folderRow(state)
                    }
                    .buttonStyle(.plain)
                }

                if !legacy.isEmpty {
                    NavigationLink {
                        GalleryGrid(items: legacy, backgroundState: .idle, onChange: refresh) {
                            legacyHeader
                        }
                        .navigationTitle("기타")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        legacyRow
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(backgroundGradient(for: heroState).ignoresSafeArea())
        .navigationTitle("캐릭터 갤러리")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
        .overlay {
            if totalCount == 0 { emptyState }
        }
    }

    private func refresh() {
        let g = CharacterImageStore.loadGalleryGrouped()
        grouped = g.byState
        legacy = g.legacy
    }

    /// 적용 중인 폴더 → 항목 있는 폴더 → 빈 폴더. 같은 그룹 안은 userFacing 선언 순서.
    private var sortedFolders: [CharacterState] {
        let order = CharacterState.userFacing
        func rank(_ s: CharacterState) -> Int {
            if CharacterImageStore.hasImage(for: s) { return 0 }
            if !(grouped[s]?.isEmpty ?? true) { return 1 }
            return 2
        }
        return order.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return (order.firstIndex(of: a) ?? 0) < (order.firstIndex(of: b) ?? 0)
        }
    }

    private func folderRow(_ state: CharacterState) -> some View {
        let count = grouped[state]?.count ?? 0
        let isEmpty = count == 0
        let applied = CharacterImageStore.hasImage(for: state)
        let subtitle = isEmpty ? "아직 없어요"
            : (applied ? "\(count)개 · 지금 적용 중" : "\(count)개")
        return HStack(spacing: 14) {
            StateEmojiChip(state: state, size: 44)
                .overlay(alignment: .topTrailing) {
                    if applied {
                        Circle()
                            .fill(.green)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(state.koreanShortLabel)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .opacity(isEmpty ? 0.55 : 1)
        .frostedCard()
    }

    private var legacyRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.secondary.opacity(0.15))
                Image(systemName: "tray.full")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("기타")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(legacy.count)개 · 예전에 만든 캐릭터")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frostedCard()
    }

    private var legacyHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.secondary.opacity(0.15))
                Image(systemName: "tray.full").font(.title2).foregroundStyle(.secondary)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("예전에 만든 캐릭터")
                    .font(.callout.weight(.semibold))
                Text("\(legacy.count)개")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frostedCard()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.withuPink.opacity(0.18))
                    .frame(width: 120, height: 120)
                Text("🎨").font(.system(size: 52))
            }
            VStack(spacing: 6) {
                Text("아직 만든 캐릭터가 없어요")
                    .font(.callout.weight(.semibold))
                Text("캐릭터를 만들면 상태별 폴더에\n차곡차곡 모여요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}

// MARK: - Folder: 한 상태의 캐릭터 그리드

struct StateFolderView: View {
    let state: CharacterState
    var onChange: () -> Void = {}

    @State private var items: [GalleryItem] = []

    var body: some View {
        Group {
            if items.isEmpty {
                ScrollView {
                    VStack(spacing: 20) {
                        miniHero
                        emptyState
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .background(backgroundGradient(for: state).ignoresSafeArea())
            } else {
                GalleryGrid(items: items, backgroundState: state, onChange: refresh) {
                    miniHero
                }
            }
        }
        .navigationTitle(state.koreanShortLabel)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
    }

    private func refresh() {
        items = CharacterImageStore.loadGalleryGrouped().byState[state] ?? []
        onChange()
    }

    private var miniHero: some View {
        HStack(spacing: 14) {
            StateEmojiChip(state: state, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.caption)
                    .font(.callout.weight(.semibold))
                Text(items.isEmpty ? "아직 없어요" : "\(items.count)개")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frostedCard()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(state.tint.opacity(0.18))
                .frame(width: 96, height: 96)
                .overlay(Text(state.symbolEmoji).font(.system(size: 44)))
            Text("\(state.koreanShortLabel) 캐릭터가 아직 없어요")
                .font(.callout.weight(.semibold))
            Text("이 순간에 어울리는 캐릭터를 만들어 보세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            NavigationLink {
                CharacterGenView()
            } label: {
                Text("생성하러 가기")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Color.withuPink, in: Capsule())
            }
            .padding(.top, 4)
        }
        .padding(.top, 50)
    }
}

// MARK: - 재사용 그리드 (적용 / 삭제 / 저장 / 다중 선택)

struct GalleryGrid<Header: View>: View {
    let items: [GalleryItem]
    var backgroundState: CharacterState
    var onChange: () -> Void
    @ViewBuilder var header: () -> Header

    @State private var selectedItem: GalleryItem?
    @State private var showApplySheet: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var toastText: String?
    @State private var saveResultMessage: String?
    @State private var showSaveAlert: Bool = false

    @State private var isSelectionMode: Bool = false
    @State private var selectedIDs: Set<String> = []
    @State private var showBulkDeleteConfirm: Bool = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    header()
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items) { item in
                            card(for: item)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            if let toast = toastText {
                VStack {
                    Spacer()
                    Text(toast)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 40)
                }
                .transition(.opacity)
            }
        }
        .background(backgroundGradient(for: backgroundState).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSelectionMode {
                    Button("취소") {
                        isSelectionMode = false
                        selectedIDs = []
                    }
                } else {
                    Button("선택") { isSelectionMode = true }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelectionMode { selectionBottomBar }
        }
        .confirmationDialog(
            "'\(stateKoreanLabel(selectedItem?.sourceState ?? ""))' 캐릭터를 어디에 적용할까요?",
            isPresented: $showApplySheet,
            presenting: selectedItem
        ) { item in
            ForEach(CharacterState.userFacing, id: \.self) { state in
                Button("\(state.koreanShortLabel) 자리에") { apply(item, to: state) }
            }
            Button("취소", role: .cancel) {}
        }
        .alert("이 캐릭터를 지울까요?", isPresented: $showDeleteConfirm, presenting: selectedItem) { item in
            Button("삭제", role: .destructive) {
                CharacterImageStore.deleteGalleryItem(item.id)
                selectedItem = nil
                onChange()
                withAnimation { toastText = "지웠어요" }
                hideToastAfter(1.0)
            }
            Button("취소", role: .cancel) {}
        }
        .alert("사진 저장", isPresented: $showSaveAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(saveResultMessage ?? "")
        }
        .alert("\(selectedIDs.count)개를 지울까요?", isPresented: $showBulkDeleteConfirm) {
            Button("삭제", role: .destructive) { deleteSelected() }
            Button("취소", role: .cancel) {}
        }
        .sheet(item: $selectedItem) { item in
            galleryDetailSheet(item: item)
        }
    }

    // MARK: Selection bar

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

    // MARK: Card

    private func card(for item: GalleryItem) -> some View {
        let img = CharacterImageStore.loadGalleryImage(id: item.id)
        let isSelected = selectedIDs.contains(item.id)
        let hasFrame1 = item.hasFrame1 ?? false
        let isActive = !CharacterImageStore.statesUsingGalleryItem(item.id).isEmpty
        return VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
                if let img {
                    Image(uiImage: img).resizable().scaledToFit().padding(6)
                } else {
                    Image(systemName: "photo")
                        .font(.title2).foregroundStyle(.secondary)
                }
                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.withuPink : .secondary)
                        .background(Circle().fill(.regularMaterial))
                        .padding(6)
                }
                // 지금 적용 중 표시 — 우상단 초록 점
                if isActive && !isSelectionMode {
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                }
                // 연속 이미지 배지
                if hasFrame1 && !isSelectionMode {
                    Text("연속")
                        .font(.system(size: 10).weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.withuPink : .clear, lineWidth: 3)
            )

            Text(item.createdAt, format: .relative(presentation: .named))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
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
                selectedItem = item
            }
        }
        .onLongPressGesture {
            if !isSelectionMode {
                isSelectionMode = true
                selectedIDs = [item.id]
            }
        }
    }

    // MARK: Detail sheet

    @ViewBuilder
    private func galleryDetailSheet(item: GalleryItem) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let img = CharacterImageStore.loadGalleryImage(id: item.id) {
                        if let f1 = CharacterImageStore.loadGalleryFrame1(id: item.id) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(spacing: 4) {
                                    Image(uiImage: img).resizable().scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    Text("1번째").font(.caption2).foregroundStyle(.secondary)
                                }
                                VStack(spacing: 4) {
                                    Image(uiImage: f1).resizable().scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    Text("2번째").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal)
                        } else {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 320)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        let activeStates = CharacterImageStore.statesUsingGalleryItem(item.id)
                        HStack {
                            if !activeStates.isEmpty {
                                StatusPill(
                                    kind: .ok,
                                    label: "\(activeStates.map(\.koreanShortLabel).joined(separator: ", ")) 자리에 적용 중"
                                )
                            } else if item.hasFrame1 ?? false {
                                Text("연속 이미지")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.createdAt, format: .relative(presentation: .named))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

                        Button {
                            apply(item, to: backgroundState)
                            selectedItem = nil
                        } label: {
                            Label("'\(backgroundState.koreanShortLabel)' 자리에 적용하기",
                                  systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.withuPink)
                        .padding(.horizontal)

                        HStack(spacing: 12) {
                            Button {
                                Task { await saveOneToPhotos(img) }
                            } label: {
                                Label("저장", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.secondary)

                            Button {
                                showApplySheet = true
                            } label: {
                                Label("다른 자리에", systemImage: "arrow.right.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.secondary)
                        }
                        .padding(.horizontal)

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("삭제", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .padding(.horizontal)
                    } else {
                        Image(systemName: "photo")
                            .font(.largeTitle).foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("\(stateKoreanLabel(item.sourceState)) 캐릭터")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { selectedItem = nil }
                }
            }
        }
    }

    // MARK: Actions

    private func apply(_ item: GalleryItem, to state: CharacterState) {
        let ok = CharacterImageStore.applyGalleryItem(item.id, to: state)
        if ok {
            WidgetCenter.shared.reloadAllTimelines()
            if let img = CharacterImageStore.loadGalleryImage(id: item.id) {
                ConnectivityManager.shared.sendCharacterImage(img, for: state, frame: 0)
            }
            if let f1 = CharacterImageStore.loadGalleryFrame1(id: item.id) {
                ConnectivityManager.shared.sendCharacterImage(f1, for: state, frame: 1)
            }
            onChange()
            withAnimation { toastText = "\(state.koreanShortLabel) 자리에 적용했어요" }
            hideToastAfter(1.6)
        } else {
            withAnimation { toastText = "적용하지 못했어요" }
            hideToastAfter(1.6)
        }
    }

    private func saveSelected() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveResultMessage = "사진 추가 권한이 꺼져 있어요. 설정에서 켜주세요."
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
            saveResultMessage = "\(imgs.count)장을 사진 앱에 저장했어요."
        } catch {
            saveResultMessage = "저장하지 못했어요. 다시 시도해 주세요."
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
        onChange()
        withAnimation { toastText = "\(count)개를 지웠어요" }
        hideToastAfter(1.2)
    }

    private func saveOneToPhotos(_ image: UIImage) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveResultMessage = "사진 추가 권한이 꺼져 있어요. 설정에서 켜주세요."
            showSaveAlert = true
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            saveResultMessage = "사진 앱에 저장했어요."
        } catch {
            saveResultMessage = "저장하지 못했어요. 다시 시도해 주세요."
        }
        showSaveAlert = true
    }

    private func hideToastAfter(_ seconds: Double) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            withAnimation { toastText = nil }
        }
    }

    private func stateKoreanLabel(_ raw: String) -> String {
        CharacterState(rawValue: raw)?.koreanShortLabel ?? raw
    }
}

#Preview { NavigationStack { CharacterGalleryView() } }
