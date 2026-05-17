//
//  withuComplication.swift
//  withuComplication
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
        // 한 시간마다 한 번씩만 자동 갱신. 실제 갱신은 메시지 도착 시
        // ConnectivityManager 가 WidgetCenter.reloadAllTimelines 호출함.
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

// MARK: - View

struct CharacterComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CharacterEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            inline
        default:
            circular
        }
    }

    /// 워치 컴플리케이션도 시스템 tint 강제. alpha PNG 면 캐릭터 실루엣이
    /// 시스템 색으로 채워져 SF Symbol 보다 더 캐릭터답게 보임.
    private var circular: some View {
        CharacterImageView(state: entry.state)
            .widgetAccentable()
    }

    private var rectangular: some View {
        HStack(spacing: 6) {
            CharacterImageView(state: entry.state)
                .frame(width: 28, height: 28)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.state.caption)
                    .font(.caption2)
                    .bold()
                    .lineLimit(1)
                if let steps = entry.todaySteps {
                    Text("👟 \(Int(steps))보")
                        .font(.system(size: 10))
                } else {
                    Text(entry.date, style: .relative)
                        .font(.system(size: 10))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var inline: some View {
        Text("\(entry.state.symbolEmoji) \(entry.state.caption)")
    }
}

// MARK: - Widget

struct withuComplication: Widget {
    let kind: String = "withuComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CharacterProvider()) { entry in
            CharacterComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("withu 캐릭터")
        .description("내 캐릭터의 지금 상태를 시계 페이스에 보여줘요.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
        .containerBackgroundRemovable(true)
    }
}

// symbolEmoji 는 공유 CharacterState 에 정의됨 (iOS 위젯과 공유)

#Preview("Circular", as: .accessoryCircular) {
    withuComplication()
} timeline: {
    CharacterEntry(date: .now, state: .running, todaySteps: 8200)
    CharacterEntry(date: .now, state: .sleeping, todaySteps: 0)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    withuComplication()
} timeline: {
    CharacterEntry(date: .now, state: .energetic, todaySteps: 12000)
}
