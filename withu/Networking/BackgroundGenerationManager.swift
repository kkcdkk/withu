//
//  BackgroundGenerationManager.swift
//  withu (iOS)
//
//  배치 캐릭터 생성을 background URLSession 으로 실행 — 화면을 끄거나 앱을 나가도
//  iOS 가 전송/수신을 이어 하고, 완료 시 앱을 잠깐 깨워 저장/적용한다. 끝나면 로컬 알림.
//
//  구조:
//    - 작업(BackgroundGenJob)은 queued → running → done/failed. 한 번에 1개씩 순차 실행
//      (기존 배치 maxConcurrent=1 과 동일 — 서버 부하/일관성 안정).
//    - 작업 목록은 jobs.json 으로 디스크 영속 — 앱이 재시작돼도 이어짐.
//    - 요청 본문은 <jobId>.body.json 파일 (background upload task 는 파일 본문 필수).
//    - frame0 완료 시 원본을 <state>_f0.png 로 저장하고, 움직임(frame1) 작업을 체이닝.
//    - Idempotency-Key = job.id — 재시작 후 재전송돼도 서버가 중복 처리 안 함.
//

import Foundation
import UIKit
import WidgetKit

struct BackgroundGenJob: Codable, Identifiable {
    enum Status: String, Codable { case queued, running, done, failed }

    let id: String
    let stateRaw: String
    let frame: Int
    let quality: String
    let artStyle: String
    let batchId: String
    var wantsFrame1: Bool
    var frame1Prompt: String?
    var status: Status
    var errorMessage: String?
    var startedAt: Date?
    /// 402 (캔디/무료 소진) 로 실패 — 뷰가 페이월을 띄우는 근거.
    var paymentRequired: Bool?
    /// 실행 횟수. 앱이 죽은 사이 완료된 upload task 는 응답 본문이 유실될 수 있어
    /// (iOS 한계) 본문 없는 2xx 는 한 번 재큐잉한다 — 그 상한.
    var attempts: Int?
}

/// 뷰가 넘겨주는 한 장 스펙. 프롬프트는 뷰가 조립(기존 runOne 로직 그대로).
struct BackgroundGenJobSpec {
    let state: CharacterState
    let frame: Int
    let prompt: String
    let referenceB64: String?
    /// frame==1 을 바로 만들 때(예: idle 움직임) 크기 정규화 기준이 되는 frame0 원본.
    let frame0Reference: UIImage?
    let wantsFrame1: Bool
    let frame1Prompt: String?
}

@Observable
final class BackgroundGenerationManager: NSObject {
    static let shared = BackgroundGenerationManager()
    static let sessionIdentifier = "com.seoyoung.withu.bggen"

    /// anchor = 기준(idle) 1장만 만드는 단계. rest = 승인 후 나머지 전체.
    /// retry = 끝난 배치에서 한 장만 다시 — 완료 알림/알럿을 배치처럼 띄우지 않음.
    enum Phase: String, Codable { case anchor, rest, retry }

    // MARK: 관찰용 상태 (MainActor 에서만 변경)

    private(set) var jobs: [BackgroundGenJob] = []
    private(set) var phase: Phase = .rest
    /// 변경 신호 — 뷰가 onChange 로 결과를 당겨 가는 트리거.
    private(set) var tick: Int = 0
    /// 완료 썸네일 (state#frame → 128px). 앱 재시작 후엔 비어 있음 —
    /// 뷰는 CharacterImageStore.loadFrame 으로 fallback.
    private(set) var images: [String: UIImage] = [:]

    var isActive: Bool { jobs.contains { $0.status == .queued || $0.status == .running } }
    var doneCount: Int { jobs.filter { $0.status == .done }.count }
    var failedCount: Int { jobs.filter { $0.status == .failed }.count }

    /// AppDelegate 가 저장하는 background 이벤트 완료 핸들러.
    @ObservationIgnored var backgroundCompletionHandler: (() -> Void)?

    // MARK: 내부

    @ObservationIgnored private var session: URLSession!
    /// taskIdentifier → 수신 데이터. 직렬 delegateQueue 에서만 접근.
    @ObservationIgnored private var buffers: [Int: Data] = [:]
    @ObservationIgnored private var wasCancelled = false
    /// background 이벤트 소진 게이팅 — 진행 중인 process() 가 다 끝난 뒤에만
    /// completionHandler 를 불러 iOS 가 저장 도중 앱을 재우지 않게 한다.
    @ObservationIgnored private let pendingLock = NSLock()
    @ObservationIgnored private var pendingProcessCount = 0
    @ObservationIgnored private var eventsDrained = false

    @ObservationIgnored private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    @ObservationIgnored private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private override init() {
        super.init()
        restore()
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.timeoutIntervalForRequest = APIConfig.timeout
        config.timeoutIntervalForResource = APIConfig.resourceTimeout
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }

    // MARK: - 시작 / 재개 / 취소

    /// 새 단계 시작 — 이전 단계의 작업 목록은 교체된다.
    @MainActor
    func start(specs: [BackgroundGenJobSpec], quality: String, artStyle: String,
               batchId: String, phase: Phase) {
        wasCancelled = false
        self.phase = phase
        jobs = []
        images.removeAll()
        for spec in specs {
            appendJob(spec: spec, quality: quality, artStyle: artStyle, batchId: batchId)
        }
        persist()
        tick += 1
        runNextIfIdle()
    }

    /// 실패한 한 장 재시도 — 같은 state·frame 의 실패 작업을 교체하고 큐에 추가.
    /// 배치가 이미 끝난 뒤라면 retry 단계로 전환 — 완료 시 배치 알림/알럿을 다시 띄우지 않음.
    @MainActor
    func retry(spec: BackgroundGenJobSpec, quality: String, artStyle: String, batchId: String) {
        wasCancelled = false
        if !isActive { phase = .retry }
        jobs.removeAll { $0.stateRaw == spec.state.rawValue && $0.frame == spec.frame && $0.status == .failed }
        appendJob(spec: spec, quality: quality, artStyle: artStyle, batchId: batchId)
        persist()
        tick += 1
        runNextIfIdle()
    }

    /// 앱 재시작 후 미완료 작업 이어가기 — AppDelegate 런치에서 호출.
    /// 프로세스가 죽는 사이 URLSession 에서 증발한 running 작업은 재큐잉
    /// (Idempotency-Key 로 서버 중복 처리 없음).
    @MainActor
    func resumeIfNeeded() {
        guard isActive else { return }
        session.getAllTasks { [weak self] tasks in
            let liveIds = Set(tasks.compactMap { $0.taskDescription })
            Task { @MainActor in
                guard let self else { return }
                var changed = false
                for i in self.jobs.indices
                where self.jobs[i].status == .running && !liveIds.contains(self.jobs[i].id) {
                    self.jobs[i].status = .queued
                    changed = true
                }
                if changed {
                    self.persist()
                    self.tick += 1
                }
                self.runNextIfIdle()
            }
        }
    }

    @MainActor
    func cancelAll() {
        wasCancelled = true
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
        for i in jobs.indices where jobs[i].status == .queued || jobs[i].status == .running {
            jobs[i].status = .failed
            jobs[i].errorMessage = "취소했어요"
        }
        persist()
        tick += 1
    }

    /// frame0 원본(1024) 로드 — 승인 앵커/frame1 정규화 기준.
    func loadFrame0FullRes(_ state: CharacterState) -> UIImage? {
        guard let url = frame0URL(state),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - 큐 실행

    @MainActor
    private func appendJob(spec: BackgroundGenJobSpec, quality: String, artStyle: String, batchId: String) {
        let job = BackgroundGenJob(id: UUID().uuidString,
                                   stateRaw: spec.state.rawValue,
                                   frame: spec.frame,
                                   quality: quality,
                                   artStyle: artStyle,
                                   batchId: batchId,
                                   wantsFrame1: spec.wantsFrame1,
                                   frame1Prompt: spec.frame1Prompt,
                                   status: .queued)
        let req = GenerateImageRequest(prompt: spec.prompt,
                                       referenceImageBase64: spec.referenceB64,
                                       steps: 30, width: 1024, height: 1024,
                                       quality: quality, artStyle: artStyle, style: "auto")
        guard let bodyURL = bodyURL(job.id),
              let body = try? encoder.encode(req),
              (try? body.write(to: bodyURL, options: .atomic)) != nil else {
            var failed = job
            failed.status = .failed
            failed.errorMessage = "요청을 준비하지 못했어요"
            jobs.append(failed)
            return
        }
        // frame1 직접 작업(idle 움직임)의 정규화 기준 원본 저장
        if spec.frame == 1, let f0 = spec.frame0Reference {
            saveFrame0FullRes(f0, for: spec.state)
        }
        jobs.append(job)
    }

    @MainActor
    private func runNextIfIdle() {
        guard !jobs.contains(where: { $0.status == .running }),
              let idx = jobs.firstIndex(where: { $0.status == .queued }) else { return }
        let job = jobs[idx]
        guard let bodyURL = bodyURL(job.id),
              FileManager.default.fileExists(atPath: bodyURL.path) else {
            jobs[idx].status = .failed
            jobs[idx].errorMessage = "요청 파일이 없어요"
            persist()
            tick += 1
            runNextIfIdle()
            return
        }

        var req = URLRequest(url: APIConfig.baseURL.appendingPathComponent("/generate"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = APIConfig.apiToken, !token.isEmpty {
            req.setValue(token, forHTTPHeaderField: "X-Withu-Token")
        }
        if let sessionToken = KeychainStore.sessionToken() {
            req.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
        req.setValue(job.id, forHTTPHeaderField: "Idempotency-Key")
        req.setValue("batch", forHTTPHeaderField: "X-Withu-Kind")
        req.setValue(job.batchId, forHTTPHeaderField: "X-Withu-Batch")
        req.timeoutInterval = APIConfig.timeout

        let task = session.uploadTask(with: req, fromFile: bodyURL)
        task.taskDescription = job.id
        jobs[idx].status = .running
        jobs[idx].startedAt = Date()
        jobs[idx].attempts = (jobs[idx].attempts ?? 0) + 1
        persist()
        tick += 1
        task.resume()
    }

    // MARK: - 완료 처리

    @MainActor
    private func process(jobId: String, data: Data?, response: URLResponse?, error: Error?) async {
        // running 이 아닌 작업의 완료 콜백은 무시 — 재시작 후 재큐잉과 원래 태스크의
        // 늦은 콜백이 겹쳐도 이중 차감/이중 frame1 체이닝이 없다. (취소된 작업도 여기서 걸러짐)
        guard let idx = jobs.firstIndex(where: { $0.id == jobId }),
              jobs[idx].status == .running else {
            runNextIfIdle()
            return
        }

        var failure: String?
        if let error {
            failure = error.koreanizedDescription
        } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 402 {
                failure = "무료 횟수를 다 썼어요"
                jobs[idx].paymentRequired = true
            } else if http.statusCode == 422 {
                failure = "프롬프트가 안전 정책에 걸렸어요. 단어를 살짝 바꿔서 다시 시도해 주세요."
            } else {
                failure = "서버 오류 (\(http.statusCode)). 잠시 후 다시 시도해 주세요."
            }
        }

        var requeued = false
        if failure == nil {
            if let data, !data.isEmpty,
               let resp = try? decoder.decode(GenerateImageResponse.self, from: data),
               let imgData = Data(base64Encoded: resp.imageBase64),
               let img = UIImage(data: imgData),
               let state = CharacterState(rawValue: jobs[idx].stateRaw) {
                let job = jobs[idx]
                // frame1: frame0 원본 기준으로 크기·위치 정규화 (기존 runOne 과 동일)
                let flat: UIImage
                if job.frame == 1, let ref0 = loadFrame0FullRes(state) {
                    flat = await ImageProcessing.matchedToReference(img, reference: ref0)
                } else {
                    flat = img
                }
                let small = flat.preparingThumbnail(of: CGSize(width: 128, height: 128)) ?? flat
                CharacterImageStore.save(small, for: state, frame: job.frame)
                ConnectivityManager.shared.sendCharacterImage(small, for: state, frame: job.frame)
                if let ent = resp.entitlement { AuthManager.shared.applyEntitlement(ent) }
                GenerationQuota.record(GenerationQuota.cost(forQuality: job.quality))
                images["\(job.stateRaw)#\(job.frame)"] = small
                let flatPNG = job.frame == 0 ? flat.pngData() : nil
                if job.frame == 0, let flatPNG, let url = frame0URL(state) {
                    try? flatPNG.write(to: url, options: .atomic)
                }
                jobs[idx].status = .done
                // 움직임(frame1) 체이닝 — 방금 받은 frame0 원본을 reference 로
                if job.frame == 0, job.wantsFrame1, let f1Prompt = job.frame1Prompt,
                   let refB64 = flatPNG?.base64EncodedString() {
                    let spec = BackgroundGenJobSpec(state: state, frame: 1, prompt: f1Prompt,
                                                    referenceB64: refB64, frame0Reference: nil,
                                                    wantsFrame1: false, frame1Prompt: nil)
                    appendJob(spec: spec, quality: job.quality, artStyle: job.artStyle, batchId: job.batchId)
                }
            } else if (data == nil || data?.isEmpty == true), (jobs[idx].attempts ?? 1) < 2 {
                // 2xx 인데 본문 없음 — 앱이 죽은 사이 완료된 upload task 는 iOS 가
                // 응답 본문을 보존하지 않는다. 한 번 재큐잉해 다시 생성.
                jobs[idx].status = .queued
                jobs[idx].startedAt = nil
                requeued = true
            } else {
                failure = "이미지를 받지 못했어요"
            }
        }

        if let failure {
            jobs[idx].status = .failed
            jobs[idx].errorMessage = failure
        }
        // 재큐잉이면 body 파일을 남겨야 재실행 가능.
        if !requeued, let url = bodyURL(jobId) {
            try? FileManager.default.removeItem(at: url)
        }
        persist()
        tick += 1

        if isActive {
            runNextIfIdle()
        } else {
            await finish()
        }
    }

    /// 큐가 빌 때 한 번 — 위젯 갱신 + 로컬 알림.
    @MainActor
    private func finish() async {
        WidgetCenter.shared.reloadAllTimelines()
        guard !wasCancelled else {
            wasCancelled = false
            return
        }
        switch phase {
        case .anchor:
            if doneCount > 0 {
                await NotificationManager.shared.notifyAnchorReady()
            }
        case .rest:
            await NotificationManager.shared.notifyGenerationFinished(done: doneCount,
                                                                      failed: failedCount)
        case .retry:
            break   // 한 장 재시도 — 배치 완료 알림을 다시 보내지 않음
        }
    }

    // MARK: - 영속화

    private struct Persisted: Codable {
        var phase: Phase
        var jobs: [BackgroundGenJob]
    }

    private var folderURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("bggen", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var jobsFileURL: URL? { folderURL?.appendingPathComponent("jobs.json") }
    private func bodyURL(_ jobId: String) -> URL? {
        folderURL?.appendingPathComponent("\(jobId).body.json")
    }
    private func frame0URL(_ state: CharacterState) -> URL? {
        folderURL?.appendingPathComponent("\(state.rawValue)_f0.png")
    }

    private func saveFrame0FullRes(_ image: UIImage, for state: CharacterState) {
        guard let url = frame0URL(state), let data = image.pngData() else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func persist() {
        guard let url = jobsFileURL,
              let data = try? JSONEncoder().encode(Persisted(phase: phase, jobs: jobs)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func restore() {
        guard let url = jobsFileURL,
              let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        phase = saved.phase
        jobs = saved.jobs
    }
}

// MARK: - URLSession delegate (직렬 delegateQueue 에서 호출)

extension BackgroundGenerationManager: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffers[dataTask.taskIdentifier, default: Data()].append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let data = buffers.removeValue(forKey: task.taskIdentifier)
        guard let jobId = task.taskDescription else { return }
        let response = task.response
        pendingLock.lock()
        pendingProcessCount += 1
        pendingLock.unlock()
        Task { @MainActor in
            await self.process(jobId: jobId, data: data, response: response, error: error)
            self.pendingLock.lock()
            self.pendingProcessCount -= 1
            let shouldCall = self.eventsDrained && self.pendingProcessCount == 0
            self.pendingLock.unlock()
            if shouldCall { self.callBackgroundCompletionHandler() }
        }
    }

    /// 백그라운드 세션 이벤트 소진 — 진행 중인 process() 까지 끝나야
    /// completion handler 를 호출한다 (호출 즉시 iOS 가 앱을 다시 재울 수 있으므로).
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        pendingLock.lock()
        eventsDrained = true
        let shouldCall = pendingProcessCount == 0
        pendingLock.unlock()
        if shouldCall { callBackgroundCompletionHandler() }
    }

    private func callBackgroundCompletionHandler() {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
            self.pendingLock.lock()
            self.eventsDrained = false
            self.pendingLock.unlock()
        }
    }
}
