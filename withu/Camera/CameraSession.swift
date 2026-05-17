//
//  CameraSession.swift
//  withu
//

import AVFoundation
import UIKit

enum CameraError: LocalizedError {
    case notAuthorized
    case noCamera
    case configurationFailed
    case captureFailed
    case unavailableOnSimulator

    var errorDescription: String? {
        switch self {
        case .notAuthorized:         return "카메라 권한이 없어요. 설정에서 켜주세요."
        case .noCamera:              return "이 기기에서 카메라를 찾을 수 없어요."
        case .configurationFailed:   return "카메라 구성에 실패했어요."
        case .captureFailed:         return "사진 캡처에 실패했어요."
        case .unavailableOnSimulator:return "시뮬레이터에서는 카메라를 쓸 수 없어요. 실기기로 테스트해주세요."
        }
    }
}

/// AVCaptureSession을 감싸는 카메라 관리 객체.
/// - 권한 요청
/// - 세션 구성 / 시작 / 정지
/// - 셔터 (async 함수로 노출)
@Observable
@MainActor
final class CameraSession: NSObject {
    /// 카메라는 시스템 단일 자원 — singleton 으로 재사용.
    /// CameraView 가 NavigationStack 에서 다시 push 돼도 같은 인스턴스 사용.
    static let shared = CameraSession()

    /// AVCaptureVideoPreviewLayer 가 참조할 raw 세션
    @ObservationIgnored let session = AVCaptureSession()

    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "withu.camera.session")
    @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private var captureContinuation: CheckedContinuation<UIImage, Error>?

    private(set) var isConfigured: Bool = false
    private(set) var isRunning: Bool = false
    private(set) var lastError: String?

    private override init() { super.init() }

    // MARK: - 권한

    func requestAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - 세션 구성

    func configure() async throws {
        #if targetEnvironment(simulator)
        throw CameraError.unavailableOnSimulator
        #else
        guard await requestAuthorization() else { throw CameraError.notAuthorized }

        // 이미 input/output 추가된 상태면 재구성 skip (멱등).
        // CameraView 가 NavigationStack 에서 다시 push 됐을 때 같은 session 인스턴스가
        // 재사용되면 canAddInput 이 false 가 돼서 noCamera 로 잘못 보고되던 것 방지.
        if isConfigured && !session.inputs.isEmpty && !session.outputs.isEmpty {
            return
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo

                // 잔존 input/output 정리 (이전 진입 흔적이 부분만 남은 케이스)
                for input in self.session.inputs {
                    self.session.removeInput(input)
                }
                for output in self.session.outputs {
                    self.session.removeOutput(output)
                }

                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                            for: .video,
                                                            position: .back),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    cont.resume(throwing: CameraError.noCamera)
                    return
                }
                self.session.addInput(input)

                guard self.session.canAddOutput(self.photoOutput) else {
                    self.session.commitConfiguration()
                    cont.resume(throwing: CameraError.configurationFailed)
                    return
                }
                self.session.addOutput(self.photoOutput)
                self.session.commitConfiguration()
                cont.resume(returning: ())
            }
        }
        isConfigured = true
        #endif
    }

    // MARK: - start / stop

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            Task { @MainActor in self.isRunning = true }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            Task { @MainActor in self.isRunning = false }
        }
    }

    // MARK: - 셔터

    func capturePhoto() async throws -> UIImage {
        #if targetEnvironment(simulator)
        throw CameraError.unavailableOnSimulator
        #else
        return try await withCheckedThrowingContinuation { cont in
            captureContinuation = cont
            let settings = AVCapturePhotoSettings()
            sessionQueue.async {
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
        #endif
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraSession: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let result: Result<UIImage, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation(), let img = UIImage(data: data) {
            result = .success(img)
        } else {
            result = .failure(CameraError.captureFailed)
        }

        Task { @MainActor in
            let cont = self.captureContinuation
            self.captureContinuation = nil
            switch result {
            case .success(let img): cont?.resume(returning: img)
            case .failure(let err): cont?.resume(throwing: err)
            }
        }
    }
}
