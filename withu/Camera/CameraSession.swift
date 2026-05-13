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
    /// AVCaptureVideoPreviewLayer 가 참조할 raw 세션
    @ObservationIgnored let session = AVCaptureSession()

    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "withu.camera.session")
    @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private var captureContinuation: CheckedContinuation<UIImage, Error>?

    private(set) var isConfigured: Bool = false
    private(set) var isRunning: Bool = false
    private(set) var lastError: String?

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

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo

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
