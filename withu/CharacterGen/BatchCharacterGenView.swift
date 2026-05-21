//
//  BatchCharacterGenView.swift
//  withu
//
//  여러 상태를 한 번에 생성. "캐릭터 정체성" (공통) + state 별 hint 조합.
//  참고 이미지 첨부 가능. 첫 결과 미리보기 후 계속 결정 옵션.
//

import SwiftUI
import PhotosUI
import Photos
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

    /// 전체 참고 이미지 (state 별 reference 가 없을 때의 fallback)
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var referenceImage: UIImage?

    /// state 별 개별 참고 이미지. 있으면 전체 reference 보다 우선.
    @State private var stateReferenceImages: [CharacterState: UIImage] = [:]
    @State private var stateReferencePickerItems: [CharacterState: PhotosPickerItem] = [:]

    // MARK: - Progress

    @State private var isGenerating: Bool = false
    /// 현재 진행 중인 state 들 (병렬이라 여러 개 동시 가능)
    @State private var inProgressStates: Set<CharacterState> = []
    @State private var stateStartedAt: [CharacterState: Date] = [:]

    @State private var results: [CharacterState: UIImage] = [:]
    @State private var errors: [CharacterState: String] = [:]

    @State private var showFinishedAlert: Bool = false

    // 사진 앱 저장 상태
    @State private var isSavingPhotos: Bool = false
    @State private var saveResultMessage: String?
    @State private var showSaveResultAlert: Bool = false

    // MARK: - Body

    var body: some View {
        Form {
            identitySection
            stateListSection
            referenceSection
            optionsSection
            startSection
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
        .alert("사진 저장", isPresented: $showSaveResultAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(saveResultMessage ?? "")
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

            // state 별 참고 이미지 (있으면 전체 reference 보다 우선)
            stateReferencePicker(state)

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

    /// state 별 참고 이미지 선택기. 작은 thumbnail + Picker / 제거 버튼.
    @ViewBuilder
    private func stateReferencePicker(_ state: CharacterState) -> some View {
        HStack(spacing: 10) {
            if let ref = stateReferenceImages[state] {
                Image(uiImage: ref).resizable().scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.secondary.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "photo")
                        .foregroundStyle(.secondary).font(.caption))
            }
            VStack(alignment: .leading, spacing: 2) {
                PhotosPicker(
                    stateReferenceImages[state] == nil ? "참고 이미지 추가" : "변경",
                    selection: Binding(
                        get: { stateReferencePickerItems[state] },
                        set: { item in
                            if let item {
                                stateReferencePickerItems[state] = item
                                Task { await loadStateReference(state, item: item) }
                            } else {
                                stateReferencePickerItems.removeValue(forKey: state)
                                stateReferenceImages.removeValue(forKey: state)
                            }
                        }
                    ),
                    matching: .images
                )
                .font(.footnote)
                .disabled(isGenerating)

                if stateReferenceImages[state] != nil {
                    Button("이 state 참고 제거", role: .destructive) {
                        stateReferenceImages.removeValue(forKey: state)
                        stateReferencePickerItems.removeValue(forKey: state)
                    }
                    .font(.caption2)
                    .disabled(isGenerating)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func resultBadge(_ state: CharacterState) -> some View {
        if inProgressStates.contains(state), let started = stateStartedAt[state] {
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
        } header: {
            Text("옵션")
        } footer: {
            Text("모든 state 가 병렬로 동시에 생성돼요. 참고 이미지 우선순위: state 별 > 전체 > 없음.")
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
            .disabled(isGenerating || selectedStates.isEmpty
                      || baseIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if isGenerating {
                Text("⚠️ 진행 중엔 앱을 그대로 켜둬 주세요. 병렬로 \(inProgressStates.count)개 동시 진행 중.")
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

            if !results.isEmpty {
                Button {
                    Task { await saveAllToPhotos() }
                } label: {
                    if isSavingPhotos {
                        HStack {
                            ProgressView()
                            Text("저장 중…")
                        }
                    } else {
                        Label("사진 앱에 모두 저장 (\(results.count)장)",
                              systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(isSavingPhotos)
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
        Button {
            Task { await retryOne(state) }
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 12).fill(.red.opacity(0.15)).frame(height: 120)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .foregroundStyle(.red).font(.title)
                            Text("탭해서 재시도")
                                .font(.caption2).foregroundStyle(.red)
                        }
                    )
                HStack {
                    Text(state.symbolEmoji)
                    Text(state.rawValue).font(.caption).lineLimit(1)
                    Spacer()
                }
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .disabled(inProgressStates.contains(state))
    }

    // MARK: - Actions

    /// state 의 reference base64 결정. state 별 > 공통 > nil.
    /// startBatch / retryOne 양쪽에서 사용.
    private func resolveReference(for state: CharacterState) -> String? {
        if let img = stateReferenceImages[state],
           let data = img.pngData() {
            return data.base64EncodedString()
        }
        return referenceImage?.pngData()?.base64EncodedString()
    }

    /// 전체 순차 시작 — 한 state 가 완전히 끝나야 다음 state 진행.
    /// 가장 단순하고 안정적. 서버 / OpenAI 부담 최소.
    private func startBatch() async {
        isGenerating = true
        results.removeAll()
        errors.removeAll()
        inProgressStates.removeAll()
        stateStartedAt.removeAll()

        defer {
            isGenerating = false
            inProgressStates.removeAll()
            stateStartedAt.removeAll()
            showFinishedAlert = true
            WidgetCenter.shared.reloadAllTimelines()
        }

        let toGen = CharacterState.allCases.filter { selectedStates.contains($0) }
        for state in toGen {
            let refB64 = resolveReference(for: state)
            await runOne(state, reference: refB64, consistencyPrefix: refB64 != nil)
        }
    }

    /// 실패한 카드 탭 시 재시도. 같은 prompt + reference 그대로.
    private func retryOne(_ state: CharacterState) async {
        // 이전 에러 표시 제거 + 진행 표시 시작
        errors.removeValue(forKey: state)
        let refB64 = resolveReference(for: state)
        await runOne(state, reference: refB64, consistencyPrefix: refB64 != nil)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 한 state 생성 — 성공 시 true. 결과는 results / errors 에 기록.
    @discardableResult
    private func runOne(_ state: CharacterState, reference: String?, consistencyPrefix: Bool) async -> Bool {
        inProgressStates.insert(state)
        stateStartedAt[state] = .now
        defer {
            inProgressStates.remove(state)
            stateStartedAt.removeValue(forKey: state)
        }
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

    /// state 별 참고 이미지를 PhotosPickerItem 에서 로드해 dict 에 저장.
    private func loadStateReference(_ state: CharacterState, item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                stateReferenceImages[state] = img
            }
        } catch {
            // 조용히 무시 — 사용자가 다시 선택하면 됨
        }
    }

    /// 결과 이미지들을 사진 앱(카메라 롤)에 저장.
    /// add-only 권한 사용 — 라이브러리 읽기 권한 없이 추가만 가능.
    private func saveAllToPhotos() async {
        isSavingPhotos = true
        defer { isSavingPhotos = false }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveResultMessage = "사진 추가 권한이 거부됐어요. 설정 → withu 에서 허용해 주세요."
            showSaveResultAlert = true
            return
        }

        // CharacterState 순서대로 정렬 — 사진 앱에서도 같은 순서로 보임
        let items: [(CharacterState, UIImage)] = CharacterState.allCases.compactMap { s in
            results[s].map { (s, $0) }
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for (_, img) in items {
                    PHAssetChangeRequest.creationRequestForAsset(from: img)
                }
            }
            saveResultMessage = "\(items.count)장 사진 앱에 저장됐어요."
        } catch {
            saveResultMessage = "저장 실패: \(error.localizedDescription)"
        }
        showSaveResultAlert = true
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
