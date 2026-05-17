//
//  BatchCharacterGenView.swift
//  withu
//
//  여러 상태를 한 번에 생성. "캐릭터 정체성" (공통) + state 별 hint 조합.
//  생성된 이미지는 자동으로 해당 state 슬롯에 적용됨.
//

import SwiftUI
import WidgetKit

struct BatchCharacterGenView: View {
    // MARK: - Input

    /// 캐릭터 자체 (모든 상태 공통). 예: "주근깨 많은 분홍 토끼 마스코트"
    @State private var baseIdentity: String = "round chibi mascot character with simple features and friendly closed-eye smile"

    /// 상태별 포즈/상황. 기본값은 CharacterState.generationHint.
    @State private var stateHints: [CharacterState: String] = Dictionary(
        uniqueKeysWithValues: CharacterState.allCases.map { ($0, $0.generationHint) }
    )

    /// 생성할 상태 선택 (기본 전부 ON)
    @State private var selectedStates: Set<CharacterState> = Set(CharacterState.allCases)

    @State private var quality: String = "medium"
    @State private var artStyle: String = "casual"

    /// 일관성 유지: 첫 호출의 결과를 두 번째 호출부터 reference 로 사용해서
    /// 같은 캐릭터의 다른 포즈로 만들어지게 함. (gpt-image-2 의 images.edit)
    @State private var keepConsistency: Bool = true

    // MARK: - Progress

    @State private var isGenerating: Bool = false
    /// 지금 생성 중인 state (nil = idle)
    @State private var currentState: CharacterState?
    @State private var currentStartedAt: Date?

    /// 완료된 결과
    @State private var results: [CharacterState: UIImage] = [:]
    @State private var errors: [CharacterState: String] = [:]

    @State private var showFinishedAlert: Bool = false

    // MARK: - Body

    var body: some View {
        Form {
            identitySection
            stateListSection
            optionsSection
            startSection
            if !results.isEmpty || !errors.isEmpty {
                resultsSection
            }
        }
        .navigationTitle("일괄 생성")
        .alert("완료", isPresented: $showFinishedAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("\(results.count)개 생성 성공, \(errors.count)개 실패. 성공한 캐릭터는 자동으로 적용됐어요.")
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section {
            TextEditor(text: $baseIdentity)
                .frame(minHeight: 80)
                .font(.callout)
                .disabled(isGenerating)
        } header: {
            Text("캐릭터 정체성 (모든 상태 공통)")
        } footer: {
            Text("매 호출에 이 문장이 앞에 붙어요. 캐릭터 외형·성격을 한 번에 정의.\n예: \"주근깨 많은 분홍 토끼, 큰 머리에 작은 몸\"")
                .foregroundStyle(.secondary)
        }
    }

    private var stateListSection: some View {
        Section {
            ForEach(CharacterState.allCases, id: \.self) { state in
                stateRow(state)
            }
            HStack {
                Button("모두 켜기") {
                    selectedStates = Set(CharacterState.allCases)
                }
                Spacer()
                Button("모두 끄기", role: .destructive) {
                    selectedStates = []
                }
            }
            .disabled(isGenerating)
        } header: {
            Text("생성할 상태 (\(selectedStates.count)개)")
        } footer: {
            let cost = costPer(quality: quality) * Double(selectedStates.count)
            Text("예상 비용: \(selectedStates.count)개 × \(String(format: "$%.3f", costPer(quality: quality))) = \(String(format: "$%.2f", cost))")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func stateRow(_ state: CharacterState) -> some View {
        DisclosureGroup {
            TextEditor(text: Binding(
                get: { stateHints[state] ?? state.generationHint },
                set: { stateHints[state] = $0 }
            ))
            .frame(minHeight: 60)
            .font(.footnote)
            .disabled(isGenerating)

            Button("기본값으로 되돌리기") {
                stateHints[state] = state.generationHint
            }
            .font(.footnote)
            .disabled(isGenerating)
        } label: {
            HStack {
                Toggle("", isOn: Binding(
                    get: { selectedStates.contains(state) },
                    set: { on in
                        if on { selectedStates.insert(state) }
                        else  { selectedStates.remove(state) }
                    }
                ))
                .labelsHidden()
                .disabled(isGenerating)

                Text(state.symbolEmoji)
                Text(state.rawValue)
                    .strikethrough(!selectedStates.contains(state))
                Spacer()
                resultBadge(state)
            }
        }
    }

    @ViewBuilder
    private func resultBadge(_ state: CharacterState) -> some View {
        if currentState == state, let started = currentStartedAt {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let elapsed = Int(ctx.date.timeIntervalSince(started))
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.7)
                    Text("\(elapsed)초").font(.caption2)
                }
            }
        } else if results[state] != nil {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if errors[state] != nil {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private var optionsSection: some View {
        Section {
            Picker("그림체", selection: $artStyle) {
                Text("일반 (파스텔)").tag("casual")
                Text("픽셀 (8/16-bit)").tag("pixel")
            }
            .pickerStyle(.segmented)
            .disabled(isGenerating)

            Picker("품질", selection: $quality) {
                Text("low — $0.011").tag("low")
                Text("medium — $0.04").tag("medium")
                Text("high — $0.17").tag("high")
            }
            .pickerStyle(.menu)
            .disabled(isGenerating)

            Toggle("일관성 유지 (첫 결과를 다음 호출의 reference 로)", isOn: $keepConsistency)
                .disabled(isGenerating)
        } header: {
            Text("옵션")
        } footer: {
            if keepConsistency {
                Text("처음 만들어진 캐릭터를 기준으로 나머지 상태가 변형됨 — 디테일 (귀 색, 무늬 등) 이 일관됨. 단, 첫 결과가 마음에 들지 않으면 다 비슷하게 안 마음에 들 수 있음.")
                    .foregroundStyle(.secondary)
            } else {
                Text("매 상태마다 새로 생성 — 디테일이 살짝씩 달라질 수 있음.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var startSection: some View {
        Section {
            Button {
                Task { await runBatch() }
            } label: {
                if isGenerating {
                    HStack {
                        ProgressView()
                        Text("일괄 생성 중… \(results.count + errors.count)/\(selectedStates.count)")
                    }
                } else {
                    Label("전체 생성 시작", systemImage: "wand.and.stars")
                        .font(.headline)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating || selectedStates.isEmpty
                      || baseIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if isGenerating {
                Text("⚠️ 진행 중엔 앱을 그대로 켜둬 주세요. 모든 상태 끝까지 자동 진행.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var resultsSection: some View {
        Section("결과") {
            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(CharacterState.allCases, id: \.self) { state in
                    if let img = results[state] {
                        resultCard(state: state, image: img)
                    } else if let err = errors[state] {
                        errorCard(state: state, error: err)
                    }
                }
            }
        }
    }

    private func resultCard(state: CharacterState, image: UIImage) -> some View {
        VStack(spacing: 6) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            HStack {
                Text(state.symbolEmoji)
                Text(state.rawValue).font(.caption).lineLimit(1)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
    }

    private func errorCard(state: CharacterState, error: String) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.red.opacity(0.15))
                .frame(height: 120)
                .overlay(
                    Image(systemName: "xmark.octagon").foregroundStyle(.red).font(.title)
                )
            HStack {
                Text(state.symbolEmoji)
                Text(state.rawValue).font(.caption).lineLimit(1)
                Spacer()
            }
            Text(error)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    // MARK: - Actions

    private func runBatch() async {
        isGenerating = true
        results.removeAll()
        errors.removeAll()
        defer {
            isGenerating = false
            currentState = nil
            currentStartedAt = nil
            showFinishedAlert = true
        }

        // 순차 실행 (OpenAI 동시 호출 시 rate limit 위험 + 순차가 사용자에게 안정적 진행 표시)
        // keepConsistency 가 켜져 있으면 첫 결과를 두 번째 호출부터 reference 로 박음.
        var referenceForChain: String? = nil
        let toGen = CharacterState.allCases.filter { selectedStates.contains($0) }
        for state in toGen {
            currentState = state
            currentStartedAt = .now
            let promptPrefix = keepConsistency && referenceForChain != nil
                ? "Same exact character as the reference image — only the pose/scene differs. "
                : ""
            let prompt = "\(promptPrefix)\(baseIdentity), \(stateHints[state] ?? state.generationHint)"
            do {
                let req = GenerateImageRequest(
                    prompt: prompt,
                    referenceImageBase64: referenceForChain,
                    steps: 30,
                    width: 1024,
                    height: 1024,
                    quality: quality,
                    artStyle: artStyle,
                    style: "auto"
                )
                let resp = try await APIClient.shared.generateImage(req)
                guard let data = Data(base64Encoded: resp.imageBase64),
                      let img = UIImage(data: data) else {
                    errors[state] = "이미지 디코드 실패"
                    continue
                }
                // AI 출력의 가짜 체커보드를 진짜 alpha 로 후처리
                let transparent = await ImageProcessing.bestEffortTransparent(img)
                results[state] = transparent
                CharacterImageStore.save(transparent, for: state)

                // 첫 성공한 결과를 reference 로 — 이후 호출들이 같은 캐릭터 정체성 유지
                if keepConsistency && referenceForChain == nil {
                    referenceForChain = transparent.pngData()?.base64EncodedString()
                }
            } catch {
                errors[state] = error.localizedDescription
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func costPer(quality: String) -> Double {
        switch quality {
        case "low":    return 0.011
        case "medium": return 0.04
        case "high":   return 0.17
        default:       return 0.04
        }
    }
}

#Preview {
    NavigationStack { BatchCharacterGenView() }
}
