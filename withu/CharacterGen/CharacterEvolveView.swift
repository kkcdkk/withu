//
//  CharacterEvolveView.swift
//  withu
//

import SwiftUI
import WidgetKit

/// 이미 만든 캐릭터를 '진화'시키는 화면.
/// 기존 캐릭터를 참고 이미지로 넣고 원하는 진화 모습을 받아 새 그림 한 장을 만든다.
/// 카드·헤더·버튼 모듈은 '하나씩 만들기'(CharacterGenView) 와 같은 것을 그대로 쓴다.
struct CharacterEvolveView: View {
    /// 진화시킬 원본 — 내 캐릭터 갤러리에서 고른 그림.
    @State private var sourceImage: UIImage?
    @State private var showGalleryPicker: Bool = false

    @State private var targetState: CharacterState = .idle
    @State private var characterName: String = ""
    /// 고른 원본의 진화 단계 — 이름 뒤 '진화 N단계' 를 읽어서 다음 단계를 정한다.
    @State private var sourceStage: Int = 0

    @State private var isGenerating: Bool = false
    @State private var generateTask: Task<Void, Never>?
    @State private var generationStartedAt: Date?
    @State private var resultImage: UIImage?
    @State private var lastError: String?
    /// 직전 만들기가 실패했는지 — 실패면 결과 자리에 이전 그림 대신 이유를 띄운다.
    @State private var lastAttemptFailed: Bool = false
    /// 마지막으로 서버에 보낸 프롬프트 — 내부 기록용. 화면에 노출하지 않는다.
    @State private var lastSentPrompt: String?
    /// 결과를 자동 저장한 갤러리 항목 — '적용' 시 재사용해 중복 저장을 막음.
    @State private var galleryId: String?
    /// 한 캐릭터로 묶는 id — 갤러리 '캐릭터별' batchId.
    @State private var sessionId: String = UUID().uuidString

    @State private var showCandyConfirm: Bool = false
    @State private var showAppliedAlert: Bool = false
    @State private var showSavedAlert: Bool = false
    @State private var showPaywall: Bool = false
    @State private var remainingGenerations: Int = GenerationQuota.remainingToday()

    /// 진화는 항상 한 장 — low 품질로 만들고 캔디는 2개 소모.
    private let quality: String = "low"
    private let cost: Int = 2

    private static let resultAnchor = "withu.evolve.result"

    private var canGenerate: Bool { sourceImage != nil }

    /// 이번에 만들 진화 단계 (원본이 '진화 2단계'면 3).
    private var nextStage: Int { sourceStage + 1 }

    /// 결과에 붙일 이름 — '(이름)-진화 N단계'.
    private var evolvedName: String {
        let base = characterName.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? String(localized: "진화 \(nextStage)단계")
                            : "\(base)-진화 \(nextStage)단계"
    }

    var body: some View {
        ZStack {
            backgroundGradient(for: targetState, topTint: .withuPinkSoft).ignoresSafeArea()
                .animation(.snappy, value: targetState)
            ScrollViewReader { proxy in
                Form {
                    sourceSection
                    stateSection
                    nameSection
                    generateButtonSection
                    resultSection
                }
                .scrollContentBackground(.hidden)
                .onChange(of: isGenerating) { was, now in
                    guard was, !now, resultImage != nil else { return }
                    withAnimation { proxy.scrollTo(Self.resultAnchor, anchor: .top) }
                }
            }
        }
        .navigationTitle("캐릭터 진화시키기")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { candyBadge }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { remainingGenerations = GenerationQuota.remainingToday() }
        .sheet(isPresented: $showGalleryPicker) {
            GalleryReferencePicker(onPickItem: { item, img in
                sourceImage = img
                applySource(item)
            })
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(onClose: {
                showPaywall = false
                remainingGenerations = GenerationQuota.remainingToday()
            })
        }
        .alert("캔디를 사용해요", isPresented: $showCandyConfirm) {
            Button("만들기") { generateTask = Task { await generate() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이번 진화에 캔디 \(cost)개를 써요. 성공했을 때만 차감돼요.")
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
    }

    // MARK: - Sections

    /// 1. 진화시킬 캐릭터 — 내 캐릭터 갤러리에서 고른다. (참고 사진 섹션과 같은 모양)
    private var sourceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    if let src = sourceImage {
                        Image(uiImage: src)
                            .resizable()
                            .scaledToFit()
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
                    Button {
                        showGalleryPicker = true
                    } label: {
                        Label(sourceImage == nil
                              ? String(localized: "내 캐릭터에서 선택")
                              : String(localized: "다른 캐릭터로 바꾸기"),
                              systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isGenerating)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .plainCard()
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        } header: {
            Text("진화시킬 캐릭터")
                .font(.pretendardBold(16, relativeTo: .callout))
        } footer: {
            Text("선택한 캐릭터의 진화한 모습을 생성해요")
                .font(.pretendard(12, relativeTo: .caption))
                .foregroundStyle(.secondary)
        }
    }

    /// 2. 현재 캐릭터의 상태 — 어떤 자리의 모습으로 그릴지. ('하나씩 만들기'와 같은 모듈)
    private var stateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Picker("상태", selection: $targetState) {
                    ForEach(CharacterState.userFacing, id: \.self) { s in
                        Text(s.koreanShortLabel).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isGenerating)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .plainCard()
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        } header: {
            Text("현재 캐릭터의 상태")
                .font(.pretendardBold(16, relativeTo: .callout))
        }
    }

    /// 3. 캐릭터 이름 (선택)
    private var nameSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                TextField("이름 (선택)", text: $characterName)
                    .font(.pretendard(16, relativeTo: .callout))
                    .disabled(isGenerating)
                    .submitLabel(.done)
                // 갤러리에 저장될 이름 — 원본 이름을 이어받아 단계를 붙인다.
                Text(evolvedName)
                    .font(.pretendard(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
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

    /// 4. 만들기 — '하나씩 만들기'의 만들기 섹션과 같은 구조·문구.
    private var generateButtonSection: some View {
        Section {
            Button {
                showCandyConfirm = true
            } label: {
                if isGenerating {
                    generatingLabel
                } else {
                    Text("진화시키기")
                }
            }
            .buttonStyle(WithuCTAButtonStyle())
            .disabled(isGenerating || !canGenerate || remainingGenerations < cost)

            if isGenerating {
                Text("너무 오래 떠나 있으면 결과가 사라질 수 있으니, 화면에 머무르는 것을 권장해요.")
                    .font(.pretendard(13, relativeTo: .footnote))
                    .foregroundStyle(.orange)
                Button(role: .destructive) {
                    generateTask?.cancel()
                    generateTask = nil
                    isGenerating = false
                    generationStartedAt = nil
                    lastError = String(localized: "이미지 생성을 그만뒀어요.")
                } label: {
                    Label("그만두기", systemImage: "stop.circle.fill")
                }
                .tint(.secondary)
            } else if remainingGenerations < cost {
                Text("캔디가 부족해요. 충전하면 계속 만들 수 있어요.")
                    .font(.pretendard(13, relativeTo: .footnote))
                    .foregroundStyle(.orange)
                Button {
                    showPaywall = true
                } label: {
                    Label("더 만들기 (구독·충전)", systemImage: "sparkles")
                }
                .tint(.withuPink)
            } else if sourceImage == nil {
                // 왜 못 누르는지 알려준다 — 버튼만 비활성이면 이유를 모름.
                Text("진화시킬 캐릭터를 골라 주세요.")
                    .font(.pretendard(13, relativeTo: .footnote))
                    .foregroundStyle(.orange)
            } else {
                Text("보유 캔디 \(remainingGenerations)개 · \(cost)캔디 소모")
                    .font(.pretendard(13, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                if !isGenerating {
                    Text("약 20~30초 소요돼요.")
                }
                Text("\(cost)캔디 소모")
            }
            .font(.pretendard(12, relativeTo: .caption))
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var generatingLabel: some View {
        if let start = generationStartedAt {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let elapsed = Int(ctx.date.timeIntervalSince(start))
                HStack {
                    ProgressView().tint(.white)
                    Text("그리는 중… \(elapsed)초")
                }
            }
        } else {
            HStack { ProgressView().tint(.white); Text("그리는 중…") }
        }
    }

    /// 생성 중 결과 자리 — 이전 사진 대신 '만드는 중'.
    private var generatingPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.secondary.opacity(0.12))
            .frame(height: 220)
            .overlay {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("만드는 중…")
                        .font(.pretendard(13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
    }

    /// 실패한 결과 자리 — 이전 그림이 새 결과처럼 보이지 않게 이유를 여기 띄운다.
    private func failedPlaceholder(_ message: String) -> some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 220)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.pretendard(22, relativeTo: .title3))
                            .foregroundStyle(.orange)
                        Text("만들지 못했어요")
                            .font(.pretendard(13, relativeTo: .footnote))
                            .foregroundStyle(.secondary)
                    }
                }
            Text(message)
                .font(.pretendard(13, relativeTo: .footnote))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var resultSection: some View {
        if resultImage != nil || isGenerating || lastAttemptFailed {
            Section(header: Text("진화한 모습")
                .font(.pretendardBold(16, relativeTo: .callout))
                .id(Self.resultAnchor)) {
                VStack(alignment: .leading, spacing: 12) {
                    if isGenerating {
                        generatingPlaceholder
                    } else if lastAttemptFailed {
                        failedPlaceholder(lastError ?? String(localized: "다시 시도해 주세요."))
                    } else if let img = resultImage {
                        if galleryId != nil {
                            Label("캐릭터 갤러리에 저장됨", systemImage: "checkmark.circle")
                                .font(.pretendard(11, relativeTo: .caption2))
                                .foregroundStyle(.secondary)
                        }
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        HStack(spacing: 10) {
                            Button {
                                apply(img)
                            } label: {
                                Text("'\(targetState.koreanShortLabel)' 자리에 적용하기")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(WithuCTAButtonStyle())

                            PixelIconButton(systemImage: "square.and.arrow.down",
                                            accessibilityTitle: "사진 앱에 저장") {
                                Task { await saveToPhotos(img) }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .plainCard()
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
            }
        }
        // 생성 실패는 결과 자리에 띄운다 — 여기 배너는 그 외(저장 실패 등)만.
        if let err = lastError, !lastAttemptFailed {
            Section {
                WarningBanner(text: err)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
            }
        }
    }

    /// 보유 캔디 배지 — 탭하면 충전.
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

    // MARK: - Actions

    /// 고른 원본에서 이름과 진화 단계를 이어받는다.
    /// '위디-진화 2단계' 를 고르면 base='위디', stage=2 → 결과는 '위디-진화 3단계'.
    private func applySource(_ item: GalleryItem) {
        guard let batchId = item.batchId,
              let full = CharacterImageStore.characterName(for: batchId), !full.isEmpty else {
            characterName = ""
            sourceStage = 0
            return
        }
        let (base, stage) = Self.splitStage(full)
        characterName = base
        sourceStage = stage
    }

    /// '이름-진화 N단계' → (이름, N). 형식이 아니면 (원문, 0).
    static func splitStage(_ name: String) -> (base: String, stage: Int) {
        guard let range = name.range(of: "-진화 ", options: .backwards),
              name.hasSuffix("단계") else { return (name, 0) }
        let digits = name[range.upperBound...].dropLast(2)
        guard let n = Int(digits), n > 0 else { return (name, 0) }
        return (String(name[..<range.lowerBound]), n)
    }

    /// 서버로 보낼 프롬프트 — 사용자 입력 없이 우리가 조립한다(가챠).
    /// 정체성은 지키고, 더 강하고 성숙하게, 옷은 더 멋지게, 선정적이지 않게.
    private func composedPrompt() -> String {
        let name = characterName.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = name.isEmpty ? "" : " The character's name is \(name)."
        return """
        Use the reference image. Draw the SAME character in an EVOLVED form \
        (stage \(nextStage) — the higher the stage, the grander the presence).\(named)

        KEEP: same species and body plan, same face structure and expression style, same color \
        palette, same art style and line thickness, same signature motifs. It must read at a \
        glance as the same character, grown up.

        EVOLVE: stronger and more mature — a confident, capable presence. The face reads seasoned \
        and self-assured: steadier gaze, calm composure. Grown up, not aged; the same cute face \
        with depth behind it. Sharper silhouette, better proportions, richer detail and shading. \
        If it wears clothing, upgrade the outfit into a cooler, better-crafted version of the same \
        idea. Add ONE new trait the viewer would not have predicted, growing naturally out of what \
        it already is.

        RULES: wholesome only — no revealing clothing, no suggestive posing; a cute character, not \
        a pin-up. Do not change the species. Not grotesque, gory, or frightening. Cute-cool, not \
        edgy. Pose and scene: \(targetState.generationHint).
        """
    }

    private func generate() async {
        guard GenerationQuota.canGenerate(cost) else {
            lastError = String(localized: "캔디가 부족해요. 충전하면 계속 만들 수 있어요.")
            return
        }
        guard let source = sourceImage,
              let referenceB64 = source.pngData()?.base64EncodedString() else {
            lastError = String(localized: "진화시킬 캐릭터를 골라 주세요.")
            return
        }
        isGenerating = true
        generationStartedAt = .now
        lastError = nil
        lastAttemptFailed = false
        sessionId = UUID().uuidString      // 새 결과 = 새 캐릭터(갤러리 묶음)
        CharacterImageStore.setCharacterName(evolvedName, for: sessionId)

        // 백그라운드 진입해도 잠시 살아남게 — 만료 핸들러 필수(없으면 iOS 가 강제 종료).
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "withu.evolve") {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }
        defer {
            isGenerating = false
            generationStartedAt = nil
            generateTask = nil
            remainingGenerations = GenerationQuota.remainingToday()
            if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
        }
        do {
            try await APIClient.shared.preflightPing()
        } catch {
            lastError = String(localized: "지금은 연결이 어려워요. 와이파이나 인터넷을 확인하고 다시 해주세요.")
            return
        }

        let prevResult = resultImage
        await send(reference: referenceB64)
        guard resultImage !== prevResult, let img = resultImage else {
            lastAttemptFailed = true
            return
        }
        GenerationQuota.record(cost)
        // 결과 유실 방지 — 갤러리에 자동 저장 (활성 슬롯은 '적용' 눌러야 반영).
        let item = CharacterImageStore.save(img, for: targetState, frame: 0,
                                            applyToActiveSlot: false,
                                            batchId: sessionId, prompt: lastSentPrompt,
                                            userInput: nil)
        galleryId = item?.id
    }

    private func send(reference: String) async {
        // kind 를 넘겨 계정 무료 1회('처음 만드는 화면' 전용)를 소진하지 않게 한다.
        let finalPrompt = "\(composedPrompt()) Only the character on a transparent background — no background fill, no shadows, no extra elements."
        do {
            let req = GenerateImageRequest(
                prompt: finalPrompt,
                referenceImageBase64: reference,
                steps: 30,
                width: 1024,
                height: 1024,
                quality: quality,
                artStyle: "pixel",
                style: "auto",
                kind: "evolve",
                model: "gpt-image-2",
                userInput: "진화 \(nextStage)단계",
                inputField: "진화"
            )
            let resp = try await APIClient.shared.generateImage(req, sessionId: sessionId,
                                                               state: targetState.rawValue)
            guard let data = Data(base64Encoded: resp.imageBase64),
                  let rawImg = UIImage(data: data) else {
                lastError = String(localized: "이미지를 불러오지 못했어요. 다시 시도해 주세요.")
                return
            }
            // gpt-image-2 는 마젠타 단색 배경으로 옴 → 크로마키로 투명화.
            let img = await ImageProcessing.transparentized(rawImg)
            resultImage = img.preparingThumbnail(of: CGSize(width: 128, height: 128)) ?? img
            lastSentPrompt = finalPrompt
            if let ent = resp.entitlement { AuthManager.shared.applyEntitlement(ent) }
        } catch APIError.paymentRequired {
            showPaywall = true
        } catch {
            lastError = error.koreanizedDescription
        }
    }

    private func apply(_ image: UIImage) {
        // 이미 자동 저장된 결과면 그 갤러리 항목을 재사용 — '적용'이 같은 결과를 또 저장하지 않게.
        let ok: Bool
        if let galleryId, CharacterImageStore.applyGalleryItem(galleryId, to: targetState) {
            ok = true
        } else {
            ok = CharacterImageStore.save(image, for: targetState, frame: 0,
                                          prompt: lastSentPrompt,
                                          userInput: nil) != nil
        }
        if ok {
            CharacterProfileStore.syncNameFromApplied(targetState)
            ConnectivityManager.shared.sendCharacterImage(image, for: targetState, frame: 0)
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
    NavigationStack { CharacterEvolveView() }
}
