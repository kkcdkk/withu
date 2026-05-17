//
//  CharacterGenView.swift
//  withu
//
//  로컬 FastAPI 서버 → DALL-E 3 로 캐릭터 이미지 생성.
//

import SwiftUI

struct CharacterGenView: View {
    @State private var prompt: String = """
A cute round chibi mascot character with simple features, \
soft pastel colors, friendly face with closed-eye smile, \
big head and tiny body, flat 2D illustration, \
transparent background, full body visible.
"""
    /// "low" $0.011 / "medium" $0.04 / "high" $0.17
    @State private var quality: String = "medium"
    @State private var isGenerating: Bool = false
    @State private var resultImage: UIImage?
    @State private var revisedPrompt: String?
    @State private var lastError: String?
    @State private var showSavedAlert: Bool = false

    var body: some View {
        Form {
            promptSection
            optionsSection
            resultSection
        }
        .navigationTitle("캐릭터 만들기")
        .alert("저장됨", isPresented: $showSavedAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("사진 앱에 추가됐어요.")
        }
    }

    // MARK: - Sections

    private var promptSection: some View {
        Section {
            TextEditor(text: $prompt)
                .frame(minHeight: 120)
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
                Text("low ~60초 · medium 1~3분 · high 2~5분. 생성 중엔 앱을 켜둬야 합니다.")
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
                    DisclosureGroup("DALL-E 가 사용한 실제 프롬프트") {
                        Text(revised).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("사진 앱에 저장") {
                    Task { await saveToPhotos(img) }
                }
            }
        }
        if let err = lastError {
            Section { Text(err).foregroundStyle(.red) }
        }
    }

    // MARK: - Actions

    private func generate() async {
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }
        do {
            let req = GenerateImageRequest(
                prompt: prompt,
                referenceImageBase64: nil,
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
