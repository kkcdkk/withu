//
//  BatchCharacterGenView.swift
//  withu
//
//  여러 상태를 한 번에 생성. "캐릭터 정체성" (공통) + state 별 hint 조합.
//  참고 이미지 첨부 가능. 첫 결과 미리보기 후 계속 결정 옵션.
//

import SwiftUI
import PhotosUI
import Photos
import WidgetKit

struct BatchCharacterGenView: View {
    // MARK: - Input

    @State private var baseIdentity: String = {
        let p = CharacterProfileStore.load().aiPrompt
        return p.isEmpty ? "round chibi mascot character with simple features and friendly closed-eye smile" : p
    }()

    @State private var stateHints: [CharacterState: String] = Dictionary(
        uniqueKeysWithValues: CharacterState.userFacing.map { ($0, $0.generationHint) }
    )

    @State private var selectedStates: Set<CharacterState> = Set(CharacterState.userFacing)

    @State private var quality: String = "low"
    @State private var artStyle: String = "casual"
    /// 켜져 있으면 state 당 frame 0 + frame 1 두 장 생성 → 메인 화면이 swap 애니메이션
    @State private var generateAnimated: Bool = false
    /// frame 2 변화 힌트 (영어, 전체 state 공통). 비우면 각 state 의 animationFrame2Hint 자동 사용.
    @State private var animationHintOverride: String = ""
    /// Vision 처리된 transparent 버전 캐시 (per-state).
    /// bulk "투명 모두 적용" 또는 detail sheet per-state 토글로 채워짐.
    @State private var transparentResults: [CharacterState: UIImage] = [:]
    @State private var transparentResultsFrame1: [CharacterState: UIImage] = [:]
    /// 표시 모드 (per-state). true 면 transparent (있을 때), false 면 raw.
    @State private var displayTransparentByState: [CharacterState: Bool] = [:]
    @State private var isProcessingTransparentBulk: Bool = false

    /// 전체 참고 이미지 (state 별 reference 가 없을 때의 fallback)
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var referenceImage: UIImage?

    /// state 별 개별 참고 이미지. 있으면 전체 reference 보다 우선.
    @State private var stateReferenceImages: [CharacterState: UIImage] = [:]
    @State private var stateReferencePickerItems: [CharacterState: PhotosPickerItem] = [:]

    // MARK: - Progress

    @State private var isGenerating: Bool = false
    /// 현재 진행 중인 state 들 (병렬이라 여러 개 동시 가능)
    @State private var inProgressStates: Set<CharacterState> = []
    @State private var stateStartedAt: [CharacterState: Date] = [:]

    @State private var results: [CharacterState: UIImage] = [:]
    /// 연속 이미지 ON 일 때 state 의 frame 1 결과. 카드에 우하단 미니 썸네일로 표시.
    @State private var resultsFrame1: [CharacterState: UIImage] = [:]
    @State private var errors: [CharacterState: String] = [:]

    @State private var showFinishedAlert: Bool = false
    /// 배치 생성 Task — 중단 버튼이 cancel() 호출
    @State private var batchTask: Task<Void, Never>?

    // 결과 사진 클릭 시 sheet
    @State private var selectedResult: (state: CharacterState, image: UIImage)?
    @State private var revisionText: String = ""
    @State private var isRevising: Bool = false
    @State private var revisionRefItem: PhotosPickerItem?
    @State private var revisionRefImage: UIImage?

    // 사진 앱 저장 상태
    @State private var isSavingPhotos: Bool = false
    @State private var saveResultMessage: String?
    @State private var showSaveResultAlert: Bool = false

    // 오늘 남은 생성 횟수 (App Group quota)
    @State private var remainingGenerations: Int = GenerationQuota.remainingToday()
    @State private var showPaywall: Bool = false
    /// 이번 일괄 세션 식별자 — 서버가 같은 세션의 장을 무료(free_batch)로 묶음.
    @State private var batchSessionId: String = UUID().uuidString

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundGradient(for: .idle).ignoresSafeArea()
            Form {
                identitySection
                stateListSection
                referenceSection
                optionsSection
                startSection
                if !results.isEmpty || !errors.isEmpty {
                    resultsSection
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("여러 모습 만들기")
        .scrollDismissesKeyboard(.interactively)
        .onAppear { remainingGenerations = GenerationQuota.remainingToday() }
        .sheet(isPresented: $showPaywall) {
            PaywallView(onClose: {
                showPaywall = false
                remainingGenerations = GenerationQuota.remainingToday()
            })
        }
        .alert("다 만들었어요", isPresented: $showFinishedAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("\(results.count)개 완성, \(errors.count)개 못 만들었어요. 잘 만들어진 모습은 바로 적용됐어요.")
        }
        .alert("사진 저장", isPresented: $showSaveResultAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(saveResultMessage ?? "")
        }
        .onChange(of: photoPickerItem) { _, item in
            Task { await loadReference(item) }
        }
        .sheet(item: Binding(
            get: { selectedResult.map { ResultSelection(state: $0.state, image: $0.image) } },
            set: { _ in selectedResult = nil }
        )) { sel in
            resultDetailSheet(state: sel.state, image: sel.image)
        }
    }

    /// sheet 의 item 으로 쓸 wrapper (Identifiable 필요)
    private struct ResultSelection: Identifiable {
        let state: CharacterState
        let image: UIImage
        var id: String { state.rawValue }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section {
            TextEditor(text: $baseIdentity)
                .frame(minHeight: 80)
                .font(.callout)
                .disabled(isGenerating)
        } header: {
            Text("우리 캐릭터의 모습")
        } footer: {
            Text("모든 모습에 이 설명이 함께 쓰여요. 캐릭터의 생김새와 성격을 한 번에 정해 주세요.\n예: \"주근깨 많은 분홍 토끼, 큰 머리에 작은 몸\"")
                .foregroundStyle(.secondary)
        }
    }

    private var stateListSection: some View {
        Section {
            ForEach(CharacterState.userFacing, id: \.self) { state in
                stateRow(state)
            }
            HStack {
                Button("모두 켜기") { selectedStates = Set(CharacterState.userFacing) }
                Spacer()
                Button("모두 끄기", role: .destructive) { selectedStates = [] }
            }
            .disabled(isGenerating)
        } header: {
            Text("만들고 싶은 순간 (\(selectedStates.count)개)")
        } footer: {
            let count = selectedStates.count
            let cost = costPer(quality: quality) * Double(count)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)개의 순간을 만들어요")
                Text("드는 비용은 약 \(Int(cost * 1380))원이에요 (한 장당 약 \(Int(costPer(quality: quality) * 1380))원)")
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func stateRow(_ state: CharacterState) -> some View {
        DisclosureGroup {
            TextEditor(text: Binding(
                get: { stateHints[state] ?? state.generationHint },
                set: { stateHints[state] = $0 }
            ))
            .frame(minHeight: 60)
            .font(.footnote)
            .disabled(isGenerating)

            // state 별 참고 이미지 (있으면 전체 reference 보다 우선)
            stateReferencePicker(state)

            Button("기본값으로 되돌리기") {
                stateHints[state] = state.generationHint
            }
            .font(.footnote)
            .disabled(isGenerating)
        } label: {
            HStack {
                Toggle("", isOn: Binding(
                    get: { selectedStates.contains(state) },
                    set: { on in
                        if on { selectedStates.insert(state) } else { selectedStates.remove(state) }
                    }
                ))
                .labelsHidden()
                .disabled(isGenerating)

                Text(state.koreanShortLabel)
                    .strikethrough(!selectedStates.contains(state))
                Spacer()
                resultBadge(state)
            }
        }
    }

    /// state 별 참고 이미지 선택기. 작은 thumbnail + Picker / 제거 버튼.
    @ViewBuilder
    private func stateReferencePicker(_ state: CharacterState) -> some View {
        HStack(spacing: 10) {
            if let ref = stateReferenceImages[state] {
                Image(uiImage: ref).resizable().scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.secondary.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "photo")
                        .foregroundStyle(.secondary).font(.caption))
            }
            VStack(alignment: .leading, spacing: 2) {
                PhotosPicker(
                    stateReferenceImages[state] == nil ? "이 순간에 쓸 사진 넣기" : "변경",
                    selection: Binding(
                        get: { stateReferencePickerItems[state] },
                        set: { item in
                            if let item {
                                stateReferencePickerItems[state] = item
                                Task { await loadStateReference(state, item: item) }
                            } else {
                                stateReferencePickerItems.removeValue(forKey: state)
                                stateReferenceImages.removeValue(forKey: state)
                            }
                        }
                    ),
                    matching: .images
                )
                .font(.footnote)
                .disabled(isGenerating)

                if stateReferenceImages[state] != nil {
                    Button("이 순간 사진 빼기", role: .destructive) {
                        stateReferenceImages.removeValue(forKey: state)
                        stateReferencePickerItems.removeValue(forKey: state)
                    }
                    .font(.caption2)
                    .disabled(isGenerating)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func resultBadge(_ state: CharacterState) -> some View {
        if inProgressStates.contains(state), let started = stateStartedAt[state] {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let elapsed = Int(ctx.date.timeIntervalSince(started))
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.7)
                    Text("\(elapsed)초").font(.caption2)
                }
            }
        } else if results[state] != nil {
            Image(systemName: "checkmark").foregroundStyle(.secondary)
        } else if errors[state] != nil {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var referenceSection: some View {
        Section {
            HStack(spacing: 12) {
                if let ref = referenceImage {
                    Image(uiImage: ref).resizable().scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.secondary.opacity(0.15))
                        .frame(width: 64, height: 64)
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                }
                VStack(alignment: .leading) {
                    PhotosPicker(referenceImage == nil ? "사진 선택" : "다른 사진으로 변경",
                                 selection: $photoPickerItem,
                                 matching: .images)
                        .disabled(isGenerating)
                    if referenceImage != nil {
                        Button("사진 빼기", role: .destructive) {
                            referenceImage = nil
                            photoPickerItem = nil
                        }
                        .disabled(isGenerating)
                    }
                }
            }
        } header: {
            Text("이미 있는 캐릭터 사진 (선택)")
        } footer: {
            Text("사진을 넣으면 그 캐릭터의 여러 모습으로 만들어 줘요. 비워두면 위에 적은 설명만으로 새로 그려요.")
                .foregroundStyle(.secondary)
        }
    }

    private var optionsSection: some View {
        Section {
            Picker("그림 스타일", selection: $artStyle) {
                Text("Soft").tag("casual")
                Text("Pixel").tag("pixel")
            }
            .pickerStyle(.segmented).disabled(isGenerating)

            Picker("선명함", selection: $quality) {
                Text("빠르게 (약 20초 · 15원)").tag("low")
                Text("보통 (약 50초 · 55원)").tag("medium")
                Text("선명하게 (1~2분 · 230원)").tag("high")
            }
            .pickerStyle(.menu).disabled(isGenerating)

            Toggle("움직이는 캐릭터 만들기 (한 모습당 2장)", isOn: $generateAnimated)
                .disabled(isGenerating)
            if generateAnimated {
                VStack(alignment: .leading, spacing: 4) {
                    Text("두 번째 장면은 어떻게 바뀌면 좋을까요 (모든 모습에 함께 쓰여요)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $animationHintOverride)
                        .frame(minHeight: 60)
                        .font(.callout)
                        .disabled(isGenerating)
                    Text("비워두면 각 모습에 어울리게 알아서 움직여요 (걷기는 다른 발을 앞으로, 자기는 숨 쉬듯이).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("분위기 정하기")
        } footer: {
            Text("움직이는 캐릭터를 켜면 한 모습마다 두 장을 만들어 메인 화면에서 살아 움직여요. 그만큼 비용은 두 배예요.")
                .foregroundStyle(.secondary)
        }
    }

    private var startSection: some View {
        Section {
            Button {
                batchTask = Task { await startBatch() }
            } label: {
                if isGenerating {
                    HStack {
                        ProgressView()
                        Text("만드는 중… \(results.count + errors.count)/\(selectedStates.count)")
                    }
                } else {
                    Label("만들기 시작", systemImage: "wand.and.stars")
                        .font(.callout.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.withuPink)
            .disabled(isGenerating || selectedStates.isEmpty
                      || baseIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || remainingGenerations < selectedStates.count)

            if isGenerating {
                Text("만드는 동안엔 앱을 그대로 켜둬 주세요. 지금 \(inProgressStates.count)개를 만들고 있어요.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button(role: .destructive) {
                    batchTask?.cancel()
                    batchTask = nil
                } label: {
                    Label("그만두기", systemImage: "stop.circle.fill")
                }
                .tint(.secondary)
            } else if remainingGenerations < selectedStates.count {
                Text("오늘 남은 \(remainingGenerations)회로는 \(selectedStates.count)개를 한 번에 만들 수 없어요. 만들 순간을 줄이거나 더 충전해 주세요.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button {
                    showPaywall = true
                } label: {
                    Label("더 만들기 (구독·충전)", systemImage: "sparkles")
                }
                .tint(.withuPink)
            } else {
                Text("오늘 \(remainingGenerations)번 더 만들 수 있어요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var resultsSection: some View {
        Section("만들어진 모습") {
            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(CharacterState.allCases, id: \.self) { state in
                    if let img = displayedImage(for: state) {
                        resultCard(state: state, image: img)
                    } else if let err = errors[state] {
                        errorCard(state: state, error: err)
                    }
                }
            }

            if !results.isEmpty {
                // 투명 처리 bulk 토글 — gallery 원본은 raw 유지, active slot 만 갱신.
                HStack(spacing: 12) {
                    Button {
                        Task { await applyTransparentToAll() }
                    } label: {
                        if isProcessingTransparentBulk {
                            HStack { ProgressView(); Text("다듬는 중…") }
                        } else {
                            Label("배경 모두 지우기", systemImage: "wand.and.sparkles")
                        }
                    }
                    .tint(.secondary)
                    .disabled(isProcessingTransparentBulk)
                    Button(role: .destructive) {
                        Task { await restoreOriginalToAll() }
                    } label: {
                        Label("처음 그림으로", systemImage: "arrow.uturn.backward")
                    }
                    .tint(.secondary)
                    .disabled(isProcessingTransparentBulk)
                }
                .font(.callout)

                Button {
                    Task { await saveAllToPhotos() }
                } label: {
                    if isSavingPhotos {
                        HStack {
                            ProgressView()
                            Text("저장하는 중…")
                        }
                    } else {
                        Label("사진 앱에 모두 저장 (\(results.count)장)",
                              systemImage: "square.and.arrow.down")
                    }
                }
                .tint(.secondary)
                .disabled(isSavingPhotos)
            }
        }
    }

    /// per-state 현재 표시 이미지 — toggle 따라 raw 또는 transparent.
    private func displayedImage(for state: CharacterState) -> UIImage? {
        let useTransparent = displayTransparentByState[state] ?? false
        if useTransparent, let t = transparentResults[state] { return t }
        return results[state]
    }

    /// bulk — 모든 state 의 raw 를 Vision 처리, active slot 에 적용 + 워치 push.
    /// gallery 항목은 raw 유지 (원본 보존).
    @MainActor
    private func applyTransparentToAll() async {
        isProcessingTransparentBulk = true
        defer { isProcessingTransparentBulk = false }
        for state in CharacterState.allCases {
            guard let raw = results[state] else { continue }
            let transparent: UIImage
            if let cached = transparentResults[state] {
                transparent = cached
            } else {
                transparent = await ImageProcessing.bestEffortTransparent(raw)
                transparentResults[state] = transparent
            }
            CharacterImageStore.saveActiveSlotOnly(transparent, for: state, frame: 0)
            ConnectivityManager.shared.sendCharacterImage(transparent, for: state, frame: 0)
            // frame 1 도 있으면 같이
            if let rawF1 = resultsFrame1[state] {
                let tF1: UIImage
                if let cachedF1 = transparentResultsFrame1[state] {
                    tF1 = cachedF1
                } else {
                    tF1 = await ImageProcessing.bestEffortTransparent(rawF1)
                    transparentResultsFrame1[state] = tF1
                }
                CharacterImageStore.saveActiveSlotOnly(tF1, for: state, frame: 1)
                ConnectivityManager.shared.sendCharacterImage(tF1, for: state, frame: 1)
            }
            displayTransparentByState[state] = true
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// bulk — raw 로 active slot 복원.
    @MainActor
    private func restoreOriginalToAll() async {
        for state in CharacterState.allCases {
            guard let raw = results[state] else { continue }
            CharacterImageStore.saveActiveSlotOnly(raw, for: state, frame: 0)
            ConnectivityManager.shared.sendCharacterImage(raw, for: state, frame: 0)
            if let rawF1 = resultsFrame1[state] {
                CharacterImageStore.saveActiveSlotOnly(rawF1, for: state, frame: 1)
                ConnectivityManager.shared.sendCharacterImage(rawF1, for: state, frame: 1)
            }
            displayTransparentByState[state] = false
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func resultCard(state: CharacterState, image: UIImage) -> some View {
        Button {
            selectedResult = (state, image)
            revisionText = ""
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: image).resizable().scaledToFit().frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    // 연속 이미지 ON 일 때 frame 1 우하단 미니. 메인 화면이 0.7s 간격으로 swap.
                    if let f1 = resultsFrame1[state] {
                        Image(uiImage: f1)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white, lineWidth: 2)
                            )
                            .padding(6)
                    }
                }
                HStack {
                    Text(state.koreanShortLabel).font(.caption).lineLimit(1)
                    Spacer()
                    Image(systemName: "checkmark").foregroundStyle(.secondary).font(.caption)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func errorCard(state: CharacterState, error: String) -> some View {
        Button {
            Task { await retryOne(state) }
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 12).fill(.orange.opacity(0.12)).frame(height: 120)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .foregroundStyle(.orange).font(.title)
                            Text("눌러서 다시 만들기")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                    )
                HStack {
                    Text(state.koreanShortLabel).font(.caption).lineLimit(1)
                    Spacer()
                }
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .disabled(inProgressStates.contains(state))
    }

    // MARK: - Actions

    /// state 의 reference base64 결정. state 별 > 공통 > nil.
    /// startBatch / retryOne 양쪽에서 사용.
    private func resolveReference(for state: CharacterState) -> String? {
        if let img = stateReferenceImages[state],
           let data = img.pngData() {
            return data.base64EncodedString()
        }
        return referenceImage?.pngData()?.base64EncodedString()
    }

    /// 동시 호출 개수. 1 = 순차 (가장 안정적). 연속 이미지 ON 시도 한 번에 한 호출.
    private static let maxConcurrent: Int = 1

    /// 전체 병렬 시작 — TaskGroup 풀 패턴으로 maxConcurrent 개만 동시 진행.
    private func startBatch() async {
        isGenerating = true
        batchSessionId = UUID().uuidString   // 새 일괄 세션 — 서버가 free_batch 로 묶음
        results.removeAll()
        resultsFrame1.removeAll()
        errors.removeAll()
        inProgressStates.removeAll()
        stateStartedAt.removeAll()

        defer {
            isGenerating = false
            inProgressStates.removeAll()
            stateStartedAt.removeAll()
            showFinishedAlert = true
            // 성공한 장수만큼 오늘 횟수 차감 (frame 0 + 연속 frame 1)
            GenerationQuota.record(results.count + resultsFrame1.count)
            remainingGenerations = GenerationQuota.remainingToday()
            WidgetCenter.shared.reloadAllTimelines()
            // 결과 종합 알림 — 모두 성공이면 success, 일부 실패면 warning.
            if errors.isEmpty {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }

        // 사전 reachability 체크 — 18+ 호출 실패하면서 시간만 가는 거 방지.
        do {
            try await APIClient.shared.preflightPing()
        } catch {
            errors[.idle] = "서버에 연결할 수 없어요. 네트워크 또는 서버 상태를 확인하고 다시 시도해 주세요."
            return
        }

        let toGen = CharacterState.allCases.filter { selectedStates.contains($0) }
        var iterator = toGen.makeIterator()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<Self.maxConcurrent {
                guard let state = iterator.next() else { break }
                addStateTask(group: &group, state: state)
            }
            while await group.next() != nil {
                guard let state = iterator.next() else { continue }
                addStateTask(group: &group, state: state)
            }
        }
    }

    /// state 하나의 task — frame 0 (+ animated 면 frame 1 도 순차) 실행
    private func addStateTask(group: inout TaskGroup<Void>, state: CharacterState) {
        let refB64 = resolveReference(for: state)
        let animated = generateAnimated
        group.addTask { @MainActor in
            // frame 0
            let ok = await runOne(state, reference: refB64,
                                  consistencyPrefix: refB64 != nil, frame: 0)
            // frame 1 — frame 0 성공 시에만, 그 결과를 reference 로 체이닝
            if ok, animated, let f0 = results[state],
               let f0Ref = f0.pngData()?.base64EncodedString() {
                await runOne(state, reference: f0Ref,
                             consistencyPrefix: true, frame: 1)
            }
        }
    }

    /// 실패한 카드 탭 시 재시도. 같은 prompt + reference 그대로.
    private func retryOne(_ state: CharacterState) async {
        // 이전 에러 표시 제거 + 진행 표시 시작
        errors.removeValue(forKey: state)
        let refB64 = resolveReference(for: state)
        await runOne(state, reference: refB64, consistencyPrefix: refB64 != nil)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 한 state 생성 — 성공 시 true. 결과는 results / errors 에 기록.
    /// frame == 0: 기본. frame == 1: 애니메이션용 (이전 결과를 reference 로 chain + 다른 포즈).
    @discardableResult
    private func runOne(_ state: CharacterState, reference: String?,
                        consistencyPrefix: Bool, frame: Int = 0) async -> Bool {
        inProgressStates.insert(state)
        stateStartedAt[state] = .now
        defer {
            inProgressStates.remove(state)
            stateStartedAt.removeValue(forKey: state)
        }
        let prefix = consistencyPrefix
            ? "Same exact character as the reference image — only the pose/scene differs. "
            : ""
        var prompt = "\(prefix)\(baseIdentity), \(stateHints[state] ?? state.generationHint)"
        if frame == 1 {
            let trimmed = animationHintOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            let hint = trimmed.isEmpty ? state.animationFrame2Hint : trimmed
            prompt += ". Animation frame 2 (for a 2-frame swap loop): \(hint)"
        }
        // AI 에 흰 배경 강제 — 사용자가 post-gen 에 Vision 으로 정제 가능.
        // 격자(체커보드) 방지: "투명"을 격자로 그리는 모델 대비 단색 흰배경 명시.
        prompt += ". Solid clean WHITE background, no shadows, no gradients. Never draw a checkerboard or transparency grid pattern — the background must be one flat solid white color."
        do {
            let req = GenerateImageRequest(
                prompt: prompt,
                referenceImageBase64: reference,
                steps: 30,
                width: 1024,
                height: 1024,
                quality: quality,
                artStyle: artStyle,
                style: "auto"
            )
            let resp = try await APIClient.shared.generateImage(req, kind: "batch", batchId: batchSessionId)
            guard let data = Data(base64Encoded: resp.imageBase64),
                  let img = UIImage(data: data) else {
                errors[state] = "이미지를 받지 못했어요"
                return false
            }
            // raw (white BG) 그대로 저장. Vision 처리는 사용자가 post-gen 에 선택.
            // 128px 다운샘플 — 메인 화면 200 / 워치 64 / 위젯 60 다 커버, 디스크 절약
            let small = img.preparingThumbnail(of: CGSize(width: 128, height: 128)) ?? img
            if frame == 0 {
                results[state] = small
            } else {
                resultsFrame1[state] = small
            }
            CharacterImageStore.save(small, for: state, frame: frame)
            ConnectivityManager.shared.sendCharacterImage(small, for: state, frame: frame)
            if let ent = resp.entitlement { AuthManager.shared.applyEntitlement(ent) }
            return true
        } catch APIError.paymentRequired {
            showPaywall = true
            errors[state] = "무료 횟수를 다 썼어요"
            return false
        } catch {
            errors[state] = error.koreanizedDescription
            return false
        }
    }

    /// 결과 카드 탭 시 열리는 sheet — 큰 이미지 + 저장 / 수정 옵션
    @ViewBuilder
    private func resultDetailSheet(state: CharacterState, image: UIImage) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Text(state.koreanShortLabel)
                        .font(.callout.weight(.semibold))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("어떻게 바꿀까요").font(.caption).foregroundStyle(.secondary)
                        TextField("예: 더 귀엽게, 표정 밝게, 모자 씌워줘", text: $revisionText, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.roundedBorder)
                        HStack(spacing: 10) {
                            if let ref = revisionRefImage {
                                Image(uiImage: ref).resizable().scaledToFill()
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.secondary.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                    .overlay(Image(systemName: "photo")
                                        .foregroundStyle(.secondary).font(.caption))
                            }
                            PhotosPicker(revisionRefImage == nil ? "사진 넣기" : "변경",
                                         selection: $revisionRefItem,
                                         matching: .images)
                                .font(.footnote)
                            if revisionRefImage != nil {
                                Button("제거", role: .destructive) {
                                    revisionRefImage = nil
                                    revisionRefItem = nil
                                }
                                .font(.caption2)
                            }
                            Spacer()
                        }
                    }
                    .padding(.horizontal)
                    .onChange(of: revisionRefItem) { _, item in
                        Task { await loadRevisionRef(item) }
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task { await saveOneToPhotos(image) }
                        } label: {
                            Label("저장", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)

                        Button {
                            Task { await reviseOne(state, text: revisionText) }
                        } label: {
                            if isRevising {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("바꾸기", systemImage: "wand.and.stars")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.withuPink)
                        .disabled(isRevising || revisionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("자세히 보기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { selectedResult = nil }
                }
            }
        }
    }

    /// 단일 이미지를 사진 앱에 저장 (add-only 권한).
    private func saveOneToPhotos(_ image: UIImage) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveResultMessage = "사진 추가 권한이 거부됐어요. 설정 → withu 에서 허용해 주세요."
            showSaveResultAlert = true
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            saveResultMessage = "사진 앱에 저장됐어요."
        } catch {
            saveResultMessage = "저장하지 못했어요. 다시 시도해 주세요."
        }
        showSaveResultAlert = true
    }

    /// 기존 결과 + 자연어 수정 요청으로 재생성.
    /// reference 우선순위: 사용자 첨부 > 기존 결과
    private func reviseOne(_ state: CharacterState, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isRevising = true
        defer { isRevising = false }

        // reference: 사용자가 새로 첨부한 거 우선, 없으면 기존 결과
        let refB64 = revisionRefImage?.pngData()?.base64EncodedString()
            ?? results[state]?.pngData()?.base64EncodedString()
        let basePrompt = "\(baseIdentity), \(stateHints[state] ?? state.generationHint)"
        let modifiedPrompt = "\(basePrompt). User modification: \(trimmed)"

        inProgressStates.insert(state)
        stateStartedAt[state] = .now
        defer {
            inProgressStates.remove(state)
            stateStartedAt.removeValue(forKey: state)
        }
        do {
            let req = GenerateImageRequest(
                prompt: modifiedPrompt,
                referenceImageBase64: refB64,
                steps: 30,
                width: 1024,
                height: 1024,
                quality: quality,
                artStyle: artStyle,
                style: "auto"
            )
            let resp = try await APIClient.shared.generateImage(req)
            if let data = Data(base64Encoded: resp.imageBase64),
               let img = UIImage(data: data) {
                let transparent = await ImageProcessing.bestEffortTransparent(img)
                let small = transparent.preparingThumbnail(of: CGSize(width: 128, height: 128)) ?? transparent
                results[state] = small
                CharacterImageStore.save(small, for: state)
                ConnectivityManager.shared.sendCharacterImage(small, for: state)
                selectedResult = (state, small)
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            errors[state] = error.koreanizedDescription
        }
    }

    /// 수정 sheet 의 참고 이미지 로드
    private func loadRevisionRef(_ item: PhotosPickerItem?) async {
        guard let item else {
            revisionRefImage = nil
            return
        }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                revisionRefImage = img
            }
        } catch {
            // 조용히 무시
        }
    }

    /// state 별 참고 이미지를 PhotosPickerItem 에서 로드해 dict 에 저장.
    private func loadStateReference(_ state: CharacterState, item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                stateReferenceImages[state] = img
            }
        } catch {
            // 조용히 무시 — 사용자가 다시 선택하면 됨
        }
    }

    /// 결과 이미지들을 사진 앱(카메라 롤)에 저장.
    /// add-only 권한 사용 — 라이브러리 읽기 권한 없이 추가만 가능.
    private func saveAllToPhotos() async {
        isSavingPhotos = true
        defer { isSavingPhotos = false }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveResultMessage = "사진 추가 권한이 거부됐어요. 설정 → withu 에서 허용해 주세요."
            showSaveResultAlert = true
            return
        }

        // CharacterState 순서대로 정렬 — 사진 앱에서도 같은 순서로 보임
        let items: [(CharacterState, UIImage)] = CharacterState.allCases.compactMap { s in
            results[s].map { (s, $0) }
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for (_, img) in items {
                    PHAssetChangeRequest.creationRequestForAsset(from: img)
                }
            }
            saveResultMessage = "\(items.count)장 사진 앱에 저장됐어요."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            saveResultMessage = "저장하지 못했어요. 다시 시도해 주세요."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        showSaveResultAlert = true
    }

    private func loadReference(_ item: PhotosPickerItem?) async {
        guard let item else {
            referenceImage = nil
            return
        }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                referenceImage = img
            }
        } catch {
            errors[.idle] = "참고 이미지를 불러올 수 없어요. 다른 사진으로 시도해 주세요."
        }
    }

    private func costPer(quality: String) -> Double {
        switch quality {
        case "low":    return 0.011
        case "medium": return 0.04
        case "high":   return 0.17
        default:       return 0.04
        }
    }
}

#Preview {
    NavigationStack { BatchCharacterGenView() }
}
