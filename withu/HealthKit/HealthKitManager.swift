//
//  HealthKitManager.swift
//  withu
//

import Foundation
import HealthKit
import WidgetKit

enum HealthError: LocalizedError {
    case notAvailable
    case typeUnavailable(String)
    case query(Error)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return String(localized: "이 기기에서는 HealthKit을 쓸 수 없어요.")
        case .typeUnavailable(let name):
            return String(localized: "HealthKit 데이터 타입 사용 불가: \(name)")
        case .query(let err):
            return String(localized: "쿼리 실패: \(err.localizedDescription)")
        }
    }
}

/// 표시용 HealthKit 권한 상태 3단.
/// iOS 는 read 권한의 실제 허용/거부를 앱에 알려주지 않는다 —
/// `HKHealthStore.authorizationStatus(for:)` 는 share(write) 전용이라
/// read 만 쓰는 이 앱에선 항상 거부처럼 보인다. 대신 두 신호로 추론:
/// (1) getRequestStatusForAuthorization — .unnecessary 면 사용자가 이미 결정함
/// (2) 실제 데이터 조회 성공 — 값이 읽히면 사실상 허용
enum HealthAuthStatus {
    case notRequested       // 권한 시트를 띄운 적 없음
    case determinedNoData   // 사용자가 결정했지만 읽히는 데이터 없음 (거부 가능성 높음)
    case authorized         // 데이터가 실제로 읽힘 = 사실상 허용
}

// 화면에 보여주기 위한 가벼운 요약 모델
struct SleepSummary {
    let totalAsleep: TimeInterval   // 초
    let sampleCount: Int
    let lastNight: Date?
}

struct WorkoutSummary: Equatable {
    let activity: HKWorkoutActivityType
    let start: Date
    let duration: TimeInterval
    let totalEnergyKcal: Double?
    let totalDistanceMeters: Double?
}

@Observable
@MainActor
final class HealthKitManager {
    static let shared = HealthKitManager()

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var workoutObserverQuery: HKObserverQuery?
    @ObservationIgnored private var stepObserverQuery: HKObserverQuery?
    @ObservationIgnored private var sleepObserverQuery: HKObserverQuery?
    @ObservationIgnored private var heartRateObserverQuery: HKObserverQuery?

    /// 표시용 권한 상태 — `HealthAuthStatus` 주석 참고.
    /// 앱 시작 시 `startObservingChanges()` 가, 요청 직후엔 `requestAuthorization()` 이 갱신.
    private(set) var authStatus: HealthAuthStatus = .notRequested
    /// 데이터가 실제로 읽혔는지 (= .authorized). 기존 호출부 호환용.
    var isAuthorized: Bool { authStatus == .authorized }
    private(set) var sleep: SleepSummary?
    private(set) var recentWorkouts: [WorkoutSummary] = []
    private(set) var todaySteps: Double?
    /// 오늘의 활동(운동) 분. HealthKit 의 appleExerciseTime.
    private(set) var todayActiveMinutes: Double?
    /// 오늘의 활성 칼로리. activeEnergyBurned.
    private(set) var todayActiveKcal: Double?
    /// iOS 의 수면 일정(Health 앱) 안에 현재 시각이 들어있는지.
    /// Apple 이 wind-down ~ 기상 시간을 자동으로 `inBed` sample 로 미리 기록함.
    private(set) var isInBedSchedule: Bool = false
    /// 사용자가 Health 수면 일정 설정해뒀는지 (= inBed sample 존재 여부).
    /// 없으면 resolver 가 기본 22-07 시간대로 fallback.
    private(set) var hasSleepSchedule: Bool = false
    /// 진단용 — 최근 24시간 동안 존재한 inBed 샘플 개수.
    private(set) var inBedSampleCount24h: Int = 0
    /// 진단용 — 마지막 inBed 샘플의 시작 시각.
    private(set) var lastInBedSampleStart: Date?
    /// 진단용 — 마지막 inBed 샘플의 종료 시각.
    private(set) var lastInBedSampleEnd: Date?

    // MARK: - 워치 운동 추론 (HR 빈도 기반)
    /// 최근 90초 동안 받은 HR sample 개수.
    /// 평상시 ~1개, 운동중 워치 stream 모드 ~10-30개.
    private(set) var recentHRSampleCount: Int = 0
    /// 최근 90초 HR sample 의 평균 bpm.
    private(set) var recentHRAverage: Double = 0
    /// HR 패턴이 "워치 운동 진행 중" 으로 보이는지.
    /// 조건: 5+ sample / 90s AND avg >= 95 bpm.
    private(set) var isLikelyInWorkout: Bool = false
    /// 최근 10분 평균 걸음 페이스(분당 걸음수) — 진행 중 운동의 걷기/달리기 구분용.
    private(set) var recentStepsPerMinute: Double = 0

    private init() {}

    // MARK: - 권한

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        if let active = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(active)
        }
        if let exercise = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) {
            types.insert(exercise)
        }
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(hr)
        }
        return types
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthError.notAvailable
        }
        // 한계: 이 completion 의 ok 는 "요청 절차가 정상 처리됨"까지만 뜻한다
        // (사용자가 거부해도 true) — 허용 여부 판정에 쓰지 않는다.
        let _: Bool = try await withCheckedThrowingContinuation { continuation in
            store.requestAuthorization(toShare: [], read: readTypes) { ok, error in
                if let error {
                    continuation.resume(throwing: HealthError.query(error))
                } else {
                    continuation.resume(returning: ok)
                }
            }
        }
        // 시트가 닫힌 직후 request status + 데이터 probe 로 표시 상태 확정.
        await refreshAuthorizationStatus()
    }

    /// 표시용 권한 상태 갱신 — 앱 시작·권한 요청 직후 호출.
    /// 1) getRequestStatusForAuthorization: .shouldRequest = 아직 요청 안 함,
    ///    .unnecessary = 사용자가 이미 결정함 (허용/거부는 알 수 없음).
    /// 2) 최근 7일 걸음 probe: 값이 읽히면 사실상 허용으로 확정.
    ///    (개별 fetch 성공 시에도 authorized 로 올라가므로 여기선 보조 신호.)
    func refreshAuthorizationStatus() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let request: HKAuthorizationRequestStatus = await withCheckedContinuation { cont in
            store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, _ in
                cont.resume(returning: status)
            }
        }
        if request == .shouldRequest {
            // 아직 권한 시트를 띄운 적 없음. (이미 데이터가 읽혔다면 유지)
            if authStatus != .authorized { authStatus = .notRequested }
            return
        }
        if request == .unnecessary, authStatus == .notRequested {
            authStatus = .determinedNoData
        }
        guard authStatus != .authorized,
              let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else { return }
        // 데이터 probe — 오늘 걸음은 자정 직후 0 일 수 있어 7일 합으로 본다.
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let total: Double = await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                // 거부/무데이터면 stats 가 nil (errorNoData) → 0 취급
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            }
            store.execute(q)
        }
        if total > 0 { authStatus = .authorized }
    }

    // MARK: - 수면 (지난 N일)

    func fetchSleep(days: Int = 7) async throws -> SleepSummary {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthError.typeUnavailable("sleepAnalysis")
        }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let q = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: HealthError.query(error)); return }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }

        // "잠든" 카테고리만 합산 (asleep* 시리즈)
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let asleep = samples.filter { asleepValues.contains($0.value) }
        // '오늘 활동'의 수면은 '지난 밤'만 — 예전엔 7일치를 전부 합산해 값이 부풀거나
        // 새 수면이 없으면 옛날 총합이 고정으로 남았음(2h 고정 버그).
        // 가장 최근 수면 샘플 기준 14시간 창 안에서 시작한 것만 = 한 번의 수면 세션.
        let lastNight: [HKCategorySample]
        if let lastEnd = asleep.map(\.endDate).max() {
            let windowStart = lastEnd.addingTimeInterval(-14 * 3600)
            lastNight = asleep.filter { $0.startDate >= windowStart }
        } else {
            lastNight = []
        }
        let total = lastNight.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        let summary = SleepSummary(
            totalAsleep: total,
            sampleCount: lastNight.count,
            lastNight: lastNight.map(\.startDate).min()
        )
        sleep = summary
        // 값이 실제로 읽혔을 때만 허용 확정 — 거부돼도 read 쿼리는 빈 결과로 "성공"한다.
        // (지난밤이 비어도 최근 7일에 샘플이 있으면 권한은 확정)
        if !asleep.isEmpty { authStatus = .authorized }
        return summary
    }

    // MARK: - 자동 감지 (observer + background delivery)

    /// HealthKit 의 workout / step 변화 자동 감지 + 백그라운드 위젯 reload.
    ///
    /// === ⚠️ Apple 의 백그라운드 딜레이 정책 주의사항 ===
    ///
    /// 1. **Entitlement 필요**: Xcode → Signing & Capabilities → "Background Modes"
    ///    추가 후 "Background fetch" 체크. + "HealthKit" capability 의 Background Delivery 도.
    ///    안 하면 enableBackgroundDelivery 가 silent 하게 무시됨.
    ///
    /// 2. **frequency 의미**: HKWorkout / sleepAnalysis 같은 category/correlation 은
    ///    `.immediate` 사용 가능. HKQuantityType (stepCount 등) 은 `.hourly` 가 최대.
    ///    iOS 가 배터리 보호 위해 *.immediate 도 수십 초 ~ 수 분 지연시킬 수 있음.*
    ///    "즉시" 보장 X — best-effort.
    ///
    /// 3. **completionHandler 필수**: HKObserverQuery callback 안에서 반드시 호출.
    ///    안 하면 OS 가 retry 안 보내고 background delivery 자동 비활성화 가능.
    ///
    /// 4. **백그라운드 실행 시간**: 깨어난 후 약 30초 안에 작업 끝내야. async fetch +
    ///    widget reload 정도면 충분. 길어지면 OS 가 강제 종료.
    ///
    /// 5. **앱이 force-quit 상태면 안 깨어남**: 사용자가 위로 swipe up 으로 종료한 상태면
    ///    iOS 가 background callback 안 보냄. 보통 launch 한 번 해두면 그 후 작동.
    ///
    /// 6. **observer 는 long-lived**: 한 번 execute 하면 앱 종료까지 살아있음.
    ///    중복 execute 방지 위해 nil 체크.
    ///
    /// 7. **권한 필요**: 해당 type 의 read 권한 있어야 callback 옴.
    func startObservingChanges() {
        // 표시용 권한 상태 자동 갱신 — 앱 시작 경로에서 매번 불리므로 여기서 한 번.
        Task { await refreshAuthorizationStatus() }
        // 1) Workout 변화 (운동 종료 시점 감지)
        if workoutObserverQuery == nil {
            let workoutType = HKObjectType.workoutType()
            let query = HKObserverQuery(sampleType: workoutType,
                                        predicate: nil) { [weak self] _, completionHandler, error in
                // completionHandler 반드시 호출 — 안 하면 다음 callback 안 옴
                defer { completionHandler() }
                guard error == nil, let self else { return }
                Task { @MainActor in
                    _ = try? await self.fetchWorkouts(days: 1)
                    // HKWorkout 이 commit 됐다 = 운동 종료. HR 추론은 stale 가능성 → 즉시 클리어.
                    // resolver 가 HKWorkout 우선이라 이론상 무관하지만 진단/일관성 위해 명시.
                    self.isLikelyInWorkout = false
                    // SharedAppState 갱신 + 워치 push + 위젯 reload 한 번에.
                    SyncCoordinator.syncNow()
                }
            }
            workoutObserverQuery = query
            store.execute(query)
            // 백그라운드 delivery 활성화 — 앱이 백그라운드여도 callback 옴.
            store.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { _, _ in
                // 결과 무시. 실패해도 foreground observer 는 작동.
            }
        }
        // 2) Step 변화 (활동량 갱신)
        if stepObserverQuery == nil,
           let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) {
            let query = HKObserverQuery(sampleType: stepType,
                                        predicate: nil) { [weak self] _, completionHandler, error in
                defer { completionHandler() }
                guard error == nil, let self else { return }
                Task { @MainActor in
                    _ = try? await self.fetchTodaySteps()
                    _ = try? await self.fetchTodayActiveMinutes()
                    _ = try? await self.fetchTodayActiveKcal()
                    SyncCoordinator.syncNow()
                }
            }
            stepObserverQuery = query
            store.execute(query)
            // stepCount 는 quantity type — frequency .immediate 가 .hourly 로 강등될 수 있음
            store.enableBackgroundDelivery(for: stepType, frequency: .immediate) { _, _ in }
        }
        // 3) Sleep 변화 (inBed sample 생성/종료 시점 감지 → sleeping state)
        if sleepObserverQuery == nil,
           let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            let query = HKObserverQuery(sampleType: sleepType,
                                        predicate: nil) { [weak self] _, completionHandler, error in
                defer { completionHandler() }
                guard error == nil, let self else { return }
                Task { @MainActor in
                    _ = await self.fetchInBedSchedule()
                    SyncCoordinator.syncNow()
                }
            }
            sleepObserverQuery = query
            store.execute(query)
            // sleepAnalysis 는 category type — .immediate 지원
            store.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { _, _ in }
        }
        // 4) Heart rate 변화 — 워치 운동중일 때 stream sample 빈도 급증으로 추론
        if heartRateObserverQuery == nil,
           let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            let query = HKObserverQuery(sampleType: hrType,
                                        predicate: nil) { [weak self] _, completionHandler, error in
                defer { completionHandler() }
                guard error == nil, let self else { return }
                Task { @MainActor in
                    await self.refreshWorkoutInference()
                    SyncCoordinator.syncNow()
                }
            }
            heartRateObserverQuery = query
            store.execute(query)
            // heart rate 는 quantity type — frequency .immediate 가 .hourly 강등 가능하지만,
            // 워치 운동중 burst 들은 observer 가 forground delivery 로 빨리 옴.
            store.enableBackgroundDelivery(for: hrType, frequency: .immediate) { _, _ in }
        }
    }

    /// 최근 90초 HR sample 통계 + isLikelyInWorkout 판정.
    func refreshWorkoutInference() async {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let now = Date()
        let start = now.addingTimeInterval(-90)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)

        let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }

        recentHRSampleCount = samples.count
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let avg: Double
        if samples.isEmpty {
            avg = 0
        } else {
            avg = samples.map { $0.quantity.doubleValue(for: bpmUnit) }.reduce(0, +) / Double(samples.count)
        }
        recentHRAverage = avg
        // 5+ samples in 90s = 워치가 운동 모드라 stream 중일 가능성
        // avg >= 95 = 평상시 휴식 (60-80) 보다 명백히 높음
        isLikelyInWorkout = samples.count >= 5 && avg >= 95

        // 최근 걸음 페이스(분당 걸음수) — 진행 중 운동의 걷기/달리기 구분용.
        // HKWorkout 은 운동이 끝나야 생기므로, 진행 중엔 이 cadence 로 타입을 추정.
        // 10분 창은 운동 시작 초반(대부분 정지였던 시간이 분모에 포함)에 과소평가되므로,
        // 3분 창과 함께 재서 큰 쪽을 쓴다 — 시작 직후엔 3분이, 안정 구간엔 10분이 잡음.
        if let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) {
            func stepsPerMinute(windowMin: Double) async -> Double {
                let stepStart = now.addingTimeInterval(-windowMin * 60)
                let stepPredicate = HKQuery.predicateForSamples(withStart: stepStart, end: now)
                let total: Double = await withCheckedContinuation { cont in
                    let q = HKStatisticsQuery(
                        quantityType: stepType,
                        quantitySamplePredicate: stepPredicate,
                        options: .cumulativeSum
                    ) { _, stats, _ in
                        cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                    }
                    store.execute(q)
                }
                return total / windowMin
            }
            recentStepsPerMinute = max(await stepsPerMinute(windowMin: 10),
                                       await stepsPerMinute(windowMin: 3))
        }
    }

    // MARK: - 현재 수면 일정 안인지

    /// Health 앱의 수면 일정에 따르면 지금 자고 있어야 하는 시각인지 확인.
    /// iOS 는 schedule 의 wind-down ~ 기상 시각을 `inBed` 카테고리 sample 로 미리 기록.
    /// 어떤 사유 (권한 거부, 일정 미설정 등) 든 false 반환 — never throws.
    @discardableResult
    func fetchInBedSchedule() async -> Bool {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            isInBedSchedule = false
            return false
        }
        let now = Date()
        let start = now.addingTimeInterval(-24 * 3600)
        let end = now.addingTimeInterval(24 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        // throws 없는 continuation — query error 도 빈 결과로 처리.
        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }

        // 수면 샘플이 읽혔다는 것 자체가 read 통과 증거.
        if !samples.isEmpty { authStatus = .authorized }

        let inBedValue = HKCategoryValueSleepAnalysis.inBed.rawValue
        let inBedSamples = samples.filter { $0.value == inBedValue }
        // 어떤 시점이든 inBed sample 있음 = 사용자가 수면 일정 설정함.
        // ⚠️ 워치 수면 추적은 inBed 없이 asleep(수면 단계)만 남기는 경우가 많음 —
        //    그런 사용자는 예측 신호가 없어 아래 '지금 덮는 샘플' + 프로필 시간이 기준.
        hasSleepSchedule = !inBedSamples.isEmpty
        // '지금'을 덮는 수면 샘플은 inBed 뿐 아니라 asleep 도 인정 —
        // 워치가 밤중에 동기화한 실시간 수면 기록으로도 자는 상태를 잡는다.
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let nowInside = samples.contains { s in
            (s.value == inBedValue || asleepValues.contains(s.value))
                && s.startDate <= now && now < s.endDate
        }
        isInBedSchedule = nowInside
        // 진단 — 마지막 (가장 최근 시작) sample 찾기
        let last = inBedSamples.max(by: { $0.startDate < $1.startDate })
        inBedSampleCount24h = inBedSamples.filter {
            $0.endDate >= now.addingTimeInterval(-24 * 3600)
        }.count
        lastInBedSampleStart = last?.startDate
        lastInBedSampleEnd = last?.endDate
        return nowInside
    }

    /// 최근 N일 asleep 샘플로 평균 취침/기상 시각 계산 — '최근 수면 시간에 맞추기'용.
    /// 밤 단위로 묶고(시작-12h 날짜 버킷), 밤이 2개 미만이면 nil (낮잠 오탐 방지).
    func averageSleepWindow(days: Int = 7) async -> (startHour: Int, startMinute: Int,
                                                     endHour: Int, endMinute: Int)? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let now = Date()
        let windowStart = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: now)
        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: sleepType, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, _ in
                cont.resume(returning: (s as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.inBed.rawValue,
        ]
        let sleep = samples.filter { asleepValues.contains($0.value) }
        guard !sleep.isEmpty else { return nil }

        let cal = Calendar.current
        // '밤' 그룹: 시작 시각 -12h 의 날짜 — 자정 넘김 보정 (23시 취침과 01시 취침이 같은 밤)
        var nights: [Date: (start: Date, end: Date)] = [:]
        for s in sleep {
            let key = cal.startOfDay(for: s.startDate.addingTimeInterval(-12 * 3600))
            if let n = nights[key] {
                nights[key] = (min(n.start, s.startDate), max(n.end, s.endDate))
            } else {
                nights[key] = (s.startDate, s.endDate)
            }
        }
        guard nights.count >= 2 else { return nil }

        func minutesOfDay(_ d: Date) -> Int {
            let c = cal.dateComponents([.hour, .minute], from: d)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        // 취침: 18:00 기준 상대 분으로 평균 (자정 wrap 보정). 기상: 자정 기준 그대로.
        let startRel = nights.values.map { (minutesOfDay($0.start) + 1440 - 18 * 60) % 1440 }
        let avgStart = (startRel.reduce(0, +) / startRel.count + 18 * 60) % 1440
        let endMins = nights.values.map { minutesOfDay($0.end) }
        let avgEnd = endMins.reduce(0, +) / endMins.count
        return (avgStart / 60, avgStart % 60, avgEnd / 60, avgEnd % 60)
    }

    // MARK: - 워크아웃 (지난 N일)

    func fetchWorkouts(days: Int = 7, limit: Int = 20) async throws -> [WorkoutSummary] {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let q = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: limit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: HealthError.query(error)); return }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }

        let summaries = workouts.map {
            WorkoutSummary(
                activity: $0.workoutActivityType,
                start: $0.startDate,
                duration: $0.duration,
                totalEnergyKcal: $0.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                totalDistanceMeters: $0.totalDistance?.doubleValue(for: .meter())
            )
        }
        recentWorkouts = summaries
        if !summaries.isEmpty { authStatus = .authorized }   // 값이 읽힘 → 허용 확정
        return summaries
    }

    // MARK: - 오늘 걸음 수

    func fetchTodaySteps() async throws -> Double {
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            throw HealthError.typeUnavailable("stepCount")
        }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())

        let total: Double = try await withCheckedThrowingContinuation { continuation in
            let q = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                // "No data available" 는 진짜 에러가 아니라 0건 의미라서 0으로 처리
                if let err = error as NSError?,
                   err.domain == HKErrorDomain,
                   err.code == HKError.errorNoData.rawValue {
                    continuation.resume(returning: 0)
                    return
                }
                if let error {
                    continuation.resume(throwing: HealthError.query(error))
                    return
                }
                let sum = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: sum)
            }
            store.execute(q)
        }
        todaySteps = total
        if total > 0 { authStatus = .authorized }   // 값이 읽힘 → 허용 확정
        return total
    }

    // MARK: - 오늘 활동 분 + 칼로리

    /// 오늘의 운동(활동) 분 (appleExerciseTime, unit: minute).
    func fetchTodayActiveMinutes() async throws -> Double {
        let total = try await fetchTodayCumulative(.appleExerciseTime, unit: .minute())
        todayActiveMinutes = total
        if total > 0 { authStatus = .authorized }
        return total
    }

    /// 오늘의 활성 칼로리 (activeEnergyBurned, unit: kcal).
    func fetchTodayActiveKcal() async throws -> Double {
        let total = try await fetchTodayCumulative(.activeEnergyBurned, unit: .kilocalorie())
        todayActiveKcal = total
        if total > 0 { authStatus = .authorized }
        return total
    }

    private func fetchTodayCumulative(_ identifier: HKQuantityTypeIdentifier,
                                       unit: HKUnit) async throws -> Double {
        guard let qType = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthError.typeUnavailable(identifier.rawValue)
        }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())

        return try await withCheckedThrowingContinuation { continuation in
            let q = HKStatisticsQuery(
                quantityType: qType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                if let err = error as NSError?,
                   err.domain == HKErrorDomain,
                   err.code == HKError.errorNoData.rawValue {
                    continuation.resume(returning: 0); return
                }
                if let error {
                    continuation.resume(throwing: HealthError.query(error)); return
                }
                let sum = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: sum)
            }
            store.execute(q)
        }
    }
}

// MARK: - 표시 헬퍼

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running: return String(localized: "달리기 🏃")
        case .cycling: return String(localized: "자전거 🚴")
        case .walking: return String(localized: "걷기 🚶")
        case .hiking: return String(localized: "등산 🥾")
        case .swimming: return String(localized: "수영 🏊")
        case .yoga: return String(localized: "요가 🧘")
        case .traditionalStrengthTraining,
             .functionalStrengthTraining: return String(localized: "근력 💪")
        default: return String(localized: "운동")
        }
    }
}
