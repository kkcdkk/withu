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
        case .sunny:  return String(localized: "맑음 ☀️")
        case .cloudy: return String(localized: "흐림 ☁️")
        case .rainy:  return String(localized: "비 🌧")
        case .snowy:  return String(localized: "눈 ❄️")
        case .night:  return String(localized: "밤하늘 🌙")
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

    /// Asset Catalog 에 박아둔 고정 PNG 이름. 모든 사용자 동일.
    /// 4 타깃 (앱/워치/위젯/컴플) 각자 Assets.xcassets 에 같은 이름의 imageset 으로 추가 필요.
    /// 없으면 WeatherDecorationView 가 emoji fallback.
    var decorationAssetName: String { "weather_\(rawValue)" }

    /// 기본 emoji (Asset 없을 때 fallback).
    var fallbackEmoji: String {
        switch self {
        case .sunny:  return "☀️"
        case .cloudy: return "☁️"
        case .rainy:  return "🌧"
        case .snowy:  return "❄️"
        case .night:  return "🌙"
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
    /// '한번에 만들기'(배치) 세션 식별자 — 같은 batchId 항목들이 한 캐릭터의 여러 상태.
    /// 단건 생성·옛 항목은 nil. 갤러리 '캐릭터별' 묶기에 사용.
    var batchId: String?
    /// 이 이미지를 만들 때 서버로 보낸 프롬프트 — 갤러리 '만든 기록' 표시용. 옛 항목은 nil.
    var prompt: String?

    /// 사용자 친화적 표시용. 필요 시 추가 필드.
}

enum CharacterImageStore {

    private static let activeFolder = "characters"
    private static let galleryFolder = "gallery"
    private static let metadataName = "metadata.json"
    private static let animationEnabledKey = "withu.animationEnabled.v1"
    private static let animationDisabledStatesKey = "withu.animationDisabledStates.v1"
    private static let activeSourceMapKey = "withu.activeSourceMap.v1"
    private static let backgroundsFolder = "backgrounds"
    private static let decorationsFolder = "decorations"

    // MARK: - 날씨 표현 데코 (per condition × 5 = 5 PNG, 작은 아이콘)

    /// 사용자가 첨부한 작은 날씨 아이콘 PNG (캐릭터 옆에 표시).
    /// 없으면 WeatherDecorationView 가 emoji fallback.
    private static func decorationFileURL(for cond: WeatherBackgroundCondition) -> URL? {
        ensureFolder(decorationsFolder)?.appendingPathComponent("\(cond.rawValue).png")
    }

    static func hasDecoration(_ cond: WeatherBackgroundCondition) -> Bool {
        guard let url = decorationFileURL(for: cond) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    #if canImport(UIKit)
    static func loadDecoration(_ cond: WeatherBackgroundCondition) -> UIImage? {
        guard let url = decorationFileURL(for: cond),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    @discardableResult
    static func saveDecoration(_ image: UIImage, for cond: WeatherBackgroundCondition) -> Bool {
        guard let data = image.pngData(),
              let url = decorationFileURL(for: cond) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            NotificationCenter.default.post(name: .weatherBackgroundChanged, object: cond)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func clearDecoration(_ cond: WeatherBackgroundCondition) -> Bool {
        guard let url = decorationFileURL(for: cond) else { return false }
        try? FileManager.default.removeItem(at: url)
        NotificationCenter.default.post(name: .weatherBackgroundChanged, object: cond)
        return true
    }
    #endif

    // MARK: - 야간 시간 체크 (간단 fallback)

    /// 시간 기반 야간 판정. 4 타깃 공통.
    /// 우선순위:
    ///   1) sunrise/sunset 둘 다 있으면 그 시각 기준 (해시계 정확).
    ///   2) 없으면 fallbackStartMinute~fallbackEndMinute (분, midnight 기준).
    /// `now` 와 sunrise/sunset 의 절대시각이 다를 수 있으므로 시-분 만 비교 → staleness 안전.
    static func isCurrentlyNight(at date: Date = Date(),
                                 sunrise: Date? = nil,
                                 sunset: Date? = nil,
                                 fallbackStartMinute: Int = 20 * 60,
                                 fallbackEndMinute: Int = 6 * 60,
                                 calendar: Calendar = .current) -> Bool {
        let nowM = minuteOfDay(date, calendar: calendar)
        if let sunrise, let sunset {
            let riseM = minuteOfDay(sunrise, calendar: calendar)
            let setM = minuteOfDay(sunset, calendar: calendar)
            return nowM < riseM || nowM >= setM
        }
        let s = fallbackStartMinute % (24 * 60)
        let e = fallbackEndMinute % (24 * 60)
        return s < e ? (nowM >= s && nowM < e) : (nowM >= s || nowM < e)
    }

    private static func minuteOfDay(_ d: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
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

    /// 상태별 움직임 끄기 (전역 animationEnabled 와 별개 — 이 state 만 정적으로).
    /// frame1 파일은 남겨두고 재생만 막음. CharacterImageView.shouldAnimate 가 확인.
    static func isAnimationDisabled(for state: CharacterState) -> Bool {
        let defaults = UserDefaults(suiteName: SharedAppState.groupID)
        let set = defaults?.stringArray(forKey: animationDisabledStatesKey) ?? []
        return set.contains(state.rawValue)
    }

    static func setAnimationDisabled(_ disabled: Bool, for state: CharacterState) {
        let defaults = UserDefaults(suiteName: SharedAppState.groupID)
        var set = Set(defaults?.stringArray(forKey: animationDisabledStatesKey) ?? [])
        if disabled { set.insert(state.rawValue) } else { set.remove(state.rawValue) }
        defaults?.set(Array(set), forKey: animationDisabledStatesKey)
        evictImageCache()
        NotificationCenter.default.post(name: .characterImageChanged, object: state)
    }

    /// 활성 슬롯의 frame0 ↔ frame1 파일을 맞바꿈 (이미 적용된 애니메이션 캐릭터용).
    /// 둘 다 있어야 스왑. 성공 시 true.
    @discardableResult
    static func swapActiveFrames(for state: CharacterState) -> Bool {
        guard let f0 = activeFileURL(for: state, frame: 0),
              let f1 = activeFileURL(for: state, frame: 1),
              FileManager.default.fileExists(atPath: f0.path),
              FileManager.default.fileExists(atPath: f1.path) else { return false }
        let tmp = f0.deletingLastPathComponent().appendingPathComponent("swap_tmp.png")
        do {
            try? FileManager.default.removeItem(at: tmp)
            try FileManager.default.moveItem(at: f0, to: tmp)
            try FileManager.default.moveItem(at: f1, to: f0)
            try FileManager.default.moveItem(at: tmp, to: f1)
        } catch {
            return false
        }
        evictImageCache()
        NotificationCenter.default.post(name: .characterImageChanged, object: state)
        return true
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
    // MARK: - 디코드 캐시
    // 활성 슬롯 PNG 를 매 표시마다 디스크에서 다시 읽고/디코드하던 것을 캐시.
    // (홈 hero 의 0.7초 frame swap·갤러리 스크롤에서 메인스레드 재디코드 렉 제거)
    // 쓰기는 드물고 읽기가 hot → 쓰기 때 전체 비움(단순/안전). NSCache 는 thread-safe + 메모리압박 시 자동 evict.
    // 상한: 위젯/컴플리케이션(메모리 ~50MB) 보호 — 개수/총비용(byte) 둘 다 제한.
    private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 24
        cache.totalCostLimit = 24 * 1024 * 1024   // 24MB
        return cache
    }()

    /// 활성 파일의 내용 버전(수정시각+크기). 파일이 바뀌면 이 값이 바뀌어 캐시 키도 바뀐다.
    /// → 위젯/컴플리케이션처럼 앱과 다른 프로세스도 evict 없이 새 이미지를 자동으로 읽는다.
    private static func activeFileVersion(_ state: CharacterState, frame: Int) -> String {
        guard let url = activeFileURL(for: state, frame: frame),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "0" }
        let mod = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? Int) ?? 0
        // Int64 필수 — watchOS(arm64_32)는 Int 가 32비트라 epoch ms(1.7e12)가 Int.max 초과로 크래시.
        return "\(Int64(mod * 1000))_\(size)"
    }

    private static func imageCacheKey(_ state: CharacterState, frame: Int, maxPixelSize: CGFloat?, version: String) -> NSString {
        if let maxPixelSize {
            return "\(state.rawValue)#\(frame)#t\(Int(maxPixelSize))#\(version)" as NSString
        }
        return "\(state.rawValue)#\(frame)#full#\(version)" as NSString
    }

    /// 디코드된 비트맵 대략 바이트 — totalCostLimit 산정용.
    private static func imageCost(_ image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        return cg.bytesPerRow * cg.height
    }

    /// 활성 슬롯 이미지가 바뀌면 호출 — 다음 load 가 디스크에서 새로 읽도록.
    private static func evictImageCache() {
        imageCache.removeAllObjects()
    }

    /// 활성 슬롯 로드 (위젯/워치가 호출).
    static func load(_ state: CharacterState) -> UIImage? {
        loadFrame(state, frame: 0)
    }

    /// frame 별 로드. frame > 0 인데 없으면 nil. caller 가 frame 0 fallback.
    static func loadFrame(_ state: CharacterState, frame: Int) -> UIImage? {
        let key = imageCacheKey(state, frame: frame, maxPixelSize: nil,
                                version: activeFileVersion(state, frame: frame))
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let url = activeFileURL(for: state, frame: frame),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        imageCache.setObject(image, forKey: key, cost: imageCost(image))
        return image
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
        let key = imageCacheKey(state, frame: 0, maxPixelSize: maxPixelSize,
                                version: activeFileVersion(state, frame: 0))
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let image = computeThumbnail(state, maxPixelSize: maxPixelSize) else { return nil }
        imageCache.setObject(image, forKey: key, cost: imageCost(image))
        return image
    }

    private static func computeThumbnail(_ state: CharacterState,
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
        // frame0 저장 시 옛 frame1 제거 (애니 캐릭터면 직후 frame1 을 다시 저장). stale 움직임 방지.
        if frame == 0, let f1URL = activeFileURL(for: state, frame: 1) {
            try? FileManager.default.removeItem(at: f1URL)
        }
        evictImageCache()
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
    /// - applyToActiveSlot: false 면 갤러리에만 저장하고 활성 슬롯(홈/위젯/워치가 보는 곳)은
    ///   안 건드림. 배치 생성처럼 "만들어만 두고 나중에 버튼으로 적용" 흐름에 사용.
    @discardableResult
    static func save(_ image: UIImage, for state: CharacterState, frame: Int = 0,
                     applyToActiveSlot: Bool = true, batchId: String? = nil,
                     prompt: String? = nil) -> GalleryItem? {
        guard let data = image.pngData() else { return nil }
        // 1) 활성 슬롯 (위젯이 보는 곳) — frame 별
        if applyToActiveSlot {
            if let activeURL = activeFileURL(for: state, frame: frame) {
                try? data.write(to: activeURL, options: .atomic)
            }
            // frame0(새 기본 이미지) 저장 시 옛 frame1(움직임)은 무효 → 제거.
            // 애니메이션 캐릭터면 이 직후 frame1 이 다시 저장된다.
            // (안 지우면 frame1 없는 새 캐릭터가 옛 frame1 과 섞여 움직이는 버그)
            if frame == 0, let f1URL = activeFileURL(for: state, frame: 1) {
                try? FileManager.default.removeItem(at: f1URL)
            }
            evictImageCache()
            NotificationCenter.default.post(name: .characterImageChanged, object: state)
        }
        // 2) 갤러리 — frame 별 분기
        if frame == 0 {
            let item = addToGalleryInternal(data: data, sourceState: state,
                                            batchId: batchId, prompt: prompt)
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
        evictImageCache()
        return true
    }

    /// 계정 삭제 시 로컬 이미지 전체 초기화 — 활성 슬롯/갤러리/배경/데코 폴더 + 활성 매핑 + 캐시.
    static func wipeAll() {
        for folder in [activeFolder, galleryFolder, backgroundsFolder, decorationsFolder] {
            if let url = containerURL?.appendingPathComponent(folder, isDirectory: true) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        UserDefaults(suiteName: SharedAppState.groupID)?.removeObject(forKey: activeSourceMapKey)
        evictImageCache()
        NotificationCenter.default.post(name: .characterImageChanged, object: nil)
        NotificationCenter.default.post(name: .weatherBackgroundChanged, object: nil)
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

    /// 갤러리 폴더(상태별) 전용 그룹핑. 디스크 포맷/키 변경 없이 메모리 그룹핑만.
    ///   - byState: userFacing 상태별 항목 (각 버킷 createdAt 내림차순 유지)
    ///   - legacy:  더 이상 노출 안 하는 옛 상태(rawValue) 항목 → "기타" 버킷
    static func loadGalleryGrouped() -> (byState: [CharacterState: [GalleryItem]], legacy: [GalleryItem]) {
        let all = loadGalleryMetadata()  // 이미 createdAt desc 정렬
        let facing = Set(CharacterState.userFacing)
        var byState: [CharacterState: [GalleryItem]] = [:]
        var legacy: [GalleryItem] = []
        for item in all {
            if let st = CharacterState(rawValue: item.sourceState), facing.contains(st) {
                byState[st, default: []].append(item)
            } else {
                legacy.append(item)
            }
        }
        return (byState, legacy)
    }

    /// '캐릭터별' 그룹 — batchId('한번에 만들기' 세션)로 묶음. batchId 없는 항목(단건·옛)은 제외.
    /// 반환: 최신 캐릭터 먼저, 각 그룹 안은 userFacing 상태 순.
    static func loadGalleryByCharacter() -> [(batchId: String, createdAt: Date, items: [GalleryItem])] {
        let all = loadGalleryMetadata()   // createdAt desc
        var groups: [String: [GalleryItem]] = [:]
        for item in all {
            guard let bid = item.batchId else { continue }
            groups[bid, default: []].append(item)
        }
        let order = CharacterState.userFacing
        func rank(_ raw: String) -> Int {
            CharacterState(rawValue: raw).flatMap { order.firstIndex(of: $0) } ?? order.count
        }
        return groups.map { key, value in
            (batchId: key,
             createdAt: value.map(\.createdAt).max() ?? Date.distantPast,
             items: value.sorted { rank($0.sourceState) < rank($1.sourceState) })
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private static func saveGalleryMetadata(_ items: [GalleryItem]) {
        guard let url = metadataURL,
              let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }

    @discardableResult
    private static func addToGalleryInternal(data: Data,
                                              sourceState: CharacterState,
                                              batchId: String? = nil,
                                              prompt: String? = nil) -> GalleryItem? {
        let id = UUID().uuidString
        guard let url = galleryFileURL(id: id) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        let item = GalleryItem(id: id, sourceState: sourceState.rawValue,
                               createdAt: Date(), batchId: batchId, prompt: prompt)
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

    /// 갤러리 항목의 이미지 파일을 교체 (배경 빼기 등 후처리 결과 반영). frame 0/1.
    @discardableResult
    static func replaceGalleryImage(_ id: String, with image: UIImage, frame: Int = 0) -> Bool {
        let url = frame == 1 ? galleryFrame1URL(id: id) : galleryFileURL(id: id)
        guard let url, let data = image.pngData() else { return false }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return false
        }
        return true
    }

    /// 갤러리 항목의 frame0 ↔ frame1 파일을 맞바꿈 (연속 이미지 항목의 프레임 순서 교체).
    /// 둘 다 있어야 스왑. 성공 시 true.
    @discardableResult
    static func swapGalleryFrames(_ id: String) -> Bool {
        guard let f0 = galleryFileURL(id: id), let f1 = galleryFrame1URL(id: id),
              FileManager.default.fileExists(atPath: f0.path),
              FileManager.default.fileExists(atPath: f1.path) else { return false }
        let tmp = f0.deletingLastPathComponent().appendingPathComponent("\(id)_swap_tmp.png")
        do {
            try? FileManager.default.removeItem(at: tmp)
            try FileManager.default.moveItem(at: f0, to: tmp)
            try FileManager.default.moveItem(at: f1, to: f0)
            try FileManager.default.moveItem(at: tmp, to: f1)
        } catch {
            return false
        }
        return true
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
        evictImageCache()
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
