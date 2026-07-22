//
//  CharacterGalleryView.swift
//  withu
//
//  내가 만든/첨부한 캐릭터를 상태별 폴더로 모아보는 화면.
//  landing(폴더 목록) → StateFolderView(폴더 안 그리드) drill-down.
//  그리드·적용·삭제·저장 로직은 GalleryGrid 한 곳에 모아 재사용.
//

import SwiftUI
import Combine
import Photos
import WidgetKit

// MARK: - Landing: 상태별 폴더 목록

/// 갤러리용 상태 칩 — 이모지 대신 실제 캐릭터 이미지.
/// 우선순위: 적용 중인 사진 → 그 상태 갤러리의 맨 앞 사진 → withy 기본 캐릭터(번들).
struct GalleryStateChip: View {
    var state: CharacterState
    var firstItem: GalleryItem?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(state.tint.opacity(0.22))
            if !CharacterImageStore.hasImage(for: state),
               let item = firstItem,
               let img = CharacterImageStore.loadGalleryImage(id: item.id) {
                // 적용 전이지만 만들어 둔 사진이 있으면 그 첫 장으로
                Image(uiImage: img)
                    .resizable().scaledToFit()
                    .padding(size * 0.12)
            } else {
                // 적용본 → 번들 기본 캐릭터 → 심볼 순 fallback (CharacterImageView)
                CharacterImageView(state: state)
                    .padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
    }
}

struct CharacterGalleryView: View {
    enum Mode: Hashable { case byState, byCharacter }
    @State private var mode: Mode = .byState
    @State private var grouped: [CharacterState: [GalleryItem]] = [:]
    @State private var legacy: [GalleryItem] = []
    /// 캐릭터별('한번에 만들기') 그룹 — batchId 로 묶음.
    @State private var characters: [(batchId: String, createdAt: Date, items: [GalleryItem])] = []
    @State private var toastText: String?
    /// '모두 적용' 확인 대기 중인 그룹 items — 여러 자리를 한 번에 덮으니 확인 후 실행.
    @State private var pendingApplyAll: [GalleryItem]?

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
                Picker("보기", selection: $mode) {
                    Text("상태별").tag(Mode.byState)
                    Text("캐릭터별").tag(Mode.byCharacter)
                }
                .pickerStyle(.segmented)

                if mode == .byState {
                    stateFolders
                } else {
                    characterFolders
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
        // 서버 백업에서 복원 완료 — 화면 떠 있는 동안 도착해도 바로 보이게.
        .onReceive(NotificationCenter.default.publisher(for: .gallerySyncDidImport)) { _ in
            refresh()
        }
        .alert("이 캐릭터로 모두 적용할까요?", isPresented: Binding(
            get: { pendingApplyAll != nil },
            set: { if !$0 { pendingApplyAll = nil } }
        )) {
            Button("모두 적용") {
                if let items = pendingApplyAll { applyCharacter(items) }
                pendingApplyAll = nil
            }
            Button("취소", role: .cancel) { pendingApplyAll = nil }
        } message: {
            Text("\(pendingApplyAll?.count ?? 0)개 상태 자리의 캐릭터가 모두 이 캐릭터로 바뀌어요.")
        }
        .overlay(alignment: .bottom) {
            if let toast = toastText {
                Text(toast)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 40)
                    .transition(.opacity)
            }
        }
        .overlay {
            if totalCount == 0 && mode == .byState { emptyState }
        }
    }

    @ViewBuilder
    private var stateFolders: some View {
        SectionHeader("상태별 폴더") {
            Text("\(totalCount)개").font(.caption).foregroundStyle(.tertiary)
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

    @ViewBuilder
    private var characterFolders: some View {
        if characters.isEmpty {
            VStack(spacing: 10) {
                Image(CharacterState.idle.imageAssetName)
                    .resizable().scaledToFit().frame(width: 64, height: 64)
                Text("'여러 모습 만들기'로 만든 캐릭터가\n여기에 묶여요.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("하나씩 만든 캐릭터는 '상태별'에서 볼 수 있어요.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 60)
        } else {
            ForEach(characters, id: \.batchId) { group in
                characterCard(group)
            }
        }
    }

    private func characterCard(_ group: (batchId: String, createdAt: Date, items: [GalleryItem])) -> some View {
        VStack(spacing: 8) {
            NavigationLink {
                GalleryGrid(items: group.items, backgroundState: .idle, onChange: refresh) {
                    EmptyView()
                }
                .navigationTitle("이 캐릭터")
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack(spacing: 14) {
                    if let rep = representativeImage(group.items) {
                        Image(uiImage: rep).resizable().scaledToFit()
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "square.grid.2x2").font(.title3).foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("캐릭터 · \(group.items.count)개 모습").font(.callout.weight(.semibold))
                        Text(group.createdAt, format: .relative(presentation: .named))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Button {
                pendingApplyAll = group.items
            } label: {
                Label("이 캐릭터로 모두 적용", systemImage: "square.and.arrow.down.on.square.fill")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WithuCTAButtonStyle())
        }
        .frostedCard()
    }

    /// 대표 썸네일 — idle 있으면 idle, 없으면 첫 항목.
    private func representativeImage(_ items: [GalleryItem]) -> UIImage? {
        let rep = items.first { $0.sourceState == CharacterState.idle.rawValue } ?? items.first
        return rep.flatMap { CharacterImageStore.loadGalleryImage(id: $0.id) }
    }

    /// 이 캐릭터의 모든 모습을 각 상태 자리에 적용 + 워치 전송 + 위젯 reload.
    private func applyCharacter(_ items: [GalleryItem]) {
        var applied = 0
        for item in items {
            guard let state = CharacterState(rawValue: item.sourceState) else { continue }
            if CharacterImageStore.applyGalleryItem(item.id, to: state) {
                if let img = CharacterImageStore.loadGalleryImage(id: item.id) {
                    ConnectivityManager.shared.sendCharacterImage(img, for: state, frame: 0)
                }
                if let f1 = CharacterImageStore.loadGalleryFrame1(id: item.id) {
                    ConnectivityManager.shared.sendCharacterImage(f1, for: state, frame: 1)
                }
                applied += 1
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { toastText = String(localized: "\(applied)개 모습을 모두 적용했어요") }
        Task { try? await Task.sleep(for: .seconds(1.6)); withAnimation { toastText = nil } }
    }

    private func refresh() {
        let g = CharacterImageStore.loadGalleryGrouped()
        grouped = g.byState
        legacy = g.legacy
        characters = CharacterImageStore.loadGalleryByCharacter()
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
        let subtitle = isEmpty ? String(localized: "아직 없어요")
            : (applied ? String(localized: "\(count)개 · 지금 적용 중") : String(localized: "\(count)개"))
        return HStack(spacing: 14) {
            GalleryStateChip(state: state, firstItem: grouped[state]?.first, size: 44)
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
                Image(CharacterState.idle.imageAssetName)
                    .resizable().scaledToFit().frame(width: 84, height: 84)
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
            GalleryStateChip(state: state, firstItem: items.first, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.caption)
                    .font(.callout.weight(.semibold))
                Text(items.isEmpty ? String(localized: "아직 없어요") : String(localized: "\(items.count)개"))
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
                .overlay(
                    // 이모지 대신 번들 기본 일러스트 — 투명 PNG 라 tint 배경과 어울림.
                    Image(state.imageAssetName)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                )
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
    /// 프레임 스왑처럼 메타데이터는 그대로고 파일만 바뀌는 경우 상세 시트를 강제 재로드.
    @State private var frameSwapTick: Int = 0
    @State private var showApplySheet: Bool = false
    @State private var showDeleteConfirm: Bool = false
    /// 상세 시트에서 저장 안 한 편집(배경/다듬기)이 있는데 닫으려 할 때 확인.
    @State private var showDetailDiscardConfirm: Bool = false
    @State private var toastText: String?
    @State private var saveResultMessage: String?
    @State private var showSaveAlert: Bool = false

    @State private var isSelectionMode: Bool = false
    @State private var selectedIDs: Set<String> = []
    @State private var showBulkDeleteConfirm: Bool = false

    // 배경 보기 — 상세 sheet 에서 '배경 빼기 / 배경 있기' 미리보기 토글 후 저장.
    enum BGPreview { case transparent, white }
    @State private var bgPreview: BGPreview? = nil     // nil = 저장된 그대로
    @State private var bgCutout: UIImage? = nil        // Vision 결과 캐시 (frame 0)
    @State private var bgCutoutF1: UIImage? = nil      // Vision 결과 캐시 (frame 1)
    @State private var isRemovingBackground: Bool = false

    // 다듬기 — 이미 만든 캐릭터를 참고로 한 번 더 생성 (캔디 차감, 무료 미적용).
    @State private var refineText: String = ""
    @State private var isRefining: Bool = false
    @State private var showRefineConfirm: Bool = false

    /// 다듬기 성공 결과 임시 보관 — 전/후 비교에서 선택하기 전까지 원본을 덮어쓰지 않음.
    struct RefineCompareContext: Identifiable {
        let id = UUID()
        let itemId: String
        var versions: [UIImage]   // [0] = 원본, 이후 = 다듬은 버전
        var selected: Int
        var current: UIImage { versions[Swift.min(Swift.max(0, selected), versions.count - 1)] }
    }
    @State private var refineCompare: RefineCompareContext?
    /// 이 항목에 저장된 다듬기 이력이 있는지 — 상세 시트에 '다듬기 이력' 재열람 버튼 노출용.
    @State private var hasStoredRefineHistory: Bool = false

    // 움직이는 캐릭터 만들기 — frame 1 없는 항목에 2번째 장면을 생성해 부착.
    @State private var isMakingMotion: Bool = false
    @State private var showMotionConfirm: Bool = false

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
                withAnimation { toastText = String(localized: "지웠어요") }
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

    /// 캔디 비용 표시 — "캔디 1개 소모". (배지/아이콘은 보유량으로 오해될 수 있어 문구로.)
    private func candyBadge(_ count: Int) -> some View {
        Text("캔디 \(count)개 소모")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    /// 상세 시트에 저장 안 된 편집이 있는지 — 배경 미리보기 / 다듬기 결과 / 입력한 다듬기 문구.
    private var detailHasChanges: Bool {
        bgPreview != nil
            || refineCompare != nil
            || !refineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private func galleryDetailSheet(item: GalleryItem) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let img = CharacterImageStore.loadGalleryImage(id: item.id) {
                        let _ = frameSwapTick   // 스왑 시 이 블록 재평가 → 디스크에서 재로드
                        let activeStates = CharacterImageStore.statesUsingGalleryItem(item.id)

                        // [미리보기] — 이미지만 크게, 글자 겹침 없음
                        if let f1 = CharacterImageStore.loadGalleryFrame1(id: item.id) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(spacing: 4) {
                                    Image(uiImage: detailDisplay(img, cutout: bgCutout)).resizable().scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    Text("1번째").font(.caption2).foregroundStyle(.secondary)
                                }
                                VStack(spacing: 4) {
                                    Image(uiImage: detailDisplay(f1, cutout: bgCutoutF1)).resizable().scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    Text("2번째").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal)
                        } else {
                            Image(uiImage: detailDisplay(img, cutout: bgCutout))
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        // 캡션 — 제목·시간은 이미지 밖 한 줄로 (겹침 제거)
                        HStack(spacing: 6) {
                            Text("\(stateKoreanLabel(item.sourceState)) 캐릭터")
                                .font(.callout.weight(.semibold))
                            Text("·").foregroundStyle(.tertiary)
                            Text(item.createdAt, format: .relative(presentation: .named))
                                .font(.caption).foregroundStyle(.secondary)
                            if item.hasFrame1 ?? false {
                                Text("·").foregroundStyle(.tertiary)
                                Text("연속 이미지").font(.caption).foregroundStyle(.secondary)
                            }
                        }

                        // [상태/주 액션]
                        if !activeStates.isEmpty {
                            // 적용 중이면 상태 카드 + 그 오른쪽에 '다른 자리에' 메뉴 버튼을 한 줄에.
                            HStack(spacing: 10) {
                                StatusPill(
                                    kind: .ok,
                                    label: "\(activeStates.map(\.koreanShortLabel).joined(separator: ", ")) 자리에 적용 중"
                                )
                                Spacer()
                                Menu {
                                    ForEach(CharacterState.userFacing, id: \.self) { state in
                                        Button("\(state.koreanShortLabel) 자리에") {
                                            apply(item, to: state)
                                            withAnimation { toastText = String(localized: "\(state.koreanShortLabel) 자리에 적용했어요") }
                                            hideToastAfter(1.6)
                                        }
                                    }
                                } label: {
                                    Text("다른 자리에")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.withuCTAGreen.opacity(0.14), in: Capsule())
                                        .foregroundStyle(Color.withuCTAGreen)
                                }
                            }
                            .frostedCard()
                            .padding(.horizontal)
                        } else {
                            // 아직 어디에도 적용 안 함 — 큰 적용 CTA + 아래 전체폭 '다른 자리에' 메뉴.
                            Button {
                                apply(item, to: backgroundState)
                                selectedItem = nil
                            } label: {
                                Text("'\(backgroundState.koreanShortLabel)' 자리에 적용하기")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(WithuCTAButtonStyle())
                            .padding(.horizontal)

                            Menu {
                                ForEach(CharacterState.userFacing, id: \.self) { state in
                                    Button("\(state.koreanShortLabel) 자리에") {
                                        apply(item, to: state)
                                        withAnimation { toastText = String(localized: "\(state.koreanShortLabel) 자리에 적용했어요") }
                                        hideToastAfter(1.6)
                                    }
                                }
                            } label: {
                                Text("다른 자리에 적용하기")
                                    .font(.callout.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.withuCTAGreen.opacity(0.14),
                                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .foregroundStyle(Color.withuCTAGreen)
                            }
                            .padding(.horizontal)
                        }

                        // [편집 도구] — 배경 빼기 · (연속) 프레임 · 다듬기 · 움직이게 만들기 한 카드
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("배경 빼기", isOn: Binding(
                                get: { bgPreview == .transparent },
                                set: { on in
                                    if on {
                                        Task { await showTransparentPreview(item, base: img) }
                                    } else {
                                        withAnimation { bgPreview = .white }
                                    }
                                }
                            ))
                            .disabled(isRemovingBackground)
                            if isRemovingBackground {
                                HStack { ProgressView(); Text("배경 빼는 중…") }
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if bgPreview != nil {
                                Button {
                                    Task { await saveBackgroundChoice(item) }
                                } label: {
                                    Text("이대로 저장").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(WithuCTAButtonStyle())
                                .disabled(isRemovingBackground)
                            }

                            if item.hasFrame1 ?? false {
                                Divider()
                                HStack(spacing: 12) {
                                    Button {
                                        if CharacterImageStore.swapGalleryFrames(item.id) {
                                            for state in CharacterImageStore.statesUsingGalleryItem(item.id) {
                                                apply(item, to: state)
                                            }
                                            frameSwapTick += 1
                                            onChange()
                                        }
                                    } label: {
                                        Text("프레임 바꾸기")
                                    }
                                    .buttonStyle(.bordered).tint(.secondary).controlSize(.small)
                                    Spacer()
                                    if let st = activeStates.first {
                                        Toggle("움직임", isOn: Binding(
                                            get: { !CharacterImageStore.isAnimationDisabled(for: st) },
                                            set: { on in
                                                for s in activeStates { CharacterImageStore.setAnimationDisabled(!on, for: s) }
                                                WidgetCenter.shared.reloadAllTimelines()
                                            }
                                        ))
                                        .fixedSize()
                                    }
                                }
                            }

                            Divider()

                            HStack {
                                Text("다듬기").font(.callout.weight(.medium))
                                Spacer()
                                candyBadge(GenerationQuota.cost(forQuality: "low"))
                            }
                            // 헤더·입력칸·'이대로 다듬기'를 한 묶음으로 — 버튼이 다듬기에 속해 보이게
                            // 선은 버튼 아래(다음 섹션 Divider 또는 카드 끝)로 둔다.
                            TextField("바꾸고 싶은 점 (예: 모자를 씌워줘)", text: $refineText, axis: .vertical)
                                .font(.callout)
                            Button {
                                showRefineConfirm = true
                            } label: {
                                if isRefining {
                                    HStack { ProgressView(); Text("다듬는 중…") }
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Text("이대로 다듬기").frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.withuPinkText)
                            .disabled(isRefining || isMakingMotion || refineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Text("다듬은 이력에서 골라 적용할 수 있어요.")
                                .font(.caption2).foregroundStyle(.secondary)
                            // 저장된 다듬기 이력이 있으면 다시 열기.
                            if hasStoredRefineHistory {
                                Button { restoreRefineHistory(item) } label: {
                                    Label("다듬기 이력 보기", systemImage: "clock.arrow.circlepath")
                                        .font(.footnote)
                                }
                                .tint(Color.withuCTAGreen)
                            }

                            if !(item.hasFrame1 ?? false),
                               CharacterState(rawValue: item.sourceState)?.usesGeneratedMotion == true {
                                Divider()
                                HStack {
                                    Text("움직이는 캐릭터 만들기").font(.callout.weight(.medium))
                                    Spacer()
                                    candyBadge(GenerationQuota.cost(forQuality: "low"))
                                }
                                Button {
                                    showMotionConfirm = true
                                } label: {
                                    if isMakingMotion {
                                        HStack { ProgressView(); Text("움직임 만드는 중…") }
                                            .frame(maxWidth: .infinity)
                                    } else {
                                        Text("이대로 움직이게").frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(.withuPinkText)
                                .disabled(isMakingMotion || isRefining)
                                Text("2번째 장면을 만들어 캐릭터가 움직이게 해요.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frostedCard()
                        .padding(.horizontal)
                        .alert("캔디를 사용해요", isPresented: $showMotionConfirm) {
                            Button("만들기") { Task { await makeMotionFrame(item) } }
                            Button("취소", role: .cancel) {}
                        } message: {
                            Text("이번 만들기에 캔디 \(GenerationQuota.cost(forQuality: "low"))개를 써요. 성공했을 때만 차감돼요.")
                        }

                        // 사진 앱 저장은 상단 툴바(닫기 옆) 아이콘으로 이동 — 맨 아래 버튼 제거.

                        // 만든 기록 — 이 이미지를 만들 때 보낸 프롬프트 (옛 항목엔 없음)
                        if let prompt = item.prompt, !prompt.isEmpty {
                            DisclosureGroup {
                                Text(prompt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                Button {
                                    UIPasteboard.general.string = prompt
                                } label: {
                                    Text("프롬프트 복사")
                                        .font(.caption)
                                }
                                .padding(.top, 4)
                            } label: {
                                Text("만든 기록")
                                    .font(.callout.weight(.medium))
                            }
                            .padding(.horizontal)
                        }
                    } else {
                        Image(systemName: "photo")
                            .font(.largeTitle).foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .padding(.vertical)
            }
            // 제목 없음 — 상태·시간은 이미지 아래 캡션이 담당 (이미지와 글자 겹침 제거)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                // 사진 앱 저장 — 맨 아래 버튼에서 여기로 올림 (닫기 옆).
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let image = CharacterImageStore.loadGalleryImage(id: item.id) {
                            Task { await saveOneToPhotos(image) }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        if detailHasChanges { showDetailDiscardConfirm = true } else { selectedItem = nil }
                    }
                }
            }
            // 저장 안 한 배경/다듬기 편집이 있으면 스와이프로도 못 닫게 + 닫기 시 경고.
            .interactiveDismissDisabled(detailHasChanges)
            .confirmationDialog("저장하지 않은 변경이 있어요",
                                isPresented: $showDetailDiscardConfirm, titleVisibility: .visible) {
                Button("닫기", role: .destructive) { selectedItem = nil }
                Button("계속 편집", role: .cancel) {}
            } message: {
                Text("닫으면 방금 바꾼 배경·다듬기 내용이 지워져요.")
            }
            .alert("캔디를 사용해요", isPresented: $showRefineConfirm) {
                Button("다듬기") { Task { await refineItem(item) } }
                Button("취소", role: .cancel) {}
            } message: {
                Text("이번 다듬기에 캔디 \(GenerationQuota.cost(forQuality: "low"))개를 써요. 성공했을 때만 차감돼요.")
            }
            // 다듬기 전/후 비교 — 선택 전까지 원본 유지. 스와이프로 닫으면 '이전 그대로'.
            .sheet(item: $refineCompare) { ctx in
                refineCompareSheet(ctx)
            }
            .onAppear {
                // 시트가 열릴 때마다(항목별) 미리보기·다듬기 입력 초기화
                bgPreview = nil
                bgCutout = nil
                bgCutoutF1 = nil
                refineText = ""
                // 이 항목에 저장된 다듬기 이력이 있으면 '이력 보기' 버튼 노출.
                hasStoredRefineHistory = GalleryRefineHistoryStore.exists(itemId: item.id)
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
            withAnimation { toastText = String(localized: "\(state.koreanShortLabel) 자리에 적용했어요") }
            hideToastAfter(1.6)
        } else {
            withAnimation { toastText = String(localized: "적용하지 못했어요") }
            hideToastAfter(1.6)
        }
    }

    /// 상세 시트에 보여줄 이미지 — 미리보기 선택 반영.
    /// 배경 빼기 = Vision 결과(원본이 이미 투명이면 그대로), 배경 있기 = 흰색 합성.
    private func detailDisplay(_ base: UIImage, cutout: UIImage?) -> UIImage {
        switch bgPreview {
        case nil:           return base
        case .transparent:  return cutout ?? base
        case .white:        return ImageProcessing.flattenedOnWhite(base)
        }
    }

    /// 이미지에 투명 픽셀이 실제로 있는지 — 32px 로 줄여 알파 스캔 (저비용).
    private func hasTransparency(_ image: UIImage) -> Bool {
        guard let small = image.preparingThumbnail(of: CGSize(width: 32, height: 32)),
              let cg = small.cgImage else { return false }
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        for p in 0..<(w * h) where buf[p * 4 + 3] < 250 { return true }
        return false
    }

    /// '배경 빼기' 미리보기 — 원본이 이미 투명이면 즉시, 아니면 Vision 으로 한 번 만들어 캐시.
    private func showTransparentPreview(_ item: GalleryItem, base: UIImage) async {
        if bgCutout == nil, !hasTransparency(base) {
            isRemovingBackground = true
            defer { isRemovingBackground = false }
            let cut = await ImageProcessing.bestEffortTransparent(base)
            guard cut !== base else {
                withAnimation { toastText = String(localized: "배경을 빼지 못했어요") }
                hideToastAfter(1.6)
                return
            }
            bgCutout = cut
            if let f1 = CharacterImageStore.loadGalleryFrame1(id: item.id) {
                let cutF1 = await ImageProcessing.bestEffortTransparent(f1)
                bgCutoutF1 = cutF1 !== f1 ? cutF1 : nil
            }
        }
        withAnimation { bgPreview = .transparent }
    }

    /// 미리보기 상태(빼기/있기)를 갤러리 파일에 저장.
    /// 연속(2장) 항목은 두 장 모두 같은 배경으로 교체 — 애니메이션 어긋남 방지.
    /// 지금 어딘가에 적용 중이면 그 자리(활성 슬롯)와 워치에도 반영.
    private func saveBackgroundChoice(_ item: GalleryItem) async {
        guard let img = CharacterImageStore.loadGalleryImage(id: item.id) else { return }
        let f1 = CharacterImageStore.loadGalleryFrame1(id: item.id)
        let newImg = detailDisplay(img, cutout: bgCutout)
        let newF1 = f1.map { detailDisplay($0, cutout: bgCutoutF1) }

        CharacterImageStore.replaceGalleryImage(item.id, with: newImg)
        // 픽셀만 바뀐 교체는 reconcile diff 로 감지 안 됨 — 서버 백업 강제 갱신.
        GallerySyncManager.shared.forceUpload(item.id)
        if let newF1 {
            CharacterImageStore.replaceGalleryImage(item.id, with: newF1, frame: 1)
        }
        // 지금 적용 중인 자리에도 새 그림 반영
        let activeStates = CharacterImageStore.statesUsingGalleryItem(item.id)
        for state in activeStates {
            CharacterImageStore.applyGalleryItem(item.id, to: state)
            ConnectivityManager.shared.sendCharacterImage(newImg, for: state, frame: 0)
            if let newF1 {
                ConnectivityManager.shared.sendCharacterImage(newF1, for: state, frame: 1)
            }
        }
        if !activeStates.isEmpty {
            WidgetCenter.shared.reloadAllTimelines()
        }
        bgPreview = nil
        bgCutout = nil
        bgCutoutF1 = nil
        frameSwapTick += 1   // 상세 시트 이미지 재로드
        onChange()
        withAnimation { toastText = String(localized: "저장했어요") }
        hideToastAfter(1.6)
    }

    /// 이미 만든 캐릭터 다듬기 — 갤러리 이미지를 참고로 한 번 더 생성.
    /// 성공하면 바로 반영하지 않고 전/후 비교 시트(refineCompare)로 — 선택 시에만 원본 교체.
    /// kind=refine → 서버가 '계정 무료 1회' 를 소진하지 않음 (무료는 처음 만드는 화면 전용).
    private func refineItem(_ item: GalleryItem) async {
        let cost = GenerationQuota.cost(forQuality: "low")
        guard GenerationQuota.canGenerate(cost) else {
            withAnimation { toastText = String(localized: "캔디가 부족해요. 설정에서 충전할 수 있어요.") }
            hideToastAfter(2.0)
            return
        }
        // 이어서 다듬기면 현재 선택 버전을, 아니면 갤러리 원본을 기준으로.
        let base: UIImage
        if let ctx = refineCompare, ctx.itemId == item.id {
            base = ctx.current
        } else if let orig = CharacterImageStore.loadGalleryImage(id: item.id) {
            base = orig
        } else { return }
        guard let refB64 = base.pngData()?.base64EncodedString() else { return }
        let trimmed = refineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isRefining = true
        defer { isRefining = false }

        let prompt = "Use the reference image as the SAME character. Keep the EXACT same character — identity, face and expression style, body proportions, art style, colors and shading, line thickness, and every design detail. Change ONLY: \(trimmed). Transparent background — only the character, no shadows."
        let req = GenerateImageRequest(prompt: prompt, referenceImageBase64: refB64,
                                       steps: 30, width: 1024, height: 1024,
                                       quality: "low", artStyle: nil, style: "auto",
                                       kind: "refine", model: "gpt-image-2",
                                       userInput: trimmed, inputField: "다듬기")
        do {
            // 갤러리 다듬기 — 원본 캐릭터(batchId)의 수정 체인에 이어붙인다.
            let resp = try await APIClient.shared.generateImage(req, sessionId: item.batchId, state: item.sourceState)
            guard let data = Data(base64Encoded: resp.imageBase64),
                  let raw = UIImage(data: data) else {
                withAnimation { toastText = String(localized: "이미지를 받지 못했어요") }
                hideToastAfter(1.6)
                return
            }
            // gpt-image-2 마젠타 배경 → 크로마키 투명화
            let img = await ImageProcessing.transparentized(raw)
            let small = img.preparingThumbnail(of: CGSize(width: 128, height: 128)) ?? img
            if let ent = resp.entitlement { AuthManager.shared.applyEntitlement(ent) }
            GenerationQuota.record(cost)
            refineText = ""
            if selectedItem == nil {
                // 다듬는 중에 상세 시트를 닫아버린 경우 — 비교 시트를 띄울 곳이 없음.
                // 캔디 쓴 결과 유실 방지: 예전처럼 갤러리에 새 항목으로 저장.
                if let state = CharacterState(rawValue: item.sourceState) {
                    CharacterImageStore.save(small, for: state, frame: 0, applyToActiveSlot: false,
                                             batchId: item.batchId, prompt: prompt)
                    onChange()
                    withAnimation { toastText = String(localized: "다듬은 캐릭터를 갤러리에 저장했어요") }
                    hideToastAfter(2.0)
                }
            } else {
                // 바로 반영하지 않고 버전 이력에 이어붙임 — 선택 전까지 갤러리 원본을 덮어쓰지 않음.
                if var ctx = refineCompare, ctx.itemId == item.id {
                    ctx.versions.append(small)
                    if ctx.versions.count > 8 { ctx.versions.remove(at: 1) }   // 원본[0] 보존
                    ctx.selected = ctx.versions.count - 1
                    refineCompare = ctx
                } else {
                    let orig = CharacterImageStore.loadGalleryImage(id: item.id) ?? base
                    refineCompare = RefineCompareContext(itemId: item.id, versions: [orig, small], selected: 1)
                }
                if let ctx = refineCompare {
                    GalleryRefineHistoryStore.save(itemId: item.id, versions: ctx.versions, selected: ctx.selected)
                    hasStoredRefineHistory = true
                }
            }
        } catch {
            withAnimation { toastText = error.koreanizedDescription }
            hideToastAfter(2.5)
        }
    }

    // MARK: 다듬기 이력 (버전 스트립)

    /// 다듬기 이력 시트 — 원본/다듬음 N 스트립에서 골라 큰 미리보기 + 이어서 다듬기 + 적용/취소.
    /// (닫아도 이력은 저장돼 다시 열 수 있음. '취소'만 이력을 버림.)
    private func refineCompareSheet(_ ctx: RefineCompareContext) -> some View {
        let item = items.first { $0.id == ctx.itemId }
        return NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial)
                        Image(uiImage: ctx.current).resizable().scaledToFit().padding(12)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .padding(.horizontal)

                    // 버전 스트립 — 탭해서 고른 버전이 적용 대상.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(ctx.versions.enumerated()), id: \.offset) { idx, img in
                                VStack(spacing: 4) {
                                    Image(uiImage: img).resizable().scaledToFit()
                                        .frame(width: 68, height: 68)
                                        .background(Color(.systemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(idx == ctx.selected ? Color.withuCTAGreen : .clear,
                                                              lineWidth: 2.5)
                                        }
                                    Text(idx == 0 ? String(localized: "원본") : String(localized: "다듬음 \(idx)"))
                                        .font(.caption2.weight(idx == ctx.selected ? .semibold : .regular))
                                        .foregroundStyle(idx == ctx.selected ? Color.withuCTAGreen : .secondary)
                                }
                                .onTapGesture { selectRefineVersion(idx) }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // 이어서 다듬기 — 고른 버전을 기준으로 한 번 더.
                    if let item {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("바꾸고 싶은 점 (예: 모자를 씌워줘)", text: $refineText, axis: .vertical)
                                .font(.callout)
                            Button {
                                Task { await refineItem(item) }
                            } label: {
                                if isRefining {
                                    HStack { ProgressView(); Text("다듬는 중…") }.frame(maxWidth: .infinity)
                                } else {
                                    HStack {
                                        Text("이어서 다듬기").frame(maxWidth: .infinity)
                                        candyBadge(GenerationQuota.cost(forQuality: "low"))
                                    }
                                }
                            }
                            .buttonStyle(.bordered).tint(.withuCTAGreen)
                            .disabled(isRefining || refineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(14)
                        .frostedCard()
                        .padding(.horizontal)
                    }

                    HStack {
                        Button("적용") { adoptRefined(ctx) }
                            .font(.callout.weight(.semibold))
                            .tint(Color.withuCTAGreen)
                        Spacer()
                        Button("취소") {   // 이력 버리고 원본 유지
                            GalleryRefineHistoryStore.clear(itemId: ctx.itemId)
                            hasStoredRefineHistory = false
                            refineCompare = nil
                        }
                        .font(.callout)
                        .tint(.secondary)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("다듬기 이력")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 닫아도 이력은 남음(저장됨) — 다시 열 수 있음. 취소만 버림.
                ToolbarItem(placement: .topBarTrailing) { Button("닫기") { refineCompare = nil } }
            }
        }
        .presentationDetents([.large])
    }

    /// 스트립에서 버전 선택 — 큰 미리보기·적용 대상 변경 + 저장.
    private func selectRefineVersion(_ idx: Int) {
        guard var ctx = refineCompare, ctx.versions.indices.contains(idx) else { return }
        ctx.selected = idx
        refineCompare = ctx
        GalleryRefineHistoryStore.save(itemId: ctx.itemId, versions: ctx.versions, selected: idx)
    }

    /// 저장된 다듬기 이력 다시 열기 — 나갔다 와도 이어서 고를 수 있게.
    private func restoreRefineHistory(_ item: GalleryItem) {
        guard let restored = GalleryRefineHistoryStore.load(itemId: item.id) else {
            hasStoredRefineHistory = false
            return
        }
        refineCompare = RefineCompareContext(itemId: item.id,
                                             versions: restored.versions, selected: restored.selected)
    }

    /// '다듬은 걸로 바꾸기' — 이때 처음으로 갤러리 원본을 교체.
    /// 적용 중인 자리(활성 슬롯)가 있으면 그 자리와 워치·위젯에도 반영.
    private func adoptRefined(_ ctx: RefineCompareContext) {
        // 원본([0])을 고른 상태로 '적용'하면 바꿀 게 없음 — 이력만 정리하고 닫음.
        guard ctx.selected != 0 else {
            GalleryRefineHistoryStore.clear(itemId: ctx.itemId)
            hasStoredRefineHistory = false
            refineCompare = nil
            return
        }
        guard CharacterImageStore.replaceGalleryImage(ctx.itemId, with: ctx.current) else {
            refineCompare = nil
            withAnimation { toastText = String(localized: "적용하지 못했어요") }
            hideToastAfter(1.6)
            return
        }
        GalleryRefineHistoryStore.clear(itemId: ctx.itemId)
        hasStoredRefineHistory = false
        // 픽셀만 바뀐 교체는 reconcile diff 로 감지 안 됨 — 서버 백업 강제 갱신.
        GallerySyncManager.shared.forceUpload(ctx.itemId)
        let activeStates = CharacterImageStore.statesUsingGalleryItem(ctx.itemId)
        for state in activeStates {
            CharacterImageStore.applyGalleryItem(ctx.itemId, to: state)
            ConnectivityManager.shared.sendCharacterImage(ctx.current, for: state, frame: 0)
            if let f1 = CharacterImageStore.loadGalleryFrame1(id: ctx.itemId) {
                ConnectivityManager.shared.sendCharacterImage(f1, for: state, frame: 1)
            }
        }
        if !activeStates.isEmpty {
            WidgetCenter.shared.reloadAllTimelines()
        }
        refineCompare = nil
        selectedItem = nil   // 상세 시트도 닫기 — 그리드에서 바뀐 썸네일이 보이게
        frameSwapTick += 1
        onChange()
        withAnimation { toastText = String(localized: "다듬은 캐릭터로 바꿨어요") }
        hideToastAfter(1.6)
    }

    // MARK: 움직이는 캐릭터 만들기

    /// 움직임 프레임(frame 1) 만들기 — 이 항목 이미지를 참고로 2번째 장면을 생성해 부착.
    /// kind=refine → 계정 무료 1회 미소진. 적용 중인 자리면 활성 슬롯 frame 1 도 갱신.
    private func makeMotionFrame(_ item: GalleryItem) async {
        let cost = GenerationQuota.cost(forQuality: "low")
        guard GenerationQuota.canGenerate(cost) else {
            withAnimation { toastText = String(localized: "캔디가 부족해요. 설정에서 충전할 수 있어요.") }
            hideToastAfter(2.0)
            return
        }
        guard let base = CharacterImageStore.loadGalleryImage(id: item.id),
              let refB64 = base.pngData()?.base64EncodedString() else { return }
        isMakingMotion = true
        defer { isMakingMotion = false }

        // 상태별 frame 2 변화 힌트 — 옛(legacy) 상태면 idle 의 미세 변화 힌트로 fallback.
        let hintState = CharacterState(rawValue: item.sourceState) ?? .idle
        let prompt = "Use the reference image as the SAME character. Keep identical: face, outfit, colors, art/pixel style, line thickness, body proportions, size, scale, centered position, and framing. This is the SECOND frame of a 2-frame animation loop, so the POSE MUST visibly CHANGE from the reference. Change the pose to: \(hintState.animationFrame2Hint). Change ONLY the pose — keep every design detail and the placement identical to the reference. Transparent background — only the character, no shadows."
        let req = GenerateImageRequest(prompt: prompt, referenceImageBase64: refB64,
                                       steps: 30, width: 1024, height: 1024,
                                       quality: "low", artStyle: nil, style: "auto",
                                       kind: "refine", model: "gpt-image-2",
                                       userInput: nil, inputField: "움직임 프레임")
        do {
            let resp = try await APIClient.shared.generateImage(req, sessionId: nil, state: item.sourceState)
            guard let data = Data(base64Encoded: resp.imageBase64),
                  let raw = UIImage(data: data) else {
                withAnimation { toastText = String(localized: "이미지를 받지 못했어요") }
                hideToastAfter(1.6)
                return
            }
            // 크로마키 투명화 → 1번째 프레임과 크기·위치 정규화 → 다운샘플 → 색 맞춤
            let img = await ImageProcessing.transparentized(raw)
            let matched = await ImageProcessing.matchedToReference(img, reference: base)
            var small = matched.preparingThumbnail(of: CGSize(width: 128, height: 128)) ?? matched
            if let refSmall = base.preparingThumbnail(of: CGSize(width: 128, height: 128)) {
                small = ImageProcessing.colorMatched(small, reference: refSmall)
            }
            guard CharacterImageStore.attachGalleryFrame1(item.id, image: small) else {
                withAnimation { toastText = String(localized: "적용하지 못했어요") }
                hideToastAfter(1.6)
                return
            }
            // 적용 중이던 자리면 활성 슬롯 frame 1 + 워치 + 위젯도 갱신
            let activeStates = CharacterImageStore.statesUsingGalleryItem(item.id)
            for state in activeStates {
                CharacterImageStore.applyGalleryItem(item.id, to: state)
                ConnectivityManager.shared.sendCharacterImage(small, for: state, frame: 1)
            }
            if !activeStates.isEmpty {
                WidgetCenter.shared.reloadAllTimelines()
            }
            if let ent = resp.entitlement { AuthManager.shared.applyEntitlement(ent) }
            GenerationQuota.record(cost)
            selectedItem = nil   // 시트 닫기 — 그리드에 '연속' 배지가 보이게
            onChange()
            withAnimation { toastText = String(localized: "이제 움직이는 캐릭터예요") }
            hideToastAfter(2.0)
        } catch {
            withAnimation { toastText = error.koreanizedDescription }
            hideToastAfter(2.5)
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
        withAnimation { toastText = String(localized: "\(count)개를 지웠어요") }
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

/// 갤러리 항목별 '다듬기 이력'(버전 체인)을 App Group 에 보관 — 상세를 나갔다 와도 복원.
/// 갤러리 원본은 하나뿐이라 각 버전 이미지를 직접 PNG 로 저장한다. count>1(다듬은 게 있음)일 때만 의미.
fileprivate enum GalleryRefineHistoryStore {
    private static func dir(_ itemId: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedAppState.groupID)?
            .appendingPathComponent("gallery_refine/\(itemId)", isDirectory: true)
    }

    static func save(itemId: String, versions: [UIImage], selected: Int) {
        guard let dir = dir(itemId), versions.count > 1 else { return }
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (i, img) in versions.enumerated() {
            try? img.pngData()?.write(to: dir.appendingPathComponent("\(i).png"),
                                      options: [.atomic, .noFileProtection])
        }
        let meta = ["selected": selected, "count": versions.count]
        try? JSONEncoder().encode(meta).write(to: dir.appendingPathComponent("meta.json"),
                                              options: [.atomic, .noFileProtection])
    }

    static func clear(itemId: String) {
        guard let dir = dir(itemId) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    static func exists(itemId: String) -> Bool {
        guard let dir = dir(itemId) else { return false }
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("meta.json").path)
    }

    static func load(itemId: String) -> (versions: [UIImage], selected: Int)? {
        guard let dir = dir(itemId),
              let data = try? Data(contentsOf: dir.appendingPathComponent("meta.json")),
              let meta = try? JSONDecoder().decode([String: Int].self, from: data),
              let count = meta["count"], count > 1 else { return nil }
        var versions: [UIImage] = []
        for i in 0..<count {
            guard let img = UIImage(contentsOfFile: dir.appendingPathComponent("\(i).png").path) else { return nil }
            versions.append(img)
        }
        return (versions, Swift.min(Swift.max(0, meta["selected"] ?? 0), versions.count - 1))
    }
}
