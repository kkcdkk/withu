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

    /// 미리보기 배경/캐릭터 — 지금 적용 중인 state (없으면 느긋).
    private var heroState: CharacterState {
        SharedAppState.loadMessage()?.state ?? .idle
    }

    var body: some View {
        ZStack {
            backgroundGradient(for: heroState).ignoresSafeArea()
            Form {
                Section {
                    heroCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    TextField("예: 코코, 모찌", text: $profile.name)
                    TextField("성격이나 말투 (선택)", text: $profile.description, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("이름과 성격")
                } footer: {
                    Text("이름은 캐릭터를 부를 때나 위젯에 표시될 때 쓰여요.")
                        .font(.caption2)
                }

                Section {
                    HStack {
                        Text("지금은")
                        Spacer()
                        Text(currentSleepSourceLabel)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("잠든 시간 자동으로 알아채기", isOn: autoDetectBinding)
                    DatePicker("잠드는 시간", selection: sleepStartBinding,
                               displayedComponents: .hourAndMinute)
                    DatePicker("일어나는 시간", selection: sleepEndBinding,
                               displayedComponents: .hourAndMinute)
                } header: {
                    Text("수면 시간")
                } footer: {
                    Text(sleepFooterText)
                        .font(.caption2)
                }

                Section {
                    DatePicker("점심 시간", selection: lunchBinding,
                               displayedComponents: .hourAndMinute)
                    DatePicker("저녁 시간", selection: dinnerBinding,
                               displayedComponents: .hourAndMinute)
                } header: {
                    Text("식사 시간")
                } footer: {
                    Text("정한 시각부터 30분 동안 밥 먹는 캐릭터로 보여요.")
                        .font(.caption2)
                }

                Section {
                    DatePicker("밤이 시작되는 시각", selection: nightStartBinding,
                               displayedComponents: .hourAndMinute)
                    DatePicker("밤이 끝나는 시각", selection: nightEndBinding,
                               displayedComponents: .hourAndMinute)
                } header: {
                    Text("밤하늘 시간")
                } footer: {
                    Text("날씨를 받아오면 실제 해 뜨고 지는 시각에 맞춰 해와 달이 저절로 바뀌어요. 위치를 알 수 없을 때만 여기서 정한 시간을 사용해요.")
                        .font(.caption2)
                }

                statesOverviewSection

                #if DEBUG
                weatherBackgroundsSection   // 개발자 전용 — 날씨 배경 디폴트 세팅용 (사용자 빌드에선 숨김)
                #endif

                Section {
                    Toggle("캐릭터 움직이게 하기", isOn: $animationEnabled)
                } header: {
                    Text("움직임")
                } footer: {
                    Text("움직이는 캐릭터로 만든 경우, 살짝살짝 움직이게 보여줄지 정해요. 끄면 한 장으로만 보이고 배터리에 더 가벼워요. 만들어 둔 그림은 그대로 남아요.")
                        .font(.caption2)
                }

                Section {
                    DisclosureGroup("캐릭터 외형 한 줄 (고급)") {
                        TextField("예: 분홍 토끼, 큰 눈에 둥글둥글한 캐릭터",
                                  text: $profile.aiPrompt, axis: .vertical)
                            .lineLimit(2...5)
                        Text("캐릭터를 만들 때 이 문장이 자동으로 채워져요. 영어로 적으면 더 잘 그려져요.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
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

    private var heroCard: some View {
        HStack(spacing: 14) {
            KoreanStateChip(state: heroState, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name.isEmpty ? "내 캐릭터" : profile.name)
                    .font(.title3.weight(.semibold))
                Text(heroState.caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frostedCard(cornerRadius: 18)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
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

    /// 상태마다 적용된 캐릭터 미리보기. 탭하면 그 상태의 갤러리 폴더로.
    private var statesOverviewSection: some View {
        Section {
            ForEach(CharacterState.userFacing, id: \.self) { state in
                NavigationLink {
                    StateFolderView(state: state)
                } label: {
                    HStack(spacing: 12) {
                        KoreanStateChip(state: state, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.koreanShortLabel)
                                .font(.callout.weight(.medium))
                            Text(CharacterImageStore.hasImage(for: state)
                                 ? "내 캐릭터가 적용됐어요"
                                 : "아직 기본 모습이에요")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("상태별 캐릭터")
        } footer: {
            Text("상태마다 어떤 캐릭터가 보일지 정할 수 있어요. 탭하면 그 상태의 갤러리 폴더가 열려요.")
                .font(.caption2)
        }
    }

    // MARK: - Sleep source indicator + toggle

    /// 지금 자는 상태로 판정되는 이유를 평서형으로.
    /// 우선순위: (1) 집중 모드 OR 건강 앱 수면 일정 → (2) 설정한 시간
    private var currentSleepSourceLabel: String {
        let inProfileWindow = isNowInProfileSleepWindow()
        if profile.manualSleepOnly ?? false {
            return inProfileWindow ? "자는 시간이에요" : "깨어 있는 시간이에요"
        }
        if focus.isFocused || focus.isFocusFilterSleeping { return "집중 모드라서 자고 있어요" }
        if health.isInBedSchedule { return "건강 앱 수면 일정이라서 자고 있어요" }
        if inProfileWindow { return "설정한 시간이라서 자고 있어요" }
        return "깨어 있어요"
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
            return "자동으로 알아채기를 껐어요. 위에서 정한 시간만 기준으로 해요."
        }
        return "먼저 아이폰의 수면·집중 모드를 따르고, 없으면 위에서 정한 시간을 사용해요. 수면 집중 모드가 켜져 있으면 언제든 자는 걸로 봐요."
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

    private var nightStartBinding: Binding<Date> {
        Binding(
            get: {
                let m = profile.effectiveNightFallbackStart
                return dateFor(m / 60, m % 60)
            },
            set: { new in
                let c = hourMinute(from: new)
                profile.nightFallbackStartMinute = c.h * 60 + c.m
            }
        )
    }

    private var nightEndBinding: Binding<Date> {
        Binding(
            get: {
                let m = profile.effectiveNightFallbackEnd
                return dateFor(m / 60, m % 60)
            },
            set: { new in
                let c = hourMinute(from: new)
                profile.nightFallbackEndMinute = c.h * 60 + c.m
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
