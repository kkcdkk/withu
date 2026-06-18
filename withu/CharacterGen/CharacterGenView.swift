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
    @State private var mode: GenerationMode = .aiGenerate

    @State private var targetState: CharacterState = .idle
    @State private var prompt: String = CharacterState.idle.generationHint
    @State private var refinementPrompt: String = ""

    /// "low" $0.011 / "medium" $0.04 / "high" $0.17
    @State private var quality: String = "low"
    @State private var artStyle: String = "casual"   // "casual" | "pixel"

    /// AI 생성 모드 — 사진 앱에서 첨부한 참고 이미지 (있으면 reference 로 보냄)
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var referenceImage: UIImage?

    /// 이미지 첨부 모드 — 첨부 + 배경 제거 처리된 결과
    @State private var importPickerItem: PhotosPickerItem?
    @State private var importedRawImage: UIImage?
    @State private var importedProcessedImage: UIImage?
    @State private var isProcessing: Bool = false
    /// 배경 빼기 스위치 (ON: 배경 제거본, OFF: 원본 그대로)
    @State private var removeBackground: Bool = true

    @State private var isGenerating: Bool = false
    @State private var generateTask: Task<Void, Never>?  // cancel 가능하도록 핸들 보관
    @State private var resultImage: UIImage?
    @State private var resultFrame2: UIImage?    // frame 1 (애니메이션용)
    @State private var generateAnimated: Bool = false
    /// frame 2 prompt 의 변화 힌트 (영어). 토글 ON 일 때만 노출.
    /// targetState 가 바뀌면 그 state 의 기본 hint 로 자동 갱신.
    @State private var animationHint: String = CharacterState.idle.animationFrame2Hint
    /// frame 0/1 의 raw (white BG) ↔ transparent (Vision 처리) 캐시.
    /// 사용자가 [원본] / [투명 적용] 토글로 표시/적용 버전 선택.
    @State private var transparentResult: UIImage?
    @State private var transparentResultFrame2: UIImage?
    @State private var displayTransparent: Bool = false
    @State private var isProcessingTransparent: Bool = false
    @State private var revisedPrompt: String?
    @State private var lastError: String?
    @State private var showAppliedAlert: Bool = false
    @State private var showSavedAlert: Bool = false
    @State private var generationStartedAt: Date?
    @State private var remainingGenerations: Int = GenerationQuota.remainingToday()
    @State private var showPaywall: Bool = false
    /// 사진 선택 후 정사각 자르기 시트
    @State private var cropTarget: CropTarget?

    var body: some View {
        ZStack {
            backgroundGradient(for: targetState).ignoresSafeArea()
                .animation(.snappy, value: targetState)
            Form {
                batchSection
                modeSection
                stateSection
                if mode == .aiGenerate {
                    optionsSection
                    referenceSection
                    promptSection
                    resultSection
                    refinementSection
                } else {
                    importSection
                    importResultSection
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("캐릭터 만들기")
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
        .onChange(of: targetState) { _, new in
            prompt = new.generationHint
            animationHint = new.animationFrame2Hint
            refinementPrompt = ""
        }
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
        }
    }

    // MARK: - Common sections

    /// 처음 시작하는 사용자가 가장 먼저 보게 — 9개 state 일괄 생성.
    private var batchSection: some View {
        Section {
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
        } footer: {
            Text("처음이라면 이걸 추천해요. 한 가지씩 만들고 싶으면 아래에서 골라요.")
                .font(.caption2)
        }
    }

    private var modeSection: some View {
        Section {
            ForEach(GenerationMode.allCases, id: \.self) { m in
                Button {
                    mode = m
                } label: {
                    HStack {
                        Text(m.rawValue)
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
        } header: {
            Text("생성 옵션")
        } footer: {
            switch mode {
            case .aiGenerate:
                Text("프롬프트대로 새 캐릭터를 그려줘요. 만들 때마다 선택한 옵션에 따라 비용이 들어요.")
                    .foregroundStyle(.secondary)
            case .importPhoto:
                Text("가지고 있는 사진이나 그림을 그대로 이용헤요. 배경을 자동으로 제거하고 정사각형으로 다듬어요. 비용은 들지 않아요.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stateSection: some View {
        Section {
            Picker("상태", selection: $targetState) {
                ForEach(CharacterState.userFacing, id: \.self) { s in
                    Text(s.koreanShortLabel).tag(s)
                }
            }
            .pickerStyle(.menu)
            .disabled(isGenerating || isProcessing)
        } header: {
            Text("상태")
        }
    }

    // MARK: - AI generate sections

    private var promptSection: some View {
        Section {
            TextEditor(text: $prompt)
                .frame(minHeight: 100)
                .font(.callout)
            if isGenerating {
                generatingLabel
                Button(role: .destructive) {
                    generateTask?.cancel()
                    generateTask = nil
                    isGenerating = false
                    generationStartedAt = nil
                    lastError = "이미지 생성을 그만뒀어요."
                } label: {
                    Label("그만두기", systemImage: "stop.circle.fill")
                }
            } else if remainingGenerations == 0 {
                Button {
                    showPaywall = true
                } label: {
                    Label("더 만들기 (구독·충전)", systemImage: "sparkles")
                }
            } else {
                Button {
                    generateTask = Task { await generate() }
                } label: {
                    Label("이 모습으로 만들기", systemImage: "wand.and.stars")
                }
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("캐릭터 생성")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if isGenerating {
                    Text("너무 오래 떠나 있으면 결과가 사라질 수 있으니, 화면에 머무르는 것을 권장해요.")
                        .foregroundStyle(.orange)
                } else {
                    Text("평균 low 20초, medium 50초, high 1~2분 정도 걸려요.")
                        .foregroundStyle(.secondary)
                }
                if remainingGenerations == 0 {
                    Text("오늘은 더 만들 수 없어요. 내일 다시 만들 수 있어요.")
                        .foregroundStyle(.orange)
                } else {
                    Text("오늘 \(remainingGenerations)번 더 만들 수 있어요.")
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
            Text("참고용 사진 (선택)")
        } footer: {
            Text("사진을 넣으면 그 모습을 참고해서 만들어요. 비워두면 글로만 만들어요.")
                .foregroundStyle(.secondary)
        }
    }

    private var optionsSection: some View {
        Section("스타일") {
            Picker("그림 스타일", selection: $artStyle) {
                Text("Soft").tag("casual")
                Text("Pixel").tag("pixel")
            }
            .pickerStyle(.segmented)
            .disabled(isGenerating)

            Picker("퀄리티", selection: $quality) {
                Text("low (약 20초 · 15원)").tag("low")
                Text("medium (약 50초 · 55원)").tag("medium")
                Text("high (1~2분 · 230원)").tag("high")
            }
            .pickerStyle(.menu)
            .disabled(isGenerating)

            DisclosureGroup("퀄리티별 미리보기") {
                qualityPreviewRow(label: "low", asset: "quality_low")
                qualityPreviewRow(label: "medium", asset: "quality_medium")
                qualityPreviewRow(label: "high", asset: "quality_high")
            }

            Toggle("움직이는 캐릭터로 만들기", isOn: $generateAnimated)
                .disabled(isGenerating)
            if generateAnimated {
                VStack(alignment: .leading, spacing: 4) {
                    Text("두 번째 장면")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $animationHint)
                        .frame(minHeight: 70)
                        .font(.callout)
                        .disabled(isGenerating)
                    Text("첫 장면과 어떻게 다를지 적어요. 영어로 적으면 더 정확해요. 비워두면 알아서 채워져요.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 퀄리티별 예시 한 줄. Assets.xcassets 에 quality_low/medium/high 추가하면 그 사진,
    /// 없으면 "사진 넣기" placeholder.
    private func qualityPreviewRow(label: String, asset: String) -> some View {
        HStack(spacing: 12) {
            Group {
                if UIImage(named: asset) != nil {
                    Image(asset)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(Color(uiColor: .tertiarySystemBackground))
                        VStack(spacing: 2) {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                            Text("사진 넣기")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(label)
                .font(.callout)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var resultSection: some View {
        if resultImage != nil {
            Section("결과") {
                // 표시할 frame 0, frame 1 — 현재 모드 (raw / transparent) 에 따라
                let f0 = currentDisplay(frame: 0)
                let f1 = currentDisplay(frame: 1)
                if let f0, let f1 {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 4) {
                            Image(uiImage: f0).resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text("1번째").font(.caption2).foregroundStyle(.secondary)
                        }
                        VStack(spacing: 4) {
                            Image(uiImage: f1).resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text("2번째").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } else if let f0 {
                    Image(uiImage: f0)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                        Label("'\(targetState.koreanShortLabel)' 자리에 적용하기", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.withuPink)
                    .disabled(isProcessingTransparent)
                    Button("사진 앱에 저장") {
                        Task { await saveToPhotos(f0) }
                    }
                    .tint(.secondary)
                }
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

    /// 현재 displayTransparent 모드에서 보여줄 이미지. 토글 ON 이고 cache 있으면 transparent, 없으면 raw.
    private func currentDisplay(frame: Int) -> UIImage? {
        let raw = frame == 0 ? resultImage : resultFrame2
        guard displayTransparent else { return raw }
        let transparent = frame == 0 ? transparentResult : transparentResultFrame2
        return transparent ?? raw
    }

    /// "투명 적용" 켰을 때 transparentResult / Frame2 가 없으면 Vision 으로 처리.
    @MainActor
    private func ensureTransparentResults() async {
        guard transparentResult == nil else { return }
        guard let raw = resultImage else { return }
        isProcessingTransparent = true
        defer { isProcessingTransparent = false }
        let t0 = await ImageProcessing.bestEffortTransparent(raw)
        transparentResult = t0
        if let rawF2 = resultFrame2 {
            let t1 = await ImageProcessing.bestEffortTransparent(rawF2)
            transparentResultFrame2 = t1
        }
    }

    /// 현재 선택된 모드의 이미지로 적용.
    private func applyCurrentSelection() {
        guard let img = currentDisplay(frame: 0) else { return }
        apply(img, to: targetState)
    }

    @ViewBuilder
    private var refinementSection: some View {
        if resultImage != nil {
            Section {
                TextEditor(text: $refinementPrompt)
                    .frame(minHeight: 80)
                    .font(.callout)
                Button {
                    Task { await refine() }
                } label: {
                    if isGenerating {
                        HStack { ProgressView(); Text("다듬는 중…") }
                    } else {
                        Label("이대로 바꾸기", systemImage: "sparkles")
                    }
                }
                .disabled(isGenerating || refinementPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("이어서 다듬기")
            } footer: {
                Text("위 결과를 바탕으로 조금씩 바꿔가요. 다듬을 때마다 같은 비용이 들어요.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Import sections

    private var importSection: some View {
        Section {
            PhotosPicker(importedRawImage == nil ? "사진 고르기" : "다른 사진으로 바꾸기",
                         selection: $importPickerItem,
                         matching: .images)
                .disabled(isProcessing)
            if isProcessing {
                HStack { ProgressView(); Text("배경 빼고 다듬는 중…") }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("사진 고르기")
        } footer: {
            Text("사진을 고르면 정사각형으로 다듬어요. 배경을 뺄지는 아래에서 고를 수 있어요. 모두 기기 안에서 처리하고 비용은 들지 않아요.")
                .foregroundStyle(.secondary)
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

                if isProcessing {
                    HStack { ProgressView(); Text("배경 빼는 중…") }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    apply(display, to: targetState)
                } label: {
                    Label("'\(targetState.koreanShortLabel)' 자리에 적용하기", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.withuPink)
                .disabled(removeBackground && isProcessing)
                Button("사진 앱에 저장") {
                    Task { await saveToPhotos(display) }
                }
                .tint(.secondary)
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

    private func generate() async {
        guard GenerationQuota.canGenerate() else {
            lastError = "오늘 만들 수 있는 횟수를 다 썼어요. 내일 다시 시도해 주세요."
            return
        }
        isGenerating = true
        generationStartedAt = .now
        lastError = nil
        resultFrame2 = nil
        // 백그라운드 진입해도 30초까지 살아남게 background task assertion.
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "withu.generate")
        defer {
            isGenerating = false
            generationStartedAt = nil
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
            lastError = "지금은 연결이 어려워요. 와이파이나 인터넷을 확인하고 다시 해주세요."
            return
        }
        let referenceB64 = referenceImage?.pngData()?.base64EncodedString()
        await send(prompt: prompt, reference: referenceB64, frame: 0)
        // 성공한 장만 횟수 차감
        if resultImage != nil { GenerationQuota.record() }
        // 연속 이미지 — frame 0 성공 시 그 결과를 reference 로 frame 1 추가
        if generateAnimated, let f0 = resultImage,
           let f0Ref = f0.pngData()?.base64EncodedString() {
            let trimmedHint = animationHint.trimmingCharacters(in: .whitespacesAndNewlines)
            let hint = trimmedHint.isEmpty ? targetState.animationFrame2Hint : trimmedHint
            let animPrompt = "\(prompt). Animation frame 2 (for a 2-frame swap loop): \(hint)"
            await send(prompt: animPrompt, reference: f0Ref, frame: 1)
            if resultFrame2 != nil { GenerationQuota.record() }
        }
    }

    private func refine() async {
        guard GenerationQuota.canGenerate() else {
            lastError = "오늘 만들 수 있는 횟수를 다 썼어요. 내일 다시 시도해 주세요."
            return
        }
        guard let current = resultImage,
              let pngData = current.pngData() else {
            lastError = "기존 이미지를 다시 불러오지 못했어요. 다시 시도해 주세요."
            return
        }
        let referenceB64 = pngData.base64EncodedString()
        isGenerating = true
        generationStartedAt = .now
        lastError = nil
        defer {
            isGenerating = false
            generationStartedAt = nil
            remainingGenerations = GenerationQuota.remainingToday()
        }
        await send(prompt: refinementPrompt, reference: referenceB64)
        if resultImage != nil { GenerationQuota.record() }
        refinementPrompt = ""
    }

    private func send(prompt: String, reference: String?, frame: Int = 0) async {
        // AI 에 흰 배경 강제 — 결과를 사용자가 post-gen 에 Vision 으로 정제할 수 있음.
        // 격자(체커보드) 방지: 일부 모델이 "투명"을 격자 무늬로 그려버림 → 단색 흰배경 명시.
        let finalPrompt = "\(prompt). Solid clean WHITE background, no shadows, no gradients, no other elements behind the character. Never draw a checkerboard or transparency grid pattern — the background must be one flat solid white color."
        do {
            let req = GenerateImageRequest(
                prompt: finalPrompt,
                referenceImageBase64: reference,
                steps: 30,
                width: 1024,
                height: 1024,
                quality: quality,
                artStyle: artStyle,
                style: "auto"
            )
            let resp = try await APIClient.shared.generateImage(req)
            guard let data = Data(base64Encoded: resp.imageBase64),
                  let img = UIImage(data: data) else {
                lastError = "이미지를 불러오지 못했어요. 다시 시도해 주세요."
                return
            }
            // raw (white BG) 그대로 저장 — Vision 처리는 사용자가 post-gen 에 선택.
            // 128px 로 다운샘플 — 메인 화면 200, 워치 64, 위젯 60 다 커버 + 디스크 절약
            let small = img.preparingThumbnail(of: CGSize(width: 128, height: 128)) ?? img
            if frame == 0 {
                resultImage = small
                revisedPrompt = resp.revisedPrompt
            } else {
                resultFrame2 = small
            }
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
            lastError = "사진을 불러오지 못했어요."
        }
    }

    // MARK: - Actions (Import)

    private func loadAndProcessImport(_ item: PhotosPickerItem?) async {
        guard let item else {
            importedRawImage = nil
            importedProcessedImage = nil
            return
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let raw = UIImage(data: data) else {
                lastError = "사진을 불러오지 못했어요."
                return
            }
            // 선택 후 정사각 자르기 → 자른 이미지로 배경 제거 처리
            cropTarget = CropTarget(image: raw) { cropped in
                Task { await processImport(cropped) }
            }
        } catch {
            lastError = "사진을 불러오지 못했어요."
        }
    }

    /// 자른 이미지 배경 제거 + 정규화.
    private func processImport(_ image: UIImage) async {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }
        importedRawImage = image
        do {
            let processed = try await ImageProcessing.prepareForCharacter(image)
            importedProcessedImage = processed
        } catch {
            lastError = error.koreanizedDescription
            importedProcessedImage = nil
        }
    }

    // MARK: - Common actions

    private func apply(_ image: UIImage, to state: CharacterState) {
        if CharacterImageStore.save(image, for: state, frame: 0) != nil {
            ConnectivityManager.shared.sendCharacterImage(image, for: state, frame: 0)
            // frame 1 — 현재 displayTransparent 모드 존중 (transparent cache 있으면 그걸 우선)
            if let f2 = currentDisplay(frame: 1) {
                CharacterImageStore.save(f2, for: state, frame: 1)
                ConnectivityManager.shared.sendCharacterImage(f2, for: state, frame: 1)
            }
            WidgetCenter.shared.reloadAllTimelines()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showAppliedAlert = true
        } else {
            lastError = "저장하지 못했어요. 다시 시도해 주세요."
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
    @State private var artStyle: String = "casual"
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
                    Text(CharacterImageStore.hasBackground(condition) ? "생성한 그림" : "없음")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            } header: {
                Text("날씨")
            }

            Section("스타일") {
                Picker("그림 스타일", selection: $artStyle) {
                    Text("soft").tag("casual")
                    Text("pixel").tag("pixel")
                }
                .pickerStyle(.segmented).disabled(isGenerating)
                Picker("퀄리티", selection: $quality) {
                    Text("빠르게 (약 20초 · 15원)").tag("low")
                    Text("보통 (약 50초 · 55원)").tag("medium")
                    Text("선명하게 (1~2분 · 230원)").tag("high")
                }
                .pickerStyle(.menu).disabled(isGenerating)
            }

            Section {
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
            } header: {
                Text("배경")
            } footer: {
                Text("캐릭터는 빼고 풍경만 그려요. 「밤하늘」, 「비 오는 도시 골목」처럼 자유롭게 적어주세요.")
                    .font(.caption2)
            }

            if let img = resultImage {
                Section {
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
                        Label("'\(condition.displayName)' 배경으로 적용하기", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.withuPink)
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
            lastError = "지금은 연결이 어려워요. 와이파이나 인터넷을 확인하고 다시 해주세요."
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
                kind: "background"   // 서버가 SYSTEM_PROMPT 건너뜀
            )
            let resp = try await APIClient.shared.generateImage(req)
            guard let data = Data(base64Encoded: resp.imageBase64),
                  let img = UIImage(data: data) else {
                lastError = "이미지를 불러오지 못했어요. 다시 시도해 주세요."
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
            lastError = "저장하지 못했어요. 다시 시도해 주세요."
        }
    }
}

#Preview("WeatherBg") {
    NavigationStack { WeatherBackgroundGenView() }
}
