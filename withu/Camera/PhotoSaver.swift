//
//  PhotoSaver.swift
//  withu
//

import Photos
import UIKit

enum PhotoSaveError: LocalizedError {
    case notAuthorized
    case writeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:    return String(localized: "사진 저장 권한이 없어요. 설정에서 허용해주세요.")
        case .writeFailed(let e): return String(localized: "저장 실패: \(e.localizedDescription)")
        }
    }
}

enum PhotoSaver {
    static func save(_ image: UIImage) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        let granted: PHAuthorizationStatus
        if status == .notDetermined {
            granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        } else {
            granted = status
        }

        guard granted == .authorized || granted == .limited else {
            throw PhotoSaveError.notAuthorized
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if success {
                    cont.resume()
                } else if let error {
                    cont.resume(throwing: PhotoSaveError.writeFailed(error))
                } else {
                    cont.resume(throwing: PhotoSaveError.writeFailed(NSError(domain: "withu", code: -1)))
                }
            }
        }
    }
}
