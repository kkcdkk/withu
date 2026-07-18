//
//  withuWidget.swift
//  withuWidget
//

import WidgetKit
import SwiftUI

// MARK: - Entry

struct CharacterEntry: TimelineEntry {
    let date: Date
    let state: CharacterState
    let todaySteps: Double?
    let todayActiveMinutes: Double?
    let todayActiveKcal: Double?
    let lastSleepHours: Double?
    let weatherEmoji: String?
    let weatherTempC: Double?
    let weatherSunrise: Date?
    let weatherSunset: Date?
    let isPlaceholder: Bool

    static let placeholder = CharacterEntry(
        date: .now,
        state: .idle,
        todaySteps: 4321,
        todayActiveMinutes: 38,
        todayActiveKcal: 412,
        lastSleepHours: 7.5,
        weatherEmoji: "☀️",
        weatherTempC: 18,
        isPlaceholder: true
    )

    init(from message: WatchMessage) {
        self.date = message.timestamp
        self.state = message.state
        self.todaySteps = message.todaySteps
        self.todayActiveMinutes = message.todayActiveMinutes
        self.todayActiveKcal = message.todayActiveKcal
        self.lastSleepHours = message.lastSleepHours
        self.weatherEmoji = message.weatherEmoji
        self.weatherTempC = message.weatherTempC
        self.weatherSunrise = message.weatherSunrise
        self.weatherSunset = message.weatherSunset
        self.isPlaceholder = false
    }

    init(date: Date,
         state: CharacterState,
         todaySteps: Double?,
         todayActiveMinutes: Double? = nil,
         todayActiveKcal: Double? = nil,
         lastSleepHours: Double? = nil,
         weatherEmoji: String? = nil,
         weatherTempC: Double? = nil,
         weatherSunrise: Date? = nil,
         weatherSunset: Date? = nil,
         isPlaceholder: Bool = false) {
        self.date = date
        self.state = state
        self.todaySteps = todaySteps
        self.todayActiveMinutes = todayActiveMinutes
        self.todayActiveKcal = todayActiveKcal
        self.lastSleepHours = lastSleepHours
        self.weatherEmoji = weatherEmoji
        self.weatherTempC = weatherTempC
        self.weatherSunrise = weatherSunrise
        self.weatherSunset = weatherSunset
        self.isPlaceholder = isPlaceholder
    }
}

// MARK: - Provider

struct CharacterProvider: TimelineProvider {
    func placeholder(in context: Context) -> CharacterEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (CharacterEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CharacterEntry>) -> Void) {
        // 매 15분 새 entry 미리 만들어둠 → iOS 가 reload 안 해도 수면→기상 경계에서 스스로 전환.
        // (예전 버그: 모든 entry 가 '지금' 상태라 07:00 기상 시각이 지나도 위젯이 계속 자고 있었음.)
        let now = Date()
        let base = currentEntry()
        let schedule = SharedAppState.loadSchedule()
        // 운동 상태는 실시간 신호라 위젯이 예측 못 함 — 지금(i=0) entry 만 앱 계산값 유지.
        let baseIsLiveWorkout: Bool
        switch base.state {
        case .walking, .running, .cycling, .energetic: baseIsLiveWorkout = true
        default: baseIsLiveWorkout = false
        }
        var entries: [CharacterEntry] = []
        for i in 0..<8 {
            let date = Calendar.current.date(byAdding: .minute, value: i * 15, to: now) ?? now
            // '설정 시간 기준'이면 스케줄로 상태 계산 → 수면/기상 경계에서 위젯이 스스로 전환.
            // (지금 시점도 스케줄로 — 오래 안 열려 base.state 가 stale 이어도 정확.)
            // 단 지금 운동 중이면 그 값을 유지. '수면 모드 기준'/구버전(스케줄 없음)은 현재 상태 유지.
            let state: CharacterState
            if let schedule, schedule.usesSchedule, !(i == 0 && baseIsLiveWorkout) {
                state = schedule.scheduledState(at: date)
            } else {
                state = base.state
            }
            entries.append(CharacterEntry(
                date: date,
                state: state,
                todaySteps: base.todaySteps,
                todayActiveMinutes: base.todayActiveMinutes,
                todayActiveKcal: base.todayActiveKcal,
                lastSleepHours: base.lastSleepHours,
                weatherEmoji: base.weatherEmoji,
                weatherTempC: base.weatherTempC,
                weatherSunrise: base.weatherSunrise,
                weatherSunset: base.weatherSunset,
                isPlaceholder: false
            ))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func currentEntry() -> CharacterEntry {
        if let msg = SharedAppState.loadMessage() {
            return CharacterEntry(from: msg)
        }
        return .placeholder
    }
}

// MARK: - Views

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CharacterEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularView(entry: entry)
        case .accessoryRectangular:
            RectangularView(entry: entry)
        case .accessoryInline:
            InlineView(entry: entry)
        case .systemSmall:
            SmallView(entry: entry)
        case .systemMedium:
            MediumView(entry: entry)
        case .systemLarge:
            LargeView(entry: entry)
        default:
            CircularView(entry: entry)
        }
    }
}

// MARK: 잠금화면 (accessory*) — 시스템이 모노톤 tint 강제하지만
// alpha PNG 의 캐릭터 실루엣은 그대로 살아남음. 시스템 색으로 채워진 캐릭터.

private struct CircularView: View {
    let entry: CharacterEntry
    var body: some View {
        // accessoryCircular 은 작은 원. 128px 면 충분 (메모리 절약).
        CharacterImageView(state: entry.state, maxPixelSize: 128)
            .widgetAccentable()
    }
}

private struct RectangularView: View {
    let entry: CharacterEntry
    var body: some View {
        HStack(spacing: 6) {
            CharacterImageView(state: entry.state, maxPixelSize: 128)
                .frame(width: 28, height: 28)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                // 1줄: 날씨 + state caption
                Text(lockRectHeader(entry)).font(.caption2).bold().lineLimit(1)
                // 2줄: 건강 metric 압축
                Text(lockRectMetric(entry)).font(.system(size: 10)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

private func lockRectHeader(_ entry: CharacterEntry) -> String {
    if let w = weatherLine(entry) { return "\(w) · \(entry.state.caption)" }
    return entry.state.caption
}

/// 잠금화면 rectangular 의 한 줄 — 핵심 metric 압축.
private func lockRectMetric(_ entry: CharacterEntry) -> String {
    var parts: [String] = []
    if let s = entry.todaySteps, s > 0 { parts.append("👟\(Int(s))") }
    if let m = entry.todayActiveMinutes, m > 0 { parts.append("🏃\(Int(m))") }
    if let h = entry.lastSleepHours, h > 0 { parts.append("💤\(formatHours(h))") }
    return parts.joined(separator: " · ")
}

private struct InlineView: View {
    let entry: CharacterEntry
    var body: some View {
        Text(inlineText(entry))
    }
}

private func inlineText(_ entry: CharacterEntry) -> String {
    var parts: [String] = ["\(entry.state.symbolEmoji) \(entry.state.caption)"]
    if let w = weatherLine(entry) { parts.append(w) }
    if let s = entry.todaySteps, s > 0 { parts.append("👟\(Int(s))") }
    return parts.joined(separator: " · ")
}

// MARK: 홈화면 (system*)

/// 위젯을 "스티커처럼" — 배경 박스 / 회색 원 제거.
/// 홈화면 wallpaper 가 비치고 캐릭터만 떠 있는 느낌.
private struct SmallView: View {
    let entry: CharacterEntry
    var body: some View {
        VStack(spacing: 3) {
            // 맨 위: 날씨 (있을 때만)
            if let weather = weatherLine(entry) {
                Text(weather)
                    .font(.system(size: 11)).bold()
                    .lineLimit(1)
            }
            ZStack {
                CharacterImageView(state: entry.state, maxPixelSize: 256)
                WeatherDecorationView(condition: widgetWeatherCondition(from: entry),
                                      size: 16)
                    .offset(y: -3)
            }
            .frame(width: 46, height: 46)
            // 핵심 metric 들 한 줄에 압축. small 은 좁아서 가장 큰 2개만.
            Text(smallMetricLine(entry))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MediumView: View {
    let entry: CharacterEntry
    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                ZStack {
                    CharacterImageView(state: entry.state, maxPixelSize: 256)
                    WeatherDecorationView(condition: widgetWeatherCondition(from: entry),
                                          size: 22)
                        .offset(y: -4)
                }
                .frame(width: 64, height: 64)
                Text(entry.state.caption).font(.caption2).bold().lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 3) {
                if let weather = weatherLine(entry) {
                    Text(weather).font(.caption).bold()
                }
                fitnessRows(entry, layout: .compact)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LargeView: View {
    let entry: CharacterEntry
    var body: some View {
        VStack(spacing: 8) {
            // 맨 위 날씨 한 줄
            if let weather = weatherLine(entry) {
                Text(weather)
                    .font(.headline)
            }
            ZStack {
                CharacterImageView(state: entry.state, maxPixelSize: 512)
                WeatherDecorationView(condition: widgetWeatherCondition(from: entry),
                                      size: 40)
                    .offset(y: -7)
            }
            .frame(width: 120, height: 120)
            Text(entry.state.caption).font(.subheadline).bold()
            Divider().padding(.horizontal, 40)
            fitnessRows(entry, layout: .expanded)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 위젯에서 표시할 날씨 condition.
/// 1순위: 일출/일몰 기준 야간이면 .night
/// 2순위: entry.weatherEmoji → sunny/cloudy/rainy/snowy
/// 잠금화면 (accessory*) 에선 호출 안 함 — 모노톤이라 어울리지 않음.
private func widgetWeatherCondition(from entry: CharacterEntry) -> WeatherBackgroundCondition? {
    let isNight = CharacterImageStore.isCurrentlyNight(
        at: entry.date,
        sunrise: entry.weatherSunrise,
        sunset: entry.weatherSunset
    )
    if isNight { return .night }
    return WeatherBackgroundCondition.from(emoji: entry.weatherEmoji)
}

// MARK: - Fitness 표시 helpers

private enum FitnessLayout { case compact, expanded }

@ViewBuilder
private func fitnessRows(_ entry: CharacterEntry, layout: FitnessLayout) -> some View {
    let font: Font = (layout == .compact) ? .caption2 : .callout
    VStack(alignment: .leading, spacing: 2) {
        if let s = entry.todaySteps {
            Text("👟 \(Int(s))보").font(font).foregroundStyle(.secondary)
        }
        if let m = entry.todayActiveMinutes, m > 0 {
            Text("🏃 \(Int(m))분").font(font).foregroundStyle(.secondary)
        }
        if let k = entry.todayActiveKcal, k > 0 {
            Text("🔥 \(Int(k))kcal").font(font).foregroundStyle(.secondary)
        }
        if let h = entry.lastSleepHours, h > 0 {
            Text("💤 \(formatHours(h))").font(font).foregroundStyle(.secondary)
        }
    }
}

/// 맨 위 한 줄: 날씨 이모지 + 온도. 둘 다 없으면 nil.
private func weatherLine(_ entry: CharacterEntry) -> String? {
    let emoji = entry.weatherEmoji ?? ""
    if let t = entry.weatherTempC {
        let head = emoji.isEmpty ? "" : "\(emoji) "
        return "\(head)\(Int(t.rounded()))°"
    }
    return emoji.isEmpty ? nil : emoji
}

/// systemSmall 의 한 줄. 걸음수 + 수면 (또는 가장 큰 metric 두 개).
private func smallMetricLine(_ entry: CharacterEntry) -> String {
    var parts: [String] = []
    if let s = entry.todaySteps, s > 0 { parts.append("👟\(Int(s))") }
    if let h = entry.lastSleepHours, h > 0 { parts.append("💤\(formatHours(h))") }
    return parts.joined(separator: " · ")
}

private func formatHours(_ h: Double) -> String {
    if h < 1 { return "\(Int(h * 60))분" }
    let whole = Int(h)
    let frac = Int((h - Double(whole)) * 10)
    return frac == 0 ? "\(whole)h" : "\(whole).\(frac)h"
}

// MARK: - Widget

struct withuWidget: Widget {
    let kind: String = "withuWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CharacterProvider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    // 풀배경 X — 호스트 wallpaper 비치게. 날씨 표현은 WidgetView 안에서.
                    Color.clear
                }
                .widgetURL(URL(string: "withu://main"))   // 위젯 탭 → 앱 열림
        }
        .configurationDisplayName("withu 캐릭터")
        .description("내 캐릭터의 지금 상태를 보여줘요.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .systemSmall,
            .systemMedium,
            .systemLarge,
        ])
        // 사용자가 위젯 추가 또는 길게 누른 후 "배경" 토글로
        // 흰색 backdrop 을 진짜 투명으로 바꿀 수 있게.
        // (iOS 17+ — Color.clear 만으론 light mode 에서 시스템이 흰색 강제)
        .containerBackgroundRemovable(true)
    }
}

#Preview("Small", as: .systemSmall) {
    withuWidget()
} timeline: {
    CharacterEntry(date: .now, state: .running, todaySteps: 8200)
    CharacterEntry(date: .now, state: .sleeping, todaySteps: 0)
}

#Preview("Medium", as: .systemMedium) {
    withuWidget()
} timeline: {
    CharacterEntry(date: .now, state: .energetic, todaySteps: 12000)
}

#Preview("Lock Circular", as: .accessoryCircular) {
    withuWidget()
} timeline: {
    CharacterEntry(date: .now, state: .running, todaySteps: 8200)
}
