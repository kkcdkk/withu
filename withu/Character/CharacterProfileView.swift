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
    /// heroCard 탭 → 이름 편집 (성격 섹션 제거 후 유일한 이름 편집 진입점)
    @State private var showNameEdit: Bool = false
    @State private var nameDraft: String = ""
    /// '최근 수면 시간에 맞추기' 진행/결과 표시
    @State private var isAligningSleep: Bool = false
    @State private var sleepAlignMessage: String?
    /// 기준 칩에서 '수면 모드 기준' 선택 시 수면 일정 안내 팝업.
    @State private var showSleepBasisTip: Bool = false

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
                    sleepStatusRow
                    Toggle("잠든 시간 자동으로 알아채기", isOn: autoDetectBinding)
                    // '수면 모드 기준'(자동 감지)에선 아래 시간 설정이 기준이 아니라 회색+비활성.
                    DatePicker("잠드는 시간", selection: sleepStartBinding,
                               displayedComponents: .hourAndMinute)
                        .disabled(sleepTimesDisabled)
                        .opacity(sleepTimesDisabled ? 0.4 : 1)
                    DatePicker("일어나는 시간", selection: sleepEndBinding,
                               displayedComponents: .hourAndMinute)
                        .disabled(sleepTimesDisabled)
                        .opacity(sleepTimesDisabled ? 0.4 : 1)
                    Button {
                        alignToRecentSleep()
                    } label: {
                        HStack {
                            Label("최근 수면 시간에 맞추기", systemImage: "moon.stars")
                            Spacer()
                            if isAligningSleep { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(isAligningSleep || sleepTimesDisabled)
                    .opacity(sleepTimesDisabled ? 0.4 : 1)
                    if let msg = sleepAlignMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

                Section {
                    Toggle("캐릭터 움직이게 하기", isOn: $animationEnabled)
                } header: {
                    Text("움직임")
                } footer: {
                    Text("움직이는 캐릭터로 만든 경우, 움직이게 보여줄지 정해요. 끄면 한 장으로만 보이고 배터리가 덜 닳아요.")
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
                HStack(spacing: 6) {
                    Text(profile.name.isEmpty ? "내 캐릭터" : profile.name)
                        .font(.title3.weight(.semibold))
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(heroState.caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frostedCard(cornerRadius: 18)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            nameDraft = profile.name
            showNameEdit = true
        }
        .alert("캐릭터 이름", isPresented: $showNameEdit) {
            TextField("예: 새싹이", text: $nameDraft)
            Button("저장") {
                profile.name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("캐릭터를 부를 이름을 정해요.")
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
                                 ? String(localized: "내 캐릭터가 적용됐어요")
                                 : String(localized: "아직 기본 모습이에요"))
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

    /// 한눈에 읽히는 수면 상태 행 — 자는 중/깨어 있음 + 기준 칩(탭해서 기준 선택).
    /// 판정은 CharacterStateResolver 의 수면 규칙과 동일해야 한다.
    private var sleepStatusRow: some View {
        HStack(spacing: 10) {
            Text(isSleepingNow ? "자는 중" : "깨어 있음")
                .font(.callout.weight(.semibold))
            Spacer()
            Menu {
                Picker("수면 기준", selection: sleepBasisBinding) {
                    Label("수면 모드 기준", systemImage: "moon.circle.fill").tag(false)
                    Label("설정 시간 기준", systemImage: "clock.fill").tag(true)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: sleepBasisIcon)
                        .font(.caption2)
                    Text(sleepBasisLabel)
                        .font(.caption.weight(.medium))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(.secondary)
            }
        }
        .alert("수면 모드 기준으로 자요", isPresented: $showSleepBasisTip) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("수면 모드가 켜지면 자고, 꺼지면 일어나요. 아이폰 건강 앱에서 수면 일정을 만들어두면 수면 모드가 매일 자동으로 켜지고 꺼져서, 캐릭터도 규칙적으로 자고 일어나요.")
        }
    }

    /// 기준 칩 선택 — 설정 시간 기준(true) = manualSleepOnly. 수면 모드 선택 시 안내 팝업.
    private var sleepBasisBinding: Binding<Bool> {
        Binding(
            get: { profile.isManualSleepOnly },
            set: { manual in
                profile.manualSleepOnly = manual
                if !manual { showSleepBasisTip = true }
            }
        )
    }

    /// 지금 자는 중인지 (resolver 의 수면 분기와 동일).
    private var isSleepingNow: Bool {
        // '설정 시간 기준' — 시간창 안이면 잔다 (Focus/건강 무시).
        if profile.isManualSleepOnly { return isNowInProfileSleepWindow() }
        // '수면 모드 기준' — 실제 수면 신호만. Sleep Focus 를 꺼두면 밤이어도 깨어 있음.
        if focus.filterSleepingCorrected(sleepEndHour: profile.sleepEndHour,
                                         sleepEndMinute: profile.sleepEndMinute)
            || health.isInBedSchedule { return true }
        // 예약 수면 모드가 필터를 못 깨운 경우 보조 — 아무 집중 모드 + 수면 시간대.
        if focus.isFocused, isNowInProfileSleepWindow() { return true }
        return false
    }

    /// 기준 칩 라벨 — 사용자가 고른 값 그대로 표시 (살아있는 신호로 추론하지 않는다).
    private var sleepBasisLabel: String {
        profile.isManualSleepOnly
            ? String(localized: "설정 시간 기준")
            : String(localized: "수면 모드 기준")
    }

    private var sleepBasisIcon: String {
        profile.isManualSleepOnly ? "clock.fill" : "moon.circle.fill"
    }

    /// 최근 7일 실제 수면 기록(워치 asleep 포함)의 평균 취침/기상을 설정 시간에 반영.
    /// 워치 수면 추적은 inBed 예측 신호가 없어 설정 시간이 사실상 기준 —
    /// 그 기준을 실제 수면 패턴에 맞춰주는 버튼.
    private func alignToRecentSleep() {
        isAligningSleep = true
        sleepAlignMessage = nil
        Task {
            defer { isAligningSleep = false }
            guard let w = await health.averageSleepWindow() else {
                sleepAlignMessage = String(localized: "최근 수면 기록이 부족해요. 며칠 자고 나면 맞출 수 있어요.")
                return
            }
            profile.sleepStartHour = w.startHour
            profile.sleepStartMinute = w.startMinute
            profile.sleepEndHour = w.endHour
            profile.sleepEndMinute = w.endMinute
            sleepAlignMessage = String(format: "최근 수면에 맞췄어요 — %02d:%02d ~ %02d:%02d",
                                       w.startHour, w.startMinute, w.endHour, w.endMinute)
        }
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
            get: { !profile.isManualSleepOnly },
            set: { profile.manualSleepOnly = !$0 }
        )
    }

    /// '수면 모드 기준'(자동 감지)에선 잠드는/일어나는 시간이 판정 기준이 아니라 회색+비활성.
    private var sleepTimesDisabled: Bool { !profile.isManualSleepOnly }

    private var sleepFooterText: String {
        if profile.isManualSleepOnly {
            return String(localized: "자동으로 알아채기를 껐어요. 위에서 정한 시간만 기준으로 해요.")
        }
        // 수면 모드 신호가 하나도 연결 안 돼 있으면 — 왜 '설정 시간'으로만 자는지 + 켜는 법 안내.
        // (INFocusStatusCenter 권한은 더 이상 수면 판정에 안 쓰므로 조건에서 제외)
        if focus.focusFilterLastPerformAt == nil && !health.hasSleepSchedule {
            return String(localized: "지금은 아이폰 수면 모드를 받아볼 수 없어서 위에서 정한 시간으로만 자요. 수면 모드에 맞춰 자게 하려면: 아이폰 설정 > 집중 모드 > 수면 > 필터 추가 > withu 를 켜 주세요. (건강 앱에서 수면 일정을 쓰고 있다면 자동으로 따라가요.)")
        }
        return String(localized: "먼저 아이폰의 수면·집중 모드를 따르고, 없으면 위에서 정한 시간을 사용해요. 수면 집중 모드가 켜져 있으면 캐릭터가 잠에 들어요.")
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
