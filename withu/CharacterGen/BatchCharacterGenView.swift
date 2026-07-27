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

    /// 만들 상태. '기본'(idle)은 나머지의 기준 이미지라 항상 포함된다.
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
    /// '배경 모두 지우기/배경 복원'은 미리보기만 바꾼다 — 눌렀을 때 잠깐 떴다 사라지는 토스트로 안내.
    @State private var bgToastVisible: Bool = false
    @State private var bgToastToken: Int = 0

    /// 전체 참고 이미지 (state 별 reference 가 없을 때의 fallback)
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var referenceImage: UIImage?

    /// state 별 개별 참고 이미지. 있으면 전체 reference 보다 우선.
    /// 상태 사진 자리를 눌러 '앨범' 선택 시 뜨는 시스템 사진 피커 — 어느 상태용인지.
    @State private var albumPickerItem: PhotosPickerItem?
    /// 움직임 설명 '?' 팝오버.
    /// '기본'은 끌 수 없다는 안내
    @State private var showIdleLockedInfo: Bool = false
    @State private var showMotionInfo: Bool = false
    /// "항목별 입력" 도우미 — 채우면 캐릭터 프롬프트(baseIdentity)에 자동 합쳐짐. (하나씩 만들기와 동일)
    @State private var subjectField: String = ""
    @State private var looksField: String = ""
    @State private var colorField: String = ""
    /// idle 앵커링 — idle 을 먼저 만들어 승인받고, 나머지 상태 생성의 reference 로 사용(일관성).
    @State private var idleAnchor: UIImage?
    /// 앵커 reference 용 원본(1024). results 는 128 썸네일이라 그대로 쓰면 일관성 reference 품질이 떨어짐.
    @State private var idleFullRes: UIImage?
    @State private var awaitingIdleApproval: Bool = false
    /// 기준(기본) 모습을 이미 승인해 나머지 생성을 시작했는지 — 재확인 트리거가 승인 후 되돌아오는 것 방지.
    @State private var idleApproved: Bool = false
    /// 승인 화면 — '수정해서 다시' 입력.
    @State private var idleRevisionText: String = ""
    /// 기준 모습 확인 화면에서 이미 쓴 수정 횟수 — 1번은 무료, 2번째부터 캔디 차감.
    @State private var idleRevisionsUsed: Int = 0
    /// 참고사진에서 무엇을 참고할지 (사용자 입력) — 참고사진 쓸 때만 프롬프트에 반영.
    /// 참고사진에서 그대로 둘 것 / 바꿀 것 (단건 생성과 동일). 참고사진 쓸 때만 프롬프트에 반영.
    @State private var referenceKeep: String = ""
    @State private var referenceChange: String = ""

    // MARK: - Progress

    @State private var isGenerating: Bool = false
    /// 현재 진행 중인 state 들 (병렬이라 여러 개 동시 가능)
    @State private var inProgressStates: Set<CharacterState> = []
    @State private var stateStartedAt: [CharacterState: Date] = [:]
    /// 기본(frame0)이 아직 안 나온 채 생성 중인 상태 — 결과 그리드에 로딩 placeholder 로 표시.
    @State private var loadingFrame0: Set<CharacterState> = []
    /// 움직임(frame1) 생성 중인 상태 — 카드 우하단 미니에 로딩 표시.
    @State private var pendingFrame1: Set<CharacterState> = []
    /// 움직임(frame1)만 실패한 상태 — 기본은 있으니 미니 슬롯에 재시도 표시(기본 카드는 정상).
    @State private var failedFrame1: [CharacterState: String] = [:]

    @State private var results: [CharacterState: UIImage] = [:]
    /// 연속 이미지 ON 일 때 state 의 frame 1 결과. 카드에 우하단 미니 썸네일로 표시.
    @State private var resultsFrame1: [CharacterState: UIImage] = [:]
    @State private var errors: [CharacterState: String] = [:]
    /// 사용자가 '적용'한 상태 (배치 생성은 갤러리에만 저장 → 적용은 수동).
    @State private var appliedStates: Set<CharacterState> = []

    @State private var showFinishedAlert: Bool = false
    /// 배치 생성 Task — 중단 버튼이 cancel() 호출
    @State private var batchTask: Task<Void, Never>?
    /// 그만두기를 눌렀으면 완료 alert 를 띄우지 않음
    @State private var didCancel: Bool = false

    /// 백그라운드 생성 큐 — 화면을 떠나거나 앱을 닫아도 계속되는 실행 주체.
    private var genManager: BackgroundGenerationManager { .shared }

    // 결과 사진 클릭 시 sheet
    @State private var selectedResult: (state: CharacterState, image: UIImage)?
    @State private var detailFrame: Int = 0   // 상세 시트에서 보고 있는 프레임(0=기본, 1=움직임)
    @State private var revisionText: String = ""
    @State private var isRevising: Bool = false
    /// 입력한 수정 문구/사진이 있는데 상세 시트를 닫으려 할 때 확인.
    @State private var showReviseDiscardConfirm: Bool = false
    /// '바꾸기' 실패 사유 — 상세 시트에 표시(예전엔 조용히 실패해 '반영 안 됨'으로 보였음).
    @State private var revisionError: String?
    /// 상세 시트에서 '바꾸기'로 재생성 중인 프레임(state→frame). 시트를 닫아도
    /// 결과 그리드가 처음 만들 때처럼 로딩을 보여주도록(고치는 프레임에만) 추적.
    @State private var revisingFrame: [CharacterState: Int] = [:]
    /// 다듬기 완료 후 적용 전 보관 — 상세 시트에서 버전 이력 스트립(원본/다듬음 N), 카드엔 '다듬음' 배지.
    /// versions[0] = 다듬기 전 원본, 이후 = 다듬은 버전. (하나씩 만들기와 같은 이력 모델)
    struct BatchRevision {
        let frame: Int
        var versions: [UIImage]      // 128 썸네일 — [0]=원본, 이후=다듬음
        var fullVersions: [UIImage]  // 대응 1024 (적용 시 frame0FullRes 갱신용)
        var selected: Int
        var prompt: String           // 갤러리 '만든 기록' 저장용
        var current: UIImage { versions[Swift.min(Swift.max(0, selected), versions.count - 1)] }
        var currentFull: UIImage { fullVersions[Swift.min(Swift.max(0, selected), fullVersions.count - 1)] }
    }
    @State private var revisedDone: [CharacterState: BatchRevision] = [:]

    /// 캔디 소모 전 확인 팝업 대상 (배치 — 단건 생성과 동일한 안내를 배치에도).
    private enum PendingBatchAction {
        case start          // 만들기 시작 (전체)
        case approveRest    // 이 모습으로 나머지 만들기
        case reviseIdle     // 수정해서 생성하기(기준 모습)
    }
    @State private var pendingAction: PendingBatchAction?
    /// 상세 시트의 '바꾸기'는 시트 위에 확인이 떠야 해서 별도 플래그.
    @State private var pendingReviseConfirm = false

    // 사진 앱 저장 상태
    @State private var isSavingPhotos: Bool = false
    @State private var saveResultMessage: String?
    @State private var showSaveResultAlert: Bool = false

    // 오늘 남은 생성 횟수 (App Group quota)
    @State private var remainingGenerations: Int = GenerationQuota.remainingToday()
    @State private var showPaywall: Bool = false
    /// 이번 일괄 세션 식별자 — 서버가 같은 세션의 장을 무료(free_batch)로 묶음.
    @State private var batchSessionId: String = UUID().uuidString
    /// 이 캐릭터에 붙일 이름 — 갤러리 '캐릭터별'에 표시. (선택)
    @State private var characterName: String = ""
    /// 사진 선택 후 정사각 자르기 시트
    @State private var cropTarget: CropTarget?
    /// 참고사진을 내 캐릭터 갤러리에서 고르는 sheet — 전체 또는 상태별.
    @State private var galleryRefTarget: GalleryRefTarget?

    private enum GalleryRefTarget: Identifiable {
        case global
        var id: String { "global" }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundGradient(for: .idle, topTint: .withuPinkSoft).ignoresSafeArea()
            Form {
                if awaitingIdleApproval {
                    // 기준 모습 승인 단계 — 사진과 버튼이 바로 보이게 이 섹션만 표시
                    idleApprovalSection
                } else {
                    stateListSection        // 만들고 싶은 상태
                    motionSection           // 움직이는 캐릭터
                    nameSection             // 캐릭터 이름
                    optionsSection          // 스타일
                    identitySection         // 캐릭터 프롬프트
                    referenceSection        // 참고 사진
                    startSection            // 만들기
                    if isGenerating || !results.isEmpty || !errors.isEmpty || !loadingFrame0.isEmpty {
                        resultsSection
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("여러 모습 만들기")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { candyBadge }
        }
        .scrollDismissesKeyboard(.interactively)
        // 배경 미리보기 변경 토스트 — 떴다 자기 혼자 사라짐.
        .overlay(alignment: .bottom) {
            if bgToastVisible {
                Text("미리보기를 바꿨어요. 적용하려면 적용 버튼을 눌러주세요.")
                    .font(.pretendard(13, relativeTo: .footnote))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 44)
                    .transition(.opacity)
            }
        }
        .onAppear {
            remainingGenerations = GenerationQuota.remainingToday()
            // 진행 중이거나 승인 대기 중인 백그라운드 배치가 있으면 이어서 표시
            if !genManager.jobs.isEmpty {
                syncFromManager()
                if !genManager.isActive, genManager.phase == .anchor, results[.idle] != nil {
                    awaitingIdleApproval = true
                }
            }
            restorePendingRevisions()
        }
        .onChange(of: genManager.tick) { _, _ in
            syncFromManager()
        }
        .onChange(of: genManager.isActive) { was, now in
            guard was, !now else { return }
            syncFromManager()
            if didCancel {
                didCancel = false
            } else if genManager.phase == .anchor {
                if results[.idle] != nil { awaitingIdleApproval = true }
            } else if genManager.phase == .rest, !genManager.jobs.isEmpty {
                // 캔디 소진(402)으로 실패한 게 있으면 완료 알럿 대신 충전 안내.
                if genManager.jobs.contains(where: { $0.paymentRequired == true }) {
                    showPaywall = true
                } else {
                    showFinishedAlert = true
                }
                if errors.filter({ $0.key != .idle }).isEmpty {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
            }
        }
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
        .sheet(item: $galleryRefTarget) { _ in
            GalleryReferencePicker { img in
                referenceImage = img
                photoPickerItem = nil
            }
        }
        .alert("다 만들었어요", isPresented: $showFinishedAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("\(results.count)개 완성, \(errors.count)개 못 만들었어요. 아래 '적용' 또는 '모두 적용하기'로 홈/워치에 반영해요.")
        }
        .alert("사진 저장", isPresented: $showSaveResultAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(saveResultMessage ?? "")
        }
        // 캔디 소모 확인 — 단건 생성과 동일하게 배치의 만들기/나머지/수정에도.
        .alert("캔디를 사용해요", isPresented: Binding(
            get: { pendingAction != nil },
            set: { if !$0 { pendingAction = nil } }
        )) {
            Button(pendingActionConfirmLabel) {
                switch pendingAction {
                case .start: batchTask = Task { await startBatch() }
                case .approveRest: batchTask = Task { await approveIdleAndContinue() }
                case .reviseIdle: batchTask = Task { await reviseIdle() }
                case nil: break
                }
                pendingAction = nil
            }
            Button("취소", role: .cancel) { pendingAction = nil }
        } message: {
            Text(pendingActionMessage)
        }
        .onChange(of: photoPickerItem) { _, item in
            Task { await loadReference(item) }
        }
        .onChange(of: subjectField) { _, _ in composeFromHelper() }
        .onChange(of: looksField) { _, _ in composeFromHelper() }
        .onChange(of: colorField) { _, _ in composeFromHelper() }
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
                Text("\(GenerationQuota.displayedCandy())")
                    .font(.pretendard(16, relativeTo: .callout))
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

    private var nameSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
            TextField("이름 (선택)", text: $characterName)
                .font(.pretendard(16, relativeTo: .callout))
                .disabled(isGenerating)
                .submitLabel(.done)
                .onChange(of: characterName) { _, new in
                    // 생성 후 이름을 바꿔도 이미 저장된 캐릭터에 반영 (같은 batchSessionId).
                    CharacterImageStore.setCharacterName(new, for: batchSessionId)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .plainCard()
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        } header: {
            Text("캐릭터 이름")
                .font(.pretendardBold(16, relativeTo: .callout))
        }
    }

    private var identitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $baseIdentity)
                .frame(minHeight: 80)
                .font(.pretendard(16, relativeTo: .callout))
                .disabled(isGenerating)
                .overlay(alignment: .topLeading) {
                    if baseIdentity.isEmpty {
                        Text("만들 캐릭터를 설명해 주세요")
                            .font(.pretendard(16, relativeTo: .callout))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .pixelInputField()
            DisclosureGroup("항목별 입력") {
                helperField("대상", text: $subjectField, placeholder: "마시멜로 캐릭터")
                helperField("생김새", text: $looksField, placeholder: "큰 눈, 둥근 몸, 새싹")
                helperField("색감", text: $colorField, placeholder: "연두 파스텔톤")
            }
            .font(.pretendard(16, relativeTo: .callout))
            .disabled(isGenerating)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .plainCard()
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        } header: {
            Text("캐릭터 프롬프트")
                .font(.pretendardBold(16, relativeTo: .callout))
        }
    }

    /// "항목별 입력" 한 줄 — 라벨 + 입력칸. (하나씩 만들기와 동일)
    private func helperField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.pretendard(12, relativeTo: .caption))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            TextField(placeholder, text: text, axis: .vertical)
                .font(.pretendard(16, relativeTo: .callout))
        }
    }

    /// 항목별 입력(대상·생김새·색감)을 합쳐 캐릭터 프롬프트(baseIdentity)에 반영.
    private func composeFromHelper() {
        let parts = [subjectField, looksField, colorField]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !parts.isEmpty {
            baseIdentity = parts.joined(separator: ", ")
        }
    }

    private var stateListSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
            ForEach(CharacterState.userFacing, id: \.self) { state in
                stateRow(state)
            }
            // Form 한 행에 버튼이 여러 개면 행 아무 데나 눌러도 전부 실행됨 —
            // .borderless 로 각 버튼이 자기 탭만 받게 해야 함.
            HStack {
                Button("모두 켜기") { selectedStates = Set(CharacterState.userFacing) }
                    .buttonStyle(.borderless)
                Spacer()
                Button("모두 끄기", role: .destructive) { selectedStates = [.idle] }
                    .buttonStyle(.borderless)
            }
            .disabled(isGenerating)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .plainCard()
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        } header: {
            Text("만들고 싶은 상태 (\(selectedStates.union([.idle]).count)개)")
                .font(.pretendardBold(16, relativeTo: .callout))
        } footer: {
            Text("'기본'은 나머지 모습의 기준이 되는 그림이라 항상 만들어요.")
                .font(.pretendard(12, relativeTo: .caption))
                .foregroundStyle(.secondary)
            // 움직임 섹션이 보일 땐 캔디 소모를 거기(아래)로 옮김 — 없을 때만 여기 표시.
            if animatableSelected.isEmpty {
                Text("\(requiredCount * GenerationQuota.cost(forQuality: quality))캔디 소모")
                    .font(.pretendard(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
        }
        .alert("'기본'은 항상 만들어요", isPresented: $showIdleLockedInfo) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("'기본' 상태를 먼저 생성하고 해당 결과물을 기준으로 나머지를 그려요.")
        }
    }

    /// 선택된 상태 중 2프레임 움직임이 가능한 것들 — 움직임 섹션 노출 여부·캔디 소모 위치 판단.
    private var animatableSelected: [CharacterState] {
        selectedStates.filter { $0.usesGeneratedMotion }
    }

    @ViewBuilder
    private func stateRow(_ state: CharacterState) -> some View {
        HStack(spacing: 8) {
            if state == .idle {
                // '기본'은 나머지 모습의 기준(앵커)이라 끌 수 없다.
                // 비활성 토글은 탭을 안 먹어서, Button 으로 가로채 이유를 알려준다.
                Button {
                    showIdleLockedInfo = true
                } label: {
                    Toggle("", isOn: .constant(true))
                        .labelsHidden()
                        .allowsHitTesting(false)
                }
                .buttonStyle(.borderless)
                .fixedSize()
            } else {
                Toggle("", isOn: Binding(
                    get: { selectedStates.contains(state) },
                    set: { on in
                        if on { selectedStates.insert(state) } else { selectedStates.remove(state) }
                    }
                ))
                .labelsHidden()
                .fixedSize()
                .disabled(isGenerating)
            }

            Text(state.koreanShortLabel)
                .strikethrough(state != .idle && !selectedStates.contains(state))

            if state == .idle {
                Text("기준")
                    .font(.pretendard(11, relativeTo: .caption2))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.withuSage.opacity(0.22), in: Capsule())
                    .foregroundStyle(Color.withuPinkText)
            }

            // 움직임 지원 상태 — 행에서 한눈에. 연한 초록 pill 로 켜짐 표시. (설명 '?'는 섹션 헤더에)
            if state.usesGeneratedMotion {
                motionPill(state)
            }
            Spacer()
            resultBadge(state)
        }
    }

    /// 움직임 지원 상태의 연한 초록 토글 pill — 켜짐=연두, 꺼짐=회색.
    private func motionPill(_ state: CharacterState) -> some View {
        let on = animatedStates.contains(state)
        return Button {
            if on { animatedStates.remove(state) } else { animatedStates.insert(state) }
        } label: {
            Text("움직임")
                .font(.pretendard(11, relativeTo: .caption2))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(on ? Color.withuCTAGreen.opacity(0.18)
                                                : Color.secondary.opacity(0.12)))
                .foregroundStyle(on ? Color.withuCTAGreen : Color.secondary)
        }
        .buttonStyle(.borderless)
        .disabled(isGenerating)
    }

    @ViewBuilder
    private func resultBadge(_ state: CharacterState) -> some View {
        if inProgressStates.contains(state), let started = stateStartedAt[state] {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let elapsed = Int(ctx.date.timeIntervalSince(started))
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.7)
                    Text("\(elapsed)초").font(.pretendard(11, relativeTo: .caption2))
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
            VStack(alignment: .leading, spacing: 12) {
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
                VStack(spacing: 8) {
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        Label("앨범에서 선택", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isGenerating)
                    Button {
                        galleryRefTarget = .global
                    } label: {
                        Label("내 캐릭터에서 선택", systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)   // 보조 액션 — pink 는 만들기 CTA 전용
                    .disabled(isGenerating)
                }
            }
            if referenceImage != nil {
                Button("사진 빼기", role: .destructive) {
                    referenceImage = nil
                    photoPickerItem = nil
                }
                .font(.pretendard(16, relativeTo: .callout))
                .disabled(isGenerating)
                .buttonStyle(.bordered)
            }
            if referenceImage != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("그대로 둘 것")
                        .font(.pretendard(12, relativeTo: .caption)).foregroundStyle(.secondary)
                    TextField("비우면 사진 그대로 유지돼요", text: $referenceKeep, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.pretendard(16, relativeTo: .callout))
                        .disabled(isGenerating)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("바꿀 것")
                        .font(.pretendard(12, relativeTo: .caption)).foregroundStyle(.secondary)
                    TextField("모든 모습에 함께 반영할 변화",
                              text: $referenceChange, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.pretendard(16, relativeTo: .callout))
                        .disabled(isGenerating)
                }
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .plainCard()
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        } header: {
            Text("참고 사진 (선택)")
                .font(.pretendardBold(16, relativeTo: .callout))
        }
    }

    private var optionsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
            Picker("그림 스타일", selection: $artStyle) {
                Text("Soft").tag("casual")
                Text("Pixel").tag("pixel")
            }
            .pickerStyle(.segmented).disabled(isGenerating)
            styleExampleImage
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .plainCard()
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        } header: {
            Text("스타일")
                .font(.pretendardBold(16, relativeTo: .callout))
        }
    }

    /// 선택한 스타일 예시 — Soft 는 기본 idle 일러스트, Pixel 은 픽셀 샘플.
    private var styleExampleImage: some View {
        ZStack(alignment: .topLeading) {
            HStack {
                Spacer()
                Image(artStyle == "pixel" ? "style_example_pixel" : CharacterState.idle.imageAssetName)
                    .resizable()
                    .interpolation(artStyle == "pixel" ? .none : .high)
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Spacer()
            }
            Text("예시 사진")
                .font(.pretendard(11, relativeTo: .caption2))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// 움직임 선택 — 상태별 칩(위) + '모두 움직이는' 토글(아래). '만들고 싶은 상태' 바로 아래.
    @ViewBuilder
    private var motionSection: some View {
        let animatable = animatableSelected
        if !animatable.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                animatedStateChips
                Toggle("모두 움직이는 캐릭터로", isOn: Binding(
                    get: { Set(animatable).isSubset(of: animatedStates) },
                    set: { on in
                        if on { animatedStates.formUnion(animatable) }
                        else { animatedStates.subtract(animatable) }
                    }
                ))
                .disabled(isGenerating)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .plainCard()
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
            } header: {
                HStack(spacing: 6) {
                    Text("움직이는 캐릭터")
                        .font(.pretendardBold(16, relativeTo: .callout))
                    Button { showMotionInfo = true } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.pretendard(12, relativeTo: .caption))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            } footer: {
                Text("\(requiredCount * GenerationQuota.cost(forQuality: quality))캔디 소모")
                    .font(.pretendard(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
            .alert("움직이는 캐릭터", isPresented: $showMotionInfo) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("2장으로 구성해서 메인 화면에서 움직이는 캐릭터를 만들어요.")
            }
        }
    }

    /// 상태별 움직임 토글 칩 — 선택된 상태만 노출. 상태 행의 '움직임' pill 과 같은 값(animatedStates) 공유.
    @ViewBuilder
    private var animatedStateChips: some View {
        // 미세 모션 상태(idle·수면 등)는 2프레임을 안 만드므로 칩에서 제외 — 절차적 모션으로 자동 애니메이션.
        let states = CharacterState.userFacing.filter { selectedStates.contains($0) && $0.usesGeneratedMotion }
        if !states.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(states, id: \.self) { state in
                        let on = animatedStates.contains(state)
                        Button {
                            if on { animatedStates.remove(state) }
                            else { animatedStates.insert(state) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(state.imageAssetName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)
                                Text(state.koreanShortLabel)
                                    .font(.pretendard(13, relativeTo: .footnote))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(on ? Color.withuCTAGreen.opacity(0.18)
                                                  : Color.secondary.opacity(0.08))
                            )
                            .overlay(
                                Capsule().stroke(on ? Color.withuCTAGreen : .clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(on ? Color.withuCTAGreen : .secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .disabled(isGenerating)
        }
    }

    /// 실제 생성 장수 — idle 은 항상 먼저 만들므로 선택 안 했으면 +1, 움직임 상태는 frame1 만큼 +1씩.
    private var requiredCount: Int {
        let base = selectedStates.contains(.idle) ? selectedStates.count : selectedStates.count + 1
        let anim = animatedStates.intersection(selectedStates.union([.idle])).count
        return base + anim
    }

    /// 완료 장수 — 기본(frame0) + 움직임(frame1) 완료/실패를 모두 셈. requiredCount(움직임 포함)과 짝.
    private var progressDone: Int {
        results.count + resultsFrame1.count + errors.count + failedFrame1.count
    }

    private var pendingActionConfirmLabel: String {
        if case .reviseIdle = pendingAction { return String(localized: "다듬기") }
        return String(localized: "만들기")
    }

    private var pendingActionMessage: String {
        let unit = GenerationQuota.cost(forQuality: quality)
        switch pendingAction {
        case .start:
            return String(localized: "이번 만들기에 캔디 \(requiredCount * unit)개를 써요. 성공했을 때만 차감돼요.")
        case .approveRest:
            // idle(기준)은 이미 만들었으니 나머지 모습분만.
            let rest = max(1, requiredCount - 1)
            return String(localized: "나머지 모습에 캔디 약 \(rest * unit)개를 써요. 성공했을 때만 차감돼요.")
        case .reviseIdle:
            return idleRevisionCost == 0
                ? String(localized: "이번 다듬기는 무료예요.")
                : String(localized: "이번 다듬기에 캔디 \(idleRevisionCost)개를 써요. 성공했을 때만 차감돼요.")
        case nil:
            return ""
        }
    }

    /// 기준 모습 수정 비용 — 1번째는 무료(0), 2번째부터 캔디 차감.
    private var idleRevisionCost: Int {
        idleRevisionsUsed == 0 ? 0 : GenerationQuota.cost(forQuality: quality)
    }

    /// 1단계 결과(idle) 승인 게이트 — 이 모습을 기준으로 나머지를 만들지 확인.
    @ViewBuilder
    private var idleApprovalSection: some View {
        if awaitingIdleApproval, let rev = revisedDone[.idle] {
            // 기준 모습 수정 결과 — 다른 수정과 똑같이 전후 비교 후 적용 선택.
            idleRevisionCompareSection(rev)
        } else if awaitingIdleApproval, let idle = results[.idle] {
            // 내용을 한 행(VStack)으로 묶어 행마다 들쭉날쭉한 구분선 없이 한 섹션처럼.
            Section {
                VStack(spacing: 14) {
                    Image(uiImage: idle)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 280)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Text("먼저 만든 '기본' 모습이에요. 이 모습을 기준으로 나머지를 일관되게 만들어요.")
                        .font(.pretendard(12, relativeTo: .caption)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        pendingAction = .approveRest
                    } label: {
                        Text("이 모습으로 나머지 만들기").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WithuCTAButtonStyle())
                    .disabled(isGenerating)

                    idleRefineGroup(label: "다듬기")

                    Button {
                        awaitingIdleApproval = false
                        results.removeAll()
                        resultsFrame1.removeAll()
                        frame0FullRes.removeAll()
                        idleFullRes = nil
                        idleAnchor = nil
                        idleRevisionText = ""
                        errors.removeAll()
                    } label: {
                        Label("처음부터 다시 만들기", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless).tint(.secondary)
                    .disabled(isGenerating)
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            } header: {
                Text("기준 모습 확인")
                    .font(.pretendardBold(16, relativeTo: .callout))
            }
        }
    }

    /// 기준 모습 '다듬기' 입력+버튼을 한 카드로 묶은 그룹 (승인/이력 양쪽에서 재사용).
    /// label: 첫 다듬기 = "다듬기", 이력에서 이어갈 땐 = "이어서 다듬기".
    private func idleRefineGroup(label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $idleRevisionText)
                .frame(minHeight: 80)
                .font(.pretendard(16, relativeTo: .callout))
                .disabled(isGenerating)
                .overlay(alignment: .topLeading) {
                    if idleRevisionText.isEmpty {
                        Text("수정사항을 입력해 주세요")
                            .font(.pretendard(16, relativeTo: .callout))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8).padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .pixelInputField()
            PixelActionButton(
                title: label,
                note: idleRevisionCost == 0 ? String(localized: "무료")
                                            : String(localized: "캔디 \(idleRevisionCost)개"),
                isBusy: isGenerating,
                isEnabled: !idleRevisionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                pendingAction = .reviseIdle
            }
        }
        .padding(12)
        .plainFrostedCard(cornerRadius: 12)
    }

    /// 기준 모습 다듬기 결과 — 한 행으로 묶어(구분선 없이) 원본/다듬음 N 스트립 + 이어서 다듬기 + 적용/취소.
    private func idleRevisionCompareSection(_ rev: BatchRevision) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 14) {
                Image(uiImage: rev.current).resizable().scaledToFit()
                    .frame(maxHeight: 280).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                revisionStrip(.idle, rev)

                idleRefineGroup(label: "이어서 다듬기")

                HStack {
                    Button("적용") { acceptRevision(.idle) }
                        .font(.pretendard(16, relativeTo: .callout)).tint(Color.withuCTAGreen)
                    Spacer()
                    Button("취소") { rejectRevision(.idle) }
                        .font(.pretendard(16, relativeTo: .callout)).tint(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .plainCard()
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        } header: {
            Text("다듬기 이력")
                .font(.pretendardBold(16, relativeTo: .callout))
        }
    }

    /// 전체 참고 사진 또는 상태별 참고 사진이 하나라도 있는지.
    private var hasAnyReferenceImage: Bool {
        referenceImage != nil
    }

    private var startSection: some View {
        let need = requiredCount * GenerationQuota.cost(forQuality: quality)
        return Section {
            Button {
                pendingAction = .start        // 캔디 안내 팝업 → 확인 시 실행
            } label: {
                if isGenerating {
                    HStack {
                        ProgressView()
                        Text("만드는 중… \(progressDone)/\(requiredCount)")
                    }
                } else {
                    Text("만들기 시작")
                }
            }
            .buttonStyle(WithuCTAButtonStyle())
            // 참고 사진이 있으면 설명 없이도 만들 수 있다 (하나씩 만들기와 동일 규칙).
            // 프롬프트 조립도 빈 설명을 이미 처리함 — desc.isEmpty 면 상태 포즈만 사용.
            .disabled(isGenerating || selectedStates.isEmpty
                      || (baseIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          && !hasAnyReferenceImage)
                      || remainingGenerations < need)

            if isGenerating {
                Text("앱을 닫거나 화면을 꺼도 계속 만들어요. 다 되면 알림으로 알려드려요. (\(progressDone)/\(requiredCount) 완료)")
                    .font(.pretendard(13, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    batchTask?.cancel()
                    batchTask = nil
                    didCancel = true
                    genManager.cancelAll()
                } label: {
                    Label("그만두기", systemImage: "stop.circle.fill")
                }
                .tint(.secondary)
            } else if remainingGenerations < need {
                Text("캔디 \(remainingGenerations)개로는 \(selectedStates.count)개 상태(약 \(need)캔디)를 한 번에 만들 수 없어요. 만들 상태를 줄이거나 캔디를 충전해 주세요.")
                    .font(.pretendard(13, relativeTo: .footnote))
                    .foregroundStyle(.orange)
                Button {
                    showPaywall = true
                } label: {
                    Label("더 만들기 (구독·충전)", systemImage: "sparkles")
                }
                .tint(.withuPink)
            } else if baseIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && !hasAnyReferenceImage {
                // 왜 못 누르는지 알려준다 — 버튼만 비활성이면 이유를 모름.
                Text("캐릭터 프롬프트를 적거나 참고 사진을 넣어 주세요.")
                    .font(.pretendard(13, relativeTo: .footnote))
                    .foregroundStyle(.orange)
            } else {
                Text("보유 캔디 \(remainingGenerations)개 · \(need)캔디 소모")
                    .font(.pretendard(13, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var resultsSection: some View {
        Section(header: Text("만들어진 모습").font(.pretendardBold(16, relativeTo: .callout))) {
            // LazyVGrid 는 Form 섹션 안에서 높이 계산이 어긋나 아래가 잘림 → 수동 2열 그리드.
            // 생성 중이면 사용자가 고른 모든 상태를 미리 placeholder 로 — '기본만 만들어진다'는 착각 방지.
            let shown = CharacterState.allCases.filter {
                displayedImage(for: $0) != nil || errors[$0] != nil || loadingFrame0.contains($0)
                    || (isGenerating && selectedStates.contains($0))
            }
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
                // 모두 적용 — 완성된 모습 전부 홈/위젯/워치에 반영.
                // 아직 만드는 중이면 다 된 것 같은 착각을 줘서 버튼은 두되 비활성화만.
                Button {
                    applyAll()
                } label: {
                    Label("모두 적용하기 (\(results.count)개)", systemImage: "square.and.arrow.down.on.square.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WithuCTAButtonStyle())
                .disabled(isGenerating)

                // 배경 미리보기 토글 — 홈/워치엔 아직 반영 안 하고 그리드 표시만 바꾼다.
                // Form 한 행에 버튼이 둘이면 행 아무 데나 눌러도 둘 다 실행됨 —
                // .borderless 로 각 버튼이 자기 탭만 받게 함.
                HStack(spacing: 12) {
                    Button {
                        previewTransparentAll()
                    } label: {
                        Label("배경 모두 지우기", systemImage: "wand.and.sparkles")
                    }
                    .buttonStyle(.borderless)
                    .tint(.secondary)
                    Spacer()
                    Button {
                        previewWhiteAll()
                    } label: {
                        Label("배경 복원", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .tint(.secondary)
                }
                .font(.pretendard(16, relativeTo: .callout))

                Button {
                    Task { await saveAllToPhotos() }
                } label: {
                    if isSavingPhotos {
                        HStack {
                            ProgressView()
                            Text("저장하는 중…")
                        }
                    } else {
                        Label("사진 앱에 모두 저장 (\(results.count + resultsFrame1.count)장)",
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
        } else if loadingFrame0.contains(state) {
            loadingCard(state: state)
        } else if let err = errors[state] {
            errorCard(state: state, error: err)
        } else if isGenerating && selectedStates.contains(state) {
            // 아직 차례가 안 온 선택 상태 — '기본만 만들어진다'는 착각 방지용 대기 placeholder.
            waitingCard(state: state)
        }
    }

    /// 아직 생성이 시작 안 된(차례 대기) 선택 상태 placeholder.
    private func waitingCard(state: CharacterState) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.07))
                .frame(height: 120)
                .overlay(
                    Image(systemName: "hourglass")
                        .foregroundStyle(.tertiary)
                        .font(.pretendard(20, relativeTo: .title3))
                )
            HStack {
                Text(state.koreanShortLabel).font(.pretendard(12, relativeTo: .caption)).lineLimit(1)
                Spacer()
            }
            Text("차례 기다리는 중").font(.pretendard(11, relativeTo: .caption2)).foregroundStyle(.secondary)
        }
    }

    /// 기본(frame0) 생성 중인 상태의 placeholder — 다 됐는지 헷갈리지 않게 로딩을 명시.
    private func loadingCard(state: CharacterState) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.10))
                .frame(height: 120)
                .overlay(
                    VStack(spacing: 8) {
                        ProgressView()
                        if let started = stateStartedAt[state] {
                            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                                Text("\(Int(ctx.date.timeIntervalSince(started)))초")
                                    .font(.pretendard(11, relativeTo: .caption2)).foregroundStyle(.secondary)
                            }
                        }
                    }
                )
            HStack {
                Text(state.koreanShortLabel).font(.pretendard(12, relativeTo: .caption)).lineLimit(1)
                Spacer()
            }
            Text("만드는 중…").font(.pretendard(11, relativeTo: .caption2)).foregroundStyle(.secondary)
        }
    }

    /// per-state 현재 표시 이미지 — toggle 따라.
    private func displayedImage(for state: CharacterState) -> UIImage? {
        displayedImage(for: state, frame: 0)
    }

    /// 프레임별 표시 이미지 — raw=투명(모델 출력). '배경 빼기'=투명 원본, '흰 배경'=즉시 흰색 합성(Vision 없음).
    private func displayedImage(for state: CharacterState, frame: Int) -> UIImage? {
        let raw = frame == 1 ? resultsFrame1[state] : results[state]
        guard let raw else { return nil }
        let useTransparent = displayTransparentByState[state] ?? true
        return useTransparent ? raw : ImageProcessing.flattenedOnWhite(raw)
    }

    /// 이 상태를 홈/위젯/워치에 적용 — 활성 슬롯 쓰기 + 워치 전송 + 위젯 reload.
    /// (배치 생성은 갤러리에만 저장되므로, 실제 반영은 이 버튼을 눌러야 일어남.)
    @MainActor
    private func applyOne(_ state: CharacterState) {
        guard let img0 = displayedImage(for: state, frame: 0) else { return }
        // 만들 때 지은 이름을 '내 캐릭터' 이름으로 반영 (적용 시점에만).
        CharacterProfileStore.syncName(characterName)
        // 갤러리 '적용 중'(초록 점) 표시는 활성 소스 맵을 본다 —
        // 배치는 픽셀만 덮어써서(saveActiveSlotOnly) 맵이 옛 항목을 가리킨 채 남았다.
        if let gid = CharacterImageStore.latestGalleryId(state: state, batchId: batchSessionId) {
            CharacterImageStore.markActiveSource(state: state, galleryId: gid)
        }
        CharacterImageStore.saveActiveSlotOnly(img0, for: state, frame: 0)   // stale frame1 정리됨
        ConnectivityManager.shared.sendCharacterImage(img0, for: state, frame: 0)
        if let img1 = displayedImage(for: state, frame: 1) {
            CharacterImageStore.saveActiveSlotOnly(img1, for: state, frame: 1)
            ConnectivityManager.shared.sendCharacterImage(img1, for: state, frame: 1)
        }
        WidgetCenter.shared.reloadAllTimelines()
        appliedStates.insert(state)
    }

    /// 완성된 모든 상태 적용.
    @MainActor
    private func applyAll() {
        for state in CharacterState.allCases where results[state] != nil {
            applyOne(state)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// bulk — 모든 모습을 '배경 빼기(투명)' 미리보기로만. 홈/위젯/워치엔 아직 반영 안 함
    /// (실제 반영은 '모두 적용하기' 또는 카드별 '적용'). 눌린 걸 알 수 있게 햅틱 + 힌트.
    @MainActor
    private func previewTransparentAll() {
        for state in CharacterState.allCases where results[state] != nil {
            displayTransparentByState[state] = true
            appliedStates.remove(state)   // 미리보기가 적용본과 달라짐 → 카드에 '적용' 다시 뜨게
        }
        UISelectionFeedbackGenerator().selectionChanged()
        flashBgToast()
    }

    /// 한 모습만 배경 미리보기 토글 — on=투명, off=흰 배경. 홈/워치엔 아직 반영 안 함
    /// (카드 '적용' 또는 '모두 적용하기'로 반영). 벌크 토글과 동작을 일치시킴.
    @MainActor
    private func previewTransparentOne(_ state: CharacterState, on: Bool) {
        guard results[state] != nil else { return }
        displayTransparentByState[state] = on
        appliedStates.remove(state)
        flashBgToast()
    }

    /// bulk — 모든 모습을 '흰 배경' 미리보기로만. 홈/위젯/워치엔 아직 반영 안 함.
    @MainActor
    private func previewWhiteAll() {
        for state in CharacterState.allCases where results[state] != nil {
            displayTransparentByState[state] = false
            appliedStates.remove(state)
        }
        UISelectionFeedbackGenerator().selectionChanged()
        flashBgToast()
    }

    /// 배경 미리보기 변경 토스트 — 잠깐 떴다 자기 혼자 사라짐. 마지막 탭 기준으로만 닫는다.
    @MainActor
    private func flashBgToast() {
        bgToastToken += 1
        let token = bgToastToken
        withAnimation { bgToastVisible = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if bgToastToken == token { withAnimation { bgToastVisible = false } }
        }
    }

    /// 카드 오른쪽 상단 '바꾸기' 배지 — 진행 중이면 로딩, 완료 후 적용 전이면 '수정 완료'.
    @ViewBuilder
    private func revisionBadge(_ state: CharacterState) -> some View {
        if revisingFrame[state] != nil {
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.55).tint(.white)
                Text("다듬는 중").font(.pretendard(11, relativeTo: .caption2))
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.55)))
            .foregroundStyle(.white)
            .padding(6)
        } else if revisedDone[state] != nil {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                Text("다듬음").font(.pretendard(11, relativeTo: .caption2))
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Capsule().fill(Color.withuCTAGreen))
            .foregroundStyle(.white)
            .padding(6)
        }
    }

    private func resultCard(state: CharacterState, image: UIImage) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Image(uiImage: image).resizable().scaledToFit().frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    // '바꾸기' 진행/완료 상태 — 오른쪽 상단 배지.
                    .overlay(alignment: .topTrailing) { revisionBadge(state) }
                // 연속 이미지 ON 일 때 frame 1 우하단 미니. 메인 화면이 0.7s 간격으로 swap.
                if revisingFrame[state] == 1 {
                    // 움직임 프레임을 '바꾸기' 로 다시 만드는 중 — 미니에 로딩.
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.withuCTAGreen.opacity(0.15))
                        .frame(width: 40, height: 40)
                        .overlay(ProgressView().scaleEffect(0.7).tint(Color.withuCTAGreen))
                        .padding(6)
                } else if let f1 = resultsFrame1[state] {
                    Image(uiImage: f1)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white, lineWidth: 2))
                        .padding(6)
                } else if pendingFrame1.contains(state) {
                    // 움직임 프레임 생성 중 — 다 됐다고 오해하지 않게 로딩 표시.
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.withuCTAGreen.opacity(0.15))
                        .frame(width: 40, height: 40)
                        .overlay(ProgressView().scaleEffect(0.7).tint(Color.withuCTAGreen))
                        .padding(6)
                } else if failedFrame1[state] != nil {
                    // 움직임 프레임만 실패 — 눌러서 다시 시도.
                    Button {
                        Task { await retryFrame1(state) }
                    } label: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.orange.opacity(0.18))
                            .frame(width: 40, height: 40)
                            .overlay(Image(systemName: "arrow.clockwise")
                                .foregroundStyle(.orange).font(.pretendard(12, relativeTo: .caption)))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {   // 이미지 탭 → 자세히 보기(수정/저장)
                selectedResult = (state, image)
                revisionText = ""
                revisionError = nil
                detailFrame = 0
            }
            HStack {
                Text(state.koreanShortLabel).font(.pretendard(12, relativeTo: .caption)).lineLimit(1)
                Spacer()
                if appliedStates.contains(state) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.pretendard(12, relativeTo: .caption))
                }
            }
            // 이 모습만 적용
            Button { applyOne(state) } label: {
                Text(appliedStates.contains(state) ? String(localized: "적용됨") : String(localized: "적용"))
                    .font(.pretendard(12, relativeTo: .caption))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(appliedStates.contains(state) ? .secondary : .withuPink)
        }
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
                                .foregroundStyle(.orange).font(.pretendard(28, relativeTo: .title))
                            Text("눌러서 다시 만들기")
                                .font(.pretendard(11, relativeTo: .caption2)).foregroundStyle(.orange)
                        }
                    )
                HStack {
                    Text(state.koreanShortLabel).font(.pretendard(12, relativeTo: .caption)).lineLimit(1)
                    Spacer()
                }
                Text(error)
                    .font(.pretendard(11, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .disabled(inProgressStates.contains(state))
    }

    // MARK: - Actions

    /// 사용자가 넣은 '참고 사진'(전체) base64. idle 앵커는 제외.
    /// startBatch / retryOne 양쪽에서 사용.
    private func resolveUserReference(for state: CharacterState) -> String? {
        referenceImage?.pngData()?.base64EncodedString()
    }

    /// 승인된 idle 앵커 base64 — 나머지 상태의 일관성 기준. 앱 재시작 후엔 디스크에서 복구.
    private func anchorReferenceB64() -> String? {
        (idleAnchor ?? genManager.loadFrame0FullRes(.idle) ?? results[.idle])?
            .pngData()?.base64EncodedString()
    }

    /// 참고사진 '그대로 둘 것' — 사용자 참고사진이 실제로 쓰일 때만(idle 앵커엔 미적용).
    private func userRefKeep(for state: CharacterState) -> String {
        guard referenceImage != nil else { return "" }
        return referenceKeep.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 참고사진 '바꿀 것' — 모든 상태의 포즈에 더해 적용. 사용자 참고사진 쓸 때만.
    private func userRefChange(for state: CharacterState) -> String {
        guard referenceImage != nil else { return "" }
        return referenceChange.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 1단계 — idle 을 먼저 만들어 앵커로 삼고, 사용자 승인을 기다린다.
    /// 생성은 BackgroundGenerationManager (background URLSession) 가 실행 —
    /// 화면을 끄거나 앱을 나가도 계속되고, 결과는 onChange(tick) 로 동기화된다.
    private func startBatch() async {
        isGenerating = true
        batchSessionId = UUID().uuidString   // 새 일괄 세션 — 서버가 free_batch 로 묶음
        CharacterImageStore.setCharacterName(characterName, for: batchSessionId)  // 갤러리 '캐릭터별' 이름
        saveDescription()                    // 캐릭터 설명을 프로필에 저장 — 단건 생성과 공유
        results.removeAll()
        appliedStates.removeAll()
        resultsFrame1.removeAll()
        frame0FullRes.removeAll()
        transparentResults.removeAll()          // 이전 배치의 배경제거 캐시 잔존 방지
        transparentResultsFrame1.removeAll()
        displayTransparentByState.removeAll()
        errors.removeAll()
        inProgressStates.removeAll()
        stateStartedAt.removeAll()
        loadingFrame0.removeAll()
        pendingFrame1.removeAll()
        failedFrame1.removeAll()
        idleApproved = false
        idleRevisionsUsed = 0
        revisedDone.removeAll()
        PendingRevisionStore.clearAll()
        idleAnchor = nil
        idleFullRes = nil
        awaitingIdleApproval = false

        // 완료 알림 권한 — 처음 한 번만 시스템 시트가 뜸.
        await NotificationManager.shared.requestAuthorization()

        do {
            try await APIClient.shared.preflightPing()
        } catch {
            errors[.idle] = "서버에 연결할 수 없어요. 네트워크 또는 서버 상태를 확인하고 다시 시도해 주세요."
            isGenerating = false
            return
        }

        // idle 먼저 (앵커, frame 0). 사용자 참고사진이 있으면 그걸 reference 로.
        let idleRef = resolveUserReference(for: .idle)
        let spec = BackgroundGenJobSpec(
            state: .idle, frame: 0,
            prompt: buildPrompt(for: .idle, consistencyPrefix: idleRef != nil,
                                keepNote: userRefKeep(for: .idle),
                                changeNote: userRefChange(for: .idle), frame: 0),
            referenceB64: idleRef, frame0Reference: nil,
            wantsFrame1: false, frame1Prompt: nil)
        genManager.start(specs: [spec], quality: quality, artStyle: artStyle,
                         batchId: batchSessionId, phase: .anchor)
        syncFromManager()
    }

    /// 2단계 — 승인된 idle 을 앵커로 나머지 선택 상태(+애니메이션)를 백그라운드 생성.
    private func approveIdleAndContinue() async {
        // 연타 재진입 차단 — awaitingIdleApproval 을 await 전에 동기로 끔.
        guard awaitingIdleApproval,
              let idle = idleFullRes ?? genManager.loadFrame0FullRes(.idle) ?? results[.idle] else { return }
        awaitingIdleApproval = false
        idleApproved = true         // 재확인 트리거가 승인 후 되돌아오지 않게.
        idleAnchor = idle           // 원본(1024) 우선 — 일관성 reference 품질
        isGenerating = true
        let anchorB64 = idle.pngData()?.base64EncodedString()

        var specs: [BackgroundGenJobSpec] = []
        // idle 의 움직임(frame 1) — frame 0(앵커)을 reference 로.
        // (idle 은 usesGeneratedMotion=false 라 실제로는 안 들어옴 — 절차적 모션으로 애니메이션)
        if animatedStates.contains(.idle), CharacterState.idle.usesGeneratedMotion, let anchorB64 {
            specs.append(BackgroundGenJobSpec(
                state: .idle, frame: 1,
                prompt: buildPrompt(for: .idle, consistencyPrefix: true, frame: 1),
                referenceB64: anchorB64, frame0Reference: idle,
                wantsFrame1: false, frame1Prompt: nil))
        }
        // 나머지 선택 상태 (idle 제외) — 승인한 idle 앵커가 기준.
        // (전역 첨부사진·keep/change 는 idle 만들 때만 반영됨.)
        let rest = CharacterState.allCases.filter { selectedStates.contains($0) && $0 != .idle }
        for state in rest {
            let refB64 = anchorB64
            // 미세 모션 상태는 2프레임 생성 안 함 — 절차적 모션으로 애니메이션(색·이목구비 드리프트 방지)
            let animated = animatedStates.contains(state) && state.usesGeneratedMotion
            specs.append(BackgroundGenJobSpec(
                state: state, frame: 0,
                prompt: buildPrompt(for: state, consistencyPrefix: refB64 != nil, frame: 0),
                referenceB64: refB64, frame0Reference: nil,
                wantsFrame1: animated,
                frame1Prompt: animated ? buildPrompt(for: state, consistencyPrefix: true, frame: 1) : nil,
                // 앵커 기반이라 idle 색에 통일.
                matchIdleColor: true))
        }
        // 만들 게 없음 (idle 만 선택 + 움직임 없음) — 즉시 완료 처리.
        guard !specs.isEmpty else {
            isGenerating = false
            showFinishedAlert = true
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        genManager.start(specs: specs, quality: quality, artStyle: artStyle,
                         batchId: batchSessionId, phase: .rest)
        syncFromManager()
    }

    /// 매니저(백그라운드 큐)의 작업 상태를 뷰 상태로 동기화.
    private func syncFromManager() {
        var progress: Set<CharacterState> = []
        var started: [CharacterState: Date] = [:]
        var loadingF0: Set<CharacterState> = []
        var pendingF1: Set<CharacterState> = []
        var failedF1: [CharacterState: String] = [:]
        for job in genManager.jobs {
            guard let state = CharacterState(rawValue: job.stateRaw) else { continue }
            switch job.status {
            case .queued, .running:
                progress.insert(state)
                started[state] = job.startedAt ?? stateStartedAt[state] ?? Date()
                if job.frame == 1 { pendingF1.insert(state) }
                else { loadingF0.insert(state) }
            case .done:
                // done job 이미지는 '이 배치'의 실제 출력만 쓴다 — in-memory(images) 우선,
                // 앱 재시작으로 비었으면 bggen 에 저장된 이 배치의 frame0 원본.
                // 활성 슬롯(loadFrame)은 예전에 '적용'한 다른(전전) 배치일 수 있어 폴백에서 제외
                // — 안 그러면 재진입 시 전전 결과가 이번 결과인 척 그리드에 뜬다.
                let img = genManager.images["\(job.stateRaw)#\(job.frame)"]
                    ?? (job.frame == 0 ? genManager.loadFrame0FullRes(state) : nil)
                if let img {
                    if job.frame == 0 { results[state] = img }
                    else { resultsFrame1[state] = img }
                }
                if job.frame == 0 {
                    errors.removeValue(forKey: state)
                    if state == .idle, idleFullRes == nil {
                        idleFullRes = genManager.loadFrame0FullRes(.idle)
                    }
                } else {
                    failedF1.removeValue(forKey: state)
                }
            case .failed:
                // 움직임(frame1)만 실패한 건 별도로 — 기본 카드는 정상 표시하고 미니 슬롯에서 재시도.
                if job.frame == 1 {
                    failedF1[state] = job.errorMessage ?? "만들지 못했어요"
                } else {
                    errors[state] = job.errorMessage ?? "만들지 못했어요"
                }
            }
        }
        inProgressStates = progress
        stateStartedAt = started
        loadingFrame0 = loadingF0
        pendingFrame1 = pendingF1
        failedFrame1 = failedF1
        // 앵커(idle)는 rest 단계 작업 목록에 없음 — 이 배치의 bggen frame0 원본에서 복원.
        // (활성 슬롯은 전전 배치일 수 있어 마지막 수단으로만.)
        if !genManager.jobs.isEmpty, genManager.phase != .anchor, results[.idle] == nil {
            results[.idle] = genManager.loadFrame0FullRes(.idle)
                ?? CharacterImageStore.loadFrame(.idle, frame: 0)
        }
        isGenerating = genManager.isActive
        remainingGenerations = GenerationQuota.remainingToday()

        // 앵커(기본) 승인 대기 재확인 — 기본을 '다시 만들기'로 재시도하면 phase 가 .retry 로 바뀌어
        // 기존 트리거(phase==.anchor)를 놓쳐 '나머지 만들기' 버튼이 안 뜨던 버그 방지.
        // 아직 승인 전이고(나머지 생성 미시작), 작업이 idle 뿐이며, 기본이 나왔고, 생성 안 중이면 승인 대기.
        let onlyIdleJobs = !genManager.jobs.isEmpty
            && genManager.jobs.allSatisfy { $0.stateRaw == CharacterState.idle.rawValue }
        if !idleApproved, !awaitingIdleApproval, !genManager.isActive,
           onlyIdleJobs, results[.idle] != nil, errors[.idle] == nil {
            awaitingIdleApproval = true
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
        let pose = CharacterState.idle.generationHint
        let desc = baseIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = desc.isEmpty ? pose : "\(desc), \(pose)"
        let prompt = "\(base). User modification: \(trimmed). Transparent background — only the character, no background fill, no shadows."
        do {
            let req = GenerateImageRequest(prompt: prompt, referenceImageBase64: refB64,
                                           steps: 30, width: 1024, height: 1024,
                                           quality: quality, artStyle: artStyle, style: "auto",
                                           model: "gpt-image-2")
            let resp = try await APIClient.shared.generateImage(req, kind: "batch", batchId: batchSessionId)
            if let data = Data(base64Encoded: resp.imageBase64), let img = UIImage(data: data) {
                // gpt-image-2 마젠타 배경 → 크로마키 투명화 (투명 결과엔 no-op)
                let flat = await ImageProcessing.transparentized(img)
                let small = flat.preparingThumbnail(of: CGSize(width: 128, height: 128)) ?? flat
                // 즉시 덮어쓰지 않고 이력에 이어붙임 — 골라서 '적용'해야 기준 모습이 바뀜.
                appendRevision(state: .idle, frame: 0, small: small, full: flat, prompt: prompt)
                if let ent = resp.entitlement { AuthManager.shared.applyEntitlement(ent) }
                // 1번째 수정은 무료, 2번째부터 차감.
                if idleRevisionsUsed > 0 {
                    GenerationQuota.record(GenerationQuota.cost(forQuality: quality))
                }
                idleRevisionsUsed += 1
                idleRevisionText = ""
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

    /// 캐릭터 설명을 프로필에 저장 — 다음에 열어도 유지되고 단건 생성과 같은 설명을 씀.
    private func saveDescription() {
        var p = CharacterProfileStore.load()
        let trimmed = baseIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.aiPrompt != trimmed {
            p.aiPrompt = trimmed
            CharacterProfileStore.save(p)
        }
    }

    /// 실패한 카드 탭 시 재시도 — 백그라운드 큐에 다시 추가. 같은 prompt + reference 그대로.
    private func retryOne(_ state: CharacterState) async {
        // 이전 에러 표시 제거 + 진행 표시 시작
        errors.removeValue(forKey: state)
        // idle: 전역 첨부사진 + keep/change. 나머지: 승인한 idle 앵커 기준.
        let refB64: String?
        let keep: String, change: String
        let alignIdle: Bool
        if state == .idle {
            refB64 = resolveUserReference(for: .idle)
            keep = userRefKeep(for: .idle); change = userRefChange(for: .idle)
            alignIdle = false
        } else {
            refB64 = anchorReferenceB64()
            keep = ""; change = ""
            alignIdle = true   // 앵커 기반이라 idle 색에 통일
        }
        let spec = BackgroundGenJobSpec(
            state: state, frame: 0,
            prompt: buildPrompt(for: state, consistencyPrefix: refB64 != nil,
                                keepNote: keep, changeNote: change, frame: 0),
            referenceB64: refB64, frame0Reference: nil,
            wantsFrame1: false, frame1Prompt: nil, matchIdleColor: alignIdle)
        genManager.retry(spec: spec, quality: quality, artStyle: artStyle, batchId: batchSessionId)
        syncFromManager()
    }

    /// 움직임(frame1)만 실패했을 때 재시도 — 이미 있는 기본(frame0)을 reference 로 다시 만든다.
    /// frame0 실패와 달리 기본 카드는 정상이므로, 미니 슬롯의 재시도 버튼에서만 호출된다.
    @MainActor
    private func retryFrame1(_ state: CharacterState) async {
        guard let f0 = genManager.loadFrame0FullRes(state) ?? results[state] else { return }
        failedFrame1.removeValue(forKey: state)
        let refB64 = f0.pngData()?.base64EncodedString()
        let spec = BackgroundGenJobSpec(
            state: state, frame: 1,
            prompt: buildPrompt(for: state, consistencyPrefix: true, frame: 1),
            referenceB64: refB64, frame0Reference: f0,
            wantsFrame1: false, frame1Prompt: nil,
            matchIdleColor: state != .idle)
        genManager.retry(spec: spec, quality: quality, artStyle: artStyle, batchId: batchSessionId)
        syncFromManager()
    }

    /// 한 state 의 생성 프롬프트 조립 (기존 runOne 의 프롬프트 로직).
    /// frame == 0: 기본. frame == 1: 애니메이션용 (frame 0 을 reference 로 chain + 다른 포즈).
    private func buildPrompt(for state: CharacterState, consistencyPrefix: Bool,
                             keepNote: String = "", changeNote: String = "", frame: Int = 0) -> String {
        let pose = state.generationHint
        let desc = baseIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        let keepClause = keepNote.isEmpty ? "" : " Keep especially: \(keepNote)."
        // '바꿀 것'은 상태별 포즈에 '추가'로 적용 (포즈는 상태마다 다르므로 대체가 아니라 더함).
        let changeScene = changeNote.isEmpty ? pose : "\(pose), and also \(changeNote)"
        var prompt: String
        if frame == 1 {
            // frame1 — 캐릭터 디자인·크기·위치는 그대로, 포즈는 '확실히' 바뀌게.
            // (A 로 미세 모션 상태는 frame1 을 안 만드므로, frame1 은 항상 실제 포즈 변화용.
            //  예전 "tiny hint of life / do not change overall appearance" 문구가 다리 교체 같은
            //  큰 포즈 변화를 억눌러서 '말을 안 듣던' 문제를 해소.)
            prompt = "Use the reference image as the SAME character. Keep identical: face, outfit, colors, art/pixel style, line thickness, body proportions, size, scale, centered position, framing, and the flat solid white background. This is the SECOND frame of a 2-frame animation loop, so the POSE MUST visibly CHANGE from the reference. Change the pose to: \(state.animationFrame2Hint). Change ONLY the pose — keep every design detail and the placement identical to the reference."
        } else if consistencyPrefix {
            // frame0 + 참고(idle 앵커 또는 사용자 사진) — Keep=캐릭터 전부, Change=이 state 의 포즈/장면(+바꿀것).
            let charNote = desc.isEmpty ? "" : " The character is: \(desc)."
            prompt = "Use the reference image. Keep the EXACT same character — identity, face and expression style, body proportions, art style, colors and shading, line thickness, and every design detail.\(charNote)\(keepClause) Change ONLY: \(changeScene). Do not change the character design; keep all other visual details identical to the reference."
        } else {
            // frame0, 참고 없음 (보통 idle 최초 생성) — 설명 + 포즈 (+바꿀것).
            let base = desc.isEmpty ? pose : "\(desc), \(pose)"
            prompt = changeNote.isEmpty ? base : "\(base), \(changeNote)"
        }
        // AI 에 흰 배경 강제 — 사용자가 post-gen 에 Vision 으로 정제 가능.
        // 격자(체커보드) 방지: "투명"을 격자로 그리는 모델 대비 단색 흰배경 명시.
        prompt += ". Transparent background — only the character, no background fill, no shadows."
        return prompt
    }

    /// 상세 시트에 저장(생성) 안 한 수정 입력이 있는지.
    private var reviseHasChanges: Bool {
        !revisionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 결과 카드 탭 시 열리는 sheet — 프레임 페이지(좌우 스와이프) + 저장 / 수정
    @ViewBuilder
    private func resultDetailSheet(state: CharacterState) -> some View {
        let hasF1 = resultsFrame1[state] != nil
        NavigationStack {
            if let rev = revisedDone[state] {
                revisionCompareView(state, rev)
            } else {
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
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 320)

                    // 페이지 점 — 이미지 위 대신 아래에 별도로.
                    if hasF1 {
                        HStack(spacing: 8) {
                            ForEach(0..<2, id: \.self) { i in
                                Circle()
                                    .fill(detailFrame == i ? Color.primary : Color.secondary.opacity(0.3))
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }

                    Text(hasF1
                         ? "\(state.koreanShortLabel) · \(detailFrame == 1 ? String(localized: "움직임 프레임") : String(localized: "기본"))"
                         : state.koreanShortLabel)
                        .font(.pretendard(16, relativeTo: .callout))

                    // 이 모습만 배경 토글 (개별)
                    Picker("배경", selection: Binding(
                        get: { displayTransparentByState[state] ?? true },
                        set: { on in previewTransparentOne(state, on: on) }
                    )) {
                        Text("흰 배경").tag(false)
                        Text("배경 빼기").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // 연속 이미지(2장)일 때만 — 프레임 순서 바꾸기 + 움직임 켜기/끄기
                    if hasF1 {
                        HStack(spacing: 12) {
                            Button {
                                let tmp = results[state]
                                results[state] = resultsFrame1[state]
                                resultsFrame1[state] = tmp
                                if appliedStates.contains(state) { applyOne(state) }
                            } label: {
                                Label("프레임 바꾸기", systemImage: "arrow.left.arrow.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered).tint(.secondary).controlSize(.small)

                            Toggle("움직임", isOn: Binding(
                                get: { !CharacterImageStore.isAnimationDisabled(for: state) },
                                set: { on in
                                    CharacterImageStore.setAnimationDisabled(!on, for: state)
                                    WidgetCenter.shared.reloadAllTimelines()
                                }
                            ))
                            .labelsHidden()
                            .fixedSize()
                        }
                        .padding(.horizontal)
                    }

                    // 다듬기 — 하나씩 만들기의 다듬기와 같은 형식(넓은 입력칸 + 우하단 픽셀 버튼).
                    VStack(alignment: .leading, spacing: 10) {
                        Text("다듬기")
                            .font(.pretendard(15, relativeTo: .subheadline)).foregroundStyle(.primary)
                        TextEditor(text: $revisionText)
                            .frame(minHeight: 80)
                            .font(.pretendard(16, relativeTo: .callout))
                            .overlay(alignment: .topLeading) {
                                if revisionText.isEmpty {
                                    Text("수정사항을 입력해 주세요")
                                        .font(.pretendard(16, relativeTo: .callout))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8).padding(.leading, 5)
                                        .allowsHitTesting(false)
                                }
                            }
                            .pixelInputField()
                        PixelActionButton(
                            title: "다듬기",
                            note: String(localized: "캔디 \(GenerationQuota.cost(forQuality: quality))개"),
                            isBusy: isRevising,
                            isEnabled: !revisionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ) {
                            pendingReviseConfirm = true
                        }
                    }
                    .padding(14)
                    .plainFrostedCard()
                    .padding(.horizontal)

                    // 저장은 아이보리 픽셀 아이콘 버튼 — 하나씩 만들기 결과와 같은 형식.
                    HStack {
                        Spacer()
                        PixelIconButton(systemImage: "square.and.arrow.down",
                                        accessibilityTitle: "사진 앱에 저장") {
                            let img = displayedImage(for: state, frame: hasF1 ? detailFrame : 0)
                                ?? results[state] ?? UIImage()
                            Task { await saveOneToPhotos(img) }
                        }
                    }
                    .padding(.horizontal)

                    if let revisionError {
                        Text(revisionError)
                            .font(.pretendard(12, relativeTo: .caption))
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("자세히 보기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        if reviseHasChanges { showReviseDiscardConfirm = true } else { selectedResult = nil }
                    }
                }
            }
            // 입력한 수정 문구/사진이 있으면 스와이프로도 못 닫게 + 닫기 시 경고.
            .interactiveDismissDisabled(reviseHasChanges)
            .confirmationDialog("입력한 다듬기 내용이 있어요",
                                isPresented: $showReviseDiscardConfirm, titleVisibility: .visible) {
                Button("닫기", role: .destructive) { selectedResult = nil }
                Button("계속 편집", role: .cancel) {}
            } message: {
                Text("닫으면 방금 입력한 다듬기 문구가 지워져요.")
            }
            // 캔디 소모 확인 — 시트 위에 떠야 해서 시트 로컬 alert.
            .alert("캔디를 사용해요", isPresented: $pendingReviseConfirm) {
                Button("다듬기") {
                    Task { await reviseOne(state, frame: hasF1 ? detailFrame : 0, text: revisionText) }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("이번 다듬기에 캔디 \(GenerationQuota.cost(forQuality: quality))개를 써요. 성공했을 때만 차감돼요.")
            }
            }
        }
    }

    /// 다듬기 이력 — 고른 버전 크게 + 원본/다듬음 N 스트립 + 이어서 다듬기 + 적용/취소.
    /// (하나씩 만들기와 같은 이력 모델. 취소 아니면 닫아도 카드 '다듬음'으로 남아 재열람.)
    @ViewBuilder
    private func revisionCompareView(_ state: CharacterState, _ rev: BatchRevision) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial)
                    Image(uiImage: rev.current).resizable().scaledToFit().padding(12)
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxHeight: 320)
                .padding(.horizontal)

                revisionStrip(state, rev)

                // 이어서 다듬기 — 고른 버전 기준으로 한 번 더.
                VStack(alignment: .leading, spacing: 8) {
                    TextField("수정사항을 입력해 주세요", text: $revisionText, axis: .vertical)
                        .font(.pretendard(13, relativeTo: .footnote)).lineLimit(2...4)
                        .pixelInputField()
                    PixelActionButton(
                        title: "이어서 다듬기",
                        note: String(localized: "캔디 \(GenerationQuota.cost(forQuality: quality))개"),
                        isBusy: isRevising,
                        isEnabled: !revisionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        Task { await reviseOne(state, frame: rev.frame, text: revisionText) }
                    }
                }
                .padding(14).plainFrostedCard().padding(.horizontal)

                HStack {
                    Button("적용") { acceptRevision(state) }
                        .font(.pretendard(16, relativeTo: .callout)).tint(Color.withuCTAGreen)
                    Spacer()
                    Button("취소") { rejectRevision(state) }
                        .font(.pretendard(16, relativeTo: .callout)).tint(.secondary)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("다듬기 이력")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("닫기") { selectedResult = nil }
            }
        }
    }

    /// 원본/다듬음 N 버전 스트립 — 탭해서 고른 버전이 적용·이어서 다듬기 기준.
    private func revisionStrip(_ state: CharacterState, _ rev: BatchRevision) -> some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(rev.versions.enumerated()), id: \.offset) { idx, img in
                        VStack(spacing: 4) {
                            Image(uiImage: img).resizable().scaledToFit()
                                .frame(width: 68, height: 68)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(idx == rev.selected ? Color.withuCTAGreen : .clear, lineWidth: 2.5)
                                }
                            Text(idx == 0 ? String(localized: "원본") : String(localized: "다듬음 \(idx)"))
                                .font(.pretendard(11, relativeTo: .caption2))
                                .foregroundStyle(idx == rev.selected ? Color.withuCTAGreen : .secondary)
                        }
                        .onTapGesture { selectRevisionVersion(state, idx) }
                    }
                }
                .padding(.horizontal)
            }
            if rev.versions.count > 1 {
                Text("선택한 버전을 기준으로 다듬어요.")
                    .font(.pretendard(11, relativeTo: .caption2)).foregroundStyle(.secondary)
            }
        }
    }

    /// 단일 이미지를 사진 앱에 저장 (add-only 권한).
    private func saveOneToPhotos(_ image: UIImage) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveResultMessage = "사진 추가 권한이 거부됐어요. 설정 → Withy 에서 허용해 주세요."
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
        revisionError = nil
        let cost = GenerationQuota.cost(forQuality: quality)
        guard GenerationQuota.canGenerate(cost) else {
            showPaywall = true
            return
        }
        isRevising = true
        defer { isRevising = false }

        // 다듬기 참고는 1024 원본으로 — 128 썸네일을 반복 참고하면 화질이 계속 떨어진다.
        // 이력이 있으면 고른 버전의 1024, 없으면 이 상태의 frame0 원본.
        let anchor: UIImage?
        if let chain = revisedDone[state], chain.frame == frame {
            anchor = frame == 1 ? chain.current : chain.currentFull
        } else {
            anchor = frame == 1 ? (results[state] ?? resultsFrame1[state])
                                : (frame0FullRes[state] ?? genManager.loadFrame0FullRes(state) ?? results[state])
        }
        let refB64 = anchor?.pngData()?.base64EncodedString()
        let pose = state.generationHint
        let desc = baseIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        let basePrompt = desc.isEmpty ? pose : "\(desc), \(pose)"
        var modifiedPrompt = "\(basePrompt). User modification: \(trimmed)"
        if frame == 1 {
            modifiedPrompt += ". Animation frame 2 (for a 2-frame swap loop): \(state.animationFrame2Hint). CRITICAL: keep the character at the EXACT same size, scale, and centered position as the reference image; only the pose changes."
        }
        modifiedPrompt += ". Transparent background — only the character, no shadows."

        inProgressStates.insert(state)
        stateStartedAt[state] = .now
        revisingFrame[state] = frame          // 시트를 닫아도 이 프레임 카드에 로딩 표시
        defer {
            inProgressStates.remove(state)
            stateStartedAt.removeValue(forKey: state)
            revisingFrame.removeValue(forKey: state)
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
                style: "auto",
                model: "gpt-image-2"
            )
            let resp = try await APIClient.shared.generateImage(req)
            if let data = Data(base64Encoded: resp.imageBase64),
               let rawImg = UIImage(data: data) {
                // gpt-image-2 마젠타 배경 → 크로마키 투명화 (투명 결과엔 no-op)
                let img = await ImageProcessing.transparentized(rawImg)
                // frame1: 1번째 기준으로 크기·위치·흰배경 강제. frame0: 흰배경 평탄화.
                let ref0: UIImage? = frame == 1
                    ? (frame0FullRes[state] ?? genManager.loadFrame0FullRes(state) ?? results[state])
                    : nil
                let flat: UIImage
                if let ref0 {
                    flat = await ImageProcessing.matchedToReference(img, reference: ref0)
                } else {
                    flat = img
                }
                var small = flat.preparingThumbnail(of: CGSize(width: 128, height: 128)) ?? flat
                // frame1 색 드리프트 제거 — frame0 색에 맞춤
                if let ref0, let ref0Small = ref0.preparingThumbnail(of: CGSize(width: 128, height: 128)) {
                    small = ImageProcessing.colorMatched(small, reference: ref0Small)
                }
                // 즉시 덮어쓰지 않고 버전 이력에 이어붙임 — 상세 시트에서 골라 '적용'해야 반영.
                appendRevision(state: state, frame: frame, small: small, full: flat, prompt: modifiedPrompt)
                if let ent = resp.entitlement { AuthManager.shared.applyEntitlement(ent) }
                GenerationQuota.record(cost)   // 바꾸기도 실제 생성 — 캔디 차감
                remainingGenerations = GenerationQuota.remainingToday()
                revisionText = ""
            } else {
                revisionError = String(localized: "이미지를 받지 못했어요. 다시 시도해 주세요.")
            }
        } catch APIError.paymentRequired {
            showPaywall = true
        } catch {
            revisionError = error.koreanizedDescription
        }
    }

    /// 다듬기 결과를 버전 이력에 이어붙임 — 없으면 [원본, 새버전], 있으면 append. 저장까지.
    @MainActor
    private func appendRevision(state: CharacterState, frame: Int, small: UIImage, full: UIImage, prompt: String) {
        if var chain = revisedDone[state], chain.frame == frame {
            chain.versions.append(small)
            chain.fullVersions.append(full)
            if chain.versions.count > 8 { chain.versions.remove(at: 1); chain.fullVersions.remove(at: 1) }
            chain.selected = chain.versions.count - 1
            chain.prompt = prompt
            revisedDone[state] = chain
        } else {
            let before = (frame == 1 ? resultsFrame1[state] : results[state]) ?? small
            let beforeFull = frame == 1 ? before : (frame0FullRes[state] ?? results[state] ?? small)
            revisedDone[state] = BatchRevision(frame: frame, versions: [before, small],
                                               fullVersions: [beforeFull, full], selected: 1, prompt: prompt)
        }
        if let chain = revisedDone[state] {
            PendingRevisionStore.save(state: state, chain: chain)
        }
    }

    /// 스트립에서 버전 선택.
    @MainActor
    private func selectRevisionVersion(_ state: CharacterState, _ idx: Int) {
        guard var chain = revisedDone[state], chain.versions.indices.contains(idx) else { return }
        chain.selected = idx
        revisedDone[state] = chain
        PendingRevisionStore.save(state: state, chain: chain)
    }

    /// 이력에서 고른 버전으로 적용 — 이때 처음으로 결과를 교체하고 갤러리에 저장.
    @MainActor
    private func acceptRevision(_ state: CharacterState) {
        guard let rev = revisedDone[state] else { return }
        // 원본([0])을 고른 채 적용하면 바꿀 게 없음.
        if rev.selected != 0 {
            if rev.frame == 1 {
                resultsFrame1[state] = rev.current
                transparentResultsFrame1[state] = nil
            } else {
                results[state] = rev.current
                frame0FullRes[state] = rev.currentFull
                if state == .idle { idleFullRes = rev.currentFull }
                transparentResults[state] = nil
            }
            displayTransparentByState[state] = false
            CharacterImageStore.save(rev.current, for: state, frame: rev.frame, applyToActiveSlot: false,
                                     batchId: batchSessionId, prompt: rev.prompt)
            if state == .idle {
                appliedStates.remove(state)   // idle 은 앵커 — 홈/워치 반영은 나머지 만들기 단계에서.
            } else {
                applyOne(state)               // '적용' = 이 사진으로 바꿔 홈/워치에 바로 반영.
            }
        }
        revisedDone.removeValue(forKey: state)
        PendingRevisionStore.remove(state: state)
        selectedResult = nil          // 그리드로 — 바뀐 게 보이게
    }

    /// 이력 버리고 원래 결과 유지.
    @MainActor
    private func rejectRevision(_ state: CharacterState) {
        revisedDone.removeValue(forKey: state)
        PendingRevisionStore.remove(state: state)
        selectedResult = nil
    }

    /// 완전히 나갔다 온 뒤 저장된 다듬기 이력 복원 — 카드 '다듬음'/기준 모습 이력이 다시 뜨게.
    @MainActor
    private func restorePendingRevisions() {
        for r in PendingRevisionStore.loadAll() where revisedDone[r.state] == nil {
            revisedDone[r.state] = BatchRevision(frame: r.frame, versions: r.versions,
                                                 fullVersions: r.fullVersions, selected: r.selected, prompt: r.prompt)
        }
        // 기준 모습을 이미 다듬었으면 무료 1회는 쓴 것 — 재진입해도 '무료'로 잘못 뜨지 않게 복원.
        if let idle = revisedDone[.idle] {
            idleRevisionsUsed = max(idleRevisionsUsed, idle.versions.count - 1)
        }
    }

    /// 결과 이미지들을 사진 앱(카메라 롤)에 저장.
    /// add-only 권한 사용 — 라이브러리 읽기 권한 없이 추가만 가능.
    private func saveAllToPhotos() async {
        isSavingPhotos = true
        defer { isSavingPhotos = false }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveResultMessage = "사진 추가 권한이 거부됐어요. 설정 → Withy 에서 허용해 주세요."
            showSaveResultAlert = true
            return
        }

        // CharacterState 순서대로 정렬 — 사진 앱에서도 같은 순서로 보임.
        // 움직이는 캐릭터는 2번째 프레임도 바로 뒤에 이어서 저장.
        let items: [(CharacterState, UIImage)] = CharacterState.allCases.flatMap { s -> [(CharacterState, UIImage)] in
            var imgs: [(CharacterState, UIImage)] = []
            if let f0 = results[s] { imgs.append((s, f0)) }
            if let f1 = resultsFrame1[s] { imgs.append((s, f1)) }
            return imgs
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
}

#Preview {
    NavigationStack { BatchCharacterGenView() }
}

/// 다듬기 이력(버전 체인)을 적용/취소 전에 App Group 에 보관 —
/// 배치 화면을 완전히 나갔다 들어와도 결정 안 한 이력을 복원한다. (캔디 쓴 결과 유실 방지)
fileprivate enum PendingRevisionStore {
    private struct Meta: Codable { let frame: Int; let selected: Int; let count: Int; let prompt: String }

    private static var folder: URL? {
        guard let c = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedAppState.groupID) else { return nil }
        let f = c.appendingPathComponent("pending_revisions", isDirectory: true)
        try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        return f
    }

    static func save(state: CharacterState, chain: BatchCharacterGenView.BatchRevision) {
        guard let folder else { return }
        let key = state.rawValue
        remove(state: state)
        for (i, img) in chain.versions.enumerated() {
            try? img.pngData()?.write(to: folder.appendingPathComponent("\(key).v\(i).png"),
                                      options: [.atomic, .noFileProtection])
        }
        for (i, img) in chain.fullVersions.enumerated() {
            try? img.pngData()?.write(to: folder.appendingPathComponent("\(key).f\(i).png"),
                                      options: [.atomic, .noFileProtection])
        }
        let meta = Meta(frame: chain.frame, selected: chain.selected, count: chain.versions.count, prompt: chain.prompt)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: folder.appendingPathComponent("\(key).json"), options: [.atomic, .noFileProtection])
        }
    }

    static func remove(state: CharacterState) {
        guard let folder,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        let prefix = state.rawValue + "."
        for url in files where url.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func clearAll() {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// 저장된 이력 복원 — (state, frame, versions, fullVersions, selected, prompt).
    static func loadAll() -> [(state: CharacterState, frame: Int, versions: [UIImage], fullVersions: [UIImage], selected: Int, prompt: String)] {
        guard let folder,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        var out: [(CharacterState, Int, [UIImage], [UIImage], Int, String)] = []
        for url in files where url.pathExtension == "json" {
            let key = url.deletingPathExtension().lastPathComponent
            guard let state = CharacterState(rawValue: key),
                  let data = try? Data(contentsOf: url),
                  let meta = try? JSONDecoder().decode(Meta.self, from: data), meta.count > 1 else { continue }
            var versions: [UIImage] = [], fulls: [UIImage] = []
            var ok = true
            for i in 0..<meta.count {
                guard let v = UIImage(contentsOfFile: folder.appendingPathComponent("\(key).v\(i).png").path),
                      let f = UIImage(contentsOfFile: folder.appendingPathComponent("\(key).f\(i).png").path)
                else { ok = false; break }
                versions.append(v); fulls.append(f)
            }
            guard ok else { continue }
            out.append((state, meta.frame, versions, fulls,
                        Swift.min(Swift.max(0, meta.selected), versions.count - 1), meta.prompt))
        }
        return out
    }
}
