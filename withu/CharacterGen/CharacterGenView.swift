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
    @State private var quality: String = "medium"
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
                promptSection
                referenceSection
                optionsSection
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
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let img = resultImage {
            Section("결과") {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                if let revised = revisedPrompt {
                    DisclosureGroup("OpenAI 가 사용한 실제 프롬프트") {
                        Text(revised).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button {
                    apply(img, to: targetState)
                } label: {
                    Label("'\(targetState.rawValue)' 자리에 적용", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                Button("사진 앱에 저장") {
                    Task { await saveToPhotos(img) }
                }
            }
        }
        if let err = lastError {
            Section { Text(err).foregroundStyle(.red) }
        }
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
        defer {
            isGenerating = false
            generationStartedAt = nil
        }
        let referenceB64 = referenceImage?.pngData()?.base64EncodedString()
        await send(prompt: prompt, reference: referenceB64)
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

    private func send(prompt: String, reference: String?) async {
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
            let resp = try await APIClient.shared.generateImage(req)
            guard let data = Data(base64Encoded: resp.imageBase64),
                  let img = UIImage(data: data) else {
                lastError = "이미지 디코드 실패"
                return
            }
            // AI 출력의 가짜 체커보드를 진짜 alpha 로 후처리 (Vision 실패 시 원본)
            resultImage = await ImageProcessing.bestEffortTransparent(img)
            revisedPrompt = resp.revisedPrompt
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
        if CharacterImageStore.save(image, for: state) != nil {
            WidgetCenter.shared.reloadAllTimelines()
            // 워치도 같이 갱신 — file transfer (백그라운드, OS 가 안정적 처리)
            ConnectivityManager.shared.sendCharacterImage(image, for: state)
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
