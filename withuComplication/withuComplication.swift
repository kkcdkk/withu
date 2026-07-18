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
        guard let msg = SharedAppState.loadMessage() else {
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
            completion(Timeline(entries: [.placeholder], policy: .after(next)))
            return
        }
        // iOS 위젯과 동일 — 미래 entry 를 각 시각의 스케줄 상태로 계산해 수면→기상 경계에서 스스로 전환.
        // (예전 버그: 단일 entry 라 아이폰이 늦게 sync 하면 기상 시각 지나도 계속 자고 있었음.)
        let now = Date.now
        let base = CharacterEntry(from: msg)
        let baseIsLiveWorkout: Bool
        switch base.state {
        case .walking, .running, .cycling, .energetic: baseIsLiveWorkout = true
        default: baseIsLiveWorkout = false
        }
        var entries: [CharacterEntry] = []
        for i in 0..<8 {
            let date = Calendar.current.date(byAdding: .minute, value: i * 15, to: now) ?? now
            let state: CharacterState
            if let schedule = msg.schedule, schedule.usesSchedule, !(i == 0 && baseIsLiveWorkout) {
                state = schedule.scheduledState(at: date)
            } else {
                state = base.state
            }
            entries.append(CharacterEntry(
                date: date,
                state: state,
                todaySteps: base.todaySteps,
                todayActiveMinutes: base.todayActiveMinutes,
                todayActiveKcal: base.todayActiveKcal
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

// MARK: - View

struct CharacterComplicationView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
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

    /// fullColor (Modular 등) → 원본 그대로
    /// accented/vibrant (단색 강제 face) → outline + 어두운 디테일
    private var useOutline: Bool {
        renderingMode != .fullColor
    }

    private var circular: some View {
        CharacterImageView(state: entry.state,
                           maxPixelSize: 128,
                           outlineOnly: useOutline)
    }

    private var rectangular: some View {
        HStack(spacing: 6) {
            CharacterImageView(state: entry.state,
                               maxPixelSize: 128,
                               outlineOnly: useOutline)
                .frame(width: 28, height: 28)
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
                .containerBackground(for: .widget) {
                    // 워치 컴플리케이션은 모노톤 강제라 효과 작지만 일관성 위해 동일 처리.
                    Color.clear
                }
                .widgetURL(URL(string: "withu://main"))   // 컴플리케이션 탭 → 워치 앱 열림
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
