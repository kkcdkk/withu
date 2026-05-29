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

extension Notification.Name {
    /// 활성 슬롯 캐릭터 이미지가 변경됨 — ContentView 등이 재로드 트리거에 사용.
    static let characterImageChanged = Notification.Name("withu.characterImageChanged")
    /// 날씨 배경 이미지가 변경됨.
    static let weatherBackgroundChanged = Notification.Name("withu.weatherBackgroundChanged")
}

/// 배경 레이어용 날씨 카테고리 — 4 날씨 + 야간.
/// .night 는 시간 기반 (날씨 무관) — 야간엔 어둠이 가장 강한 시각 신호라 다른 조건 다 누름.
enum WeatherBackgroundCondition: String, CaseIterable, Codable {
    case sunny, cloudy, rainy, snowy, night

    var displayName: String {
        switch self {
        case .sunny:  return "맑음 ☀️"
        case .cloudy: return "흐림 ☁️"
        case .rainy:  return "비 🌧"
        case .snowy:  return "눈 ❄️"
        case .night:  return "밤하늘 🌙"
        }
    }

    var generationHint: String {
        switch self {
        case .sunny:
            return "Bright sunny sky background, soft white clouds, warm sunlight, clean pastel landscape, illustration. NO character, NO person — empty scene only."
        case .cloudy:
            return "Soft overcast cloudy sky background, gray pastel atmosphere, calm empty landscape, illustration. NO character, NO person — empty scene only."
        case .rainy:
            return "Rainy weather background scene, light rain falling, wet pavement, soft gray sky, pastel illustration, cinematic. NO character, NO person — empty scene only."
        case .snowy:
            return "Snowy winter background, gentle snowflakes falling, snow on ground, soft cold pastel colors, illustration. NO character, NO person — empty scene only."
        case .night:
            return "Calm night sky background, dark blue / deep purple, scattered stars, soft crescent moon, dreamy pastel illustration. NO character, NO person — empty scene only."
        }
    }

    /// 위젯/워치 메시지에 담긴 emoji 로부터 매핑.
    /// WeatherCondition.emoji 와 일치해야 — sunny=☀️, cloudy=☁️, rainy=🌧, snowy=❄️, thunder=⛈ (→ rainy 로).
    /// 야간 (.night) 은 시간 기반이라 emoji 매핑 없음.
    static func from(emoji: String?) -> WeatherBackgroundCondition? {
        switch emoji {
        case "☀️":      return .sunny
        case "☁️":      return .cloudy
        case "🌧", "⛈": return .rainy
        case "❄️":      return .snowy
        default:        return nil
        }
    }
}

/// 갤러리 한 항목.
struct GalleryItem: Identifiable, Codable, Equatable {
    let id: String              // UUID().uuidString
    let sourceState: String     // 처음 만들 때의 CharacterState.rawValue
    let createdAt: Date
    /// 연속 이미지 (frame 1) 도 같이 저장됐는지. nil/false 면 frame 0 만.
    /// Optional 인 이유: 옛 메타엔 이 키가 없어 nil → false 로 fallback.
    var hasFrame1: Bool?

    /// 사용자 친화적 표시용. 필요 시 추가 필드.
}

enum CharacterImageStore {

    private static let activeFolder = "characters"
    private static let galleryFolder = "gallery"
    private static let metadataName = "metadata.json"
    private static let animationEnabledKey = "withu.animationEnabled.v1"
    private static let activeSourceMapKey = "withu.activeSourceMap.v1"
    private static let backgroundsFolder = "backgrounds"

    // MARK: - 야간 시간 체크 (간단 fallback)

    /// 시간 기반 야간 판정 (20:00~06:00). 4 타깃 공통 fallback.
    /// iOS app 은 profile sleep window 로 더 정확하게 별도 분기 사용 가능.
    static func isCurrentlyNight(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 20 || hour < 6
    }

    // MARK: - 날씨 배경 (per condition × 4 = 4 PNG)

    private static func backgroundFileURL(for cond: WeatherBackgroundCondition) -> URL? {
        ensureFolder(backgroundsFolder)?.appendingPathComponent("\(cond.rawValue).png")
    }

    static func hasBackground(_ cond: WeatherBackgroundCondition) -> Bool {
        guard let url = backgroundFileURL(for: cond) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    #if canImport(UIKit)
    /// 사용자 생성 배경 로드 — 없으면 nil.
    static func loadBackground(_ cond: WeatherBackgroundCondition) -> UIImage? {
        guard let url = backgroundFileURL(for: cond),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    @discardableResult
    static func saveBackground(_ image: UIImage, for cond: WeatherBackgroundCondition) -> Bool {
        guard let data = image.pngData(),
              let url = backgroundFileURL(for: cond) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            NotificationCenter.default.post(name: .weatherBackgroundChanged, object: cond)
            return true
        } catch {
            return false
        }
    }
    #endif

    // MARK: - active slot ↔ gallery id 매핑 (어떤 state 가 어떤 갤러리 항목 사용 중인지)

    /// [state.rawValue: gallery_id] 로 어떤 state 슬롯이 어떤 갤러리 항목을 쓰고 있는지 저장.
    /// save(frame:0) / applyGalleryItem 이 갱신, deleteGalleryItem 이 정리.
    private static func loadActiveSourceMap() -> [String: String] {
        let defaults = UserDefaults(suiteName: SharedAppState.groupID)
        return defaults?.dictionary(forKey: activeSourceMapKey) as? [String: String] ?? [:]
    }

    private static func saveActiveSourceMap(_ map: [String: String]) {
        let defaults = UserDefaults(suiteName: SharedAppState.groupID)
        defaults?.set(map, forKey: activeSourceMapKey)
    }

    private static func setActiveSource(state: CharacterState, galleryId: String?) {
        var map = loadActiveSourceMap()
        if let id = galleryId {
            map[state.rawValue] = id
        } else {
            map.removeValue(forKey: state.rawValue)
        }
        saveActiveSourceMap(map)
    }

    /// 특정 state 슬롯에 현재 적용된 갤러리 id (없으면 nil).
    static func currentGalleryItemId(for state: CharacterState) -> String? {
        loadActiveSourceMap()[state.rawValue]
    }

    /// 한 갤러리 항목이 어떤 state 슬롯들에 적용 중인지 (역검색).
    static func statesUsingGalleryItem(_ id: String) -> [CharacterState] {
        let map = loadActiveSourceMap()
        return map.compactMap { (k, v) -> CharacterState? in
            guard v == id else { return nil }
            return CharacterState(rawValue: k)
        }
    }

    // MARK: - 애니메이션 표시 토글 (4개 타겟 공통)

    /// frame 1 이 있어도 swap 애니메이션을 재생할지. 사용자 토글.
    /// 기본 true. CharacterImageView 가 이 값을 읽어 정적/애니메이션 결정.
    static var animationEnabled: Bool {
        let defaults = UserDefaults(suiteName: SharedAppState.groupID)
        return (defaults?.object(forKey: animationEnabledKey) as? Bool) ?? true
    }

    static func setAnimationEnabled(_ enabled: Bool) {
        let defaults = UserDefaults(suiteName: SharedAppState.groupID)
        defaults?.set(enabled, forKey: animationEnabledKey)
        // 모든 state 갱신 트리거 — object: nil 로 broadcast.
        NotificationCenter.default.post(name: .characterImageChanged, object: nil)
    }

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

    /// 애니메이션 frame 별 파일 URL. frame 0 = 기존 base 파일.
    private static func activeFileURL(for state: CharacterState, frame: Int) -> URL? {
        guard frame > 0 else { return activeFileURL(for: state) }
        return ensureFolder(activeFolder)?
            .appendingPathComponent("\(state.rawValue)_f\(frame).png")
    }

    #if canImport(UIKit)
    /// 활성 슬롯 로드 (위젯/워치가 호출).
    static func load(_ state: CharacterState) -> UIImage? {
        loadFrame(state, frame: 0)
    }

    /// frame 별 로드. frame > 0 인데 없으면 nil. caller 가 frame 0 fallback.
    static func loadFrame(_ state: CharacterState, frame: Int) -> UIImage? {
        guard let url = activeFileURL(for: state, frame: frame),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// 애니메이션 frame 존재 여부 (frame >= 1)
    static func hasAnimationFrames(for state: CharacterState) -> Bool {
        guard let url = activeFileURL(for: state, frame: 1) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// 위젯 메모리 절약용 다운샘플 로드.
    /// CGContext 로 RGBA 명시해서 그려서 alpha 확실히 유지 (iOS/watchOS 둘 다 작동).
    /// 일시적으로 원본 디코드되긴 하지만, render 후엔 작은 thumbnail 만 메모리에 남음.
    static func loadThumbnail(_ state: CharacterState,
                              maxPixelSize: CGFloat) -> UIImage? {
        guard let url = activeFileURL(for: state),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let original = UIImage(data: data),
              let originalCG = original.cgImage else { return nil }

        let originalSize = original.size
        let maxDim = max(originalSize.width, originalSize.height)
        guard maxDim > 0 else { return original }
        // 원본이 이미 작으면 그대로
        if maxDim <= maxPixelSize { return original }

        let scale = maxPixelSize / maxDim
        let targetWidth = Int(originalSize.width * scale)
        let targetHeight = Int(originalSize.height * scale)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // premultipliedLast = RGBA — alpha 채널 유지 보장
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil,
                                      width: targetWidth,
                                      height: targetHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
            return original
        }
        context.interpolationQuality = .high
        context.draw(originalCG, in: CGRect(x: 0, y: 0,
                                            width: targetWidth,
                                            height: targetHeight))
        guard let scaledCG = context.makeImage() else { return original }
        return UIImage(cgImage: scaledCG)
    }

    /// 활성 슬롯 파일만 덮어쓰기 (갤러리 항목/매핑 건드리지 않음).
    /// 사용자가 결과 보고 transparent 토글했을 때 등 — 갤러리 원본은 유지하면서 표시만 바꾸는 용도.
    static func saveActiveSlotOnly(_ image: UIImage, for state: CharacterState, frame: Int = 0) {
        guard let data = image.pngData(),
              let activeURL = activeFileURL(for: state, frame: frame) else { return }
        try? data.write(to: activeURL, options: .atomic)
        NotificationCenter.default.post(name: .characterImageChanged, object: state)
    }

    static func hasImage(for state: CharacterState) -> Bool {
        guard let url = activeFileURL(for: state) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// PNG 의 alpha 채널 진단 — 워치 디버그용. "RGBA", "RGB(no alpha)" 또는 nil.
    static func alphaInfoDescription(for state: CharacterState) -> String? {
        guard let url = activeFileURL(for: state),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let img = UIImage(data: data),
              let cg = img.cgImage else { return nil }
        let alphaInfo = cg.alphaInfo
        let hasAlpha: String
        switch alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst:
            hasAlpha = "❌ alpha 없음 (RGB only)"
        case .premultipliedLast, .premultipliedFirst, .last, .first:
            hasAlpha = "✅ alpha 있음 (RGBA)"
        case .alphaOnly:
            hasAlpha = "alpha only"
        @unknown default:
            hasAlpha = "?"
        }
        return "\(cg.width)x\(cg.height) · \(hasAlpha)"
    }

    /// state 의 활성 슬롯 + 갤러리에 동시 저장. (생성 흐름에서 호출)
    /// 반환: 갤러리에 저장된 GalleryItem (재선택용 id).
    /// - frame 0: 새 갤러리 항목 생성
    /// - frame 1: 같은 state 의 가장 최근 갤러리 항목에 frame 1 파일 추가 + hasFrame1=true
    @discardableResult
    static func save(_ image: UIImage, for state: CharacterState, frame: Int = 0) -> GalleryItem? {
        guard let data = image.pngData() else { return nil }
        // 1) 활성 슬롯 (위젯이 보는 곳) — frame 별
        if let activeURL = activeFileURL(for: state, frame: frame) {
            try? data.write(to: activeURL, options: .atomic)
        }
        NotificationCenter.default.post(name: .characterImageChanged, object: state)
        // 2) 갤러리 — frame 별 분기
        if frame == 0 {
            let item = addToGalleryInternal(data: data, sourceState: state)
            if let id = item?.id {
                // 새로 만든 갤러리 항목이 이 state 의 현재 활성 source.
                setActiveSource(state: state, galleryId: id)
            }
            return item
        } else {
            return attachFrame1ToLatestGalleryItem(data: data, sourceState: state)
        }
    }

    /// frame 1 을 같은 state 의 가장 최근 갤러리 항목에 추가.
    /// 없으면 nil (frame 0 없이 frame 1 만 만든 케이스 — 정상 흐름엔 없음).
    @discardableResult
    private static func attachFrame1ToLatestGalleryItem(data: Data,
                                                         sourceState: CharacterState) -> GalleryItem? {
        var all = loadGalleryMetadata()  // createdAt desc 로 정렬됨
        guard let idx = all.firstIndex(where: { $0.sourceState == sourceState.rawValue }) else {
            return nil
        }
        let item = all[idx]
        guard let url = galleryFrame1URL(id: item.id) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        all[idx].hasFrame1 = true
        saveGalleryMetadata(all)
        return all[idx]
    }

    private static func galleryFrame1URL(id: String) -> URL? {
        ensureFolder(galleryFolder)?.appendingPathComponent("\(id)_f1.png")
    }

    /// 갤러리 항목의 frame 1 이미지 로드. 없으면 nil.
    static func loadGalleryFrame1(id: String) -> UIImage? {
        guard let url = galleryFrame1URL(id: id),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
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
    /// frame 1 있는 갤러리 항목이면 frame 1 도 같이 복사. 없으면 기존 frame 1 잔재 제거.
    @discardableResult
    static func applyGalleryItem(_ id: String, to state: CharacterState) -> Bool {
        guard let img = loadGalleryImage(id: id),
              let data = img.pngData(),
              let activeURL = activeFileURL(for: state) else { return false }
        do {
            try data.write(to: activeURL, options: .atomic)
        } catch {
            return false
        }
        // frame 1 처리 — 갤러리에 있으면 복사, 없으면 기존 active frame 1 지움 (다른 캐릭터 잔재 방지)
        if let f1 = loadGalleryFrame1(id: id),
           let f1Data = f1.pngData(),
           let f1URL = activeFileURL(for: state, frame: 1) {
            try? f1Data.write(to: f1URL, options: .atomic)
        } else if let f1URL = activeFileURL(for: state, frame: 1) {
            try? FileManager.default.removeItem(at: f1URL)
        }
        // 이 state 슬롯의 활성 source 갱신.
        setActiveSource(state: state, galleryId: id)
        NotificationCenter.default.post(name: .characterImageChanged, object: state)
        return true
    }

    /// 갤러리 항목 삭제 (frame 0 + frame 1 + 메타 + 활성 source 매핑 정리).
    @discardableResult
    static func deleteGalleryItem(_ id: String) -> Bool {
        if let url = galleryFileURL(id: id) {
            try? FileManager.default.removeItem(at: url)
        }
        if let f1URL = galleryFrame1URL(id: id) {
            try? FileManager.default.removeItem(at: f1URL)
        }
        var all = loadGalleryMetadata()
        all.removeAll { $0.id == id }
        saveGalleryMetadata(all)
        // 활성 source 매핑에서 이 id 가리키던 state 들 제거.
        var map = loadActiveSourceMap()
        let staleKeys = map.compactMap { $1 == id ? $0 : nil }
        for k in staleKeys { map.removeValue(forKey: k) }
        if !staleKeys.isEmpty { saveActiveSourceMap(map) }
        return true
    }
    #endif
}
