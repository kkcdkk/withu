//
//  CharacterImageStore.swift
//  withu (Shared: iOS + Watch + Widget extensions)
//
//  사용자가 만든 / 첨부한 캐릭터 이미지의 영구 저장소.
//  - characters/<state>.png : 각 상태의 "현재 활성" 이미지 (위젯/워치가 읽음)
//  - gallery/<uuid>.png + metadata.json : 모든 이력 보관 (재선택 가능)
//
//  Target Membership: 4개 타겟 모두.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 갤러리 한 항목.
struct GalleryItem: Identifiable, Codable, Equatable {
    let id: String              // UUID().uuidString
    let sourceState: String     // 처음 만들 때의 CharacterState.rawValue
    let createdAt: Date

    /// 사용자 친화적 표시용. 필요 시 추가 필드.
}

enum CharacterImageStore {

    private static let activeFolder = "characters"
    private static let galleryFolder = "gallery"
    private static let metadataName = "metadata.json"

    // MARK: - App Group container

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedAppState.groupID)
    }

    private static func ensureFolder(_ name: String) -> URL? {
        guard let container = containerURL else { return nil }
        let folder = container.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: - 활성 (state 슬롯) — 기존 API

    private static func activeFileURL(for state: CharacterState) -> URL? {
        ensureFolder(activeFolder)?.appendingPathComponent("\(state.rawValue).png")
    }

    #if canImport(UIKit)
    /// 활성 슬롯 로드 (위젯/워치가 호출).
    static func load(_ state: CharacterState) -> UIImage? {
        guard let url = activeFileURL(for: state),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func hasImage(for state: CharacterState) -> Bool {
        guard let url = activeFileURL(for: state) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// state 의 활성 슬롯 + 갤러리에 동시 저장. (생성 흐름에서 호출)
    /// 반환: 갤러리에 저장된 GalleryItem (재선택용 id).
    @discardableResult
    static func save(_ image: UIImage, for state: CharacterState) -> GalleryItem? {
        guard let data = image.pngData() else { return nil }
        // 1) 활성 슬롯 (위젯이 보는 곳)
        if let activeURL = activeFileURL(for: state) {
            try? data.write(to: activeURL, options: .atomic)
        }
        // 2) 갤러리에도 같은 데이터 저장 + 메타 등록
        return addToGalleryInternal(data: data, sourceState: state)
    }

    /// 활성 슬롯 삭제 → asset / SF Symbol fallback 으로 돌아감.
    @discardableResult
    static func clearActive(_ state: CharacterState) -> Bool {
        guard let url = activeFileURL(for: state) else { return false }
        try? FileManager.default.removeItem(at: url)
        return true
    }

    // MARK: - 갤러리

    private static func galleryFileURL(id: String) -> URL? {
        ensureFolder(galleryFolder)?.appendingPathComponent("\(id).png")
    }

    private static var metadataURL: URL? {
        ensureFolder(galleryFolder)?.appendingPathComponent(metadataName)
    }

    /// 갤러리 메타 전체 로드.
    static func loadGalleryMetadata() -> [GalleryItem] {
        guard let url = metadataURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([GalleryItem].self, from: data) else {
            return []
        }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    private static func saveGalleryMetadata(_ items: [GalleryItem]) {
        guard let url = metadataURL,
              let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }

    @discardableResult
    private static func addToGalleryInternal(data: Data,
                                              sourceState: CharacterState) -> GalleryItem? {
        let id = UUID().uuidString
        guard let url = galleryFileURL(id: id) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        let item = GalleryItem(id: id, sourceState: sourceState.rawValue, createdAt: Date())
        var all = loadGalleryMetadata()
        all.append(item)
        saveGalleryMetadata(all)
        return item
    }

    /// 갤러리에서 이미지 로드.
    static func loadGalleryImage(id: String) -> UIImage? {
        guard let url = galleryFileURL(id: id),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// 갤러리 항목을 지정 state 의 활성 슬롯으로 적용.
    @discardableResult
    static func applyGalleryItem(_ id: String, to state: CharacterState) -> Bool {
        guard let img = loadGalleryImage(id: id),
              let data = img.pngData(),
              let activeURL = activeFileURL(for: state) else { return false }
        do {
            try data.write(to: activeURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// 갤러리 항목 삭제 (이미지 + 메타).
    @discardableResult
    static func deleteGalleryItem(_ id: String) -> Bool {
        if let url = galleryFileURL(id: id) {
            try? FileManager.default.removeItem(at: url)
        }
        var all = loadGalleryMetadata()
        all.removeAll { $0.id == id }
        saveGalleryMetadata(all)
        return true
    }
    #endif
}
