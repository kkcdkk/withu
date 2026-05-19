//
//  HealthKitManager.swift
//  withu
//

import Foundation
import HealthKit

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
