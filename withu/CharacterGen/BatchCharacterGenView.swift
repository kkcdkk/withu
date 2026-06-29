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

    /// 내 캐릭터 설명(정체성). 저장된 묘사(aiPrompt)로 시작 — 단건 생성과 공유, 비어 있으면 빈 칸.
    @State private var baseIdentity: String = CharacterProfileStore.load().aiPrompt

    @State private var stateHints: [CharacterState: String] = Dictionary(
        uniqueKeysWithValues: CharacterState.userFacing.map { ($0, $0.generationHint) }
    )

    @State private var selectedStates: Set<CharacterState> = Set(CharacterState.userFacing)

    @State private var quality: String = "low"
    @State private var artStyle: String = "pixel"
    /// 움직임(frame 1) 만들 상태들. 비어 있으면 정적만. 상태별 토글 + '모두 움직임' 으로 관리.
    @State private var animatedStates: Set<CharacterState> = []
    /// frame1 정규화용 — state 별 1번째 프레임 원본(1024, 흰배경).
    @State private var frame0FullRes: [CharacterState: UIImage] = [:]
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
    /// idle 앵커링 — idle 을 먼저 만들어 승인받고, 나머지 상태 생성의 reference 로 사용(일관성).
    @State private var idleAnchor: UIImage?
    /// 앵커 reference 용 원본(1024). results 는 128 썸네일이라 그대로 쓰면 일관성 reference 품질이 떨어짐.
    @State private var idleFullRes: UIImage?
    @State private var awaitingIdleApproval: Bool = false
    /// 승인 화면 — '수정해서 다시' 입력.
    @State private var idleRevisionText: String = ""
    /// 참고사진에서 무엇을 참고할지 (사용자 입력) — 참고사진 쓸 때만 프롬프트에 반영.
    @State private var referenceHint: String = ""

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
    @State private var detailFrame: Int = 0   // 상세 시트에서 보고 있는 프레임(0=기본, 1=움직임)
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
    /// 사진 선택 후 정사각 자르기 시트
    @State private var cropTarget: CropTarget?

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundGradient(for: .idle).ignoresSafeArea()
            Form {
                stateListSection
                identitySection
                referenceSection
                optionsSection
                if !awaitingIdleApproval {
                    startSection
                }
                idleApprovalSection
                if !awaitingIdleApproval && (!results.isEmpty || !errors.isEmpty) {
                    resultsSection
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("여러 모습 만들기")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { candyBadge }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { remainingGenerations = GenerationQuota.remainingToday() }
        .sheet(isPresented: $showPaywall) {
            PaywallView(onClose: {
                showPaywall = false
                remainingGenerations = GenerationQuota.remainingToday()
            })
        }
        .fullScreenCover(item: $cropTarget) { target in
            SquareCropView(image: target.image,
                           onDone: { cropped in target.onDone(cropped); cropTarget = nil },
                           onCancel: { cropTarget = nil })
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
            resultDetailSheet(state: sel.state)
        }
    }

    /// 보유 캔디(충전 크레딧) 배지 — 탭하면 충전(Paywall). 서버 잔액 우선, 없으면 로컬.
    private var candyBadge: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 3) {
                Text("🍬")
                Text("\(AuthManager.shared.entitlement?.credits ?? GenerationQuota.credits())")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .tint(.withuPink)
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
            Text("캐릭터 프롬프트(캐릭터 설명)")
        } footer: {
            Text("모든 모습에 이 설명이 함께 쓰여요. 캐릭터의 생김새와 성격을 한 번에 정해 주세요.\n예: \"주근깨 많은 분홍 토끼, 커다랗고 귀여운 눈\"")
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

            Toggle("움직임 (2장 · 메인에서 움직여요)", isOn: Binding(
                get: { animatedStates.contains(state) },
                set: { on in
                    if on { animatedStates.insert(state) } else { animatedStates.remove(state) }
                }
            ))
            .font(.footnote)
            .disabled(isGenerating)

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
            if referenceImage != nil {
                TextField("이 사진에서 무엇을 참고하나요? (예: 얼굴, 색, 전체 느낌)",
                          text: $referenceHint, axis: .vertical)
                    .font(.callout)
                    .disabled(isGenerating)
            }
        } header: {
            Text("참고 사진 (선택)")
        } footer: {
            Text("사진을 넣으면 그 캐릭터의 여러 모습으로 생성해요. 비워두면 위에 적은 설명만으로 새로 그려요.")
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

            Picker("품질", selection: $quality) {
                Text("low (약 20초 · 15원)").tag("low")
                Text("medium (약 50초 · 55원)").tag("medium")
                Text("high (1~2분 · 230원)").tag("high")
            }
            .pickerStyle(.menu).disabled(isGenerating)

            Toggle("모두 움직이는 캐릭터로 (한 모습당 2장)", isOn: Binding(
                get: { !selectedStates.isEmpty && selectedStates.isSubset(of: animatedStates) },
                set: { on in
                    if on { animatedStates.formUnion(selectedStates) }
                    else { animatedStates.subtract(selectedStates) }
                }
            ))
            .disabled(isGenerating)
        } header: {
            Text("스타일")
        } footer: {
            Text("움직이는 캐릭터를 켜면 한 모습마다 두 장을 만들어 메인 화면에서 움직여요.")
                .foregroundStyle(.secondary)
        }
    }

    /// 실제 생성 장수 — idle 은 항상 먼저 만들므로 선택 안 했으면 +1, 움직임 상태는 frame1 만큼 +1씩.
    private var requiredCount: Int {
        let base = selectedStates.contains(.idle) ? selectedStates.count : selectedStates.count + 1
        let anim = animatedStates.intersection(selectedStates.union([.idle])).count
        return base + anim
    }

    /// 1단계 결과(idle) 승인 게이트 — 이 모습을 기준으로 나머지를 만들지 확인.
    @ViewBuilder
    private var idleApprovalSection: some View {
        if awaitingIdleApproval, let idle = results[.idle] {
            Section {
                Image(uiImage: idle)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 280)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Button {
                    batchTask = Task { await approveIdleAndContinue() }
                } label: {
                    Label("이 모습으로 나머지 만들기", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.withuPink)
                .disabled(isGenerating)

                // 마음에 안 들면 — ① 수정해서 생성하기(아래 수정사항 반영)  ② 완전히 새로
                Button {
                    batchTask = Task { await reviseIdle() }
                } label: {
                    if isGenerating {
                        HStack { ProgressView(); Text("만드는 중…") }
                    } else {
                        Label("수정해서 생성하기", systemImage: "wand.and.stars")
                    }
                }
                .tint(.secondary)
                .disabled(isGenerating || idleRevisionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                TextField("수정사항을 적어주세요 (예: 더 둥글게, 색 연하게)",
                          text: $idleRevisionText, axis: .vertical)
                    .font(.callout)
                    .disabled(isGenerating)
                Button {
                    // 즉시 재생성하지 않고 프롬프트 화면으로 돌아감 — 프롬프트/사진을 고친 뒤
                    // '만들기 시작'을 누를 때 캔디가 차감된다.
                    awaitingIdleApproval = false
                    results.removeAll()
                    resultsFrame1.removeAll()
                    frame0FullRes.removeAll()
                    idleFullRes = nil
                    idleAnchor = nil
                    idleRevisionText = ""
                    errors.removeAll()
                } label: {
                    Label("프롬프트 수정해서 다시", systemImage: "pencil")
                }
                .tint(.secondary)
                .disabled(isGenerating)
            } header: {
                Text("기준 모습 확인")
            } footer: {
                Text("먼저 만든 '기본' 모습이에요. 이 모습을 기준으로 나머지를 일관되게 만들어요.\n· 마음에 들면 위에서 진행 · 살짝 고치려면 '수정해서 생성하기'(수정사항 입력) · 프롬프트부터 바꾸려면 '프롬프트 수정해서 다시'")
                    .foregroundStyle(.secondary)
            }
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
                        Text("만드는 중… \(results.count + errors.count)/\(requiredCount)")
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
                      || remainingGenerations < requiredCount)

            if isGenerating {
                Text("만드는 동안엔 앱을 그대로 켜 주세요. (\(results.count + errors.count)/\(requiredCount) 완료)")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button(role: .destructive) {
                    batchTask?.cancel()
                    batchTask = nil
                } label: {
                    Label("그만두기", systemImage: "stop.circle.fill")
                }
                .tint(.secondary)
            } else if remainingGenerations < requiredCount {
                Text("지금 \(remainingGenerations)번으로는 \(selectedStates.count)개를 한 번에 만들 수 없어요. 만들 순간을 줄이거나 캔디를 충전해 주세요.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button {
                    showPaywall = true
                } label: {
                    Label("더 만들기 (구독·충전)", systemImage: "sparkles")
                }
                .tint(.withuPink)
            } else {
                Text("지금 \(remainingGenerations)번 더 만들 수 있어요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var resultsSection: some View {
        Section("만들어진 모습") {
            // LazyVGrid 는 Form 섹션 안에서 높이 계산이 어긋나 아래가 잘림 → 수동 2열 그리드.
            let shown = CharacterState.allCases.filter { displayedImage(for: $0) != nil || errors[$0] != nil }
            VStack(spacing: 12) {
                ForEach(Array(stride(from: 0, to: shown.count, by: 2)), id: \.self) { i in
                    HStack(alignment: .top, spacing: 12) {
                        resultCell(shown[i]).frame(maxWidth: .infinity)
                        if i + 1 < shown.count {
                            resultCell(shown[i + 1]).frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
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

    /// 결과 그리드 셀 — 이미지면 결과 카드, 에러면 에러 카드.
    @ViewBuilder
    private func resultCell(_ state: CharacterState) -> some View {
        if let img = displayedImage(for: state) {
            resultCard(state: state, image: img)
        } else if let err = errors[state] {
            errorCard(state: state, error: err)
        }
    }

    /// per-state 현재 표시 이미지 — toggle 따라 raw 또는 transparent.
    private func displayedImage(for state: CharacterState) -> UIImage? {
        let useTransparent = displayTransparentByState[state] ?? false
        if useTransparent, let t = transparentResults[state] { return t }
        return results[state]
    }

    /// 프레임별 표시 이미지 — 배경 토글 상태 반영 (frame 1 = 움직임).
    private func displayedImage(for state: CharacterState, frame: Int) -> UIImage? {
        let useTransparent = displayTransparentByState[state] ?? false
        if frame == 1 {
            if useTransparent, let t = transparentResultsFrame1[state] { return t }
            return resultsFrame1[state]
        }
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

    /// 한 모습만 배경 토글 — on 이면 Vision 처리본, off 면 raw 로 active slot 적용.
    @MainActor
    private func applyTransparentOne(_ state: CharacterState, on: Bool) async {
        guard let raw = results[state] else { return }
        if on {
            isProcessingTransparentBulk = true
            defer { isProcessingTransparentBulk = false }
            let transparent: UIImage
            if let cached = transparentResults[state] {
                transparent = cached
            } else {
                transparent = await ImageProcessing.bestEffortTransparent(raw)
                transparentResults[state] = transparent
            }
            CharacterImageStore.saveActiveSlotOnly(transparent, for: state, frame: 0)
            ConnectivityManager.shared.sendCharacterImage(transparent, for: state, frame: 0)
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
        } else {
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
            detailFrame = 0
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
    /// 사용자가 직접 넣은 참고사진만 (상태별 → 전역). idle 앵커는 제외.
    private func resolveUserReference(for state: CharacterState) -> String? {
        if let img = stateReferenceImages[state], let data = img.pngData() {
            return data.base64EncodedString()
        }
        return referenceImage?.pngData()?.base64EncodedString()
    }

    /// 생성에 쓸 reference: 사용자 참고사진 → (idle 외 상태면) 승인된 idle 앵커 → 없음.
    private func resolveReference(for state: CharacterState) -> String? {
        if let user = resolveUserReference(for: state) { return user }
        if state != .idle, let anchor = idleAnchor { return anchor.pngData()?.base64EncodedString() }
        return nil
    }

    /// 참고사진 "무엇을 참고" 힌트 — 사용자 참고사진이 실제로 쓰일 때만(앵커엔 미적용).
    private func userRefNote(for state: CharacterState) -> String {
        guard stateReferenceImages[state] != nil || referenceImage != nil else { return "" }
        return referenceHint.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 동시 호출 개수. 1 = 순차 (가장 안정적). 연속 이미지 ON 시도 한 번에 한 호출.
    private static let maxConcurrent: Int = 1

    /// 1단계 — idle 을 먼저 만들어 앵커로 삼고, 사용자 승인을 기다린다.
    private func startBatch() async {
        isGenerating = true
        batchSessionId = UUID().uuidString   // 새 일괄 세션 — 서버가 free_batch 로 묶음
        saveDescription()                    // 캐릭터 설명을 프로필에 저장 — 단건 생성과 공유
        results.removeAll()
        resultsFrame1.removeAll()
        frame0FullRes.removeAll()
        transparentResults.removeAll()          // 이전 배치의 배경제거 캐시 잔존 방지
        transparentResultsFrame1.removeAll()
        displayTransparentByState.removeAll()
        errors.removeAll()
        inProgressStates.removeAll()
        stateStartedAt.removeAll()
        idleAnchor = nil
        awaitingIdleApproval = false

        defer {
            isGenerating = false
            inProgressStates.removeAll()
            stateStartedAt.removeAll()
            remainingGenerations = GenerationQuota.remainingToday()
        }

        do {
            try await APIClient.shared.preflightPing()
        } catch {
            errors[.idle] = "서버에 연결할 수 없어요. 네트워크 또는 서버 상태를 확인하고 다시 시도해 주세요."
            return
        }

        // idle 먼저 (앵커, frame 0). 사용자 참고사진이 있으면 그걸 reference 로.
        let idleRef = resolveUserReference(for: .idle)
        let ok = await runOne(.idle, reference: idleRef,
                              consistencyPrefix: idleRef != nil,
                              referenceNote: userRefNote(for: .idle), frame: 0)
        if ok {
            GenerationQuota.record(1)
            WidgetCenter.shared.reloadAllTimelines()   // idle 저장 즉시 위젯 반영
            awaitingIdleApproval = true   // 승인 대기 → idleApprovalSection 노출
        }
    }

    /// 2단계 — 승인된 idle 을 앵커로 나머지 선택 상태(+애니메이션)를 생성.
    private func approveIdleAndContinue() async {
        // 연타 재진입 차단 — awaitingIdleApproval 을 await 전에 동기로 끔.
        guard awaitingIdleApproval, let idle = idleFullRes ?? results[.idle] else { return }
        awaitingIdleApproval = false
        idleAnchor = idle           // 원본(1024) 우선 — 일관성 reference 품질
        isGenerating = true

        defer {
            isGenerating = false
            inProgressStates.removeAll()
            stateStartedAt.removeAll()
            showFinishedAlert = true
            // 2단계에서 만든 장수 차감 (idle frame0 은 1단계에서 이미 반영).
            GenerationQuota.record(max(0, results.count - 1) + resultsFrame1.count)
            remainingGenerations = GenerationQuota.remainingToday()
            WidgetCenter.shared.reloadAllTimelines()
            if errors.filter({ $0.key != .idle }).isEmpty {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }

        // idle 의 움직임(frame 1) — frame 0(앵커)을 reference 로 체이닝.
        if animatedStates.contains(.idle), let f0Ref = idle.pngData()?.base64EncodedString() {
            await runOne(.idle, reference: f0Ref, consistencyPrefix: true, frame: 1)
        }

        // 나머지 선택 상태 (idle 제외) — resolveReference 가 idle 앵커를 reference 로 넣음.
        let rest = CharacterState.allCases.filter { selectedStates.contains($0) && $0 != .idle }
        var iterator = rest.makeIterator()
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

    /// idle 다시 만들기 (승인 대기 유지).
    /// idle 을 '수정사항' 으로 고쳐 다시 — 현재 idle 을 reference 로 edit. 승인 대기 유지.
    private func reviseIdle() async {
        let trimmed = idleRevisionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let current = idleFullRes ?? results[.idle],
              let refB64 = current.pngData()?.base64EncodedString() else { return }
        isGenerating = true
        defer {
            isGenerating = false
            inProgressStates.removeAll()
            stateStartedAt.removeAll()
            remainingGenerations = GenerationQuota.remainingToday()
        }
        errors.removeValue(forKey: .idle)
        let pose = stateHints[.idle] ?? CharacterState.idle.generationHint
        let desc = baseIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = desc.isEmpty ? pose : "\(desc), \(pose)"
        let prompt = "\(base). User modification: \(trimmed). Solid clean WHITE background, no shadows, no gradients. Never draw a checkerboard or transparency grid pattern — the background must be one flat solid white color."
        do {
            let req = GenerateImageRequest(prompt: prompt, referenceImageBase64: refB64,
                                           steps: 30, width: 1024, height: 1024,
                                           quality: quality, artStyle: artStyle, style: "auto")
            let resp = try await APIClient.shared.generateImage(req, kind: "batch", batchId: batchSessionId)
            if let data = Data(base64Encoded: resp.imageBase64), let img = UIImage(data: data) {
                let flat = ImageProcessing.flattenedOnWhite(img)
                let small = flat.preparingThumbnail(of: CGSize(width: 128, height: 128)) ?? flat
                results[.idle] = small
                idleFullRes = flat
                CharacterImageStore.save(small, for: .idle, frame: 0)
                ConnectivityManager.shared.sendCharacterImage(small, for: .idle, frame: 0)
                if let ent = resp.entitlement { AuthManager.shared.applyEntitlement(ent) }
                GenerationQuota.record(1)
                idleRevisionText = ""
                WidgetCenter.shared.reloadAllTimelines()
            } else {
                errors[.idle] = "이미지를 받지 못했어요"
            }
        } catch APIError.paymentRequired {
            showPaywall = true
        } catch {
            errors[.idle] = error.koreanizedDescription
        }
        // awaitingIdleApproval 유지 — 수정본을 다시 승인/수정 가능
    }

    /// state 하나의 task — frame 0 (+ animated 면 frame 1 도 순차) 실행
    private func addStateTask(group: inout TaskGroup<Void>, state: CharacterState) {
        let refB64 = resolveReference(for: state)
        let note = userRefNote(for: state)
        let animated = animatedStates.contains(state)
        group.addTask { @MainActor in
            // frame 0
            let ok = await runOne(state, reference: refB64,
                                  consistencyPrefix: refB64 != nil, referenceNote: note, frame: 0)
            // frame 1 — frame 0 성공 시에만, frame 0 원본(1024)을 reference 로 체이닝
            // (128px 썸네일을 reference 로 보내면 캐릭터 디테일이 뭉개져 drift 가 커짐)
            if ok, animated, let f0 = frame0FullRes[state] ?? results[state],
               let f0Ref = f0.pngData()?.base64EncodedString() {
                await runOne(state, reference: f0Ref,
                             consistencyPrefix: true, frame: 1)
            }
        }
    }

    /// 캐릭터 설명을 프로필에 저장 — 다음에 열어도 유지되고 단건 생성과 같은 설명을 씀.
    private func saveDescription() {
        var p = CharacterProfileStore.load()
        let trimmed = baseIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.aiPrompt != trimmed {
            p.aiPrompt = trimmed
            CharacterProfileStore.save(p)
        }
    }

    /// 실패한 카드 탭 시 재시도. 같은 prompt + reference 그대로.
    private func retryOne(_ state: CharacterState) async {
        // 이전 에러 표시 제거 + 진행 표시 시작
        errors.removeValue(forKey: state)
        let refB64 = resolveReference(for: state)
        let ok = await runOne(state, reference: refB64, consistencyPrefix: refB64 != nil,
                              referenceNote: userRefNote(for: state))
        if ok {
            GenerationQuota.record(1)
            remainingGenerations = GenerationQuota.remainingToday()
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 한 state 생성 — 성공 시 true. 결과는 results / errors 에 기록.
    /// frame == 0: 기본. frame == 1: 애니메이션용 (이전 결과를 reference 로 chain + 다른 포즈).
    @discardableResult
    private func runOne(_ state: CharacterState, reference: String?,
                        consistencyPrefix: Bool, referenceNote: String = "", frame: Int = 0) async -> Bool {
        inProgressStates.insert(state)
        stateStartedAt[state] = .now
        defer {
            inProgressStates.remove(state)
            stateStartedAt.removeValue(forKey: state)
        }
        let note = referenceNote.isEmpty ? "" : " (keep in particular: \(referenceNote))"
        let prefix = consistencyPrefix
            ? "Same exact character as the reference image\(note) — only the pose/scene differs. "
            : ""
        let pose = stateHints[state] ?? state.generationHint
        let desc = baseIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        var prompt = desc.isEmpty ? "\(prefix)\(pose)" : "\(prefix)\(desc), \(pose)"
        if frame == 1 {
            prompt += ". SECOND FRAME of a tiny 2-frame idle loop, almost identical to the reference image. Keep the EXACT same character: same face, body, proportions, outfit, colors, art/pixel style, line work, size, scale, centered position, framing, and the same flat solid white background. The ONLY change is a tiny hint of life: \(state.animationFrame2Hint). Do NOT change the size, zoom, crop, position, background, or overall appearance."
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
            // frame1: 1번째 기준으로 크기·위치·흰배경 강제. frame0: 흰배경 평탄화.
            let flat: UIImage
            if frame == 1, let ref0 = frame0FullRes[state] {
                flat = await ImageProcessing.matchedToReference(img, reference: ref0)
            } else {
                flat = ImageProcessing.flattenedOnWhite(img)
            }
            // 128px 다운샘플 — 메인 화면 200 / 워치 64 / 위젯 60 다 커버, 디스크 절약
            let small = flat.preparingThumbnail(of: CGSize(width: 128, height: 128)) ?? flat
            if frame == 0 {
                results[state] = small
                frame0FullRes[state] = flat               // frame1 정규화 reference
                if state == .idle { idleFullRes = flat }   // 앵커 reference 는 원본(1024, 흰배경)으로
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

    /// 결과 카드 탭 시 열리는 sheet — 프레임 페이지(좌우 스와이프) + 저장 / 수정
    @ViewBuilder
    private func resultDetailSheet(state: CharacterState) -> some View {
        let hasF1 = resultsFrame1[state] != nil
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 프레임 페이지 — 기본 ↔ 움직임 좌우 스와이프 (움직이는 캐릭터면 위에 점 표시)
                    TabView(selection: $detailFrame) {
                        Image(uiImage: displayedImage(for: state, frame: 0) ?? results[state] ?? UIImage())
                            .resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal)
                            .tag(0)
                        if hasF1 {
                            Image(uiImage: displayedImage(for: state, frame: 1) ?? resultsFrame1[state] ?? UIImage())
                                .resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal)
                                .tag(1)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: hasF1 ? .always : .never))
                    .indexViewStyle(.page(backgroundDisplayMode: .interactive))
                    .frame(height: 320)

                    Text(hasF1
                         ? "\(state.koreanShortLabel) · \(detailFrame == 1 ? "움직임 프레임" : "기본")"
                         : state.koreanShortLabel)
                        .font(.callout.weight(.semibold))

                    // 이 모습만 배경 토글 (개별)
                    Picker("배경", selection: Binding(
                        get: { displayTransparentByState[state] ?? false },
                        set: { on in Task { await applyTransparentOne(state, on: on) } }
                    )) {
                        Text("흰 배경").tag(false)
                        Text("배경 빼기").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .disabled(isProcessingTransparentBulk)
                    if isProcessingTransparentBulk {
                        HStack { ProgressView(); Text("배경 빼는 중…") }
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(hasF1 && detailFrame == 1 ? "이 움직임 프레임을 어떻게 바꿀까요" : "어떻게 바꿀까요")
                            .font(.caption).foregroundStyle(.secondary)
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
                            let img = displayedImage(for: state, frame: hasF1 ? detailFrame : 0)
                                ?? results[state] ?? UIImage()
                            Task { await saveOneToPhotos(img) }
                        } label: {
                            Label("저장", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)

                        Button {
                            Task { await reviseOne(state, frame: hasF1 ? detailFrame : 0, text: revisionText) }
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

    /// 기존 결과 + 자연어 수정 요청으로 재생성 (프레임별).
    /// reference 우선순위: 사용자 첨부 > (frame1이면) frame0 앵커 > 해당 프레임 기존본
    private func reviseOne(_ state: CharacterState, frame: Int, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isRevising = true
        defer { isRevising = false }

        // frame1 은 frame0 을 앵커로 두면 캐릭터/크기 일관성이 유지됨
        let anchor: UIImage? = frame == 1 ? (results[state] ?? resultsFrame1[state]) : results[state]
        let refB64 = revisionRefImage?.pngData()?.base64EncodedString()
            ?? anchor?.pngData()?.base64EncodedString()
        let pose = stateHints[state] ?? state.generationHint
        let desc = baseIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        let basePrompt = desc.isEmpty ? pose : "\(desc), \(pose)"
        var modifiedPrompt = "\(basePrompt). User modification: \(trimmed)"
        if frame == 1 {
            modifiedPrompt += ". Animation frame 2 (for a 2-frame swap loop): \(state.animationFrame2Hint). CRITICAL: keep the character at the EXACT same size, scale, and centered position as the reference image; only the pose changes."
        }
        modifiedPrompt += ". Solid clean WHITE background, no shadows, no transparency grid pattern."

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
                // frame1: 1번째 기준으로 크기·위치·흰배경 강제. frame0: 흰배경 평탄화.
                let flat: UIImage
                if frame == 1, let ref0 = frame0FullRes[state] ?? results[state] {
                    flat = await ImageProcessing.matchedToReference(img, reference: ref0)
                } else {
                    flat = ImageProcessing.flattenedOnWhite(img)
                }
                let small = flat.preparingThumbnail(of: CGSize(width: 128, height: 128)) ?? flat
                if frame == 1 {
                    resultsFrame1[state] = small
                    transparentResultsFrame1[state] = nil   // 배경 캐시 무효화
                } else {
                    results[state] = small
                    frame0FullRes[state] = flat
                    if state == .idle { idleFullRes = flat }
                    transparentResults[state] = nil
                }
                displayTransparentByState[state] = false   // 새 raw → 흰배경 기준으로 리셋
                CharacterImageStore.save(small, for: state, frame: frame)
                ConnectivityManager.shared.sendCharacterImage(small, for: state, frame: frame)
                if let ent = resp.entitlement { AuthManager.shared.applyEntitlement(ent) }
                revisionText = ""
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch APIError.paymentRequired {
            showPaywall = true
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
                cropTarget = CropTarget(image: img) { cropped in
                    revisionRefImage = cropped
                }
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
                cropTarget = CropTarget(image: img) { cropped in
                    stateReferenceImages[state] = cropped
                }
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
                cropTarget = CropTarget(image: img) { cropped in
                    referenceImage = cropped
                }
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
