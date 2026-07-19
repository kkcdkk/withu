//
//  GallerySyncManager.swift
//  withu (iOS)
//
//  갤러리 클라우드 백업/복원 — 재설치·기기 변경 후 로그인하면 만든 캐릭터가 다시 보이게.
//  캔디와 같은 모델: 로컬(App Group)이 권위, 서버는 백업 — 서버가 로컬을 덮어쓰지 않는다.
//  동기화는 best-effort — 실패해도 조용히(로그만), 사용자 노출 문구 없음.
//
//  재조정(reconcile):
//    1) pendingDeletes(로컬에서 지웠는데 서버 삭제 실패분) 재시도
//    2) 서버 GET /gallery 목록 ↔ 로컬 metadata.json 비교
//       → 로컬에만 있으면 업로드, 서버에만 있으면 다운로드(pendingDeletes 는 제외)
//  트리거: 로그인 성공/복원 직후 · 앱 포그라운드 진입 · 갤러리 저장/삭제(.galleryChanged).
//  활성 슬롯(characters/<state>.png)은 범위 밖 — 복원 후 갤러리에서 다시 적용하면 됨.
//

import Foundation

extension Notification.Name {
    /// 서버 백업에서 갤러리 항목을 복원함 — CharacterGalleryView 재로드용.
    static let gallerySyncDidImport = Notification.Name("withu.gallerySyncDidImport")
}

actor GallerySyncManager {
    static let shared = GallerySyncManager()

    private static let pendingDeletesKey = "withu.gallery.pendingDeletes.v1"
    /// [갤러리 id: 계정(appleUserId)] — 어느 계정이 만든 항목인지. 로컬 갤러리는 계정 구분 없는
    /// 기기 공용 저장소라, 이 태그 없이는 계정 전환 시 이전 계정 이미지가 새 계정으로 업로드된다.
    private static let itemOwnerKey = "withu.gallery.itemOwner.v1"
    /// 이 기기에서 로그인한 적 있는 계정 집합 — 태그 없는(legacy) 항목의 입양 판단용.
    private static let knownAccountsKey = "withu.gallery.knownAccounts.v1"

    /// 중복 실행 방지 — 실행 중 재요청은 rerun 플래그로 모아서 끝난 뒤 한 번만 다시.
    private var isSyncing = false
    private var rerunRequested = false

    private init() {}

    /// 앱 시작 시 1회 — 갤러리 변경 알림 구독 (저장 → 업로드, 삭제 → 서버 삭제 예약).
    nonisolated func start() {
        NotificationCenter.default.addObserver(forName: .galleryChanged, object: nil, queue: nil) { note in
            let deletedId = note.userInfo?["deletedId"] as? String
            let addedId = note.userInfo?["addedId"] as? String
            Task {
                if let deletedId { await GallerySyncManager.shared.enqueueDelete(deletedId) }
                // 신규 항목은 생성 시점의 로그인 계정으로 즉시 태깅 — 계정 전환 기기에서도
                // "지금 계정이 만든 것"만 업로드되게.
                if let addedId { await GallerySyncManager.shared.tagItem(addedId) }
                await GallerySyncManager.shared.reconcile()
            }
        }
    }

    /// 동기화 트리거 — 어디서든 한 줄 (로그인 직후/포그라운드 등). fire-and-forget.
    nonisolated func kick() {
        Task { await self.reconcile() }
    }

    // MARK: - pendingDeletes (App Group UserDefaults)

    private var pendingDeletes: [String] {
        UserDefaults(suiteName: SharedAppState.groupID)?
            .stringArray(forKey: Self.pendingDeletesKey) ?? []
    }

    private func setPendingDeletes(_ ids: [String]) {
        UserDefaults(suiteName: SharedAppState.groupID)?
            .set(ids, forKey: Self.pendingDeletesKey)
    }

    private func enqueueDelete(_ id: String) {
        var ids = pendingDeletes
        guard !ids.contains(id) else { return }
        ids.append(id)
        setPendingDeletes(ids)
    }

    // MARK: - 항목 소유 계정 태깅 (App Group UserDefaults)

    private var itemOwner: [String: String] {
        (UserDefaults(suiteName: SharedAppState.groupID)?
            .dictionary(forKey: Self.itemOwnerKey) as? [String: String]) ?? [:]
    }

    private func setOwner(_ account: String, for id: String) {
        var map = itemOwner
        guard map[id] != account else { return }
        map[id] = account
        UserDefaults(suiteName: SharedAppState.groupID)?.set(map, forKey: Self.itemOwnerKey)
    }

    private var knownAccounts: Set<String> {
        Set(UserDefaults(suiteName: SharedAppState.groupID)?
            .stringArray(forKey: Self.knownAccountsKey) ?? [])
    }

    private func registerKnownAccount(_ account: String) {
        var set = knownAccounts
        guard !set.contains(account) else { return }
        set.insert(account)
        UserDefaults(suiteName: SharedAppState.groupID)?
            .set(Array(set), forKey: Self.knownAccountsKey)
    }

    /// 새 갤러리 항목을 현재 로그인 계정으로 태깅 (비로그인 상태면 태그 없음 → 입양 규칙 적용).
    func tagItem(_ id: String) {
        guard let account = KeychainStore.appleUserId() else { return }
        setOwner(account, for: id)
    }

    // MARK: - Reconcile

    func reconcile() async {
        // 로그인일 때만 (Keychain 세션 토큰 기준 — DEBUG skip 로그인은 토큰 없음 → no-op).
        guard KeychainStore.sessionToken() != nil else { return }
        if isSyncing {
            rerunRequested = true
            return
        }
        isSyncing = true
        defer {
            isSyncing = false
            if rerunRequested {
                rerunRequested = false
                kick()
            }
        }

        // 1) 밀린 서버 삭제 재시도
        await processPendingDeletes()

        // 2) 서버 목록 ↔ 로컬 메타 비교
        let serverItems: [GalleryBackupItem]
        do {
            serverItems = try await APIClient.shared.fetchGalleryList()
        } catch {
            #if DEBUG
            print("GallerySync: 목록 조회 실패 — \(error)")
            #endif
            return
        }

        let localItems = await MainActor.run { CharacterImageStore.loadGalleryMetadata() }
        let localIDs = Set(localItems.map(\.id))
        let serverByID = Dictionary(serverItems.map { ($0.id, $0) },
                                    uniquingKeysWith: { first, _ in first })
        let pending = Set(pendingDeletes)

        // 계정 태깅 준비 — 세션 토큰만 있고 appleUserId 가 없으면(비정상) 업로드는 건너뛴다.
        let account = KeychainStore.appleUserId()
        if let account { registerKnownAccount(account) }
        // 태그 없는(legacy — 기능 도입 전/비로그인 생성) 항목 입양 조건:
        // 이 기기가 지금 계정만 본 경우에만. 다른 계정을 본 적 있으면 그 계정 것일 수 있어 업로드 금지.
        let adoptAllowed = account.map { knownAccounts == [$0] } ?? false

        // 로컬에만 있는 항목 → 소유 계정이 맞을 때만 업로드 (계정 전환 시 교차 유출 방지).
        // 서버에도 있지만 로컬에서 frame1 이 추가된 항목도 재업로드 (frame0 직후 frame1 저장 타이밍 커버).
        for item in localItems where !pending.contains(item.id) {
            if let server = serverByID[item.id] {
                // 현재 계정의 서버 목록에 있음 = 현재 계정 소유 확정 → 태그 보정.
                if let account { setOwner(account, for: item.id) }
                if (item.hasFrame1 ?? false) && server.hasFrame1 != true {
                    await upload(item)
                }
            } else {
                guard let account else { continue }
                switch itemOwner[item.id] {
                case account:
                    await upload(item)
                case nil where adoptAllowed:
                    setOwner(account, for: item.id)
                    await upload(item)
                default:
                    continue   // 다른 계정 소유(또는 입양 불가 legacy) — 업로드 금지
                }
            }
        }

        // 서버에만 있는 항목 → 다운로드 (로컬에서 지운 항목(pendingDeletes)은 제외)
        var imported = 0
        for item in serverItems where !localIDs.contains(item.id) && !pending.contains(item.id) {
            if await download(item) {
                imported += 1
                if let account { setOwner(account, for: item.id) }
            }
        }
        if imported > 0 {
            await MainActor.run {
                NotificationCenter.default.post(name: .gallerySyncDidImport, object: nil)
            }
        }

        // 소유 태그 청소 — 로컬·서버 어디에도 없는 id 는 제거 (무한 누적 방지).
        let live = localIDs.union(serverByID.keys).union(pending)
        let stale = itemOwner.keys.filter { !live.contains($0) }
        if !stale.isEmpty {
            var map = itemOwner
            for k in stale { map.removeValue(forKey: k) }
            UserDefaults(suiteName: SharedAppState.groupID)?.set(map, forKey: Self.itemOwnerKey)
        }
    }

    private func processPendingDeletes() async {
        for id in pendingDeletes {
            do {
                try await APIClient.shared.deleteGalleryItem(id: id)
                setPendingDeletes(pendingDeletes.filter { $0 != id })
            } catch {
                // 404 = 서버에 이미 없음(다른 계정 항목 포함) → 완료로 간주.
                // 그 외(오프라인 등)는 남겨서 다음 reconcile 때 재시도.
                if case APIError.server(let status, _) = error, status == 404 {
                    setPendingDeletes(pendingDeletes.filter { $0 != id })
                }
            }
        }
    }

    /// 로컬 갤러리 항목 업로드 — 후처리 완료본 PNG 그대로(재가공 없음).
    private func upload(_ item: GalleryItem) async {
        guard let data = CharacterImageStore.galleryImageData(id: item.id) else { return }
        let frame1Data = (item.hasFrame1 ?? false)
            ? CharacterImageStore.galleryImageData(id: item.id, frame: 1) : nil
        let body = GalleryUploadRequest(
            imageB64: data.base64EncodedString(),
            frame1B64: frame1Data?.base64EncodedString(),
            sourceState: item.sourceState,
            createdAt: Int(item.createdAt.timeIntervalSince1970),
            hasFrame1: frame1Data != nil,
            batchId: item.batchId,
            prompt: item.prompt)
        do {
            try await APIClient.shared.uploadGalleryItem(body, id: item.id)
        } catch {
            #if DEBUG
            print("GallerySync: 업로드 실패 (\(item.id)) — \(error)")
            #endif
        }
    }

    /// 서버 항목 다운로드 → id/메타 보존한 채 로컬 갤러리에 저장. 성공 시 true.
    private func download(_ item: GalleryBackupItem) async -> Bool {
        do {
            let data = try await APIClient.shared.downloadGalleryImage(id: item.id)
            var frame1Data: Data?
            if item.hasFrame1 == true {
                frame1Data = try? await APIClient.shared.downloadGalleryImage(id: item.id, frame: 1)
            }
            let createdAt = item.createdAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
            let f1 = frame1Data
            return await MainActor.run {
                CharacterImageStore.importGalleryItem(
                    id: item.id, imageData: data, frame1Data: f1,
                    sourceState: item.sourceState ?? CharacterState.idle.rawValue,
                    createdAt: createdAt, batchId: item.batchId, prompt: item.prompt)
            }
        } catch {
            #if DEBUG
            print("GallerySync: 다운로드 실패 (\(item.id)) — \(error)")
            #endif
            return false
        }
    }
}
