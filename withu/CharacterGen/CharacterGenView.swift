//
//  CharacterGenView.swift
//  withu
//

import SwiftUI
import PhotosUI
import WidgetKit

enum GenerationMode: String, CaseIterable, Hashable {
    case aiGenerate = "AI 생성"
    case importPhoto = "이미지 첨부"
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

    @State private var isGenerating: Bool = false
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

    var body: some View {
        Form {
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
            Section {
                NavigationLink {
                    BatchCharacterGenView()
                } label: {
                    Label("여러 상태 한 번에 만들기", systemImage: "square.grid.3x3.fill")
                }
            }
        }
        .navigationTitle("함께할 캐릭터 생성하기")
        .scrollDismissesKeyboard(.interactively)
        .alert("적용됨", isPresented: $showAppliedAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("\(targetState.rawValue) 상태의 캐릭터가 교체됐어요. 메인 화면/위젯/워치에 즉시 반영됩니다.")
        }
        .alert("저장됨", isPresented: $showSavedAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("사진 앱에 추가됐어요.")
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

    private var modeSection: some View {
        Section {
            Picker("방식", selection: $mode) {
                ForEach(GenerationMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isGenerating || isProcessing)
        } footer: {
            switch mode {
            case .aiGenerate:
                Text("프롬프트로 캐릭터를 새로 만듭니다 (OpenAI 호출, 비용 발생).")
                    .foregroundStyle(.secondary)
            case .importPhoto:
                Text("내가 가진 사진/그림을 그대로 사용. 자동으로 배경 제거 + 정사각형 정규화 (무료, 로컬 처리).")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stateSection: some View {
        Section {
            Picker("어떤 상태?", selection: $targetState) {
                ForEach(CharacterState.allCases, id: \.self) { s in
                    HStack {
                        Text(s.symbolEmoji)
                        Text(s.rawValue)
                    }
                    .tag(s)
                }
            }
            .pickerStyle(.menu)
            .disabled(isGenerating || isProcessing)

            HStack {
                Text("현재 적용된 이미지")
                Spacer()
                Text(CharacterImageStore.hasImage(for: targetState) ? "사용자 생성" : "placeholder")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        } header: {
            Text("어떤 상태용 이미지?")
        }
    }

    // MARK: - AI generate sections

    private var promptSection: some View {
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
                    Label("이미지 생성", systemImage: "wand.and.stars")
                }
            }
            .disabled(isGenerating || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("프롬프트")
        } footer: {
            if isGenerating {
                Text("⚠️ 생성 중엔 앱을 그대로 켜둬 주세요.")
                    .foregroundStyle(.orange)
            } else {
                Text("그림체/가드레일은 서버가 자동으로 붙입니다.\n실측: low ~20초 · medium ~50초 · high 1~2분")
                    .foregroundStyle(.secondary)
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
                    Text("생성 중… \(elapsed)초")
                }
            }
        } else {
            HStack { ProgressView(); Text("생성 중…") }
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
                        Button("참고 이미지 제거", role: .destructive) {
                            referenceImage = nil
                            photoPickerItem = nil
                        }
                        .disabled(isGenerating)
                    }
                }
            }
        } header: {
            Text("참고 이미지 (선택)")
        } footer: {
            Text("첨부하면 이 이미지를 참고해 새 캐릭터를 만들어요. 비워두면 텍스트만으로 생성.")
                .foregroundStyle(.secondary)
        }
    }

    private var optionsSection: some View {
        Section("옵션") {
            Picker("그림체", selection: $artStyle) {
                Text("일반 (파스텔)").tag("casual")
                Text("픽셀 (8/16-bit)").tag("pixel")
            }
            .pickerStyle(.segmented)
            .disabled(isGenerating)

            Picker("품질", selection: $quality) {
                Text("low — $0.011").tag("low")
                Text("medium — $0.04").tag("medium")
                Text("high — $0.17").tag("high")
            }
            .pickerStyle(.menu)
            .disabled(isGenerating)

            Toggle("연속 이미지 (2장 생성)", isOn: $generateAnimated)
                .disabled(isGenerating)
            if generateAnimated {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Frame 2 변화 힌트 (영어)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $animationHint)
                        .frame(minHeight: 70)
                        .font(.callout)
                        .disabled(isGenerating)
                    Text("Frame 1 과 어떻게 다를지. 비워두면 위 state 의 기본 힌트 자동 사용.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
                            Text("frame 1").font(.caption2).foregroundStyle(.secondary)
                        }
                        VStack(spacing: 4) {
                            Image(uiImage: f1).resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text("frame 2").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } else if let f0 {
                    Image(uiImage: f0)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                // 원본 / 투명 토글
                Picker("표시", selection: $displayTransparent) {
                    Text("원본 (흰 배경)").tag(false)
                    Text("투명 적용").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(isProcessingTransparent)
                .onChange(of: displayTransparent) { _, new in
                    if new {
                        Task { await ensureTransparentResults() }
                    }
                }
                if isProcessingTransparent {
                    HStack { ProgressView(); Text("Vision 으로 배경 추출 중…") }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let revised = revisedPrompt {
                    DisclosureGroup("OpenAI 가 사용한 실제 프롬프트") {
                        Text(revised).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let f0 {
                    Button {
                        applyCurrentSelection()
                    } label: {
                        Label("'\(targetState.rawValue)' 자리에 적용", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessingTransparent)
                    Button("사진 앱에 저장") {
                        Task { await saveToPhotos(f0) }
                    }
                }
            }
        }
        if let err = lastError {
            Section { Text(err).foregroundStyle(.red) }
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
                        Label("이어서 다듬기", systemImage: "sparkles")
                    }
                }
                .disabled(isGenerating || refinementPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("이어서 다듬기")
            } footer: {
                Text("위 결과를 참고해 새 이미지로 변형. 매 호출은 동일 비용.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Import sections

    private var importSection: some View {
        Section {
            PhotosPicker(importedRawImage == nil ? "사진 선택" : "다른 사진으로 변경",
                         selection: $importPickerItem,
                         matching: .images)
                .disabled(isProcessing)
            if isProcessing {
                HStack { ProgressView(); Text("배경 제거 + 정규화 중…") }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("사진 선택")
        } footer: {
            Text("선택하면 자동으로 배경 제거 + 정사각형 1024×1024 정규화. OpenAI 호출 없음 (무료, 로컬 처리).")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var importResultSection: some View {
        if let processed = importedProcessedImage {
            Section("처리 결과") {
                ZStack {
                    // 투명 배경 시각화: 체커보드 같은 회색
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(uiColor: .tertiarySystemBackground))
                    Image(uiImage: processed)
                        .resizable()
                        .scaledToFit()
                }
                .frame(maxHeight: 300)

                Button {
                    apply(processed, to: targetState)
                } label: {
                    Label("'\(targetState.rawValue)' 자리에 적용", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                Button("사진 앱에 저장") {
                    Task { await saveToPhotos(processed) }
                }
            }
        }
        if let err = lastError {
            Section { Text(err).foregroundStyle(.red) }
        }
    }

    // MARK: - Actions (AI generate)

    private func generate() async {
        isGenerating = true
        generationStartedAt = .now
        lastError = nil
        resultFrame2 = nil
        defer {
            isGenerating = false
            generationStartedAt = nil
        }
        // 사전 reachability 체크 — 30분 timeout 매달리지 않도록.
        do {
            try await APIClient.shared.preflightPing()
        } catch {
            lastError = "서버에 연결할 수 없어요. 네트워크 또는 서버 상태를 확인하고 다시 시도해 주세요."
            return
        }
        let referenceB64 = referenceImage?.pngData()?.base64EncodedString()
        await send(prompt: prompt, reference: referenceB64, frame: 0)
        // 연속 이미지 — frame 0 성공 시 그 결과를 reference 로 frame 1 추가
        if generateAnimated, let f0 = resultImage,
           let f0Ref = f0.pngData()?.base64EncodedString() {
            let trimmedHint = animationHint.trimmingCharacters(in: .whitespacesAndNewlines)
            let hint = trimmedHint.isEmpty ? targetState.animationFrame2Hint : trimmedHint
            let animPrompt = "\(prompt). Animation frame 2 (for a 2-frame swap loop): \(hint)"
            await send(prompt: animPrompt, reference: f0Ref, frame: 1)
        }
    }

    private func refine() async {
        guard let current = resultImage,
              let pngData = current.pngData() else {
            lastError = "기존 이미지를 base64 로 변환 실패"
            return
        }
        let referenceB64 = pngData.base64EncodedString()
        isGenerating = true
        generationStartedAt = .now
        lastError = nil
        defer {
            isGenerating = false
            generationStartedAt = nil
        }
        await send(prompt: refinementPrompt, reference: referenceB64)
        refinementPrompt = ""
    }

    private func send(prompt: String, reference: String?, frame: Int = 0) async {
        // AI 에 흰 배경 강제 — 결과를 사용자가 post-gen 에 Vision 으로 정제할 수 있음.
        let finalPrompt = "\(prompt). Solid clean WHITE background, no shadows, no gradients, no other elements behind the character."
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
                lastError = "이미지 디코드 실패"
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
        } catch {
            lastError = "❌ \(error.localizedDescription)"
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
                referenceImage = img
            }
        } catch {
            lastError = "참고 이미지 로드 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - Actions (Import)

    private func loadAndProcessImport(_ item: PhotosPickerItem?) async {
        guard let item else {
            importedRawImage = nil
            importedProcessedImage = nil
            return
        }
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let raw = UIImage(data: data) else {
                lastError = "사진 로드 실패"
                return
            }
            importedRawImage = raw
            let processed = try await ImageProcessing.prepareForCharacter(raw)
            importedProcessedImage = processed
        } catch {
            lastError = "❌ \(error.localizedDescription)"
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
            showAppliedAlert = true
        } else {
            lastError = "❌ App Group 저장 실패"
        }
    }

    private func saveToPhotos(_ image: UIImage) async {
        do {
            try await PhotoSaver.save(image)
            lastError = nil
            showSavedAlert = true
        } catch {
            lastError = "❌ \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack { CharacterGenView() }
}
