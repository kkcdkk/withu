//
//  CharacterGenView.swift
//  withu
//

import SwiftUI
import PhotosUI
import WidgetKit

struct CharacterGenView: View {
    @State private var targetState: CharacterState = .idle
    @State private var prompt: String = CharacterState.idle.generationHint
    @State private var refinementPrompt: String = ""

    /// "low" $0.011 / "medium" $0.04 / "high" $0.17
    @State private var quality: String = "medium"
    @State private var artStyle: String = "casual"   // "casual" | "pixel"

    /// 사용자가 사진 앱에서 첨부한 참고 이미지 (있으면 reference 로 보냄)
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var referenceImage: UIImage?

    @State private var isGenerating: Bool = false
    @State private var resultImage: UIImage?
    @State private var revisedPrompt: String?
    @State private var lastError: String?
    @State private var showAppliedAlert: Bool = false
    @State private var showSavedAlert: Bool = false
    @State private var generationStartedAt: Date?

    var body: some View {
        Form {
            stateSection
            promptSection
            referenceSection
            optionsSection
            resultSection
            refinementSection
        }
        .navigationTitle("캐릭터 만들기")
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
    }

    // MARK: - State picker

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
            .disabled(isGenerating)

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

    // MARK: - Prompt

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

    /// 생성 버튼 라벨 — ProgressView + 경과 초 카운트.
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

    // MARK: - Reference image attach

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

    // MARK: - Options

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

    // MARK: - Result

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

    // MARK: - Refinement

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

    // MARK: - Actions

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
            resultImage = img
            revisedPrompt = resp.revisedPrompt
        } catch {
            lastError = "❌ \(error.localizedDescription)"
        }
    }

    private func apply(_ image: UIImage, to state: CharacterState) {
        let ok = CharacterImageStore.save(image, for: state)
        if ok {
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
}

#Preview {
    NavigationStack { CharacterGenView() }
}
