//
//  BatchCharacterGenView.swift
//  withu
//
//  여러 상태를 한 번에 생성. "캐릭터 정체성" (공통) + state 별 hint 조합.
//  참고 이미지 첨부 가능. 첫 결과 미리보기 후 계속 결정 옵션.
//

import SwiftUI
import PhotosUI
import WidgetKit

struct BatchCharacterGenView: View {
    // MARK: - Input

    @State private var baseIdentity: String = "round chibi mascot character with simple features and friendly closed-eye smile"

    @State private var stateHints: [CharacterState: String] = Dictionary(
        uniqueKeysWithValues: CharacterState.allCases.map { ($0, $0.generationHint) }
    )

    @State private var selectedStates: Set<CharacterState> = Set(CharacterState.allCases)

    @State private var quality: String = "medium"
    @State private var artStyle: String = "casual"

    /// 일관성 유지 — 첫 결과를 두 번째 호출부터 reference 로
    @State private var keepConsistency: Bool = true

    /// 첫 결과를 보고 나머지 진행 여부 결정 (기본 ON)
    @State private var confirmAfterFirst: Bool = true

    /// 참고 이미지 첨부 (모든 호출의 reference 로 사용)
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var referenceImage: UIImage?

    // MARK: - Progress

    @State private var isGenerating: Bool = false
    @State private var currentState: CharacterState?
    @State private var currentStartedAt: Date?

    @State private var results: [CharacterState: UIImage] = [:]
    @State private var errors: [CharacterState: String] = [:]

    @State private var awaitingConfirm: Bool = false
    @State private var firstResult: (state: CharacterState, image: UIImage)?

    @State private var showFinishedAlert: Bool = false

    // MARK: - Body

    var body: some View {
        Form {
            identitySection
            stateListSection
            referenceSection
            optionsSection
            startSection
            if awaitingConfirm, let first = firstResult {
                confirmSection(first: first)
            }
            if !results.isEmpty || !errors.isEmpty {
                resultsSection
            }
        }
        .navigationTitle("일괄 생성")
        .scrollDismissesKeyboard(.interactively)
        .alert("완료", isPresented: $showFinishedAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("\(results.count)개 생성 성공, \(errors.count)개 실패. 성공한 캐릭터는 자동으로 적용됐어요.")
        }
        .onChange(of: photoPickerItem) { _, item in
            Task { await loadReference(item) }
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
                Button("모두 켜기") { selectedStates = Set(CharacterState.allCases) }
                Spacer()
                Button("모두 끄기", role: .destructive) { selectedStates = [] }
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
                        if on { selectedStates.insert(state) } else { selectedStates.remove(state) }
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

    private var referenceSection: some View {
        Section {
            HStack(spacing: 12) {
                if let ref = referenceImage {
                    Image(uiImage: ref).resizable().scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.secondary.opacity(0.15))
                        .frame(width: 64, height: 64)
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                }
                VStack(alignment: .leading) {
                    PhotosPicker(referenceImage == nil ? "사진 선택" : "다른 사진으로 변경",
                                 selection: $photoPickerItem,
                                 matching: .images)
                        .disabled(isGenerating)
                    if referenceImage != nil {
                        Button("참고 이미지 제거", role: .destructive) {
                            referenceImage = nil
                            photoPickerItem = nil
                        }
                        .disabled(isGenerating)
                    }
                }
            }
        } header: {
            Text("참고 이미지 (선택)")
        } footer: {
            Text("첨부하면 첫 호출의 reference 로 사용 — 그 캐릭터의 다양한 포즈로 만들어져요. 비워두면 텍스트만으로 첫 캐릭터 생성.")
                .foregroundStyle(.secondary)
        }
    }

    private var optionsSection: some View {
        Section {
            Picker("그림체", selection: $artStyle) {
                Text("일반 (파스텔)").tag("casual")
                Text("픽셀 (8/16-bit)").tag("pixel")
            }
            .pickerStyle(.segmented).disabled(isGenerating)

            Picker("품질", selection: $quality) {
                Text("low — $0.011").tag("low")
                Text("medium — $0.04").tag("medium")
                Text("high — $0.17").tag("high")
            }
            .pickerStyle(.menu).disabled(isGenerating)

            Toggle("일관성 유지 (첫 결과를 다음 호출의 reference)", isOn: $keepConsistency)
                .disabled(isGenerating)

            Toggle("첫 결과 보고 계속할지 결정", isOn: $confirmAfterFirst)
                .disabled(isGenerating)
        } header: {
            Text("옵션")
        } footer: {
            Text("\"첫 결과 보고…\" 켜두면 첫 한 장 만든 다음 미리보기 — 마음에 안 들면 나머지 생성 안 함 (비용 절약).")
                .foregroundStyle(.secondary)
        }
    }

    private var startSection: some View {
        Section {
            Button {
                Task { await startBatch() }
            } label: {
                if isGenerating {
                    HStack {
                        ProgressView()
                        Text("생성 중… \(results.count + errors.count)/\(selectedStates.count)")
                    }
                } else {
                    Label("전체 생성 시작", systemImage: "wand.and.stars")
                        .font(.headline)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating || awaitingConfirm || selectedStates.isEmpty
                      || baseIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if isGenerating {
                Text("⚠️ 진행 중엔 앱을 그대로 켜둬 주세요.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if awaitingConfirm {
                Text("👇 아래 \"첫 결과 확인\" 에서 계속 / 중단 선택")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func confirmSection(first: (state: CharacterState, image: UIImage)) -> some View {
        Section {
            Image(uiImage: first.image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text("'\(first.state.rawValue)' 자리 첫 결과")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("계속 (나머지 \(selectedStates.count - 1)개 생성)") {
                    Task { await continueRest() }
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("중단", role: .destructive) {
                    cancelBatch()
                }
            }
        } header: {
            Text("첫 결과 확인")
        } footer: {
            Text("마음에 들면 계속 — 같은 캐릭터로 나머지 진행. 마음에 안 들면 중단 후 프롬프트 / 옵션 다듬기.")
                .foregroundStyle(.secondary)
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
            Image(uiImage: image).resizable().scaledToFit().frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            HStack {
                Text(state.symbolEmoji)
                Text(state.rawValue).font(.caption).lineLimit(1)
                Spacer()
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
            }
        }
    }

    private func errorCard(state: CharacterState, error: String) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 12).fill(.red.opacity(0.15)).frame(height: 120)
                .overlay(Image(systemName: "xmark.octagon").foregroundStyle(.red).font(.title))
            HStack {
                Text(state.symbolEmoji)
                Text(state.rawValue).font(.caption).lineLimit(1)
                Spacer()
            }
            Text(error)
                .font(.caption2)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    /// 전체 시작 — 첫 한 장 만들고, confirmAfterFirst 면 미리보기 후 사용자 선택 대기
    private func startBatch() async {
        isGenerating = true
        results.removeAll()
        errors.removeAll()
        firstResult = nil
        awaitingConfirm = false

        let toGen = CharacterState.allCases.filter { selectedStates.contains($0) }
        guard let firstState = toGen.first else { isGenerating = false; return }

        // 첫 호출 reference = 사용자 첨부 (있으면)
        let userRefB64 = referenceImage?.pngData()?.base64EncodedString()
        let success = await runOne(firstState, reference: userRefB64,
                                    consistencyPrefix: userRefB64 != nil)

        if !success {
            isGenerating = false
            return
        }
        guard let firstImg = results[firstState] else {
            isGenerating = false
            return
        }
        firstResult = (firstState, firstImg)

        if confirmAfterFirst {
            // 사용자 확인 대기 모드
            awaitingConfirm = true
            isGenerating = false
        } else {
            // 자동 진행
            await continueRest()
        }
    }

    private func continueRest() async {
        awaitingConfirm = false
        isGenerating = true
        defer {
            isGenerating = false
            currentState = nil
            currentStartedAt = nil
            showFinishedAlert = true
        }

        let toGen = CharacterState.allCases.filter { selectedStates.contains($0) }
        // 첫 번째는 이미 끝남 — 두 번째부터
        let rest = toGen.dropFirst()

        // 두 번째부터는: keepConsistency ON → 첫 결과 reference, OFF → 사용자 reference (있으면)
        let firstImg = firstResult?.image
        let chainRef: String? = keepConsistency
            ? firstImg?.pngData()?.base64EncodedString()
            : referenceImage?.pngData()?.base64EncodedString()

        for state in rest {
            _ = await runOne(state, reference: chainRef,
                              consistencyPrefix: keepConsistency || chainRef != nil)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func cancelBatch() {
        awaitingConfirm = false
        isGenerating = false
        firstResult = nil
    }

    /// 한 state 생성 — 성공 시 true. 결과는 results / errors 에 기록.
    @discardableResult
    private func runOne(_ state: CharacterState, reference: String?, consistencyPrefix: Bool) async -> Bool {
        currentState = state
        currentStartedAt = .now
        let prefix = consistencyPrefix
            ? "Same exact character as the reference image — only the pose/scene differs. "
            : ""
        let prompt = "\(prefix)\(baseIdentity), \(stateHints[state] ?? state.generationHint)"
        do {
            let req = GenerateImageRequest(
                prompt: prompt,
                referenceImageBase64: reference,
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
                return false
            }
            let transparent = await ImageProcessing.bestEffortTransparent(img)
            results[state] = transparent
            CharacterImageStore.save(transparent, for: state)
            // 워치도 함께 (백그라운드 file transfer, 워치 안 보고 있어도 OS 가 큐잉)
            ConnectivityManager.shared.sendCharacterImage(transparent, for: state)
            return true
        } catch {
            errors[state] = error.localizedDescription
            return false
        }
    }

    private func loadReference(_ item: PhotosPickerItem?) async {
        guard let item else {
            referenceImage = nil
            return
        }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                referenceImage = img
            }
        } catch {
            errors[.idle] = "참고 이미지 로드 실패: \(error.localizedDescription)"
        }
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
