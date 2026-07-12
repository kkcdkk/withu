//
//  VibeKit.swift
//  withu (iOS 앱 타깃 전용)
//
//  홈 화면이 정의한 디자인 언어를 모든 메뉴가 공유하도록 모은 공용 컴포넌트.
//  규칙: frosted material 카드 · state.tint 그라데이션 배경 · .semibold 상한 ·
//        의미 기반 색 위계 (.primary/.secondary/.tertiary) · 평서형 한국어.
//
//  ⚠️ 이 파일은 iOS 앱 타깃에만 속함 (withu/ 폴더 자동 동기화).
//     위젯/워치/컴플리케이션은 자체 뷰를 쓰므로 여기 컴포넌트를 참조하지 않는다.
//

import SwiftUI

// MARK: - 배경 그라데이션

/// 모든 서브 화면 배경. 기조는 브랜드 그린(새싹 캐릭터 색) — 정체성 통일.
/// 상태 무드(state.tint)는 중간에 아주 옅게만 스며들게.
/// top → bottom: 그린 @ 0.14 → state tint @ 0.04 → 시스템 배경.
func backgroundGradient(for state: CharacterState) -> LinearGradient {
    LinearGradient(
        colors: [
            Color.withuGreen.opacity(0.14),
            state.tint.opacity(0.04),
            Color(.systemBackground),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Frosted 카드

/// 모든 카드 표면의 단일 recipe. 솔리드 색·border·그림자 금지.
struct FrostedCard: ViewModifier {
    var cornerRadius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}

extension View {
    /// 홈 카드 표면 적용. cornerRadius 18(hero/요약) / 16(일반) / 12(작은 칩).
    func frostedCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(FrostedCard(cornerRadius: cornerRadius))
    }
}

// MARK: - 섹션 헤더

/// 카드 위 작은 라벨 + (선택) 우측 보조 요소. 네비게이션 타이틀이 아닌 그룹 라벨.
struct SectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let trailing: Trailing

    init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - 액션 행 (메뉴 카드의 핵심 프리미티브)

enum ActionLinkTrailing: Equatable {
    case chevron
    case checkmark
    case none
    case text(String)
}

/// 홈의 actionLink 와 동일한 recipe. NavigationLink / Button label 안에 넣어 씀.
/// 44×44 tint chip + 제목/부제 + 우측 보조.
struct ActionLinkRow: View {
    var tint: Color
    var systemImage: String
    var title: String
    var subtitle: String? = nil
    var trailing: ActionLinkTrailing = .chevron
    var dimmed: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.18))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(tint)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailingView
        }
        .opacity(dimmed ? 0.55 : 1)
        .frostedCard()
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        case .checkmark:
            Image(systemName: "checkmark")
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
        case .none:
            EmptyView()
        case .text(let t):
            Text(t)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - 상태 표시 (이모지 금지, SF Symbol + 의미색)

enum StatusKind {
    case ok       // 초록 체크
    case warning  // 주황 경고
    case off      // 회색 — 꺼짐/아직 아님
}

/// 권한·연결 등 상태 한 줄. ✅/⚠️/❌ 텍스트 이모지 대체.
struct StatusPill: View {
    var kind: StatusKind
    var label: LocalizedStringKey

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var symbol: String {
        switch kind {
        case .ok:      return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .off:     return "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .ok:      return .green
        case .warning: return .orange
        case .off:     return .secondary
        }
    }
}

// MARK: - 캐릭터 / 상태 칩

/// 현재 적용된 캐릭터를 보여주는 원형 칩 (설정 미리보기 hero 등).
struct KoreanStateChip: View {
    var state: CharacterState
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(state.tint.opacity(0.22))
            CharacterImageView(state: state)
                .padding(size * 0.12)
        }
        .frame(width: size, height: size)
    }
}

/// 상태를 이모지로 대표하는 원형 칩 (갤러리 폴더 / 빈 슬롯).
/// 사용자가 "갤러리엔 이모지 써도 된다"고 허용 → 갤러리 컨텍스트 전용.
struct StateEmojiChip: View {
    var state: CharacterState
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(state.tint.opacity(0.22))
            Text(state.symbolEmoji)
                .font(.system(size: size * 0.46))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 보조 안내 / 경고

/// 카드·섹션 하단 친절 안내. 평서형 한 줄.
struct HelperFooter: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 오류/주의 배너. .red 직접 사용을 대체. retry 있으면 우측에 "다시 시도".
struct WarningBanner: View {
    var text: String
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let retry {
                Button("다시 시도", action: retry)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(
            Color.orange.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}
