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
            return "이 기기에서는 HealthKit을 쓸 수 없어요."
        case .typeUnavailable(let name):
            return "HealthKit 데이터 타입 사용 불가: \(name)"
        case .query(let err):
            return "쿼리 실패: \(err.localizedDescription)"
        }
    }
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

    /// 권한 요청을 한 번이라도 했거나 마지막 fetch 가 성공했는지.
    /// (Apple HealthKit 은 어떤 항목이 허용됐는지 앱에 알리지 않으므로
    ///  정확한 "허용 여부" 는 fetch 가 에러 없이 통과하면 추론.)
    private(set) var isAuthorized: Bool = false
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
        try await store.requestAuthorization(toShare: [], read: readTypes)
        isAuthorized = true
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
        let total = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        let summary = SleepSummary(
            totalAsleep: total,
            sampleCount: asleep.count,
            lastNight: asleep.first?.startDate
        )
        sleep = summary
        isAuthorized = true   // fetch 가 에러 없이 통과 → 권한 있음으로 간주
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

        // 최근 10분 걸음 페이스(분당 걸음수) — 진행 중 운동의 걷기/달리기 구분용.
        // HKWorkout 은 운동이 끝나야 생기므로, 진행 중엔 이 cadence 로 타입을 추정.
        if let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) {
            let windowMin = 10.0
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
            recentStepsPerMinute = total / windowMin
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

        let inBedValue = HKCategoryValueSleepAnalysis.inBed.rawValue
        let inBedSamples = samples.filter { $0.value == inBedValue }
        // 어떤 시점이든 inBed sample 있음 = 사용자가 수면 일정 설정함
        hasSleepSchedule = !inBedSamples.isEmpty
        let nowInside = inBedSamples.contains { s in
            s.startDate <= now && now < s.endDate
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
        isAuthorized = true   // fetch 통과 → 권한 있음으로 간주
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
        isAuthorized = true   // fetch 통과 → 권한 있음으로 간주
        return total
    }

    // MARK: - 오늘 활동 분 + 칼로리

    /// 오늘의 운동(활동) 분 (appleExerciseTime, unit: minute).
    func fetchTodayActiveMinutes() async throws -> Double {
        let total = try await fetchTodayCumulative(.appleExerciseTime, unit: .minute())
        todayActiveMinutes = total
        isAuthorized = true
        return total
    }

    /// 오늘의 활성 칼로리 (activeEnergyBurned, unit: kcal).
    func fetchTodayActiveKcal() async throws -> Double {
        let total = try await fetchTodayCumulative(.activeEnergyBurned, unit: .kilocalorie())
        todayActiveKcal = total
        isAuthorized = true
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
        case .running: return "달리기 🏃"
        case .cycling: return "자전거 🚴"
        case .walking: return "걷기 🚶"
        case .hiking: return "등산 🥾"
        case .swimming: return "수영 🏊"
        case .yoga: return "요가 🧘"
        case .traditionalStrengthTraining,
             .functionalStrengthTraining: return "근력 💪"
        default: return "운동"
        }
    }
}
