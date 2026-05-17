//
//  CharacterImageStore.swift
//  withu (Shared: iOS + Watch + Widget extensions)
//
//  사용자가 AI 로 생성한 캐릭터 이미지를 App Group 컨테이너에 PNG 로 저장.
//  메인 앱/위젯/워치가 같은 그룹 폴더를 읽어 즉시 반영.
//
//  Target Membership: 4개 타겟 모두.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum CharacterImageStore {

    /// "characters/" 하위 폴더 안에 `<state>.png`.
    private static let folderName = "characters"

    /// App Group container 의 루트.
    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedAppState.groupID)
    }

    /// 캐릭터 이미지 폴더. 없으면 lazy 생성.
    private static func ensureFolder() -> URL? {
        guard let container = containerURL else { return nil }
        let folder = container.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func fileURL(for state: CharacterState) -> URL? {
        ensureFolder()?.appendingPathComponent("\(state.rawValue).png")
    }

    // MARK: - Read

    #if canImport(UIKit)
    /// 사용자 생성 이미지가 있으면 UIImage 로 로드. 없으면 nil.
    static func load(_ state: CharacterState) -> UIImage? {
        guard let url = fileURL(for: state),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// 동일 state 에 대해 사용자 이미지 존재 여부.
    static func hasImage(for state: CharacterState) -> Bool {
        guard let url = fileURL(for: state) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Write

    /// PNG 데이터를 해당 state 슬롯에 저장. 이미 있으면 덮어씀.
    @discardableResult
    static func save(_ image: UIImage, for state: CharacterState) -> Bool {
        guard let url = fileURL(for: state),
              let data = image.pngData() else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// 사용자 이미지 삭제 (asset 으로 fallback 됨).
    @discardableResult
    static func remove(_ state: CharacterState) -> Bool {
        guard let url = fileURL(for: state) else { return false }
        try? FileManager.default.removeItem(at: url)
        return true
    }
    #endif
}
