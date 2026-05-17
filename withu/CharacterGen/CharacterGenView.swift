//
//  CharacterGenView.swift
//  withu
//
//  로컬 FastAPI 서버 → OpenAI gpt-image-2 로 캐릭터 이미지 생성/편집.
//

import SwiftUI
import WidgetKit

struct CharacterGenView: View {
    /// 어떤 상태용 이미지를 만들 건지. 변경되면 prompt placeholder 가 자동 갱신.
    @State private var targetState: CharacterState = .idle
    @State private var prompt: String = CharacterState.idle.generationHint
    @State private var refinementPrompt: String = ""

    /// "low" $0.011 / "medium" $0.04 / "high" $0.17
    @State private var quality: String = "medium"
    @State private var isGenerating: Bool = false
    @State private var resultImage: UIImage?
    @State private var revisedPrompt: String?
    @State private var lastError: String?
    @State private var showAppliedAlert: Bool = false
    @State private var showSavedAlert: Bool = false

    var body: some View {
        Form {
            stateSection
            promptSection
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
            // 상태 바뀔 때 prompt 가 비어있거나 기본값이면 새 hint 로 교체
            prompt = new.generationHint
            refinementPrompt = ""
        }
    }

    // MARK: - Sections

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
        } footer: {
            Text("선택한 상태에 어울리는 프롬프트가 아래에 자동으로 채워져요.")
                .foregroundStyle(.secondary)
        }
    }

    private var promptSection: some View {
        Section {
            TextEditor(text: $prompt)
                .frame(minHeight: 100)
                .font(.callout)
            Button {
                Task { await generate() }
            } label: {
                if isGenerating {
                    HStack { ProgressView(); Text("생성 중…") }
                } else {
                    Label("이미지 생성", systemImage: "wand.and.stars")
                }
            }
            .disabled(isGenerating || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("프롬프트")
        } footer: {
            if isGenerating {
                Text("⚠️ 생성 중엔 앱을 그대로 켜둬 주세요. 다른 앱으로 전환하면 생성이 중단될 수 있어요.")
                    .foregroundStyle(.orange)
            } else {
                Text("그림체/가드레일은 서버가 자동으로 붙입니다.\nlow ~60초 · medium 1~3분 · high 2~5분")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var optionsSection: some View {
        Section("품질") {
            Picker("품질", selection: $quality) {
                Text("low — $0.011 (빠름)").tag("low")
                Text("medium — $0.04 (균형)").tag("medium")
                Text("high — $0.17 (느림, 정밀)").tag("high")
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
                Text("위 이미지를 참고해 새 이미지로 변형. 예: \"표정만 더 환하게\", \"파스텔 톤으로 부드럽게\". 매 호출은 동일 비용.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func generate() async {
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }
        await send(prompt: prompt, reference: nil)
    }

    private func refine() async {
        guard let current = resultImage,
              let pngData = current.pngData() else {
            lastError = "기존 이미지를 base64 로 변환 실패"
            return
        }
        let referenceB64 = pngData.base64EncodedString()
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }
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
}

#Preview {
    NavigationStack { CharacterGenView() }
}
