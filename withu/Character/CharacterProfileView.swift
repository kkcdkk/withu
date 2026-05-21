//
//  CharacterProfileView.swift
//  withu
//
//  내 캐릭터 설정 — 이름, 설명, 수면/식사 시간.
//  값 변경 시 자동 저장 (App Group 공유).
//

import SwiftUI

struct CharacterProfileView: View {
    @State private var profile: CharacterProfile = CharacterProfileStore.load()

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
                DatePicker("취침", selection: sleepStartBinding,
                           displayedComponents: .hourAndMinute)
                DatePicker("기상", selection: sleepEndBinding,
                           displayedComponents: .hourAndMinute)
            } header: {
                Text("💤 수면 시간")
            } footer: {
                Text("이 시간대에 캐릭터가 자고 있어요. 자정 넘김 OK. (Health 수면 일정 있으면 그게 우선)")
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
        }
        .navigationTitle("내 캐릭터 설정")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: profile) { _, new in
            CharacterProfileStore.save(new)
        }
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
