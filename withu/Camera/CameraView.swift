//
//  CameraView.swift
//  withu
//

import SwiftUI

struct CameraView: View {
    let characterState: CharacterState

    @State private var camera = CameraSession()
    @State private var statusText: String = "초기화 중…"
    @State private var isCapturing: Bool = false
    @State private var previewCaptured: UIImage?
    @State private var showSavedToast: Bool = false

    /// 캐릭터를 화면(=사진) 가운데 아래쪽에 두기 위한 정규화 좌표 (0~1).
    /// (x, y, w, h). 화면 비율과 사진 비율이 거의 같다고 가정.
    private let characterRect = CGRect(x: 0.30, y: 0.55, width: 0.40, height: 0.30)

    var body: some View {
        ZStack {
            cameraLayer
            overlayLayer
            controlsLayer
            if let img = previewCaptured {
                preview(img)
            }
            if showSavedToast {
                toast("📚 사진에 저장됐어요")
            }
        }
        .ignoresSafeArea()
        .task {
            await setupCamera()
        }
        .onDisappear {
            camera.stop()
        }
    }

    // MARK: - Layers

    @ViewBuilder
    private var cameraLayer: some View {
        #if targetEnvironment(simulator)
        Color.black
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "camera.metering.unknown")
                        .font(.system(size: 60))
                    Text("시뮬레이터엔 카메라가 없어요\n실기기에서 테스트하세요")
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white.opacity(0.7))
            )
        #else
        CameraPreviewView(session: camera.session)
        #endif
    }

    /// 카메라 위에 떠 있는 캐릭터. characterRect 와 같은 비율로 배치.
    private var overlayLayer: some View {
        GeometryReader { geo in
            let rect = CGRect(
                x: characterRect.minX * geo.size.width,
                y: characterRect.minY * geo.size.height,
                width: characterRect.width * geo.size.width,
                height: characterRect.height * geo.size.height
            )
            ZStack {
                Circle()
                    .fill(characterState.tint.opacity(0.18))
                Image(systemName: characterState.symbolName)
                    .resizable()
                    .scaledToFit()
                    .padding(rect.width * 0.22)
                    .foregroundStyle(characterState.tint)
                    .symbolEffect(.bounce, value: characterState)
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
        }
        .allowsHitTesting(false)
    }

    private var controlsLayer: some View {
        VStack {
            HStack {
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 60)
                    .padding(.trailing, 16)
            }
            Spacer()
            HStack {
                Spacer()
                Button {
                    Task { await shoot() }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 78, height: 78)
                        Circle()
                            .fill(.white)
                            .frame(width: 64, height: 64)
                        if isCapturing { ProgressView().tint(.black) }
                    }
                }
                .disabled(isCapturing)
                Spacer()
            }
            .padding(.bottom, 50)
        }
    }

    private func preview(_ image: UIImage) -> some View {
        ZStack {
            Color.black.opacity(0.9)
            VStack(spacing: 16) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
                HStack(spacing: 16) {
                    Button("취소", role: .cancel) {
                        previewCaptured = nil
                    }
                    .buttonStyle(.bordered)
                    Button("저장") {
                        Task { await saveCurrent(image) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.bottom, 40)
            }
        }
    }

    private func toast(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 140)
        }
        .transition(.opacity)
    }

    // MARK: - Actions

    private func setupCamera() async {
        do {
            try await camera.configure()
            camera.start()
            statusText = "준비됨"
        } catch let err as CameraError {
            statusText = err.errorDescription ?? "에러"
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func shoot() async {
        isCapturing = true
        defer { isCapturing = false }
        do {
            let raw = try await camera.capturePhoto()
            let composed = PhotoCompositor.compose(
                photo: raw,
                state: characterState,
                normalizedRect: characterRect
            )
            previewCaptured = composed
        } catch {
            statusText = "❌ \(error.localizedDescription)"
        }
    }

    private func saveCurrent(_ image: UIImage) async {
        do {
            try await PhotoSaver.save(image)
            previewCaptured = nil
            withAnimation { showSavedToast = true }
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { showSavedToast = false }
        } catch {
            statusText = "❌ \(error.localizedDescription)"
        }
    }
}

#Preview {
    CameraView(characterState: .idle)
}
