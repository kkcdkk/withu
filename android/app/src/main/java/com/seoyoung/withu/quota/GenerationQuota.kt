package com.seoyoung.withu.quota

import com.seoyoung.withu.BuildConfig
import com.seoyoung.withu.shared.SharedAppState
import java.util.Calendar
import kotlin.math.max
import kotlin.math.min

/**
 * AI 생성 횟수 관리 — iOS GenerationQuota.swift 포팅 (스펙 07 §3.2).
 *   1) 무료 하루 한도 freeDailyLimit = 0 (무료 없음 — 캔디로만 생성)
 *   2) 충전 크레딧 = 캔디 (만료 없음)
 *
 * ⚠️ 캔디 잔액의 권위는 로컬 (서버는 /generate 에서 차감하지 않음).
 *    서버 잔액은 syncCreditsUp 으로 '증가분만' 반영 — 절대값 덮어쓰기 금지
 *    (덮어쓰면 로컬 차감이 새로고침마다 되돌아오는 '캔디 안 닳는' 버그).
 * 저장소: 공유 SharedPreferences — 키 문자열은 iOS 원문 유지.
 */
object GenerationQuota {
    /** 무료 사용자 하루 한도. 0 = 무료 없음. */
    const val freeDailyLimit: Int = 0

    // 테스트 캔디 코드 (TestFlight/샌드박스 대응 — Android 는 DEBUG 전용)
    const val testCandyCode: String = "CANDY20"
    const val testCandyAmount: Int = 20

    /** 테스트 캔디 코드 허용 여부 — 운영 릴리즈 무료 캔디 악용 방지. */
    val allowsTestCandyCode: Boolean get() = BuildConfig.DEBUG

    private const val COUNT_KEY = "withu.genQuota.count.v1"
    private const val DATE_KEY = "withu.genQuota.date.v1"        // yyyymmdd 정수
    private const val CREDITS_KEY = "withu.genQuota.credits.v1"
    /** 마지막으로 로컬에 반영한 서버 잔액 기준선 — '증가분'만 더하기 위함. */
    private const val LAST_SYNCED_SERVER_KEY = "withu.genQuota.lastSyncedServer.v1"

    private val prefs get() = SharedAppState.prefs()

    /** 오늘 yyyymmdd. 자정 넘으면 값이 바뀌어 일일 카운트 자동 리셋. */
    private fun todayStamp(calendar: Calendar = Calendar.getInstance()): Int =
        calendar.get(Calendar.YEAR) * 10000 +
            (calendar.get(Calendar.MONTH) + 1) * 100 +
            calendar.get(Calendar.DAY_OF_MONTH)

    /** 오늘 일일 한도에서 사용한 횟수. */
    fun usedToday(): Int =
        computeUsedToday(prefs.getInt(DATE_KEY, 0), prefs.getInt(COUNT_KEY, 0), todayStamp())

    /** 충전 크레딧 잔액 (만료 없음). */
    fun credits(): Int = prefs.getInt(CREDITS_KEY, 0)

    /** 지금 더 만들 수 있는 총 횟수. DEBUG 빌드는 9999 (무제한 테스트 — 출시 빌드는 실제 한도). */
    fun remainingToday(): Int =
        if (BuildConfig.DEBUG) 9999
        else max(0, freeDailyLimit - usedToday()) + credits()

    fun canGenerate(n: Int = 1): Boolean = remainingToday() >= n

    /**
     * n 회 사용 기록 — 오늘 한도부터 차감, 부족분은 크레딧에서.
     * DEBUG 는 no-op (차감 안 함). 반드시 생성 '성공 시에만' 호출할 것.
     */
    fun record(n: Int = 1) {
        if (BuildConfig.DEBUG) return
        if (n <= 0) return
        val today = todayStamp()
        val usedBase = computeUsedToday(prefs.getInt(DATE_KEY, 0), prefs.getInt(COUNT_KEY, 0), today)
        val result = computeRecord(n, usedBase, credits(), freeDailyLimit)
        val e = prefs.edit()
        e.putInt(DATE_KEY, today)
        e.putInt(COUNT_KEY, result.newUsed)
        if (result.creditsChanged) e.putInt(CREDITS_KEY, result.newCredits)
        e.apply()
    }

    /**
     * 퀄리티별 캔디 비용 (프레임 1장 기준) — high 6 · medium 3 · 기본(low) 1.
     * 움직이는 캐릭터는 frame0·frame1 을 각각 생성·과금하므로 호출 측이 프레임마다 record —
     * 여기서 2배 계산하지 말 것.
     */
    fun cost(forQuality: String): Int = when (forQuality) {
        "high" -> 6
        "medium" -> 3
        else -> 1
    }

    /** 캔디 팩 구매/코드 적용 시 크레딧 적립. */
    fun addCredits(n: Int) {
        if (n <= 0) return
        prefs.edit().putInt(CREDITS_KEY, credits() + n).apply()
    }

    /**
     * 서버 잔액(entitlement.credits)을 로컬에 반영 — delta > 0 만 가산.
     * 기준선이 없으면(최초 동기화) 서버 잔액이 더 클 때만 한 번 끌어올림. 기준선은 항상 갱신.
     */
    fun syncCreditsUp(serverCredits: Int) {
        val lastSynced = if (prefs.contains(LAST_SYNCED_SERVER_KEY)) {
            prefs.getInt(LAST_SYNCED_SERVER_KEY, 0)
        } else null
        val newCredits = computeSyncedCredits(credits(), lastSynced, serverCredits)
        prefs.edit()
            .putInt(CREDITS_KEY, newCredits)
            .putInt(LAST_SYNCED_SERVER_KEY, serverCredits)
            .apply()
    }

    /**
     * 로그아웃 시 서버 잔액 기준선 리셋 — 같은 기기 다른 계정의 delta 왜곡 방지.
     * 로컬 credits 는 유지 (미로그인 구매분 보호).
     */
    fun resetServerBaseline() {
        prefs.edit().remove(LAST_SYNCED_SERVER_KEY).apply()
    }

    /**
     * 화면 표시용 보유 캔디 = 로컬 잔액 그대로.
     * canGenerate 가 로컬 credits 만 보므로 배지도 같은 값 — 과대표시 방지.
     */
    fun displayedCandy(): Int = credits()

    // MARK: - 순수 코어 (단위 테스트 대상 — DEBUG 분기/SharedPreferences 와 분리)

    internal fun computeUsedToday(storedStamp: Int, storedCount: Int, todayStamp: Int): Int =
        if (storedStamp == todayStamp) storedCount else 0

    internal data class RecordResult(
        val newUsed: Int,
        val newCredits: Int,
        val creditsChanged: Boolean,
    )

    /** 오늘 무료 한도부터 차감, 부족분은 크레딧에서 (음수 방지 clamp). */
    internal fun computeRecord(n: Int, usedBase: Int, credits: Int, dailyAllowance: Int): RecordResult {
        val dailyLeft = max(0, dailyAllowance - usedBase)
        val fromDaily = min(n, dailyLeft)
        val fromCredits = n - fromDaily
        return RecordResult(
            newUsed = usedBase + fromDaily,
            newCredits = if (fromCredits > 0) max(0, credits - fromCredits) else credits,
            creditsChanged = fromCredits > 0,
        )
    }

    /**
     * syncCreditsUp 코어 — lastSynced 가 null(최초)이면 서버가 더 클 때만 끌어올리고,
     * 이후엔 delta > 0 만 가산 (delta < 0 은 무시 — 기준선만 갱신).
     */
    internal fun computeSyncedCredits(localCredits: Int, lastSynced: Int?, serverCredits: Int): Int {
        if (lastSynced == null) {
            return if (serverCredits > localCredits) serverCredits else localCredits
        }
        val delta = serverCredits - lastSynced
        return if (delta > 0) localCredits + delta else localCredits
    }
}
