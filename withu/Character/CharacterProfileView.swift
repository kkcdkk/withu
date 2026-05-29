//
//  CharacterProfileView.swift
//  withu
//
//  내 캐릭터 설정 — 이름, 설명, 수면/식사 시간.
//  값 변경 시 자동 저장 (App Group 공유).
//

import SwiftUI
import WidgetKit

struct CharacterProfileView: View {
    @State private var profile: CharacterProfile = CharacterProfileStore.load()
    @State private var health = HealthKitManager.shared
    @State private var focus = FocusModeManager.shared
    @State private var animationEnabled: Bool = CharacterImageStore.animationEnabled

    var body: some View {
        Form {
            Section {
                TextField("예: 코코, 모찌", text: $profile.name)
                TextField("성격/말투 등 (선택)", text: $profile.description, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("프로필")
            } footer: {
                Text("이름은 캐릭터를 부르거나 위젯에 표시될 때 사용돼요.")
                    .font(.caption2)
            }

            Section {
                TextField("예: round chibi mascot, pink rabbit with big eyes",
                          text: $profile.aiPrompt, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("🎨 AI 기본 프롬프트")
            } footer: {
                Text("\"함께할 캐릭터 생성하기\" 진입 시 자동으로 채워져요. 외형 한 줄로 정의 (영어 권장).")
                    .font(.caption2)
            }

            Section {
                HStack {
                    Text("지금 기준")
                    Spacer()
                    Text(currentSleepSourceLabel)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Toggle("수면 자동 감지", isOn: autoDetectBinding)
                DatePicker("취침", selection: sleepStartBinding,
                           displayedComponents: .hourAndMinute)
                DatePicker("기상", selection: sleepEndBinding,
                           displayedComponents: .hourAndMinute)
            } header: {
                Text("💤 수면 시간")
            } footer: {
                Text(sleepFooterText)
                    .font(.caption2)
            }

            Section {
                DatePicker("점심 시작", selection: lunchBinding,
                           displayedComponents: .hourAndMinute)
                DatePicker("저녁 시작", selection: dinnerBinding,
                           displayedComponents: .hourAndMinute)
            } header: {
                Text("🍽️ 식사 시간")
            } footer: {
                Text("설정한 시각 ~ 30분 후까지 식사 캐릭터로 표시돼요.")
                    .font(.caption2)
            }

            statesOverviewSection

            weatherBackgroundsSection

            Section {
                Toggle("연속 이미지 사용 (있을 때)", isOn: $animationEnabled)
            } header: {
                Text("🎬 캐릭터 표시")
            } footer: {
                Text("""
                    ON — 연속 이미지를 생성한 캐릭터는 0.7초 간격으로 swap 애니메이션.
                    OFF — frame 1 이 있어도 정적 (frame 0 만). 배터리/시각 부담 줄이고 싶을 때.
                    ※ 갤러리의 frame 1 데이터는 유지됨 — 이 토글은 표시 방식만 바꿔요.
                    """)
                    .font(.caption2)
            }
        }
        .navigationTitle("내 캐릭터 설정")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: animationEnabled) { _, new in
            CharacterImageStore.setAnimationEnabled(new)
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: profile) { _, new in
            CharacterProfileStore.save(new)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Weather backgrounds

    /// 4 날씨 배경의 현재 상태 + 각 condition 의 생성 화면 진입.
    private var weatherBackgroundsSection: some View {
        Section {
            ForEach(WeatherBackgroundCondition.allCases, id: \.self) { cond in
                NavigationLink {
                    WeatherBackgroundGenView(initialCondition: cond)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(uiColor: .tertiarySystemBackground))
                            if let img = CharacterImageStore.loadBackground(cond) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 44, height: 44)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(cond.displayName).font(.callout.weight(.medium))
                            Text(CharacterImageStore.hasBackground(cond)
                                 ? "사용자 생성"
                                 : "기본 (없음)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("🌤 날씨 배경")
        } footer: {
            Text("현재 날씨에 따라 메인 화면 · 위젯 · 워치 의 캐릭터 뒤에 자동으로 배경이 합성돼요. 비어 있는 날씨는 배경 없이 캐릭터만 표시. 행을 탭하면 해당 날씨 배경 생성 화면으로.")
                .font(.caption2)
        }
    }

    // MARK: - States overview

    /// 9개 state 각각 현재 적용된 캐릭터 이미지 + 이름. 적용 안 된 곳은 placeholder.
    private var statesOverviewSection: some View {
        Section {
            ForEach(CharacterState.allCases, id: \.self) { state in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(state.tint.opacity(0.12))
                        CharacterImageView(state: state)
                            .padding(4)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(state.symbolEmoji).font(.caption)
                            Text(state.rawValue).font(.callout.weight(.medium))
                            if CharacterImageStore.hasAnimationFrames(for: state) {
                                Text("🎬").font(.caption2)
                            }
                        }
                        Text(CharacterImageStore.hasImage(for: state)
                             ? "사용자 캐릭터"
                             : "기본 (placeholder)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("📚 상태별 현재 캐릭터")
        } footer: {
            Text("각 상태에 어떤 캐릭터가 적용돼 있는지. 비어 있으면 placeholder (SF Symbol 또는 기본 일러스트). 캐릭터 갤러리 / 캐릭터 생성 화면에서 교체.")
                .font(.caption2)
        }
    }

    // MARK: - Sleep source indicator + toggle

    /// 지금 sleeping 을 트리거하는 활성 신호 표시.
    /// resolver 우선순위: (1) Focus 모드 OR HealthKit inBed → (2) 프로필 시간
    private var currentSleepSourceLabel: String {
        let inProfileWindow = isNowInProfileSleepWindow()
        if profile.manualSleepOnly ?? false {
            return inProfileWindow ? "프로필 시간 안" : "프로필 시간 밖"
        }
        // 1순위 — 외부 신호
        if focus.isFocused || focus.isFocusFilterSleeping { return "Focus 모드 (1순위)" }
        if health.isInBedSchedule { return "HealthKit inBed (1순위)" }
        // 2순위 — 프로필 fallback
        if inProfileWindow { return "프로필 시간 (2순위)" }
        return "지금은 안 잠"
    }

    private func isNowInProfileSleepWindow() -> Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMin = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let startMin = profile.sleepStartHour * 60 + profile.sleepStartMinute
        let endMin = profile.sleepEndHour * 60 + profile.sleepEndMinute
        let s = startMin % (24 * 60)
        let e = endMin % (24 * 60)
        return s < e ? (nowMin >= s && nowMin < e) : (nowMin >= s || nowMin < e)
    }

    /// 토글 켜짐 = 자동 감지 사용 = manualSleepOnly false.
    private var autoDetectBinding: Binding<Bool> {
        Binding(
            get: { !(profile.manualSleepOnly ?? false) },
            set: { profile.manualSleepOnly = !$0 }
        )
    }

    private var sleepFooterText: String {
        if profile.manualSleepOnly ?? false {
            return "자동 감지 OFF — 위의 시간대만 기준. iOS Focus / Health 수면 일정과 무관."
        }
        return """
            우선순위:
              1순위 — iOS 수면 집중 모드 (또는 Health 수면 일정)
              2순위 — 위의 시간대 (사용자 설정)
            ※ Sleep Focus 가 켜져 있으면 어떤 시각이든 자고 있는 걸로. 둘 다 없으면 위 시간대를 fallback 으로 사용.
            """
    }

    // MARK: - DatePicker bindings (hour/minute ↔ Date)

    private var sleepStartBinding: Binding<Date> {
        Binding(
            get: { dateFor(profile.sleepStartHour, profile.sleepStartMinute) },
            set: { new in
                let c = hourMinute(from: new)
                profile.sleepStartHour = c.h
                profile.sleepStartMinute = c.m
            }
        )
    }

    private var sleepEndBinding: Binding<Date> {
        Binding(
            get: { dateFor(profile.sleepEndHour, profile.sleepEndMinute) },
            set: { new in
                let c = hourMinute(from: new)
                profile.sleepEndHour = c.h
                profile.sleepEndMinute = c.m
            }
        )
    }

    private var lunchBinding: Binding<Date> {
        Binding(
            get: { dateFor(profile.lunchHour, profile.lunchMinute) },
            set: { new in
                let c = hourMinute(from: new)
                profile.lunchHour = c.h
                profile.lunchMinute = c.m
            }
        )
    }

    private var dinnerBinding: Binding<Date> {
        Binding(
            get: { dateFor(profile.dinnerHour, profile.dinnerMinute) },
            set: { new in
                let c = hourMinute(from: new)
                profile.dinnerHour = c.h
                profile.dinnerMinute = c.m
            }
        )
    }

    private func dateFor(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    }

    private func hourMinute(from date: Date) -> (h: Int, m: Int) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0, c.minute ?? 0)
    }
}

#Preview {
    NavigationStack { CharacterProfileView() }
}
