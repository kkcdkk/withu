package com.seoyoung.withu.health

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.seoyoung.withu.WithuApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * 건강 데이터 매니저 — iOS HealthKitManager.swift 의 Health Connect 대응 (스펙 10 §3.2/§5).
 *
 * 계약 (00-PLAN §2-8):
 *  - Health Connect 미설치/권한 없음이면 오늘 값들은 null (홈 카드가 항목 미표시).
 *  - 데이터가 '없는 것'(no data)은 0 — null 과 구분 (iOS "No data available → 0" 규칙).
 *  - iOS 의 isAuthorized '추론'과 달리 Health Connect 는 getGrantedPermissions 로 정확히 판정.
 *  - HK inBed '예정 수면 샘플' 등가물이 없음 → hasSleepSchedule 은 항상 false,
 *    리졸버는 프로필 수면 창 fallback 을 탄다 (스펙 10 §5 표).
 */
object HealthManager {

    /** 지난밤 유효 판정 — 마지막 수면 종료가 이 시간보다 오래됐으면 '기록 없음' (iOS 36시간). */
    private const val LAST_NIGHT_MAX_AGE_HOURS = 36L

    /** 한 밤으로 묶는 창 — 마지막 수면 종료 기준 이 시간 안에 시작한 구간만 (iOS 14시간). */
    private const val SLEEP_SESSION_WINDOW_HOURS = 14L

    private const val HOUR_MS = 60L * 60L * 1000L

    private val _isAuthorized = MutableStateFlow(false)
    val isAuthorized: StateFlow<Boolean> = _isAuthorized

    private val _sleep = MutableStateFlow<SleepSummary?>(null)
    val sleep: StateFlow<SleepSummary?> = _sleep

    private val _recentWorkouts = MutableStateFlow<List<WorkoutSummary>>(emptyList())
    val recentWorkouts: StateFlow<List<WorkoutSummary>> = _recentWorkouts   // 최신순

    private val _todaySteps = MutableStateFlow<Double?>(null)
    val todaySteps: StateFlow<Double?> = _todaySteps

    private val _todayActiveMinutes = MutableStateFlow<Double?>(null)
    val todayActiveMinutes: StateFlow<Double?> = _todayActiveMinutes

    private val _todayActiveKcal = MutableStateFlow<Double?>(null)
    val todayActiveKcal: StateFlow<Double?> = _todayActiveKcal

    private val _isInBedSchedule = MutableStateFlow(false)
    val isInBedSchedule: StateFlow<Boolean> = _isInBedSchedule

    private val _hasSleepSchedule = MutableStateFlow(false)
    val hasSleepSchedule: StateFlow<Boolean> = _hasSleepSchedule

    private val _recentHRSampleCount = MutableStateFlow(0)
    val recentHRSampleCount: StateFlow<Int> = _recentHRSampleCount

    private val _recentHRAverage = MutableStateFlow(0.0)
    val recentHRAverage: StateFlow<Double> = _recentHRAverage

    private val _isLikelyInWorkout = MutableStateFlow(false)
    val isLikelyInWorkout: StateFlow<Boolean> = _isLikelyInWorkout

    private val _recentStepsPerMinute = MutableStateFlow(0.0)
    val recentStepsPerMinute: StateFlow<Double> = _recentStepsPerMinute

    /** 진단 — iOS inBedSampleCount24h 근사: ±24h 창의 수면 세션 수. */
    private val _sleepSampleCount48h = MutableStateFlow(0)
    val sleepSampleCount48h: StateFlow<Int> = _sleepSampleCount48h

    /** 진단 — 가장 최근 수면 세션 시작 (epoch millis). */
    private val _lastSleepSessionStart = MutableStateFlow<Long?>(null)
    val lastSleepSessionStart: StateFlow<Long?> = _lastSleepSessionStart

    /** Health Connect 사용 가능 여부 — 미설치/미지원 기기 분기 (minSdk 28 은 앱 설치 필요 케이스 존재). */
    fun isAvailable(): Boolean =
        HealthConnectClient.getSdkStatus(WithuApp.context) == HealthConnectClient.SDK_AVAILABLE

    /**
     * 읽기 권한 6종 (쓰기 없음) — 온보딩/설정 권한 요청 계약 상수.
     * iOS: workout·sleep·steps·activeEnergy·exerciseTime·heartRate 대응 + Distance(워크아웃 거리).
     */
    fun requiredPermissions(): Set<String> = setOf(
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class),
        HealthPermission.getReadPermission(HeartRateRecord::class),
        HealthPermission.getReadPermission(DistanceRecord::class),
    )

    private fun clientOrNull(): HealthConnectClient? =
        if (isAvailable()) runCatching { HealthConnectClient.getOrCreate(WithuApp.context) }.getOrNull()
        else null

    /** getGrantedPermissions 로 isAuthorized 갱신.
     *  요구 6종 중 '하나라도' 허용되면 authorized — iOS 처럼 부분 허용도 동작(각 조회는 없는 데이터 null 처리).
     *  containsAll(전부) 로 하면 삼성 헬스에서 심박 등 하나만 꺼도 '허용 안됨' 으로 떠서 사용자가 혼란. */
    suspend fun refreshAuthorizationStatus() = withContext(Dispatchers.IO) {
        val client = clientOrNull()
        if (client == null) {
            _isAuthorized.value = false
            return@withContext
        }
        _isAuthorized.value = runCatching {
            val granted = client.permissionController.getGrantedPermissions()
            requiredPermissions().any { it in granted }
        }.getOrDefault(false)
    }

    // MARK: - 조회 6종 (실패/미설치 → null 유지, no data → 0)

    /**
     * 지난 밤 수면 — asleep 계열만, **마지막 한 밤 분량만** 집계 (AWAKE/침대 밖 stage 제외).
     * N일치를 전부 합산하면 '오늘 활동'에 며칠치가 얹혀 20시간 같은 값이 나온다 (iOS 가 고친 버그).
     */
    suspend fun fetchSleep(days: Int = 7) = withContext(Dispatchers.IO) {
        val client = clientOrNull() ?: run { _sleep.value = null; return@withContext }
        runCatching {
            val now = Instant.now()
            val sessions = client.readRecords(
                ReadRecordsRequest(
                    SleepSessionRecord::class,
                    TimeRangeFilter.between(now.minus(Duration.ofDays(days.toLong())), now),
                ),
            ).records
            val intervals = mutableListOf<SleepInterval>()
            for (s in sessions) {
                if (s.stages.isEmpty()) {
                    // stage 없는 세션은 전체를 asleep 으로 간주 (스펙 10 §5 표)
                    intervals += SleepInterval(s.startTime.toEpochMilli(), s.endTime.toEpochMilli())
                } else {
                    for (st in s.stages) {
                        if (isAsleepStage(st.stage)) {
                            intervals += SleepInterval(
                                st.startTime.toEpochMilli(),
                                st.endTime.toEpochMilli(),
                            )
                        }
                    }
                }
            }
            val summary = lastNightSummary(intervals, now.toEpochMilli())
            _sleep.value = summary
            // 진단 표시도 '지난밤 시작'으로 통일 — iOS 는 진단에 sleep.lastNight 를 그대로 쓴다.
            _lastSleepSessionStart.value = summary.lastNight
        }.onFailure { _sleep.value = null }
    }

    /** 수면 구간 하나 — 세션 전체 또는 asleep stage 하나 (epoch millis). */
    internal data class SleepInterval(val startMs: Long, val endMs: Long)

    /**
     * '지난 밤' 한 밤 분량만 집계 — iOS HealthKitManager.fetchSleep(:213-238) 규칙 포팅.
     *  1) asleep 계열만 (caller 가 이미 걸러 넘긴다 — inBed/AWAKE 제외)
     *  2) 가장 최근 수면 **종료**가 now 기준 36시간 이내일 때만 유효.
     *     아니면 (0, 0, null) → 홈이 '-' 로 표시 (오래된 기록을 오늘 수면으로 보여주지 않는다).
     *  3) 그 종료 시각 기준 14시간 창 안에서 **시작**한 구간만 = 한 밤.
     *     → 이틀 전 낮잠·전전날 수면이 섞이지 않는다.
     * lastNight 은 지난밤 구간들의 **가장 이른 시작** (iOS min).
     */
    internal fun lastNightSummary(intervals: List<SleepInterval>, nowMs: Long): SleepSummary {
        val lastEnd = intervals.maxOfOrNull { it.endMs }
        if (lastEnd == null || nowMs - lastEnd >= LAST_NIGHT_MAX_AGE_HOURS * HOUR_MS) {
            return SleepSummary(0.0, 0, null)
        }
        val windowStart = lastEnd - SLEEP_SESSION_WINDOW_HOURS * HOUR_MS
        val lastNight = intervals.filter { it.startMs >= windowStart }
        val totalSeconds = lastNight.sumOf { (it.endMs - it.startMs) / 1000.0 }
        return SleepSummary(totalSeconds, lastNight.size, lastNight.minOfOrNull { it.startMs })
    }

    /** asleep 계열 stage 판정 — AWAKE / AWAKE_IN_BED / OUT_OF_BED 제외. */
    internal fun isAsleepStage(stage: Int): Boolean = when (stage) {
        SleepSessionRecord.STAGE_TYPE_SLEEPING,
        SleepSessionRecord.STAGE_TYPE_LIGHT,
        SleepSessionRecord.STAGE_TYPE_DEEP,
        SleepSessionRecord.STAGE_TYPE_REM,
        -> true
        else -> false
    }

    /** 최근 N일 운동 세션 — 시작시각 내림차순 최대 limit 개. */
    suspend fun fetchWorkouts(days: Int = 7, limit: Int = 20) = withContext(Dispatchers.IO) {
        val client = clientOrNull() ?: run { _recentWorkouts.value = emptyList(); return@withContext }
        runCatching {
            val now = Instant.now()
            val sessions = client.readRecords(
                ReadRecordsRequest(
                    ExerciseSessionRecord::class,
                    TimeRangeFilter.between(now.minus(Duration.ofDays(days.toLong())), now),
                ),
            ).records
            _recentWorkouts.value = sessions
                .sortedByDescending { it.startTime }
                .take(limit)
                .map { s ->
                    WorkoutSummary(
                        activity = mapExerciseType(s.exerciseType),
                        start = s.startTime.toEpochMilli(),
                        durationSeconds = Duration.between(s.startTime, s.endTime).seconds.toDouble(),
                        // 세션별 kcal/거리 연관 조회는 세션 수만큼 aggregate 호출이 필요 —
                        // 리졸버/알림이 쓰지 않는 표시용 값이라 null 로 둔다 (스펙 10 §5: 없으면 nil 허용).
                        kcal = null,
                        meters = null,
                    )
                }
        }.onFailure { _recentWorkouts.value = emptyList() }
    }

    /** 오늘 걸음 — 자정~현재 누적합. no data → 0 (에러 아님, iOS 주석 그대로). */
    suspend fun fetchTodaySteps() = withContext(Dispatchers.IO) {
        val client = clientOrNull() ?: run { _todaySteps.value = null; return@withContext }
        runCatching {
            val result = client.aggregate(
                AggregateRequest(
                    setOf(StepsRecord.COUNT_TOTAL),
                    TimeRangeFilter.between(startOfToday(), Instant.now()),
                ),
            )
            _todaySteps.value = (result[StepsRecord.COUNT_TOTAL] ?: 0L).toDouble()
        }.onFailure { _todaySteps.value = null }
    }

    /**
     * 오늘 활동 분 — appleExerciseTime 의 완전 등가물이 없어 오늘 운동 세션
     * duration 합을 분으로 환산해 근사 (스펙 10 §5 표). 세션 없으면 0.
     */
    suspend fun fetchTodayActiveMinutes() = withContext(Dispatchers.IO) {
        val client = clientOrNull() ?: run { _todayActiveMinutes.value = null; return@withContext }
        runCatching {
            val sessions = client.readRecords(
                ReadRecordsRequest(
                    ExerciseSessionRecord::class,
                    TimeRangeFilter.between(startOfToday(), Instant.now()),
                ),
            ).records
            val totalSeconds = sessions.sumOf { Duration.between(it.startTime, it.endTime).seconds }
            _todayActiveMinutes.value = totalSeconds / 60.0
        }.onFailure { _todayActiveMinutes.value = null }
    }

    /** 오늘 활성 칼로리 — 누적합 kcal. no data → 0. */
    suspend fun fetchTodayActiveKcal() = withContext(Dispatchers.IO) {
        val client = clientOrNull() ?: run { _todayActiveKcal.value = null; return@withContext }
        runCatching {
            val result = client.aggregate(
                AggregateRequest(
                    setOf(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL),
                    TimeRangeFilter.between(startOfToday(), Instant.now()),
                ),
            )
            _todayActiveKcal.value =
                result[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]?.inKilocalories ?: 0.0
        }.onFailure { _todayActiveKcal.value = null }
    }

    /**
     * 수면 일정/현재 수면 판정 — 실패는 전부 false (never throws, iOS 동일).
     * 조회 창: 현재 ±24시간 (iOS 는 미래 inBed 샘플 때문 — HC 는 예정 개념이 없지만 창은 동형 유지).
     * hasSleepSchedule: HC 에 '예정된 수면' 등가물이 없어 항상 false —
     *   리졸버는 프로필 수면 창 fallback 을 탄다 (스펙 10 §5).
     * isInBedSchedule: '지금'을 시간상 덮는 수면 세션 존재 (AWAKE 아닌 stage 인정).
     */
    suspend fun fetchInBedSchedule() = withContext(Dispatchers.IO) {
        val client = clientOrNull() ?: run {
            _isInBedSchedule.value = false
            _hasSleepSchedule.value = false
            return@withContext
        }
        runCatching {
            val now = Instant.now()
            val sessions = client.readRecords(
                ReadRecordsRequest(
                    SleepSessionRecord::class,
                    TimeRangeFilter.between(
                        now.minus(Duration.ofHours(24)),
                        now.plus(Duration.ofHours(24)),
                    ),
                ),
            ).records
            _sleepSampleCount48h.value = sessions.size
            _isInBedSchedule.value = sessions.any { s ->
                if (!s.startTime.isAfter(now) && s.endTime.isAfter(now)) {
                    // stage 가 있으면 '지금' 구간의 stage 가 AWAKE 계열이 아닐 때만 수면 중
                    val covering = s.stages.filter { !it.startTime.isAfter(now) && it.endTime.isAfter(now) }
                    if (covering.isEmpty()) true else covering.any { isAsleepStage(it.stage) }
                } else false
            }
            _hasSleepSchedule.value = false
        }.onFailure {
            _isInBedSchedule.value = false
            _hasSleepSchedule.value = false
        }
    }

    /**
     * 워치 운동 추론 — HR 빈도 기반 (iOS refreshWorkoutInference 동형).
     * 판정: 최근 90초 샘플 5개 이상 AND 평균 >= 95bpm
     *   (평상시 ~1개/90초·휴식 60-80bpm, 운동중 stream ~10-30개 — iOS 주석의 '왜').
     * Wear OS 미보유 사용자는 HR 스트림이 없어 항상 false — iOS 도 워치 없으면 동일.
     */
    suspend fun refreshWorkoutInference() = withContext(Dispatchers.IO) {
        val client = clientOrNull() ?: run {
            _recentHRSampleCount.value = 0
            _recentHRAverage.value = 0.0
            _isLikelyInWorkout.value = false
            _recentStepsPerMinute.value = 0.0
            return@withContext
        }
        val now = Instant.now()
        runCatching {
            val hrRecords = client.readRecords(
                ReadRecordsRequest(
                    HeartRateRecord::class,
                    TimeRangeFilter.between(now.minusSeconds(90), now),
                ),
            ).records
            val samples = hrRecords.flatMap { it.samples }
                .filter { !it.time.isBefore(now.minusSeconds(90)) }
            _recentHRSampleCount.value = samples.size
            _recentHRAverage.value =
                if (samples.isEmpty()) 0.0 else samples.map { it.beatsPerMinute.toDouble() }.average()
            _isLikelyInWorkout.value =
                samples.size >= 5 && _recentHRAverage.value >= 95.0
        }.onFailure {
            _recentHRSampleCount.value = 0
            _recentHRAverage.value = 0.0
            _isLikelyInWorkout.value = false
        }
        // 분당 걸음 — 10분 창과 3분 창 두 번 재서 max.
        // 왜: 10분 창은 운동 시작 초반(대부분 정지였던 시간이 분모)에 과소평가 —
        // 시작 직후엔 3분이, 안정 구간엔 10분이 잡음 (iOS 주석 그대로).
        runCatching {
            val spm10 = stepsPerMinute(client, now, 10)
            val spm3 = stepsPerMinute(client, now, 3)
            _recentStepsPerMinute.value = maxOf(spm10, spm3)
        }.onFailure { _recentStepsPerMinute.value = 0.0 }
    }

    private suspend fun stepsPerMinute(client: HealthConnectClient, now: Instant, minutes: Long): Double {
        val result = client.aggregate(
            AggregateRequest(
                setOf(StepsRecord.COUNT_TOTAL),
                TimeRangeFilter.between(now.minus(Duration.ofMinutes(minutes)), now),
            ),
        )
        return (result[StepsRecord.COUNT_TOTAL] ?: 0L).toDouble() / minutes.toDouble()
    }

    /**
     * '최근 수면 시간에 맞추기' 평균 창 — 프로필 기준 칩용 (iOS averageSleepWindow 동형).
     * 밤 단위 그룹핑 키 = startOfDay(시작 - 12h) (23시 취침과 01시 취침이 같은 밤).
     * 밤 2개 미만이면 null (낮잠 오탐 방지).
     */
    suspend fun averageSleepWindow(days: Int = 7): SleepWindow? = withContext(Dispatchers.IO) {
        val client = clientOrNull() ?: return@withContext null
        runCatching {
            val zone = ZoneId.systemDefault()
            val now = Instant.now()
            val sessions = client.readRecords(
                ReadRecordsRequest(
                    SleepSessionRecord::class,
                    TimeRangeFilter.between(now.minus(Duration.ofDays(days.toLong())), now),
                ),
            ).records
            if (sessions.isEmpty()) return@runCatching null

            // 밤별 (최소 시작, 최대 종료) 병합
            val nights = mutableMapOf<LocalDate, Pair<Instant, Instant>>()
            for (s in sessions) {
                val key = s.startTime.minus(Duration.ofHours(12)).atZone(zone).toLocalDate()
                val cur = nights[key]
                nights[key] = if (cur == null) s.startTime to s.endTime
                else minOf(cur.first, s.startTime) to maxOf(cur.second, s.endTime)
            }
            if (nights.size < 2) return@runCatching null

            // 취침 평균: 18:00 기준 상대 분으로 자정 wrap 보정. 기상 평균: 자정 기준 분 그대로.
            val anchor = 18 * 60
            val dayMin = 24 * 60
            val startRel = nights.values.map { (start, _) ->
                val t = start.atZone(zone)
                val m = t.hour * 60 + t.minute
                (m + dayMin - anchor) % dayMin
            }.average()
            val endAbs = nights.values.map { (_, end) ->
                val t = end.atZone(zone)
                (t.hour * 60 + t.minute).toDouble()
            }.average()

            val startMin = ((startRel + anchor) % dayMin).toInt()
            val endMin = endAbs.toInt()
            SleepWindow(
                startHour = startMin / 60, startMinute = startMin % 60,
                endHour = endMin / 60, endMinute = endMin % 60,
            )
        }.getOrNull()
    }

    /** 홈 진입 일괄 로드 — 개별 실패 무시 (각 fetch 가 내부에서 삼킴). */
    suspend fun loadAll() {
        refreshAuthorizationStatus()
        fetchSleep()
        fetchWorkouts()
        fetchTodaySteps()
        fetchTodayActiveMinutes()
        fetchTodayActiveKcal()
        fetchInBedSchedule()
        refreshWorkoutInference()
    }

    private fun startOfToday(): Instant =
        LocalDate.now().atStartOfDay(ZoneId.systemDefault()).toInstant()

    /** ExerciseSessionRecord.exerciseType → WorkoutActivity (스펙 10 §5 매핑). */
    private fun mapExerciseType(type: Int): WorkoutActivity = when (type) {
        ExerciseSessionRecord.EXERCISE_TYPE_RUNNING,
        ExerciseSessionRecord.EXERCISE_TYPE_RUNNING_TREADMILL,
        -> WorkoutActivity.RUNNING
        ExerciseSessionRecord.EXERCISE_TYPE_BIKING,
        ExerciseSessionRecord.EXERCISE_TYPE_BIKING_STATIONARY,
        -> WorkoutActivity.CYCLING
        ExerciseSessionRecord.EXERCISE_TYPE_WALKING -> WorkoutActivity.WALKING
        ExerciseSessionRecord.EXERCISE_TYPE_HIKING -> WorkoutActivity.HIKING
        ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_POOL,
        ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_OPEN_WATER,
        -> WorkoutActivity.SWIMMING
        ExerciseSessionRecord.EXERCISE_TYPE_YOGA -> WorkoutActivity.YOGA
        ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING,
        ExerciseSessionRecord.EXERCISE_TYPE_WEIGHTLIFTING,
        -> WorkoutActivity.STRENGTH
        else -> WorkoutActivity.OTHER
    }
}
