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

// MARK: - 브랜드 폰트 (Galmuri 픽셀 폰트)

extension Font {
    /// Galmuri11 픽셀 폰트 — 브랜딩/제목/캐릭터 이름 등 '일부'에만 사용.
    /// 본문·설명은 시스템 폰트를 유지(작은 크기 가독성). Dynamic Type 대응(relativeTo).
    static func galmuri(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom("Galmuri11-Regular", size: size, relativeTo: textStyle)
    }
}

// MARK: - 배경 그라데이션

/// 모든 서브 화면 배경. 기조는 브랜드 그린(새싹 캐릭터 색) — 정체성 통일.
/// 상태 무드(state.tint)는 중간에 아주 옅게만 스며들게.
/// top → bottom: 그린 @ 0.14 → state tint @ 0.04 → 시스템 배경.
func backgroundGradient(for state: CharacterState) -> LinearGradient {
    LinearGradient(
        colors: [
            Color.withuWarmBackground,
            state.tint.opacity(0.05),
            Color.withuCardFill,
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - CTA 버튼 스타일 (핑크 공용)

/// CTA 공용 스타일 — 진한 그린(아이폰 메시지 초록 톤) 배경 + 흰 글자.
/// 누르는 동안 어두워지고 살짝 축소돼 '눌림'이 확실히 보인다.
/// (파스텔 핑크 + .borderedProminent 는 눌림 변화가 안 보인다는 피드백 대응.)
// MARK: - 픽셀 계단 테두리 Shape

/// 모서리를 픽셀 계단(2단)으로 깎은 사각형 — 캐릭터/Galmuri 폰트의 픽셀 톤과 맞춤.
/// InsettableShape 라 strokeBorder 로 테두리를 안쪽에 깔끔히 그린다.
struct PixelBorderShape: InsettableShape {
    /// 한 계단(픽셀) 크기. 모서리는 2계단(=2*pixel).
    var pixel: CGFloat = 5
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape {
        var s = self
        s.inset += amount
        return s
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        // 계단이 변 길이를 넘지 않게 제한 (아주 작은 버튼 보호).
        let p = min(pixel, min(r.width, r.height) / 4)
        let c = p * 2
        let minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        var path = Path()
        path.move(to: CGPoint(x: minX + c, y: minY))
        path.addLine(to: CGPoint(x: maxX - c, y: minY))       // 윗변
        path.addLine(to: CGPoint(x: maxX - p, y: minY))       // TR 2계단
        path.addLine(to: CGPoint(x: maxX - p, y: minY + p))
        path.addLine(to: CGPoint(x: maxX, y: minY + p))
        path.addLine(to: CGPoint(x: maxX, y: minY + c))
        path.addLine(to: CGPoint(x: maxX, y: maxY - c))       // 오른변
        path.addLine(to: CGPoint(x: maxX, y: maxY - p))       // BR 2계단
        path.addLine(to: CGPoint(x: maxX - p, y: maxY - p))
        path.addLine(to: CGPoint(x: maxX - p, y: maxY))
        path.addLine(to: CGPoint(x: maxX - c, y: maxY))
        path.addLine(to: CGPoint(x: minX + c, y: maxY))       // 아랫변
        path.addLine(to: CGPoint(x: minX + p, y: maxY))       // BL 2계단
        path.addLine(to: CGPoint(x: minX + p, y: maxY - p))
        path.addLine(to: CGPoint(x: minX, y: maxY - p))
        path.addLine(to: CGPoint(x: minX, y: maxY - c))
        path.addLine(to: CGPoint(x: minX, y: minY + c))       // 왼변
        path.addLine(to: CGPoint(x: minX, y: minY + p))       // TL 2계단
        path.addLine(to: CGPoint(x: minX + p, y: minY + p))
        path.addLine(to: CGPoint(x: minX + p, y: minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - 픽셀(도트) 아이콘

/// 직접 그린 도트 아이콘 — 기성 이모지 대신. Canvas 로 antialiasing 없이 픽셀 사각형만 채운다.
/// tint 로 의미색을 그대로 통과(SF Symbol 사용 패턴과 동일). 벡터라 배율 걱정 없음.
struct PixelIcon: View {
    let grid: [[UInt8]]      // 0 = 빈칸, 그 외 = 채움
    var tint: Color = .primary
    var size: CGFloat = 20

    var body: some View {
        Canvas { ctx, canvas in
            let rows = grid.count
            let cols = grid.map(\.count).max() ?? 0
            guard rows > 0, cols > 0 else { return }
            let cell = min(canvas.width / CGFloat(cols), canvas.height / CGFloat(rows))
            let ox = (canvas.width - cell * CGFloat(cols)) / 2
            let oy = (canvas.height - cell * CGFloat(rows)) / 2
            for (r, row) in grid.enumerated() {
                for (c, v) in row.enumerated() where v != 0 {
                    let rect = CGRect(x: ox + CGFloat(c) * cell, y: oy + CGFloat(r) * cell,
                                      width: cell + 0.5, height: cell + 0.5)  // 0.5 = 픽셀 사이 실틈 방지
                    ctx.fill(Path(rect), with: .color(tint))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum PixelIconSet {
    /// "#" = 채움, 그 외("." 등) = 빈칸. 줄 길이는 같게.
    private static func rows(_ s: String) -> [[UInt8]] {
        s.split(separator: "\n").map { line in line.map { $0 == "#" ? UInt8(1) : UInt8(0) } }
    }

    /// 걸음 — 발자국 둘.
    static let footsteps = rows("""
    .##.........
    ###.........
    ###.........
    .##.........
    ............
    ........##..
    .......####.
    .......####.
    ........##..
    """)

    /// 활동분 — 시계(테두리 + 바늘).
    static let clock = rows("""
    ...####...
    .##....##.
    #........#
    #...#....#
    #...#....#
    #...###..#
    #........#
    .##....##.
    ...####...
    """)

    /// kcal — 불꽃.
    static let flame = rows("""
    ...##....
    ..###....
    ..##.....
    .##.#....
    ##..##...
    #....##..
    #....##..
    ##...#...
    .##.##...
    ..###....
    """)

    /// 수면 — 초승달.
    static let moon = rows("""
    ..###....
    .#####...
    ####.....
    ###......
    ###......
    ###......
    ###......
    ####.....
    .#####...
    ..###....
    """)

    /// 캐릭터 생성 — 마법봉 + 반짝.
    static let wand = rows("""
    .......#.#
    ........#.
    .......#.#
    .....##...
    ....##....
    ...##.....
    ..##......
    .##.......
    ##........
    #.........
    """)

    /// 사진 찍기 — 카메라.
    static let camera = rows("""
    ...##.....
    ..####....
    ##########
    #........#
    #..####..#
    #.##..##.#
    #.#....#.#
    #.##..##.#
    #..####..#
    ##########
    """)

    /// 갤러리 — 사진(액자 + 해 + 산).
    static let gallery = rows("""
    ########
    #.#....#
    #......#
    #.....##
    #....###
    #..#####
    ########
    """)

    /// 내 캐릭터 설정 — 사람.
    static let person = rows("""
    ...####...
    ..######..
    ..######..
    ..######..
    ...####...
    .########.
    ##########
    ##########
    ##########
    ##########
    """)

}

// MARK: - 픽셀 토글 (iOS 기본 초록 스위치 대체)

/// 레트로 픽셀 토글 — 계단 트랙 + 사각 노브. off=크림, on=세이지. iOS 초록 채도 제거.
/// 라벨 있는 폼 행/라벨 숨긴 인라인 둘 다 대응 (인라인은 호출부에서 .fixedSize()).
struct PixelToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Spacer(minLength: 0)
            track(isOn: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.16)) { configuration.isOn.toggle() }
        }
    }

    private func track(isOn: Bool) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            PixelBorderShape(pixel: 3).fill(isOn ? Color.withuSage : Color.withuCardFill)
            PixelBorderShape(pixel: 3).strokeBorder(Color.withuPixelOutline, lineWidth: 2)
            Rectangle()
                .fill(Color.withuCardFill)
                .overlay(Rectangle().strokeBorder(Color.withuPixelOutline, lineWidth: 2))
                .frame(width: 12, height: 12)
                .padding(4)
        }
        .frame(width: 42, height: 24)
    }
}

struct WithuCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CTABody(configuration: configuration)
    }

    /// isEnabled 는 Environment 라 내부 View 로 감싸야 읽을 수 있음 (비활성 흐림 처리).
    private struct CTABody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.galmuri(16, relativeTo: .callout))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    PixelBorderShape()
                        .fill(Color.withuCTAGreen)
                        .overlay(
                            PixelBorderShape()
                                .fill(Color.black.opacity(configuration.isPressed ? 0.18 : 0))
                        )
                        .overlay(
                            // 픽셀 계단 딥그린 테두리 — 캐릭터/폰트와 톤 맞춘 귀여운 윤곽.
                            PixelBorderShape()
                                .strokeBorder(Color.withuCTABorder, lineWidth: 2.5)
                        )
                )
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

// MARK: - 새로고침 버튼 (공용 스피너)

/// 아이콘 새로고침 버튼 — 실행 중엔 미니 스피너로 바뀜.
/// 즉시 끝나는 동작도 최소 0.5초 스피너를 보여줘 '눌렸다'는 피드백을 준다.
struct RefreshIconButton: View {
    var action: () async -> Void
    @State private var isRunning = false

    var body: some View {
        if isRunning {
            ProgressView().controlSize(.mini)
        } else {
            Button {
                Task {
                    isRunning = true
                    let started = Date()
                    await action()
                    let elapsed = Date().timeIntervalSince(started)
                    if elapsed < 0.5 { try? await Task.sleep(for: .seconds(0.5 - elapsed)) }
                    isRunning = false
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Form 행 새로고침 버튼 — 실행 중엔 우측에 미니 스피너 표시 + 재탭 방지.
/// 완료 후엔 아이콘이 잠깐 체크마크로 바뀌어 '실행됐다'는 걸 보여준다 (showsDone 으로 끌 수 있음).
struct RefreshRowButton: View {
    let title: LocalizedStringKey
    var systemImage: String = "arrow.clockwise.circle.fill"
    var role: ButtonRole? = nil
    var showsDone: Bool = true
    var action: () async -> Void
    @State private var isRunning = false
    @State private var showDone = false
    @State private var runID = 0  // 체크마크 표시 중 재탭 시 이전 타이머가 새 표시를 지우지 않게

    var body: some View {
        Button(role: role) {
            Task { await run() }
        } label: {
            HStack {
                Label {
                    Text(title)
                } icon: {
                    if showDone {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: systemImage)
                    }
                }
                Spacer()
                if isRunning { ProgressView().controlSize(.mini) }
            }
        }
        .disabled(isRunning)
    }

    private func run() async {
        runID += 1
        let id = runID
        isRunning = true
        showDone = false
        let started = Date()
        await action()
        let elapsed = Date().timeIntervalSince(started)
        if elapsed < 0.5 { try? await Task.sleep(for: .seconds(0.5 - elapsed)) }
        isRunning = false
        if showsDone {
            showDone = true
            try? await Task.sleep(for: .seconds(1.8))
            if runID == id { showDone = false }
        }
    }
}

// MARK: - Frosted 카드

/// 모든 카드 표면의 단일 recipe. 솔리드 색·border·그림자 금지.
struct FrostedCard: ViewModifier {
    var cornerRadius: CGFloat = 16   // 호환용 — 픽셀 테두리에선 계단 모서리가 대신함
    func body(content: Content) -> some View {
        content
            .padding(14)
            .pixelCardSurface()
    }
}

extension View {
    /// 홈 카드 표면 적용 (내부 padding 14 포함).
    func frostedCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(FrostedCard(cornerRadius: cornerRadius))
    }

    /// 카드 표면만 — 동물의 숲/레트로: 따뜻한 크림 + 먹빛 픽셀 계단 테두리.
    /// padding 은 호출부가 관리 (이미 padding 을 가진 카드에 적용할 때).
    func pixelCardSurface(fill: Color = .withuCardFill, lineWidth: CGFloat = 2) -> some View {
        self
            .background(fill, in: PixelBorderShape())
            .overlay(PixelBorderShape().strokeBorder(Color.withuPixelOutline, lineWidth: lineWidth))
            .clipShape(PixelBorderShape())
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
                .font(.galmuri(12, relativeTo: .caption))
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
