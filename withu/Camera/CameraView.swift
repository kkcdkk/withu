//
//  CameraView.swift
//  withu
//

import SwiftUI
import PhotosUI

struct CameraView: View {
    /// 카메라는 항상 idle 하나로 시작. 사용자가 picker 로 추가하거나 변경.
    @State private var placed: [PlacedCharacter] = [
        PlacedCharacter(state: .idle, position: CGPoint(x: 0.5, y: 0.6))
    ]
    @State private var selectedID: UUID?
    /// 제스처 시작 시점의 값 (드래그 delta · 핀치 배율 · 회전 기준)
    @State private var dragStartPosition: CGPoint?
    @State private var pinchBaseSize: CGFloat?
    @State private var rotationBase: CGFloat?

    @State private var camera = CameraSession.shared
    @State private var statusText: String = "초기화 중…"
    @State private var isCapturing: Bool = false
    @State private var previewCaptured: UIImage?
    @State private var showSavedToast: Bool = false
    @State private var showDeleteHint: Bool = false
    /// 카메라 권한 거절돼서 사용 불가 — 정식 회복 화면 표시.
    @State private var isPermissionDenied: Bool = false
    /// 앨범에서 고른 배경 사진 (있으면 라이브 카메라 대신 이 사진 위에 캐릭터 합성)
    @State private var backgroundImage: UIImage?
    @State private var backgroundPickerItem: PhotosPickerItem?

    init() {}

    var body: some View {
        ZStack {
            if isPermissionDenied && backgroundImage == nil {
                permissionDeniedView
            } else {
                cameraLayer
                overlayLayer
                controlsLayer
                if let img = previewCaptured {
                    preview(img)
                }
                if showSavedToast {
                    toast(String(localized: "갤러리에 저장했어요"))
                }
                if showDeleteHint {
                    toast(String(localized: "드래그로 이동 · 두 손가락으로 크기 · 길게 눌러 삭제"))
                }
            }
        }
        .ignoresSafeArea()
        .task { await setupCamera() }
        .onDisappear { camera.stop() }
        .onChange(of: backgroundPickerItem) { _, item in
            Task { await loadBackground(item) }
        }
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

            PhotosPicker(selection: $backgroundPickerItem, matching: .images) {
                Text("또는 앨범 사진으로 만들기")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.withuPinkText)
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Camera preview

    @ViewBuilder
    private var cameraLayer: some View {
        if let bg = backgroundImage {
            // 앨범 배경 모드 — 라이브 카메라 대신 고른 사진
            Image(uiImage: bg)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        } else {
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
            .rotationEffect(.radians(character.wrappedValue.rotation))
            .position(x: rect.midX, y: rect.midY)
            .onTapGesture {
                selectedID = character.wrappedValue.id
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                remove(character.wrappedValue.id)
            }
            // 인스타 스티커처럼 — 드래그 이동 + 두 손가락 핀치(크기) + 비틀기(회전) 동시
            .gesture(
                DragGesture()
                    .onChanged { value in
                        selectedID = character.wrappedValue.id
                        let start = dragStartPosition ?? character.wrappedValue.position
                        if dragStartPosition == nil { dragStartPosition = start }
                        character.wrappedValue.position = CGPoint(
                            x: max(0, min(1, start.x + value.translation.width / container.width)),
                            y: max(0, min(1, start.y + value.translation.height / container.height))
                        )
                    }
                    .onEnded { _ in dragStartPosition = nil }
                    .simultaneously(with:
                        MagnifyGesture()
                            .onChanged { value in
                                selectedID = character.wrappedValue.id
                                let base = pinchBaseSize ?? character.wrappedValue.size
                                if pinchBaseSize == nil { pinchBaseSize = base }
                                character.wrappedValue.size = max(0.1, min(0.95, base * value.magnification))
                            }
                            .onEnded { _ in pinchBaseSize = nil }
                    )
                    .simultaneously(with:
                        RotateGesture()
                            .onChanged { value in
                                selectedID = character.wrappedValue.id
                                let base = rotationBase ?? character.wrappedValue.rotation
                                if rotationBase == nil { rotationBase = base }
                                character.wrappedValue.rotation = base + value.rotation.radians
                            }
                            .onEnded { _ in rotationBase = nil }
                    )
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
            characterPicker
                .padding(.bottom, 12)
            HStack {
                // 좌측: 앨범 배경 고르기 (또는 카메라로 돌아가기)
                if backgroundImage != nil {
                    Button {
                        backgroundImage = nil
                        backgroundPickerItem = nil
                    } label: {
                        Image(systemName: "camera.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                } else {
                    PhotosPicker(selection: $backgroundPickerItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
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
                // 우측: 전면/후면 전환 (앨범 배경 모드에선 의미 없어 자리만 유지)
                if backgroundImage == nil {
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
                } else {
                    Color.clear.frame(width: 50, height: 50)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 50)
        }
    }

    /// 가로 스크롤 picker — 탭 시 새 캐릭터 추가.
    private var characterPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("탭하면 캐릭터 추가 · 드래그로 이동 · 두 손가락으로 크기 · 길게 눌러 삭제")
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
        // 앨범 배경 모드 — 카메라 캡처 없이 그 사진 위에 캐릭터 합성
        if let bg = backgroundImage {
            previewCaptured = PhotoCompositor.compose(photo: bg, placed: placed)
            return
        }
        do {
            let raw = try await camera.capturePhoto()
            let composed = PhotoCompositor.compose(photo: raw, placed: placed)
            previewCaptured = composed
        } catch {
            statusText = error.koreanizedDescription
        }
    }

    private func loadBackground(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let img = UIImage(data: data) {
            backgroundImage = img
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
