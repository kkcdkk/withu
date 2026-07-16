//
//  HelpGuideView.swift
//  withu
//
//  사용법 안내 — 첫 실행 시 자동, 그리고 메뉴에서 언제든 다시 보기.
//

import SwiftUI

struct HelpGuideView: View {
    /// 확인/시작 버튼을 눌렀을 때. 시트/온보딩에서 dismiss 처리.
    var onDone: () -> Void

    private struct Step: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let body: String
    }

    private let steps: [Step] = [
        Step(icon: "wand.and.stars",
             title: String(localized: "1. 캐릭터 만들기"),
             body: String(localized: "'여러 모습 만들기'로 한 캐릭터의 여러 상태를 한 번에, 또는 '단건'으로 하나씩 만들어요. 참고 사진을 넣으면 그 모습을 살려서 그려요.")),
        Step(icon: "checkmark.circle.fill",
             title: String(localized: "2. 상태별로 적용하기"),
             body: String(localized: "만든 모습을 '적용'하면 지금 상태(자는 중·산책·식사 등)에 맞춰 홈·위젯·워치에 그 캐릭터가 나와요. 갤러리 '캐릭터별'에서 '이 캐릭터로 모두 적용'으로 한 번에 다 적용할 수도 있어요.")),
        Step(icon: "square.grid.2x2.fill",
             title: String(localized: "3. 홈·잠금화면 위젯 추가"),
             body: String(localized: "홈 화면이나 잠금 화면을 길게 눌러 위젯을 추가하면, 캐릭터와 걸음·수면 같은 정보가 위젯에 떠요.")),
        Step(icon: "applewatch",
             title: String(localized: "4. 애플워치에 추가"),
             body: String(localized: "워치 페이스를 길게 눌러 편집 → 컴플리케이션 칸에 withu를 넣으면 시계 화면에도 캐릭터가 나와요. 산책·달리기 같은 운동은 워치가 연결돼 있으면 워치(심박)로, 워치가 없으면 아이폰의 움직임으로 알아채요.")),
        Step(icon: "sparkles",
             title: String(localized: "5. 캔디"),
             body: String(localized: "캐릭터를 만들 땐 캔디를 써요 — 한 장에 1개, 움직이는 캐릭터는 2개예요. 캔디는 상점에서 충전할 수 있어요.")),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text("withu 사용법")
                            .font(.title2.weight(.bold))
                        Text("캐릭터를 만들고 내 하루에 맞춰 보여줘요.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 14) {
                        ForEach(steps) { step in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: step.icon)
                                    .font(.title3)
                                    .foregroundStyle(Color.withuPinkText)
                                    .frame(width: 32, height: 32)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(step.title)
                                        .font(.callout.weight(.semibold))
                                    Text(step.body)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    Button {
                        onDone()
                    } label: {
                        Text("확인")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(WithuCTAButtonStyle())
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("사용법")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { onDone() }
                }
            }
        }
    }
}

#Preview { HelpGuideView(onDone: {}) }
