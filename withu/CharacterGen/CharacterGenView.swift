//
//  CharacterGenView.swift
//  withu
//

import SwiftUI
import PhotosUI
import WidgetKit

enum GenerationMode: String, CaseIterable, Hashable {
    case aiGenerate = "AI로 캐릭터 생성하기"
    case importPhoto = "내 이미지로 캐릭터 생성하기"

    var sfSymbol: String {
        switch self {
        case .aiGenerate:  return "wand.and.stars"
        case .importPhoto: return "photo.on.rectangle.angled"
        }
    }
}

struct CharacterGenView: View {
    /// true 면 '하나씩 만들기' 폼만 표시 — 생성 방식 화면에서 push 로 진입하는 하위 화면.
    var singleFormOnly: Bool = false

    @State private var mode: GenerationMode = .aiGenerate

    @State private var targetState: CharacterState = .idle
    /// 내 캐릭터 "설명"(정체성). 포즈는 선택한 상태(generationHint)에서 자동으로 붙음.
    /// 저장된 묘사(CharacterProfile.aiPrompt)로 시작 — 비어 있으면 빈 칸(placeholder 안내).
    @State private var prompt: String = CharacterProfileStore.load().aiPrompt
    @State private var refinementPrompt: String = ""
    /// "항목별로 채우기" 도우미 — 채우면 위 자유 설명칸(prompt)에 자동 합쳐짐.
    @State private var subjectField: String = ""
    @State private var looksField: String = ""
    @State private var colorField: String = ""

    /// "low" $0.011 / "medium" $0.04 / "high" $0.17
    @State private var quality: String = "low"
    @State private var artStyle: String = "pixel"   // "casual" | "pixel"

    /// AI 생성 모드 — 사진 앱에서 첨부한 참고 이미지 (있으면 reference 로 보냄)
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var referenceImage: UIImage?
    /// 참고사진을 내 캐릭터 갤러리에서 고르는 sheet
    @State private var showGalleryRefPicker: Bool = false
    /// 참고사진에서 무엇을 참고할지 (참고사진 있을 때만 프롬프트에 반영).
    @State private var referenceKeep: String = ""     // 사진에서 그대로 둘 것
    @State private var referenceChange: String = ""   // 사진에서 바꿀 것

    /// 이미지 첨부 모드 — 첨부 + 배경 제거 처리된 결과
    @State private var importPickerItem: PhotosPickerItem?
    @State private var importedRawImage: UIImage?
    @State private var importedProcessedImage: UIImage?
    /// 가져온 이미지를 reference 로 만든 움직임 프레임 (frame 1)
    @State private var importedFrame1: UIImage?
    @State private var isProcessing: Bool = false
    /// 배경 빼기 스위치 (ON: 배경 제거본, OFF: 원본 그대로)
    @State private var removeBackground: Bool = true

    @State private var isGenerating: Bool = false
    @State private var generateTask: Task<Void, Never>?  // cancel 가능하도록 핸들 보관
    @State private var resultImage: UIImage?
    @State private var resultFrame2: UIImage?    // frame 1 (애니메이션용)
    @State private var generateAnimated: Bool = false
    @State private var lastFrame0FullRes: UIImage?   // frame1 정규화용 1번째 프레임 원본(1024)
    /// frame 2 prompt 의 변화 힌트 (영어). 토글 ON 일 때만 노출.
    /// targetState 가 바뀌면 그 state 의 기본 hint 로 자동 갱신.
    /// frame 0/1 의 raw (white BG) ↔ transparent (Vision 처리) 캐시.
    /// 사용자가 [원본] / [투명 적용] 토글로 표시/적용 버전 선택.
    @State private var transparentResult: UIImage?
    @State private var transparentResultFrame2: UIImage?
    @State private var displayTransparent: Bool = true   // 기본 투명 (모델이 투명으로 줌)
    @State private var singleDetailFrame: Int = 0   // 결과에서 보고 있는 프레임(0=기본, 1=움직임)
    /// 움직임 프레임(frame 1) 을 만드는 중 — 결과 우하단 슬롯에 로딩 표시 (완성 착각 방지).
    @State private var isGeneratingMotionFrame: Bool = false
    @State private var isProcessingTransparent: Bool = false
    @State private var revisedPrompt: String?
    /// 마지막 성공 생성에 실제로 보낸 프롬프트 — 갤러리 '만든 기록' 저장용.
    @State private var lastSentPrompt: String?
    @State private var lastError: String?
    @State private var showAppliedAlert: Bool = false
    @State private var showSavedAlert: Bool = false
    @State private var generationStartedAt: Date?
    @State private var remainingGenerations: Int = GenerationQuota.remainingToday()
    @State private var showPaywall: Bool = false
    /// 사진 선택 후 정사각 자르기 시트
    @State private var cropTarget: CropTarget?

    /// 생성/다듬기 전 캔디 안내 팝업 — 확인해야 실행.
    private enum PendingAction: Identifiable {
        case newGeneration
        case refine(frame: Int)
        case importMotion   // 가져온 이미지를 reference 로 움직임 프레임 생성
        var id: String {
            switch self {
            case .newGeneration: return "new"
            case .refine(let f): return "refine\(f)"
            case .importMotion: return "importMotion"
            }
        }
    }
    @State private var pendingAction: PendingAction?

    /// 결과 버전 이력 — [0] = 처음 만든 원본, 이후는 다듬은 버전.
    /// 버전을 탭해 선택하면 그 버전이 현재 결과(적용 대상)가 된다.
    private struct ResultVersion: Identifiable {
        let id = UUID()
        let small: UIImage          // 결과 슬롯(128) 이미지
        let frame2: UIImage?        // 움직임 프레임 (있으면)
        let fullRes: UIImage?       // frame1 앵커용 원본(1024)
        let isRefined: Bool
        /// 자동 저장된 갤러리 항목 id — '적용' 시 이 항목을 재사용해 중복 저장을 막음.
        let galleryId: String?
    }
    @State private var versions: [ResultVersion] = []
    @State private var selectedVersion: Int = 0

    /// 계정 무료 1회 남았는지 — 서버(entitlement)가 진실. 재설치와 무관하게 계정당 1회.
    private var hasFreeCreation: Bool {
        (AuthManager.shared.entitlement?.freeSingleRemaining ?? 0) > 0
    }
    /// 이번 '만들기'가 실제로 무료인지 — 무료가 남아 있고 '사진 없이 프롬프트로만' 만들 때만.
    /// 사진을 넣으면 무료를 안 쓰고 캔디로 — 공짜 사진→캐릭터 남용 방지.
    private var creationIsFree: Bool { hasFreeCreation && referenceImage == nil }
    /// 직전 send() 를 서버가 무료로 소진했는지 (응답 free_consumed).
    @State private var lastFreeConsumed: Bool = false
    /// 생성 모니터링용 수정 체인 id — 새 원본 생성마다 갱신, 다듬기는 같은 값을 재사용.
    /// 갤러리 '캐릭터별' batchId 로도 재사용 — 한 세션의 결과가 한 캐릭터로 묶임.
    @State private var currentSessionId: String = UUID().uuidString
    /// 결과에 붙일 이름 — 채우면 갤러리 '캐릭터별'에 이 이름으로 표시. (선택)
    @State private var characterName: String = ""

    var body: some View {
        ZStack {
            backgroundGradient(for: targetState).ignoresSafeArea()
                .animation(.snappy, value: targetState)
            Form {
                if singleFormOnly {
                    // '하나씩 만들기' 하위 화면 — 단건 생성 폼 전체
                    stateSection
                    promptSection       // 1. 캐릭터 설명
                    referenceSection    // 2. 참고 사진
                    optionsSection      // 3. 스타일
                    generateButtonSection   // 만들기
                    resultSection
                    refinementSection
                } else {
                    modeSection             // 생성 옵션 먼저 (AI / 내 이미지)
                    if mode == .aiGenerate {
                        scopeSection        // 생성 방식: 여러 상태 한 번에 / 하나씩 (각각 push)
                    } else {
                        stateSection
                        importSection
                        importResultSection
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(singleFormOnly ? "하나씩 만들기" : "캐릭터 만들기")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { candyBadge }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            remainingGenerations = GenerationQuota.remainingToday()
            restoreVersionChain()
        }
        // 서버 무료/잔액 스냅샷 최신화 — '첫 만들기 무료' 배지가 옛 캐시로 잘못 뜨는 것 방지.
        .task { await AuthManager.shared.refreshEntitlement() }
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
        .sheet(isPresented: $showGalleryRefPicker) {
            GalleryReferencePicker { img in
                referenceImage = img
                photoPickerItem = nil
            }
        }
        .alert(pendingActionTitle, isPresented: Binding(
            get: { pendingAction != nil },
            set: { if !$0 { pendingAction = nil } }
        )) {
            Button(pendingActionConfirmLabel) {
                switch pendingAction {
                case .newGeneration: generateTask = Task { await generate() }
                case .refine(let f): Task { await refine(frame: f) }
                case .importMotion: Task { await generateImportMotionFrame() }
                case nil: break
                }
                pendingAction = nil
            }
            Button("취소", role: .cancel) { pendingAction = nil }
        } message: {
            Text(pendingActionMessage)
        }
        .alert("적용했어요", isPresented: $showAppliedAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("\(targetState.koreanShortLabel) 자리의 캐릭터를 바꿨어요. 홈 화면·위젯·워치에 바로 반영돼요.")
        }
        .alert("저장했어요", isPresented: $showSavedAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("사진 앱에 저장했어요.")
        }
        .onChange(of: targetState) { _, _ in
            // prompt(캐릭터 설명)은 상태와 무관하게 유지 — 포즈는 generationHint 로 자동 반영.
            refinementPrompt = ""
        }
        .onChange(of: subjectField) { _, _ in composeFromHelper() }
        .onChange(of: looksField) { _, _ in composeFromHelper() }
        .onChange(of: colorField) { _, _ in composeFromHelper() }
        .onChange(of: photoPickerItem) { _, item in
            Task { await loadReference(item) }
        }
        .onChange(of: importPickerItem) { _, item in
            Task { await loadAndProcessImport(item) }
        }
        .onChange(of: mode) { _, _ in
            // 모드 전환 시 결과/에러 reset
            resultImage = nil
            revisedPrompt = nil
            lastError = nil
            importedRawImage = nil
            importedProcessedImage = nil
            importedFrame1 = nil
        }
    }

    // MARK: - Common sections

    /// AI 생성의 생성 방식 — 두 행 모두 같은 형식의 이동 행(제목+부제+chevron).
    /// '여러 상태 한 번에' → 배치 화면, '하나씩' → 단건 생성 폼 화면.
    private var scopeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                BatchCharacterGenView()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("여러 상태 한 번에 만들기")
                        .font(.callout.weight(.semibold))
                    Text("모든 상태의 모습을 한번에 만들어요")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            NavigationLink {
                CharacterGenView(singleFormOnly: true)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("하나씩 만들기")
                        .font(.callout.weight(.semibold))
                    Text("원하는 상태 하나만 만들어요")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .pixelCardSurface()
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text("생성 방식")
        }
    }

    private var modeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
            ForEach(GenerationMode.allCases, id: \.self) { m in
                Button {
                    mode = m
                } label: {
                    HStack {
                        Text(LocalizedStringKey(m.rawValue))
                            .foregroundStyle(.primary)
                        Spacer()
                        if mode == m {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .disabled(isGenerating || isProcessing)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .pixelCardSurface()
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text("생성 옵션")
        } footer: {
            if mode == .importPhoto {
                Text("모두 기기 안에서 처리하고 비용은 들지 않아요.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
            Picker("상태", selection: $targetState) {
                ForEach(CharacterState.userFacing, id: \.self) { s in
                    Text(s.koreanShortLabel).tag(s)
                }
            }
            .pickerStyle(.menu)
            .disabled(isGenerating || isProcessing)
            // 움직임 지원 상태면 여기서 움직이는 이미지로 만들지 선택.
            if targetState.usesGeneratedMotion {
                Toggle("움직이는 캐릭터로 만들기", isOn: $generateAnimated)
                    .disabled(isGenerating || isProcessing)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .pixelCardSurface()
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text("상태 선택")
        }
    }

    // MARK: - AI generate sections

    private var promptSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $prompt)
                .frame(minHeight: 80)
                .font(.callout)
                .overlay(alignment: .topLeading) {
                    if prompt.isEmpty {
                        Text("만들 캐릭터를 설명해 주세요")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
            DisclosureGroup("항목별 입력") {
                helperField("대상", text: $subjectField, placeholder: "마시멜로 캐릭터")
                helperField("생김새", text: $looksField, placeholder: "큰 눈, 둥근 몸, 새싹")
                helperField("색감", text: $colorField, placeholder: "연두 파스텔톤")
            }
            .font(.callout)
            .disabled(isGenerating)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .pixelCardSurface()
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            VStack(alignment: .leading, spacing: 3) {
                Text("캐릭터 프롬프트")
            }
        }
    }

    /// 보유 캔디(충전 크레딧) 배지 — 탭하면 충전(Paywall). 서버 잔액 우선, 없으면 로컬.
    private var candyBadge: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 3) {
                Text("🍬")
                Text("\(GenerationQuota.displayedCandy())")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .tint(.withuPink)
    }

    // MARK: 캔디 안내 팝업 텍스트

    /// 이번 확인 팝업의 동작이 무료인지 — 만들기는 사진 없을 때만, 다듬기는 무료 남았으면.
    private var pendingActionIsFree: Bool {
        switch pendingAction {
        case .newGeneration: return creationIsFree
        case .refine: return hasFreeCreation
        case .importMotion, nil: return false
        }
    }

    private var pendingActionTitle: String {
        pendingActionIsFree
            ? String(localized: "첫 만들기는 무료예요")
            : String(localized: "캔디를 사용해요")
    }

    private var pendingActionConfirmLabel: String {
        if case .refine = pendingAction { return String(localized: "다듬기") }
        return String(localized: "만들기")
    }

    private var pendingActionMessage: String {
        let unit = GenerationQuota.cost(forQuality: quality)
        let isNew: Bool = { if case .newGeneration = pendingAction { return true }; return false }()
        let cost = (isNew && generateAnimated && targetState.usesGeneratedMotion) ? unit * 2 : unit
        if pendingActionIsFree {
            return String(localized: "이번 1번은 무료로 만들어요. 다음부터는 만들기·다듬기마다 캔디를 써요 (한 장 1개).")
        }
        let isRefine: Bool = { if case .refine = pendingAction { return true }; return false }()
        return isRefine
            ? String(localized: "이번 다듬기에 캔디 \(cost)개를 써요. 성공했을 때만 차감돼요.")
            : String(localized: "이번 만들기에 캔디 \(cost)개를 써요. 성공했을 때만 차감돼요.")
    }

    /// 마지막 단계 — 설명·참고·스타일을 다 정한 뒤 누르는 만들기 버튼.
    private var generateButtonSection: some View {
        let cost = GenerationQuota.cost(forQuality: quality)
        return Section {
            if isGenerating {
                generatingLabel
                Button(role: .destructive) {
                    generateTask?.cancel()
                    generateTask = nil
                    isGenerating = false
                    generationStartedAt = nil
                    lastError = String(localized: "이미지 생성을 그만뒀어요.")
                } label: {
                    Label("그만두기", systemImage: "stop.circle.fill")
                }
            } else if remainingGenerations < cost && !creationIsFree {
                Button {
                    showPaywall = true
                } label: {
                    Label("더 만들기 (충전)", systemImage: "sparkles")
                }
            } else {
                // 움직임 토글은 '상태 선택'으로 옮김 (여러 상태 만들기와 형식 통일).
                Button {
                    pendingAction = .newGeneration   // 캔디 안내 팝업 → 확인 시 생성
                } label: {
                    Label("이 모습으로 만들기", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WithuCTAButtonStyle())
                // 참고 사진이 있으면 설명 없이도 생성 가능 (composedPrompt 가 참고사진 템플릿으로 대체)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && referenceImage == nil)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if isGenerating {
                    Text("너무 오래 떠나 있으면 결과가 사라질 수 있으니, 화면에 머무르는 것을 권장해요.")
                        .foregroundStyle(.orange)
                } else {
                    Text("보통 20~30초 정도 걸려요.")
                        .foregroundStyle(.secondary)
                }
                if creationIsFree {
                    Text("첫 만들기 1번은 무료예요! 다음부터는 만들기·다듬기마다 캔디를 써요.")
                        .foregroundStyle(Color.withuPinkText)
                } else if referenceImage != nil && hasFreeCreation {
                    Text("사진을 넣으면 캔디를 써요. 무료 1번은 사진 없이 만들 때 쓸 수 있어요.")
                        .foregroundStyle(.secondary)
                } else if remainingGenerations < cost {
                    Text("캔디가 부족해요. 충전하면 계속 만들 수 있어요.")
                        .foregroundStyle(.orange)
                } else {
                    Text("보유 캔디 \(remainingGenerations)개 · 이번 만들기 \((generateAnimated && targetState.usesGeneratedMotion) ? cost * 2 : cost)캔디")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var generatingLabel: some View {
        if let start = generationStartedAt {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let elapsed = Int(ctx.date.timeIntervalSince(start))
                HStack {
                    ProgressView()
                    Text("그리는 중… \(elapsed)초")
                }
            }
        } else {
            HStack { ProgressView(); Text("그리는 중…") }
        }
    }

    private var referenceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let ref = referenceImage {
                    Image(uiImage: ref)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.secondary.opacity(0.15))
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        )
                }
                VStack(spacing: 8) {
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        Label("앨범에서 선택", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isGenerating)
                    Button {
                        showGalleryRefPicker = true
                    } label: {
                        Label("내 캐릭터에서 선택", systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)   // 보조 액션 — pink 는 실제 만들기 CTA 전용
                    .disabled(isGenerating)
                }
            }
            if referenceImage != nil {
                Button("사진 빼기", role: .destructive) {
                    referenceImage = nil
                    photoPickerItem = nil
                }
                .font(.callout)
                .disabled(isGenerating)
            }
            if referenceImage != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("그대로 둘 것")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("비우면 사진 그대로 유지돼요", text: $referenceKeep, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.callout)
                        .disabled(isGenerating)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("바꿀 것")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("바꿀 점을 적어요", text: $referenceChange, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.callout)
                        .disabled(isGenerating)
                }
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .pixelCardSurface()
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text("참고 사진 (선택)")
        } footer: {
            if referenceImage == nil {
                Text("사진을 넣으면 그 모습을 참고해서 만들어요. 비워두면 텍스트로만 만들어요.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var optionsSection: some View {
        Section("스타일") {
            VStack(alignment: .leading, spacing: 12) {
            Picker("그림 스타일", selection: $artStyle) {
                Text("Soft").tag("casual")
                Text("Pixel").tag("pixel")
            }
            .pickerStyle(.segmented)
            .disabled(isGenerating)
            styleExampleImage
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .pixelCardSurface()
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
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
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }


    @ViewBuilder
    private var resultSection: some View {
        if resultImage != nil {
            Section("결과") {
                VStack(alignment: .leading, spacing: 12) {
                // 다듬은 버전인지 표시 — 원본과 헷갈리지 않게.
                if versions.indices.contains(selectedVersion), versions[selectedVersion].isRefined {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("다듬은 버전 \(selectedVersion) 을 보고 있어요", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.withuPinkText)
                        Text("다듬었어요 — 다듬기 이력에서 이전 버전과 비교해 보세요")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                // 결과 유실 방지 — 만들어진 결과는 갤러리에 자동 저장됨을 알림.
                if versions.indices.contains(selectedVersion), versions[selectedVersion].galleryId != nil {
                    Label("캐릭터 갤러리에 저장됨", systemImage: "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                // 표시할 frame 0, frame 1 — 현재 모드 (raw / transparent) 에 따라
                let f0 = currentDisplay(frame: 0)
                let f1 = currentDisplay(frame: 1)
                if let f0, let f1 {
                    // 기본 ↔ 움직임 좌우 스와이프 (위 점으로 프레임 표시)
                    TabView(selection: $singleDetailFrame) {
                        Image(uiImage: f0).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12)).tag(0)
                        Image(uiImage: f1).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12)).tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .interactive))
                    .frame(height: 260)
                    Text(singleDetailFrame == 1 ? String(localized: "2번째 (움직임)") : String(localized: "1번째"))
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                } else if let f0 {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: f0)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        // 움직임 프레임(frame 1) 생성 중 — 우하단 슬롯 자리에 로딩 (완성 착각 방지).
                        if isGeneratingMotionFrame {
                            motionFrameLoadingSlot
                        }
                    }
                    if isGeneratingMotionFrame {
                        Text("움직임 프레임을 만드는 중이에요 — 잠시만 기다려 주세요")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // 흰 배경 / 배경 빼기 토글
                Picker("배경", selection: $displayTransparent) {
                    Text("흰 배경").tag(false)
                    Text("배경 빼기").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(isProcessingTransparent)
                .onChange(of: displayTransparent) { _, new in
                    if new {
                        Task { await ensureTransparentResults() }
                    }
                }
                if isProcessingTransparent {
                    HStack { ProgressView(); Text("배경 빼는 중…") }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let revised = revisedPrompt {
                    DisclosureGroup("실제로 사용한 설명 보기") {
                        Text(revised).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let f0 {
                    Button {
                        applyCurrentSelection()
                    } label: {
                        Label("'\(targetState.koreanShortLabel)' 자리에 적용하기", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(WithuCTAButtonStyle())
                    .disabled(isProcessingTransparent)
                    Button("사진 앱에 저장") {
                        let img = (f1 != nil ? currentDisplay(frame: singleDetailFrame) : f0) ?? f0
                        Task { await saveToPhotos(img) }
                    }
                    .tint(.secondary)

                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("이 캐릭터의 이름 (선택)")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("이름", text: $characterName)
                            .font(.callout)
                            .submitLabel(.done)
                            .onChange(of: characterName) { _, new in
                                CharacterImageStore.setCharacterName(new, for: currentSessionId)
                            }
                        Text("갤러리 '캐릭터별'에 이 이름으로 보여요.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .pixelCardSurface()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        if let err = lastError {
            Section {
                WarningBanner(text: err)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
    }

    /// 보여줄 이미지. raw 는 투명(모델 출력). '배경 빼기'=투명 원본, '흰 배경'=흰색 합성(즉시, Vision 없음).
    private func currentDisplay(frame: Int) -> UIImage? {
        let raw = frame == 0 ? resultImage : resultFrame2
        guard let raw else { return nil }
        if displayTransparent { return raw }
        return ImageProcessing.flattenedOnWhite(raw)
    }

    /// 더는 Vision 불필요(모델이 투명으로 줌) — 흰배경은 currentDisplay 에서 즉시 합성. no-op 유지.
    @MainActor
    private func ensureTransparentResults() async {}

    /// 움직임 프레임(frame 1) 생성 중 우하단 미니 슬롯 자리 로딩 — 배치 결과 카드의 40×40 미니와 동일 규격.
    private var motionFrameLoadingSlot: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(.systemBackground).opacity(0.85))
            .frame(width: 40, height: 40)
            .overlay(ProgressView().controlSize(.small))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white, lineWidth: 2))
            .padding(6)
    }

    /// 현재 선택된 모드의 이미지로 적용.
    private func applyCurrentSelection() {
        guard let img = currentDisplay(frame: 0) else { return }
        apply(img, frame2: currentDisplay(frame: 1), to: targetState)
    }

    @ViewBuilder
    private var refinementSection: some View {
        if resultImage != nil {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $refinementPrompt)
                    .frame(minHeight: 80)
                    .font(.callout)
                Button {
                    pendingAction = .refine(frame: resultFrame2 != nil ? singleDetailFrame : 0)
                } label: {
                    if isGenerating {
                        HStack { ProgressView(); Text("다듬는 중…") }
                    } else {
                        Label("다듬기", systemImage: "sparkles")
                    }
                }
                .disabled(isGenerating || refinementPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .pixelCardSurface()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                Text(resultFrame2 != nil && singleDetailFrame == 1 ? String(localized: "이어서 다듬기 (움직임 프레임)") : String(localized: "이어서 다듬기"))
            } footer: {
                Text("위 결과를 바탕으로 조금씩 바꿔가요. 다듬을 때마다 만들기와 같은 캔디가 들어요 (성공했을 때만 차감).")
                    .foregroundStyle(.secondary)
            }
            versionHistorySection
        }
    }

    /// 다듬기 이력 — 원본과 다듬은 버전들을 나란히 보여주고, 탭해서 되돌리거나 고를 수 있게.
    @ViewBuilder
    private var versionHistorySection: some View {
        if versions.count > 1 {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(versions.enumerated()), id: \.element.id) { idx, v in
                            VStack(spacing: 4) {
                                Image(uiImage: v.small)
                                    .resizable().scaledToFit()
                                    .frame(width: 72, height: 72)
                                    .background(Color(.systemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(idx == selectedVersion ? Color.withuPinkText : .clear,
                                                          lineWidth: 2.5)
                                    }
                                Text(v.isRefined ? String(localized: "다듬음 \(idx)") : String(localized: "원본"))
                                    .font(.caption2.weight(idx == selectedVersion ? .semibold : .regular))
                                    .foregroundStyle(idx == selectedVersion ? Color.withuPinkText : .secondary)
                            }
                            .onTapGesture { selectVersion(idx) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .pixelCardSurface()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                Text("다듬기 이력")
            } footer: {
                Text("탭해서 고른 버전이 적용 대상이 돼요. '원본'을 고르면 다듬기 전으로 돌아가요.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 이력에서 버전 선택 — 현재 결과 슬롯을 그 버전으로 교체 (적용 대상 변경).
    private func selectVersion(_ idx: Int) {
        guard versions.indices.contains(idx), idx != selectedVersion, !isGenerating else { return }
        let v = versions[idx]
        selectedVersion = idx
        resultImage = v.small
        resultFrame2 = v.frame2
        lastFrame0FullRes = v.fullRes
        if v.frame2 == nil { singleDetailFrame = 0 }
        // 투명(배경 제거) 캐시는 버전별로 안 들고 있음 — 무효화 후 필요 시 재계산.
        transparentResult = nil
        transparentResultFrame2 = nil
        if displayTransparent {
            Task { await ensureTransparentResults() }
        }
        saveVersionChain()
    }

    /// 다듬기 이력(버전 체인)을 App Group 에 저장 — 화면을 나갔다 와도 복원되게.
    private func saveVersionChain() {
        guard mode == .aiGenerate, !versions.isEmpty else { return }
        RefineHistoryStore.save(stateRaw: targetState.rawValue, selected: selectedVersion,
                                versions: versions.map { ($0.galleryId, $0.isRefined, $0.frame2 != nil) })
    }

    /// 저장된 다듬기 이력 복원 — 진입 시 결과가 없을 때만. 이미지는 갤러리에서 다시 읽는다.
    private func restoreVersionChain() {
        guard mode == .aiGenerate, versions.isEmpty, resultImage == nil,
              let r = RefineHistoryStore.load() else { return }
        if let st = CharacterState(rawValue: r.stateRaw) { targetState = st }
        versions = r.versions.map {
            ResultVersion(small: $0.small, frame2: $0.frame2, fullRes: $0.small,
                          isRefined: $0.isRefined, galleryId: $0.galleryId)
        }
        selectedVersion = r.selected
        let v = versions[r.selected]
        resultImage = v.small
        resultFrame2 = v.frame2
        lastFrame0FullRes = v.small
        if v.frame2 == nil { singleDetailFrame = 0 }
        // 이름/세션도 복원 — 저장된 갤러리 항목의 batchId 를 이어받아 같은 캐릭터로 유지.
        if let gid = versions.compactMap(\.galleryId).first,
           let bid = CharacterImageStore.loadGalleryMetadata().first(where: { $0.id == gid })?.batchId {
            currentSessionId = bid
            characterName = CharacterImageStore.characterName(for: bid) ?? ""
        }
    }

    // MARK: - Import sections

    private var importSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
            PhotosPicker(importedRawImage == nil ? String(localized: "사진 고르기") : String(localized: "다른 사진으로 바꾸기"),
                         selection: $importPickerItem,
                         matching: .images)
                .disabled(isProcessing)
            if isProcessing {
                HStack { ProgressView(); Text("배경 빼고 다듬는 중…") }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .pixelCardSurface()
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text("사진 고르기")
        }
    }

    /// 미리보기/적용에 쓸 이미지 — 토글에 따라 배경 제거본 또는 원본.
    private var displayedImport: UIImage? {
        guard let raw = importedRawImage else { return nil }
        if removeBackground { return importedProcessedImage ?? raw }
        return raw
    }

    @ViewBuilder
    private var importResultSection: some View {
        if let raw = importedRawImage {
            let display = displayedImport ?? raw
            Section("미리보기") {
                VStack(alignment: .leading, spacing: 12) {
                Toggle("배경 빼기", isOn: $removeBackground)
                    .disabled(isProcessing)

                ZStack {
                    // 배경 제거본은 투명 — 체커보드로 투명 영역 표시.
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemBackground))
                    Image(uiImage: display)
                        .resizable()
                        .scaledToFit()
                }
                .frame(maxHeight: 300)
                // 움직임 프레임 — 만들어졌으면 우하단 미니, 만드는 중이면 로딩 슬롯.
                .overlay(alignment: .bottomTrailing) {
                    if isGeneratingMotionFrame {
                        motionFrameLoadingSlot
                    } else if let f1 = importedFrame1 {
                        Image(uiImage: f1)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white, lineWidth: 2))
                            .padding(6)
                    }
                }

                if isProcessing {
                    HStack { ProgressView(); Text("배경 빼는 중…") }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // 가져온 이미지도 움직이게 — 이 이미지를 reference 로 움직임 프레임(frame 1) 생성.
                // 생성되는 프레임은 항상 투명 배경이라, '배경 빼기' OFF(원본 배경 유지)와
                // 섞으면 두 프레임 배경이 어긋나 애니메이션이 깨진다 → 배경 제거 상태에서만 노출.
                if targetState.usesGeneratedMotion, removeBackground {
                    Button {
                        pendingAction = .importMotion   // 캔디 안내 팝업 → 확인 시 생성
                    } label: {
                        if isGenerating {
                            HStack { ProgressView(); Text("움직임 프레임 만드는 중…") }
                        } else {
                            Label(importedFrame1 == nil
                                  ? String(localized: "움직이는 캐릭터로 만들기")
                                  : String(localized: "움직임 다시 만들기"),
                                  systemImage: "figure.walk.motion")
                        }
                    }
                    .disabled(isGenerating || isProcessing)
                }

                Button {
                    // '배경 빼기' OFF 로 적용하면 frame0(원본 배경)과 투명 frame1 이
                    // 어긋나므로, 움직임 프레임은 배경 제거 상태에서만 함께 적용.
                    apply(display, frame2: removeBackground ? importedFrame1 : nil, to: targetState)
                } label: {
                    Label("'\(targetState.koreanShortLabel)' 자리에 적용하기", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(WithuCTAButtonStyle())
                .disabled(removeBackground && isProcessing)
                Button("사진 앱에 저장") {
                    Task { await saveToPhotos(display) }
                }
                .tint(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .pixelCardSurface()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        if let err = lastError {
            Section {
                WarningBanner(text: err)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Actions (AI generate)

    /// 서버로 보낼 프롬프트 = 캐릭터 설명 + 선택한 상태의 포즈(generationHint).
    /// 설명이 비어 있으면 포즈만(서버 스타일 가드가 채움).
    private var composedPrompt: String {
        let desc = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let pose = targetState.generationHint
        // 참고 사진이 있으면 Keep/Change 템플릿 — 캐릭터는 그대로, '바꿀 것'만 바뀌게.
        if referenceImage != nil {
            let keep = referenceKeep.trimmingCharacters(in: .whitespacesAndNewlines)
            let change = referenceChange.trimmingCharacters(in: .whitespacesAndNewlines)
            let keepClause = keep.isEmpty ? "" : " Keep especially: \(keep)."
            // '바꿀 것'·'캐릭터 프롬프트' 둘 중 하나만 채워도 됨 — 바꿀것 > 프롬프트 > 상태 포즈 순.
            let changeClause = !change.isEmpty ? change : (!desc.isEmpty ? desc : pose)
            return "Use the reference image. Keep the EXACT same character — identity, face and expression style, body proportions, art style, colors and shading, line thickness, and every design detail.\(keepClause) Change ONLY: \(changeClause). Do not change the character design; keep all other visual details identical to the reference."
        }
        return desc.isEmpty ? pose : "\(desc), \(pose)"
    }

    /// 생성 모니터링 표시용 — 사용자가 실제 입력한 원문 + 어떤 칸이었는지 라벨.
    private var rawUserInput: (text: String, field: String) {
        let desc = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if referenceImage != nil {
            let keep = referenceKeep.trimmingCharacters(in: .whitespacesAndNewlines)
            let change = referenceChange.trimmingCharacters(in: .whitespacesAndNewlines)
            var parts: [String] = []
            if !change.isEmpty { parts.append("바꿀 것: \(change)") }
            if !keep.isEmpty { parts.append("그대로: \(keep)") }
            if parts.isEmpty && !desc.isEmpty { parts.append(desc) }
            return (parts.joined(separator: " / "), "참고사진")
        }
        return (desc, "설명")
    }

    /// "항목별로 채우기" 한 줄 — 라벨 + 입력칸.
    private func helperField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            TextField(placeholder, text: text, axis: .vertical)
                .font(.callout)
        }
    }

    /// 항목별 입력(주제·생김새·색감)을 합쳐 캐릭터 설명칸(prompt)에 반영.
    private func composeFromHelper() {
        let parts = [subjectField, looksField, colorField]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !parts.isEmpty {
            prompt = parts.joined(separator: ", ")
        }
    }

    /// 캐릭터 설명을 프로필에 저장 — 다음에 열어도 유지되고, 일괄 생성도 같은 설명을 씀.
    private func saveDescription() {
        var p = CharacterProfileStore.load()
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.aiPrompt != trimmed {
            p.aiPrompt = trimmed
            CharacterProfileStore.save(p)
        }
    }

    private func generate() async {
        // 무료 1회는 '사진 없이 프롬프트로만' 만들 때만 — 사진을 넣으면 캔디로(공짜 사진→캐릭터 남용 방지).
        let freeAvailable = creationIsFree
        guard freeAvailable || GenerationQuota.canGenerate(GenerationQuota.cost(forQuality: quality)) else {
            lastError = String(localized: "캔디가 부족해요. 충전하면 계속 만들 수 있어요.")
            return
        }
        isGenerating = true
        generationStartedAt = .now
        lastError = nil
        resultFrame2 = nil
        singleDetailFrame = 0
        currentSessionId = UUID().uuidString   // 새 원본 → 새 수정 체인
        characterName = ""                     // 새 캐릭터 → 이름 초기화

        // 새 생성 — 이전 투명(배경 제거) 캐시 무효화. 안 그러면 '배경 빼기' 보기에 옛 이미지가 남음.
        transparentResult = nil
        transparentResultFrame2 = nil
        // 백그라운드 진입해도 30초까지 살아남게 background task assertion.
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "withu.generate")
        defer {
            isGenerating = false
            generationStartedAt = nil
            isGeneratingMotionFrame = false
            generateTask = nil
            remainingGenerations = GenerationQuota.remainingToday()
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
            }
        }
        // 사전 reachability 체크 — 30분 timeout 매달리지 않도록.
        do {
            try await APIClient.shared.preflightPing()
        } catch {
            lastError = String(localized: "지금은 연결이 어려워요. 와이파이나 인터넷을 확인하고 다시 해주세요.")
            return
        }
        saveDescription()
        let cost = GenerationQuota.cost(forQuality: quality)
        let referenceB64 = referenceImage?.pngData()?.base64EncodedString()
        let prevResult = resultImage   // 실패 시 이전 런 이미지가 남아 frame1/쿼터에 새는 것 방지
        let raw = rawUserInput
        // 사진 첨부 생성은 kind=photo → 서버가 무료 1회를 소진하지 않음(캔디로 차감).
        await send(prompt: composedPrompt, reference: referenceB64, frame: 0,
                   userInput: raw.text, inputField: raw.field,
                   kind: referenceImage != nil ? "photo" : nil)
        let frame0Succeeded = resultImage !== prevResult
        // 서버가 이번 생성을 계정 무료 1회로 소진했으면 세션 전체(프레임 2장까지) 미차감.
        let freeSession = lastFreeConsumed
        if frame0Succeeded, !freeSession { GenerationQuota.record(cost) }
        // 연속 이미지 — frame 0 성공 시 그 원본(1024)을 reference 로 frame 1 추가
        if generateAnimated, targetState.usesGeneratedMotion, frame0Succeeded,
           let f0Full = lastFrame0FullRes ?? resultImage,
           let f0Ref = f0Full.pngData()?.base64EncodedString() {
            isGeneratingMotionFrame = true   // 결과 우하단 슬롯에 로딩 표시 — 완성 착각 방지
            let animPrompt = "\(composedPrompt).\(animationFrame2Instruction(targetState))"
            await send(prompt: animPrompt, reference: f0Ref, frame: 1, matchReference: f0Full,
                       inputField: "움직임 프레임")
            isGeneratingMotionFrame = false
            if resultFrame2 != nil, !freeSession { GenerationQuota.record(cost) }
        }
        if frame0Succeeded {
            // 새 결과 = 이력 리셋. [0] = 원본.
            if let img = resultImage {
                // 결과 유실 방지 — 갤러리에 자동 저장 (활성 슬롯은 '적용' 눌러야 반영).
                let savedId = autoSaveToGallery()
                versions = [ResultVersion(small: img, frame2: resultFrame2,
                                          fullRes: lastFrame0FullRes, isRefined: false,
                                          galleryId: savedId)]
                selectedVersion = 0
                saveVersionChain()   // 새 캐릭터 = 이력 갈아끼움(저장본 덮어씀)
            }
        }
        // '배경 빼기' 보기 중이면 새 결과를 즉시 재처리(stale 방지).
        if displayTransparent { await ensureTransparentResults() }
    }

    /// 보고 있는 프레임만 다듬기. frame1 은 frame0 을 앵커로 둬서 캐릭터/크기 일관성 유지.
    private func refine(frame: Int) async {
        let freeAvailable = hasFreeCreation
        guard freeAvailable || GenerationQuota.canGenerate(GenerationQuota.cost(forQuality: quality)) else {
            lastError = String(localized: "캔디가 부족해요. 충전하면 계속 만들 수 있어요.")
            return
        }
        let currentSlot = frame == 1 ? resultFrame2 : resultImage
        guard currentSlot != nil else {
            lastError = String(localized: "기존 이미지를 다시 불러오지 못했어요. 다시 시도해 주세요.")
            return
        }
        // reference: frame1 이면 frame0 앵커, frame0 이면 자기 자신
        let anchor = frame == 1 ? (resultImage ?? currentSlot) : currentSlot
        let referenceB64 = anchor?.pngData()?.base64EncodedString()
        isGenerating = true
        generationStartedAt = .now
        lastError = nil
        // 선택한 프레임의 투명 캐시만 무효화 (다른 프레임은 보존).
        if frame == 1 { transparentResultFrame2 = nil } else { transparentResult = nil }
        defer {
            isGenerating = false
            generationStartedAt = nil
            remainingGenerations = GenerationQuota.remainingToday()
        }
        var prompt = refinementPrompt
        if frame == 1 {
            prompt += ". Animation frame 2 (for a 2-frame swap loop): \(targetState.animationFrame2Hint). CRITICAL: keep the character at the EXACT same size, scale, and centered position as the reference image; only the pose changes."
        }
        let prevSlot = frame == 1 ? resultFrame2 : resultImage   // 실패 감지 — 옛 이미지 그대로면 차감 안 함
        await send(prompt: prompt, reference: referenceB64, frame: frame,
                   matchReference: frame == 1 ? (lastFrame0FullRes ?? resultImage) : nil,
                   userInput: refinementPrompt, inputField: "다듬기")
        let succeeded = (frame == 1 ? resultFrame2 : resultImage) !== prevSlot
        if succeeded {
            if !lastFreeConsumed {   // 서버가 무료로 소진한 다듬기는 미차감
                GenerationQuota.record(GenerationQuota.cost(forQuality: quality))
            }
            // 다듬은 버전을 이력에 추가하고 선택 — 이전 버전으로 언제든 돌아갈 수 있음.
            if let img = resultImage {
                // 결과 유실 방지 — 다듬은 버전도 갤러리에 자동 저장 (활성 슬롯은 미적용).
                let savedId = autoSaveToGallery()
                versions.append(ResultVersion(small: img, frame2: resultFrame2,
                                              fullRes: lastFrame0FullRes, isRefined: true,
                                              galleryId: savedId))
                if versions.count > 8 { versions.remove(at: 1) }   // 원본([0])은 보존, 오래된 다듬기부터 정리
                selectedVersion = versions.count - 1
                saveVersionChain()
            }
        }
        refinementPrompt = ""
        // '배경 빼기' 보기 중이면 다듬은 프레임만 즉시 재처리(stale 방지).
        if displayTransparent {
            if frame == 1, let rawF2 = resultFrame2 {
                transparentResultFrame2 = await ImageProcessing.bestEffortTransparent(rawF2)
            } else if let raw = resultImage {
                transparentResult = await ImageProcessing.bestEffortTransparent(raw)
            }
        }
    }

    /// frame1(2번째 장면) 프롬프트 — "1번째와 거의 동일, 표정만 살짝" 강제.
    private func animationFrame2Instruction(_ state: CharacterState) -> String {
        " Use the reference image as the SAME character. Keep identical: face, outfit, colors, art/pixel style, line thickness, body proportions, size, scale, centered position, framing, and the flat solid background. This is the SECOND frame of a 2-frame animation loop, so the POSE MUST visibly CHANGE from the reference. Change the pose to: \(state.animationFrame2Hint). Change ONLY the pose — keep every design detail and the placement identical to the reference."
    }

    private func send(prompt: String, reference: String?, frame: Int = 0, matchReference: UIImage? = nil,
                      userInput: String? = nil, inputField: String? = nil, kind: String? = nil) async {
        // AI 에 흰 배경 강제 — 결과를 사용자가 post-gen 에 Vision 으로 정제할 수 있음.
        // 격자(체커보드) 방지: 일부 모델이 "투명"을 격자 무늬로 그려버림 → 단색 흰배경 명시.
        let finalPrompt = "\(prompt). Only the character on a transparent background — no background fill, no shadows, no extra elements."
        do {
            let req = GenerateImageRequest(
                prompt: finalPrompt,
                referenceImageBase64: reference,
                steps: 30,
                width: 1024,
                height: 1024,
                quality: quality,
                artStyle: artStyle,
                style: "auto",
                kind: kind,
                model: "gpt-image-2",
                userInput: userInput?.trimmingCharacters(in: .whitespacesAndNewlines),
                inputField: inputField
            )
            // frame 0 만 수정 체인(session)에 넣는다 — frame 1(자동 애니메이션)은 수정 횟수에서 제외.
            let resp = try await APIClient.shared.generateImage(
                req,
                sessionId: frame == 0 ? currentSessionId : nil,
                state: targetState.rawValue
            )
            guard let data = Data(base64Encoded: resp.imageBase64),
                  let rawImg = UIImage(data: data) else {
                lastError = String(localized: "이미지를 불러오지 못했어요. 다시 시도해 주세요.")
                return
            }
            // gpt-image-2 는 마젠타 단색 배경으로 옴 → 크로마키로 투명화 (1.5 투명 결과엔 no-op).
            let img = await ImageProcessing.transparentized(rawImg)
            // frame1 은 1번째 기준 크기·위치 정규화.
            let processed: UIImage
            if frame == 1, let ref = matchReference {
                processed = await ImageProcessing.matchedToReference(img, reference: ref)
            } else {
                processed = img
            }
            // 128px 로 다운샘플 — 메인 화면 200, 워치 64, 위젯 60 다 커버 + 디스크 절약
            var small = processed.preparingThumbnail(of: CGSize(width: 128, height: 128)) ?? processed
            // frame1 색 드리프트 제거 — frame0 색에 맞춤
            if frame == 1, let ref = matchReference,
               let refSmall = ref.preparingThumbnail(of: CGSize(width: 128, height: 128)) {
                small = ImageProcessing.colorMatched(small, reference: refSmall)
            }
            if frame == 0 {
                resultImage = small
                lastFrame0FullRes = processed   // frame1 정규화 reference (1024 투명)
                revisedPrompt = resp.revisedPrompt
                lastSentPrompt = finalPrompt    // 갤러리 '만든 기록' 저장용
            } else {
                resultFrame2 = small
            }
            lastFreeConsumed = resp.freeConsumed ?? false
            if let ent = resp.entitlement { AuthManager.shared.applyEntitlement(ent) }
        } catch APIError.paymentRequired {
            showPaywall = true
        } catch {
            lastError = error.koreanizedDescription
        }
    }

    private func loadReference(_ item: PhotosPickerItem?) async {
        guard let item else {
            referenceImage = nil
            return
        }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                // 선택 후 정사각 자르기 → 결과를 참고 이미지로
                cropTarget = CropTarget(image: img) { cropped in
                    referenceImage = cropped
                }
            }
        } catch {
            lastError = String(localized: "사진을 불러오지 못했어요.")
        }
    }

    // MARK: - Actions (Import)

    private func loadAndProcessImport(_ item: PhotosPickerItem?) async {
        guard let item else {
            importedRawImage = nil
            importedProcessedImage = nil
            importedFrame1 = nil
            return
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let raw = UIImage(data: data) else {
                lastError = String(localized: "사진을 불러오지 못했어요.")
                return
            }
            // 선택 후 정사각 자르기 → 자른 이미지로 배경 제거 처리
            cropTarget = CropTarget(image: raw) { cropped in
                Task { await processImport(cropped) }
            }
        } catch {
            lastError = String(localized: "사진을 불러오지 못했어요.")
        }
    }

    /// 자른 이미지 배경 제거 + 정규화.
    private func processImport(_ image: UIImage) async {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }
        importedRawImage = image
        importedFrame1 = nil   // 이전 이미지 기준 움직임 프레임은 무효
        do {
            let processed = try await ImageProcessing.prepareForCharacter(image)
            importedProcessedImage = processed
        } catch {
            lastError = error.koreanizedDescription
            importedProcessedImage = nil
        }
    }

    /// 가져온 이미지를 reference 로 움직임 프레임(frame 1) 생성 — refine(frame: 1) 과 같은 서버 호출.
    /// 성공 시 frame 0 = 가져온 이미지, frame 1 = 생성 결과로 적용/저장 가능.
    private func generateImportMotionFrame() async {
        guard let base = displayedImport else { return }
        let cost = GenerationQuota.cost(forQuality: quality)
        guard hasFreeCreation || GenerationQuota.canGenerate(cost) else {
            lastError = String(localized: "캔디가 부족해요. 충전하면 계속 만들 수 있어요.")
            return
        }
        isGenerating = true
        generationStartedAt = .now
        isGeneratingMotionFrame = true
        lastError = nil
        defer {
            isGenerating = false
            generationStartedAt = nil
            isGeneratingMotionFrame = false
            remainingGenerations = GenerationQuota.remainingToday()
        }
        do {
            try await APIClient.shared.preflightPing()
        } catch {
            lastError = String(localized: "지금은 연결이 어려워요. 와이파이나 인터넷을 확인하고 다시 해주세요.")
            return
        }
        guard let refB64 = base.pngData()?.base64EncodedString() else {
            lastError = String(localized: "이미지를 불러오지 못했어요. 다시 시도해 주세요.")
            return
        }
        // send(frame: 1) 은 resultFrame2 슬롯을 쓴다 — AI 모드 잔재 보존 후 결과만 옮겨 담음.
        let savedSlot = resultFrame2
        resultFrame2 = nil
        await send(prompt: animationFrame2Instruction(targetState), reference: refB64, frame: 1,
                   matchReference: base, inputField: "움직임 프레임(내 이미지)")
        if let f2 = resultFrame2 {
            importedFrame1 = f2
            if !lastFreeConsumed { GenerationQuota.record(cost) }   // 성공했을 때만 차감
        }
        resultFrame2 = savedSlot
    }

    // MARK: - Common actions

    /// 생성 결과(원본이든 다듬기든)를 갤러리에만 저장 — 활성 슬롯은 안 건드림 (배치 생성과 같은 패턴).
    /// 반환: 갤러리 항목 id ('적용' 시 재사용해 중복 저장 방지).
    private func autoSaveToGallery() -> String? {
        guard let img = resultImage else { return nil }
        let item = CharacterImageStore.save(img, for: targetState, frame: 0,
                                            applyToActiveSlot: false,
                                            batchId: currentSessionId, prompt: lastSentPrompt)
        if let id = item?.id, let f2 = resultFrame2 {
            CharacterImageStore.attachGalleryFrame1(id, image: f2)
        }
        return item?.id
    }

    private func apply(_ image: UIImage, frame2: UIImage?, to state: CharacterState) {
        // 이미 자동 저장된 결과면 그 갤러리 항목을 재사용 — '적용'이 같은 결과를 또 저장하지 않게.
        let autoSavedId: String? = (mode == .aiGenerate && versions.indices.contains(selectedVersion))
            ? versions[selectedVersion].galleryId : nil
        let ok: Bool
        if let autoSavedId, CharacterImageStore.applyGalleryItem(autoSavedId, to: state) {
            // 갤러리 원본은 투명 raw — '흰 배경' 표시 중이면 활성 슬롯만 합성본으로 덮어씀 (갤러리는 raw 유지).
            if !displayTransparent {
                CharacterImageStore.saveActiveSlotOnly(image, for: state, frame: 0)
                if let frame2 {
                    CharacterImageStore.saveActiveSlotOnly(frame2, for: state, frame: 1)
                }
            }
            ok = true
        } else {
            ok = CharacterImageStore.save(image, for: state, frame: 0, prompt: lastSentPrompt) != nil
            if ok, let frame2 {
                CharacterImageStore.save(frame2, for: state, frame: 1)
            }
        }
        if ok {
            ConnectivityManager.shared.sendCharacterImage(image, for: state, frame: 0)
            // frame 1 — 현재 displayTransparent 모드 존중 (transparent cache 있으면 그걸 우선)
            if let frame2 {
                ConnectivityManager.shared.sendCharacterImage(frame2, for: state, frame: 1)
            }
            WidgetCenter.shared.reloadAllTimelines()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showAppliedAlert = true
        } else {
            lastError = String(localized: "저장하지 못했어요. 다시 시도해 주세요.")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func saveToPhotos(_ image: UIImage) async {
        do {
            try await PhotoSaver.save(image)
            lastError = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showSavedAlert = true
        } catch {
            lastError = error.koreanizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

#Preview {
    NavigationStack { CharacterGenView() }
}

// MARK: - WeatherBackgroundGenView

/// 날씨 배경 (4가지) 을 AI 로 생성. 캐릭터 없이 풍경만.
/// 한 번 생성하면 App Group 에 저장 — 메인 화면 / 워치 / 위젯의 배경 layer 로 사용됨.
struct WeatherBackgroundGenView: View {
    /// 진입 시점에 미리 선택할 condition. CharacterProfileView 에서 특정 날씨 탭 시 사용.
    let initialCondition: WeatherBackgroundCondition

    @State private var condition: WeatherBackgroundCondition
    @State private var prompt: String
    @State private var quality: String = "low"
    @State private var artStyle: String = "pixel"
    @State private var isGenerating: Bool = false
    @State private var generationStartedAt: Date?
    @State private var resultImage: UIImage?
    @State private var lastError: String?
    @State private var showAppliedAlert: Bool = false

    init(initialCondition: WeatherBackgroundCondition = .sunny) {
        self.initialCondition = initialCondition
        _condition = State(initialValue: initialCondition)
        _prompt = State(initialValue: initialCondition.generationHint)
    }

    var body: some View {
        ZStack {
            backgroundGradient(for: .idle).ignoresSafeArea()
            Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                Picker("날씨", selection: $condition) {
                    ForEach(WeatherBackgroundCondition.allCases, id: \.self) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isGenerating)
                HStack {
                    Text("지금 적용된 배경")
                    Spacer()
                    Text(CharacterImageStore.hasBackground(condition) ? String(localized: "생성한 그림") : String(localized: "없음"))
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .pixelCardSurface()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                Text("날씨")
            }

            Section("스타일") {
                VStack(alignment: .leading, spacing: 12) {
                Picker("그림 스타일", selection: $artStyle) {
                    Text("soft").tag("casual")
                    Text("pixel").tag("pixel")
                }
                .pickerStyle(.segmented).disabled(isGenerating)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .pixelCardSurface()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $prompt)
                    .frame(minHeight: 100)
                    .font(.callout)
                Button {
                    Task { await generate() }
                } label: {
                    if isGenerating {
                        generatingLabel
                    } else {
                        Label("배경 만들기", systemImage: "wand.and.stars")
                    }
                }
                .disabled(isGenerating || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .pixelCardSurface()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                Text("배경")
            } footer: {
                Text("캐릭터는 빼고 풍경만 그려요. 「밤하늘」, 「비 오는 도시 골목」처럼 자유롭게 적어주세요.")
                    .font(.caption2)
            }

            if let img = resultImage {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                    // 단독 — 생성된 배경 자체
                    Image(uiImage: img).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    // 합성 미리보기 — 실제 메인 화면처럼 idle 캐릭터 올림
                    VStack(spacing: 4) {
                        Text("홈 화면에서 보이는 모습").font(.caption2).foregroundStyle(.secondary)
                        ZStack {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 200, height: 200)
                                .clipShape(Circle())
                            Circle().fill(CharacterState.idle.tint.opacity(0.18))
                                .frame(width: 200, height: 200)
                            CharacterImageView(state: .idle, animated: true)
                                .frame(width: 160, height: 160)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    Button {
                        apply(img, for: condition)
                    } label: {
                        Label("'\(condition.displayName)' 배경으로 적용하기", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(WithuCTAButtonStyle())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .pixelCardSurface()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text("결과")
                }
            }

            if let err = lastError {
                Section {
                    WarningBanner(text: err)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("날씨 배경 만들기")
        .scrollDismissesKeyboard(.interactively)
        .alert("적용했어요", isPresented: $showAppliedAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("\(condition.displayName) 배경을 적용했어요. 그 날씨일 때 홈 화면·위젯·워치에 보여요.")
        }
        .onChange(of: condition) { _, new in
            prompt = new.generationHint
            resultImage = nil
        }
    }

    @ViewBuilder
    private var generatingLabel: some View {
        if let start = generationStartedAt {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let elapsed = Int(ctx.date.timeIntervalSince(start))
                HStack { ProgressView(); Text("그리는 중… \(elapsed)초") }
            }
        } else {
            HStack { ProgressView(); Text("생성 중…") }
        }
    }

    private func generate() async {
        isGenerating = true
        generationStartedAt = .now
        lastError = nil
        defer {
            isGenerating = false
            generationStartedAt = nil
        }
        do { try await APIClient.shared.preflightPing() }
        catch {
            lastError = String(localized: "지금은 연결이 어려워요. 와이파이나 인터넷을 확인하고 다시 해주세요.")
            return
        }
        // 서버의 SYSTEM_PROMPT 가 매번 캐릭터 가드레일을 prepend 함 (FastAPI proxy).
        // 사용자 prompt 가 "밤하늘" 처럼 짧으면 캐릭터 가 그려짐.
        // → send 시점에 "NO character" 가드레일 강제 append. 그래도 캐릭터 가 나오면 서버 SYSTEM_PROMPT 수정 필요.
        let finalPrompt = "\(prompt). Background scene ONLY — NO character, NO person, NO mascot, NO creature, NO animal. Empty landscape / sky illustration only."
        do {
            let req = GenerateImageRequest(
                prompt: finalPrompt,
                referenceImageBase64: nil,
                steps: 30,
                width: 1024,
                height: 1024,
                quality: quality,
                artStyle: artStyle,
                style: "auto",
                kind: "background",   // 서버가 SYSTEM_PROMPT 건너뜀
                model: "gpt-image-2"
            )
            let resp = try await APIClient.shared.generateImage(req)
            guard let data = Data(base64Encoded: resp.imageBase64),
                  let img = UIImage(data: data) else {
                lastError = String(localized: "이미지를 불러오지 못했어요. 다시 시도해 주세요.")
                return
            }
            // 배경은 256px 면 충분 (메인 hero 240, 위젯 small ~150). 디스크 절약.
            let small = img.preparingThumbnail(of: CGSize(width: 256, height: 256)) ?? img
            resultImage = small
        } catch {
            lastError = error.koreanizedDescription
        }
    }

    private func apply(_ image: UIImage, for cond: WeatherBackgroundCondition) {
        if CharacterImageStore.saveBackground(image, for: cond) {
            WidgetCenter.shared.reloadAllTimelines()
            ConnectivityManager.shared.sendWeatherBackground(image, for: cond)
            showAppliedAlert = true
        } else {
            lastError = String(localized: "저장하지 못했어요. 다시 시도해 주세요.")
        }
    }
}

#Preview("WeatherBg") {
    NavigationStack { WeatherBackgroundGenView() }
}

/// 하나씩 만들기 '다듬기 이력' 을 App Group 에 저장 — 화면을 나갔다 와도 이력·선택이 복원된다.
/// 이미지는 각 버전이 이미 갤러리에 자동 저장돼 있으므로, 여기선 galleryId 체인만 보관한다.
/// (새 캐릭터를 만들면 generate() 가 이력을 갈아끼우며 이 저장본도 덮어쓴다.)
fileprivate enum RefineHistoryStore {
    private struct SavedVersion: Codable { let galleryId: String; let isRefined: Bool; let hasFrame2: Bool }
    private struct SavedChain: Codable { let stateRaw: String; let selected: Int; let versions: [SavedVersion] }

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedAppState.groupID)?
            .appendingPathComponent("single_refine_history.json")
    }

    /// versions: (galleryId, 다듬음 여부, 움직임 프레임 여부). galleryId 가 하나라도 없으면
    /// 인덱스가 어긋나 복원이 깨지므로 저장을 건너뛴다.
    static func save(stateRaw: String, selected: Int,
                     versions: [(galleryId: String?, isRefined: Bool, hasFrame2: Bool)]) {
        guard let fileURL else { return }
        let saved = versions.compactMap { v -> SavedVersion? in
            v.galleryId.map { SavedVersion(galleryId: $0, isRefined: v.isRefined, hasFrame2: v.hasFrame2) }
        }
        guard !saved.isEmpty, saved.count == versions.count else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        let sel = min(max(0, selected), saved.count - 1)
        if let data = try? JSONEncoder().encode(SavedChain(stateRaw: stateRaw, selected: sel, versions: saved)) {
            try? data.write(to: fileURL, options: [.atomic, .noFileProtection])
        }
    }

    struct RestoredVersion { let small: UIImage; let frame2: UIImage?; let galleryId: String; let isRefined: Bool }
    struct Restored { let stateRaw: String; let selected: Int; let versions: [RestoredVersion] }

    /// 저장된 체인 복원 — 갤러리에서 이미지를 다시 읽는다. 하나라도 사라졌으면 복원 취소(nil).
    static func load() -> Restored? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let chain = try? JSONDecoder().decode(SavedChain.self, from: data) else { return nil }
        var out: [RestoredVersion] = []
        for v in chain.versions {
            guard let small = CharacterImageStore.loadGalleryImage(id: v.galleryId) else { return nil }
            let f2 = v.hasFrame2 ? CharacterImageStore.loadGalleryFrame1(id: v.galleryId) : nil
            out.append(RestoredVersion(small: small, frame2: f2, galleryId: v.galleryId, isRefined: v.isRefined))
        }
        guard !out.isEmpty else { return nil }
        return Restored(stateRaw: chain.stateRaw, selected: min(max(0, chain.selected), out.count - 1), versions: out)
    }
}
