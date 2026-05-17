//
//  CameraView.swift
//  withu
//

import SwiftUI

struct CameraView: View {
    let initialState: CharacterState

    /// 카메라 안에서만 사용되는 임시 캐릭터. 진입 시엔 자동 계산된 initialState 로 시작,
    /// 사용자가 picker 로 자유롭게 변경 가능 (메인 화면의 자동 상태는 영향 X).
    @State private var selectedState: CharacterState

    @State private var camera = CameraSession.shared
    @State private var statusText: String = "초기화 중…"
    @State private var isCapturing: Bool = false
    @State private var previewCaptured: UIImage?
    @State private var showSavedToast: Bool = false

    /// 카메라는 항상 idle 로 시작. 다른 캐릭터로 찍고 싶으면 하단 picker 로 선택
    /// (등록된 이미지가 없으면 placeholder/SF Symbol 로 보임 — 미리 CharacterGen 에서 만들어 적용).
    init(characterState: CharacterState = .idle) {
        self.initialState = characterState
        self._selectedState = State(initialValue: characterState)
    }

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

    /// 카메라 위에 떠 있는 캐릭터. CharacterImageView 사용 → 사용자 적용 이미지 자동 반영.
    private var overlayLayer: some View {
        GeometryReader { geo in
            let rect = CGRect(
                x: characterRect.minX * geo.size.width,
                y: characterRect.minY * geo.size.height,
                width: characterRect.width * geo.size.width,
                height: characterRect.height * geo.size.height
            )
            CharacterImageView(state: selectedState)
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
            characterPicker
                .padding(.bottom, 12)
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

    /// 가로 스크롤로 9개 상태 thumbnail 보여주는 picker.
    /// 선택된 항목은 테두리 강조.
    private var characterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CharacterState.allCases, id: \.self) { state in
                    Button {
                        selectedState = state
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                            CharacterImageView(state: state)
                                .padding(6)
                        }
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .stroke(selectedState == state ? .white : .clear, lineWidth: 3)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
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
                state: selectedState,
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
