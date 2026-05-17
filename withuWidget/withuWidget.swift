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
    let isPlaceholder: Bool

    static let placeholder = CharacterEntry(
        date: .now,
        state: .idle,
        todaySteps: 4321,
        isPlaceholder: true
    )

    init(from message: WatchMessage) {
        self.date = message.timestamp
        self.state = message.state
        self.todaySteps = message.todaySteps
        self.isPlaceholder = false
    }

    init(date: Date, state: CharacterState, todaySteps: Double?, isPlaceholder: Bool = false) {
        self.date = date
        self.state = state
        self.todaySteps = todaySteps
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
        let entry = currentEntry()
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
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

// MARK: 잠금화면 (accessory*) — iOS 가 강제 모노톤 tint 라 SF Symbol 이 적합

private struct CircularView: View {
    let entry: CharacterEntry
    var body: some View {
        // 시스템이 자동 tint — Circle 배경 없이 SF Symbol 만 둬야 자연스러움
        Image(systemName: entry.state.symbolName)
            .font(.system(size: 24, weight: .semibold))
            .widgetAccentable()
    }
}

private struct RectangularView: View {
    let entry: CharacterEntry
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.state.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.state.caption).font(.caption2).bold().lineLimit(1)
                if let steps = entry.todaySteps {
                    Text("👟 \(Int(steps))보").font(.system(size: 10))
                }
            }
            Spacer(minLength: 0)
        }
    }
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
        // 캐릭터를 위젯의 약 1/3 사이즈로 작게 (화면 전체 대비 약 1/9)
        VStack {
            CharacterImageView(state: entry.state)
                .frame(width: 56, height: 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MediumView: View {
    let entry: CharacterEntry
    var body: some View {
        HStack(spacing: 12) {
            CharacterImageView(state: entry.state)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.state.caption)
                    .font(.subheadline)
                    .bold()
                if let steps = entry.todaySteps {
                    Text("👟 \(Int(steps))보")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LargeView: View {
    let entry: CharacterEntry
    var body: some View {
        VStack(spacing: 10) {
            CharacterImageView(state: entry.state)
                .frame(width: 140, height: 140)
            Text(entry.state.caption)
                .font(.headline)
            if let steps = entry.todaySteps {
                Text("👟 오늘 \(Int(steps))보")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
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
