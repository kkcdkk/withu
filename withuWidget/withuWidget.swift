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

// MARK: 잠금화면 (accessory*)

private struct CircularView: View {
    let entry: CharacterEntry
    var body: some View {
        ZStack {
            Circle().fill(entry.state.tint.opacity(0.25))
            Image(systemName: entry.state.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(entry.state.tint)
        }
    }
}

private struct RectangularView: View {
    let entry: CharacterEntry
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(entry.state.tint.opacity(0.25))
                Image(systemName: entry.state.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(entry.state.tint)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.state.caption).font(.caption2).bold().lineLimit(1)
                if let steps = entry.todaySteps {
                    Text("👟 \(Int(steps))보").font(.system(size: 10)).foregroundStyle(.secondary)
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

private struct SmallView: View {
    let entry: CharacterEntry
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(entry.state.tint.opacity(0.20))
                Image(systemName: entry.state.symbolName)
                    .resizable()
                    .scaledToFit()
                    .padding(18)
                    .foregroundStyle(entry.state.tint)
            }
            .aspectRatio(1, contentMode: .fit)
            Text(entry.state.caption)
                .font(.caption)
                .bold()
                .lineLimit(1)
        }
        .padding(8)
    }
}

private struct MediumView: View {
    let entry: CharacterEntry
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(entry.state.tint.opacity(0.20))
                Image(systemName: entry.state.symbolName)
                    .resizable()
                    .scaledToFit()
                    .padding(20)
                    .foregroundStyle(entry.state.tint)
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.state.caption)
                    .font(.headline)
                    .bold()
                if let steps = entry.todaySteps {
                    Text("👟 오늘 \(Int(steps))보")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("withu")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
}

private struct LargeView: View {
    let entry: CharacterEntry
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(entry.state.tint.opacity(0.18))
                Image(systemName: entry.state.symbolName)
                    .resizable()
                    .scaledToFit()
                    .padding(40)
                    .foregroundStyle(entry.state.tint)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)

            Text(entry.state.caption)
                .font(.title3)
                .bold()
            if let steps = entry.todaySteps {
                Text("👟 오늘 \(Int(steps))보")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Widget

struct withuWidget: Widget {
    let kind: String = "withuWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CharacterProvider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
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
