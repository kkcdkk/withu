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
    let isPlaceholder: Bool

    static let placeholder = CharacterEntry(
        date: .now,
        state: .idle,
        todaySteps: 4321,
        todayActiveMinutes: 38,
        todayActiveKcal: 412,
        isPlaceholder: true
    )

    init(from message: WatchMessage) {
        self.date = message.timestamp
        self.state = message.state
        self.todaySteps = message.todaySteps
        self.todayActiveMinutes = message.todayActiveMinutes
        self.todayActiveKcal = message.todayActiveKcal
        self.isPlaceholder = false
    }

    init(date: Date,
         state: CharacterState,
         todaySteps: Double?,
         todayActiveMinutes: Double? = nil,
         todayActiveKcal: Double? = nil,
         isPlaceholder: Bool = false) {
        self.date = date
        self.state = state
        self.todaySteps = todaySteps
        self.todayActiveMinutes = todayActiveMinutes
        self.todayActiveKcal = todayActiveKcal
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
        // 매 15분 새 entry 미리 만들어둠 → iOS 가 reload 자주 안 해도 자동 갱신
        let now = Date()
        var entries: [CharacterEntry] = []
        for i in 0..<8 {
            let date = Calendar.current.date(byAdding: .minute, value: i * 15, to: now) ?? now
            let base = currentEntry()
            entries.append(CharacterEntry(
                date: date,
                state: base.state,
                todaySteps: base.todaySteps,
                todayActiveMinutes: base.todayActiveMinutes,
                todayActiveKcal: base.todayActiveKcal,
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
        CharacterImageView(state: entry.state)
            .widgetAccentable()
    }
}

private struct RectangularView: View {
    let entry: CharacterEntry
    var body: some View {
        HStack(spacing: 6) {
            CharacterImageView(state: entry.state)
                .frame(width: 28, height: 28)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.state.caption).font(.caption2).bold().lineLimit(1)
                Text(lockRectMetric(entry)).font(.system(size: 10)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

/// 잠금화면 rectangular 의 한 줄 — 핵심 metric 2~3개 모음.
private func lockRectMetric(_ entry: CharacterEntry) -> String {
    var parts: [String] = []
    if let s = entry.todaySteps, s > 0 { parts.append("👟\(Int(s))") }
    if let k = entry.todayActiveKcal, k > 0 { parts.append("🔥\(Int(k))") }
    if let m = entry.todayActiveMinutes, m > 0 { parts.append("🏃\(Int(m))") }
    return parts.joined(separator: " · ")
}

private struct InlineView: View {
    let entry: CharacterEntry
    var body: some View {
        Text("\(entry.state.symbolEmoji) \(entry.state.caption)")
    }
}

// MARK: 홈화면 (system*)

/// 위젯을 "스티커처럼" — 배경 박스 / 회색 원 제거.
/// 홈화면 wallpaper 가 비치고 캐릭터만 떠 있는 느낌.
private struct SmallView: View {
    let entry: CharacterEntry
    var body: some View {
        VStack(spacing: 4) {
            CharacterImageView(state: entry.state)
                .frame(width: 56, height: 56)
            // 작아도 핵심 활동량 한 줄
            if entry.todaySteps != nil || entry.todayActiveKcal != nil {
                Text(fitnessLineShort(entry))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MediumView: View {
    let entry: CharacterEntry
    var body: some View {
        HStack(spacing: 14) {
            CharacterImageView(state: entry.state)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.state.caption).font(.subheadline).bold()
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
        VStack(spacing: 12) {
            CharacterImageView(state: entry.state)
                .frame(width: 140, height: 140)
            Text(entry.state.caption).font(.headline)
            fitnessRows(entry, layout: .expanded)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
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
    }
}

/// systemSmall 의 한 줄 짧은 표시. 가장 큰 metric 하나만.
private func fitnessLineShort(_ entry: CharacterEntry) -> String {
    if let s = entry.todaySteps, s > 0 {
        return "👟 \(Int(s))"
    }
    if let k = entry.todayActiveKcal, k > 0 {
        return "🔥 \(Int(k))"
    }
    return ""
}

// MARK: - Widget

struct withuWidget: Widget {
    let kind: String = "withuWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CharacterProvider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    // 투명 배경 — 호스트 wallpaper 비치게.
                    // (iOS 17+ containerBackground 는 의무라 비워둘 수 없음, Color.clear 명시.)
                    Color.clear
                }
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
