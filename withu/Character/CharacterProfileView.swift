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
    @Environment(\.dismiss) private var dismiss
    @State private var profile: CharacterProfile = CharacterProfileStore.load()
    @State private var health = HealthKitManager.shared
    @State private var focus = FocusModeManager.shared
    @State private var animationEnabled: Bool = CharacterImageStore.animationEnabled
    /// 마지막으로 '저장'한 스냅샷 — 이것과 다르면 저장 안 된 변경(hasChanges)으로 본다.
    @State private var savedProfile: CharacterProfile = CharacterProfileStore.load()
    @State private var savedAnimationEnabled: Bool = CharacterImageStore.animationEnabled
    /// 저장 안 한 채 나가려 할 때 확인 팝업.
    @State private var showDiscardConfirm: Bool = false
    /// heroCard 탭 → 이름 편집 (성격 섹션 제거 후 유일한 이름 편집 진입점)
    @State private var showNameEdit: Bool = false
    @State private var nameDraft: String = ""
    /// '최근 수면 시간에 맞추기' 진행/결과 표시
    @State private var isAligningSleep: Bool = false
    @State private var sleepAlignMessage: String?

    /// 미리보기 배경/캐릭터 — 지금 적용 중인 state (없으면 느긋).
    // 히어로 아바타 상태 — 프로필(수면/식사 시간) 변경 시 즉시 갱신되게 @State 로.
    // (예전: computed 라 SharedAppState 가 30초 sync 전엔 옛 상태를 읽어 아바타가 안 바뀜.)
    @State private var heroState: CharacterState = SharedAppState.loadMessage()?.state ?? .idle

    /// 상태별 폴더 이동 대상 — NavigationLink 다중 배치 버그 회피용.
    private struct StateRoute: Identifiable, Hashable {
        let state: CharacterState
        var id: String { state.rawValue }
    }
    @State private var stateRoute: StateRoute?

    var body: some View {
        ZStack {
            backgroundGradient(for: heroState).ignoresSafeArea()
            Form {
                Section {
                    heroCard
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                }
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                    sleepStatusRow
                    // '수면 모드 기준'(자동 감지)에선 이 시간이 판정 기준이 아니라 회색+비활성.
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
                            .font(.pretendard(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .plainCard()
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("수면 시간")
                        .font(.pretendardBold(16, relativeTo: .callout))
                } footer: {
                    Text(sleepFooterText)
                        .font(.pretendard(11, relativeTo: .caption2))
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                    DatePicker("점심 시간", selection: lunchBinding,
                               displayedComponents: .hourAndMinute)
                    DatePicker("저녁 시간", selection: dinnerBinding,
                               displayedComponents: .hourAndMinute)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .plainCard()
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("식사 시간")
                        .font(.pretendardBold(16, relativeTo: .callout))
                } footer: {
                    Text("정한 시각부터 30분 동안 밥 먹는 캐릭터로 보여요.")
                        .font(.pretendard(11, relativeTo: .caption2))
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                    DatePicker("밤이 시작되는 시각", selection: nightStartBinding,
                               displayedComponents: .hourAndMinute)
                    DatePicker("밤이 끝나는 시각", selection: nightEndBinding,
                               displayedComponents: .hourAndMinute)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .plainCard()
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("밤하늘 시간")
                        .font(.pretendardBold(16, relativeTo: .callout))
                } footer: {
                    Text("날씨를 받아오면 실제 해 뜨고 지는 시각에 맞춰 해와 달이 저절로 바뀌어요. 위치를 알 수 없을 때만 여기서 정한 시간을 사용해요.")
                        .font(.pretendard(11, relativeTo: .caption2))
                }

                statesOverviewSection

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                    Toggle("캐릭터 움직이게 하기", isOn: $animationEnabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .plainCard()
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("움직임")
                        .font(.pretendardBold(16, relativeTo: .callout))
                } footer: {
                    Text("움직이는 캐릭터로 만든 경우, 캐릭터를 움직일지 정해요.")
                        .font(.pretendard(11, relativeTo: .caption2))
                }

            }
            .scrollContentBackground(.hidden)
        }
        .navigationDestination(item: $stateRoute) { route in
            StateFolderView(state: route.state)
        }
        .navigationTitle("내 캐릭터 설정")
        .navigationBarTitleDisplayMode(.inline)
        // 필터 연결 여부(focusFilterLastPerformAt)를 최신값으로 — 안내 카드 노출 판정.
        .onAppear { focus.refresh() }
        // 자동 저장 대신 명시적 '저장' — 편집은 초안(profile)에만, 반영은 save() 에서.
        // 저장 안 한 변경이 있을 때만 기본 뒤로가기를 가린다 —
        // 항상 가리면 손가락으로 미는 뒤로가기(interactive pop)까지 막혀서 나갈 수가 없다.
        .navigationBarBackButtonHidden(hasChanges)
        .toolbar {
            if hasChanges {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showDiscardConfirm = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                            Text("설정")
                        }
                    }
                }
            }
            // 수정이 생기면 상단에 '저장' 버튼 등장.
            ToolbarItem(placement: .topBarTrailing) {
                if hasChanges {
                    Button("저장") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        .confirmationDialog("저장하지 않은 변경사항이 있어요",
                            isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("저장하고 나가기") { save(); dismiss() }
            Button("저장 안 하고 나가기", role: .destructive) { dismiss() }
            Button("계속 편집", role: .cancel) {}
        } message: {
            Text("나가면 방금 바꾼 내용이 지워져요.")
        }
    }

    /// 저장 안 된 변경이 있는지 — 초안이 마지막 저장 스냅샷과 다르면 true.
    private var hasChanges: Bool {
        profile != savedProfile || animationEnabled != savedAnimationEnabled
    }

    /// 초안(profile·animationEnabled)을 실제로 반영 — 저장 + 상태 재판정 + 위젯/워치 갱신.
    private func save() {
        CharacterProfileStore.save(profile)
        CharacterImageStore.setAnimationEnabled(animationEnabled)
        // 저장된 프로필로 상태 재판정 + SharedAppState 갱신 → 아바타(heroState)도 최신으로.
        SyncCoordinator.syncNow()
        heroState = SharedAppState.loadMessage()?.state ?? .idle
        WidgetCenter.shared.reloadAllTimelines()
        savedProfile = profile
        savedAnimationEnabled = animationEnabled
    }

    private var heroCard: some View {
        HStack(spacing: 14) {
            KoreanStateChip(state: heroState, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(profile.name.isEmpty ? "내 캐릭터" : profile.name)
                        .font(.pretendard(20, relativeTo: .title3))
                    Image(systemName: "pencil")
                        .font(.pretendard(12, relativeTo: .caption))
                        .foregroundStyle(.tertiary)
                }
                Text(heroState.caption)
                    .font(.pretendard(15, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .plainFrostedCard(cornerRadius: 18)
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
            VStack(alignment: .leading, spacing: 12) {
            ForEach(CharacterState.userFacing, id: \.self) { state in
                // ⚠️ 한 행(카드) 안에 NavigationLink 를 여러 개 두면 SwiftUI 가 목적지를 잘못
                //    짚는다(뒤로 나올 때 다른 상태의 폴더가 뜸). 상태 기반 이동으로 분리.
                Button {
                    stateRoute = StateRoute(state: state)
                } label: {
                    HStack(spacing: 12) {
                        KoreanStateChip(state: state, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.koreanShortLabel)
                                .font(.pretendard(16, relativeTo: .callout))
                                .foregroundStyle(.primary)
                            Text(CharacterImageStore.hasImage(for: state)
                                 ? String(localized: "내 캐릭터가 적용됐어요")
                                 : String(localized: "아직 기본 모습이에요"))
                                .font(.pretendard(11, relativeTo: .caption2))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .plainCard()
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        } header: {
            Text("상태별 캐릭터")
                .font(.pretendardBold(16, relativeTo: .callout))
        } footer: {
            Text("상태마다 어떤 캐릭터가 보일지 정할 수 있어요. 탭하면 그 상태의 갤러리 폴더가 열려요.")
                .font(.pretendard(11, relativeTo: .caption2))
        }
    }

    // MARK: - Sleep source indicator + toggle

    /// 한눈에 읽히는 수면 상태 행 — 자는 중/깨어 있음 + 기준 칩(탭해서 기준 선택).
    /// 판정은 CharacterStateResolver 의 수면 규칙과 동일해야 한다.
    private var sleepStatusRow: some View {
        HStack(spacing: 10) {
            Text(isSleepingNow ? "자는 중" : "깨어 있음")
                .font(.pretendard(16, relativeTo: .callout))
            Spacer()
        }
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

    /// 이제는 항상 설정 시간이 기준이라 시간 선택을 막지 않는다.
    private var sleepTimesDisabled: Bool { false }

    private var sleepFooterText: String {
        String(localized: "여기서 정한 시간에 자고 일어나요. 수면 모드를 직접 켜면 그때도 자는 모습이 돼요.")
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
                let m = c.h * 60 + c.m
                // 표시값 그대로 다시 써 넣는 경우(미설정 → 기본값)는 무시 — 헛된 '변경' 표시 방지.
                guard m != profile.effectiveNightFallbackStart else { return }
                profile.nightFallbackStartMinute = m
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
                let m = c.h * 60 + c.m
                guard m != profile.effectiveNightFallbackEnd else { return }
                profile.nightFallbackEndMinute = m
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
