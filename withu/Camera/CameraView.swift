//
//  CameraView.swift
//  withu
//

import SwiftUI

struct CameraView: View {
    /// 카메라는 항상 idle 하나로 시작. 사용자가 picker 로 추가하거나 변경.
    @State private var placed: [PlacedCharacter] = [
        PlacedCharacter(state: .idle, position: CGPoint(x: 0.5, y: 0.6))
    ]
    @State private var selectedID: UUID?

    @State private var camera = CameraSession.shared
    @State private var statusText: String = "초기화 중…"
    @State private var isCapturing: Bool = false
    @State private var previewCaptured: UIImage?
    @State private var showSavedToast: Bool = false
    @State private var showDeleteHint: Bool = false
    /// 카메라 권한 거절돼서 사용 불가 — 정식 회복 화면 표시.
    @State private var isPermissionDenied: Bool = false

    init() {}

    var body: some View {
        ZStack {
            if isPermissionDenied {
                permissionDeniedView
            } else {
                cameraLayer
                overlayLayer
                controlsLayer
                if let img = previewCaptured {
                    preview(img)
                }
                if showSavedToast {
                    toast("📚 사진에 저장됐어요")
                }
                if showDeleteHint {
                    toast("길게 눌러서 삭제 · 탭해서 선택 · 드래그해서 이동")
                }
            }
        }
        .ignoresSafeArea()
        .task { await setupCamera() }
        .onDisappear { camera.stop() }
    }

    // MARK: - Permission denied recovery

    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.18))
                    .frame(width: 130, height: 130)
                Image(systemName: "camera.fill.badge.ellipsis")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
            }
            VStack(spacing: 8) {
                Text("카메라 권한이 필요해요")
                    .font(.title2.weight(.semibold))
                Text("캐릭터와 함께 사진을 찍으려면 카메라 접근을\n허용해 주세요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("iOS 설정 열기", systemImage: "gear")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.withuPink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Camera preview

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

    // MARK: - Overlay: 여러 캐릭터, 드래그/탭/길게누름

    private var overlayLayer: some View {
        GeometryReader { geo in
            ZStack {
                ForEach($placed) { $character in
                    characterTile($character, container: geo.size)
                }
            }
        }
    }

    private func characterTile(_ character: Binding<PlacedCharacter>,
                                container: CGSize) -> some View {
        let rect = character.wrappedValue.rect(in: container)
        let isSelected = selectedID == character.wrappedValue.id
        return CharacterImageView(state: character.wrappedValue.state)
            .frame(width: rect.width, height: rect.height)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white, lineWidth: isSelected ? 3 : 0)
            )
            .position(x: rect.midX, y: rect.midY)
            .onTapGesture {
                selectedID = character.wrappedValue.id
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                remove(character.wrappedValue.id)
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        character.wrappedValue.position = CGPoint(
                            x: max(0, min(1, value.location.x / container.width)),
                            y: max(0, min(1, value.location.y / container.height))
                        )
                        selectedID = character.wrappedValue.id
                    }
            )
    }

    // MARK: - Controls

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
            if let id = selectedID,
               let char = placed.first(where: { $0.id == id }) {
                selectedCharacterControls(for: char)
                    .padding(.bottom, 8)
            }
            characterPicker
                .padding(.bottom, 12)
            HStack {
                // 좌측 placeholder — shutter 가운데 유지
                Color.clear.frame(width: 50, height: 50)
                Spacer()
                Button {
                    Task { await shoot() }
                } label: {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                        Circle().fill(.white).frame(width: 64, height: 64)
                        if isCapturing { ProgressView().tint(.black) }
                    }
                }
                .disabled(isCapturing)
                Spacer()
                // 우측: 전면/후면 전환
                Button {
                    camera.switchCamera()
                } label: {
                    Image(systemName: "camera.rotate.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .disabled(isCapturing)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 50)
        }
    }

    /// 가로 스크롤 picker — 탭 시 새 캐릭터 추가.
    private var characterPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("탭하면 캐릭터 추가됨 · 화면의 캐릭터 길게 눌러서 삭제")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CharacterState.userFacing, id: \.self) { state in
                        Button {
                            addCharacter(state)
                        } label: {
                            ZStack {
                                Circle().fill(.ultraThinMaterial)
                                CharacterImageView(state: state).padding(6)
                                VStack {
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.white)
                                        .background(Circle().fill(.black.opacity(0.4)))
                                        .padding(2)
                                }
                            }
                            .frame(width: 56, height: 56)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    /// 선택된 캐릭터에 한해 사이즈 슬라이더 + 삭제.
    private func selectedCharacterControls(for char: PlacedCharacter) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .foregroundStyle(.white)
            Slider(value: Binding(
                get: { placed.first(where: { $0.id == char.id })?.size ?? 0.35 },
                set: { newValue in
                    if let i = placed.firstIndex(where: { $0.id == char.id }) {
                        placed[i].size = newValue
                    }
                }
            ), in: 0.15...0.7)
            .tint(.white)
            Button(role: .destructive) {
                remove(char.id)
            } label: {
                Image(systemName: "trash.fill").foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 16)
    }

    // MARK: - Capture preview

    private func preview(_ image: UIImage) -> some View {
        ZStack {
            Color.black.opacity(0.9)
            VStack(spacing: 16) {
                Image(uiImage: image).resizable().scaledToFit().padding()
                HStack(spacing: 16) {
                    Button("취소", role: .cancel) { previewCaptured = nil }
                        .buttonStyle(.bordered)
                    Button("저장") { Task { await saveCurrent(image) } }
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

    private func addCharacter(_ state: CharacterState) {
        let new = PlacedCharacter(state: state, position: CGPoint(x: 0.5, y: 0.55))
        placed.append(new)
        selectedID = new.id
    }

    private func remove(_ id: UUID) {
        placed.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
    }

    private func setupCamera() async {
        do {
            try await camera.configure()
            camera.start()
            statusText = "준비됨"
        } catch CameraError.notAuthorized {
            // 권한 거절 → 정식 회복 화면
            isPermissionDenied = true
        } catch let err as CameraError {
            statusText = err.errorDescription ?? "에러"
        } catch {
            statusText = error.koreanizedDescription
        }
    }

    private func shoot() async {
        isCapturing = true
        defer { isCapturing = false }
        do {
            let raw = try await camera.capturePhoto()
            let composed = PhotoCompositor.compose(photo: raw, placed: placed)
            previewCaptured = composed
        } catch {
            statusText = error.koreanizedDescription
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
            statusText = error.koreanizedDescription
        }
    }
}

#Preview { CameraView() }
