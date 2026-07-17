package com.seoyoung.withu.weather

import android.Manifest
import android.content.pm.PackageManager
import android.location.Location
import androidx.core.content.ContextCompat
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import com.seoyoung.withu.R
import com.seoyoung.withu.WithuApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.math.roundToInt

/**
 * 날씨 매니저 — iOS WeatherManager.swift 포팅 (스펙 10 §3.1).
 * 위치(coarse) → Open-Meteo → WeatherSnapshot. API 키 불필요 (무료).
 * 캐시는 메모리 전용 30분 TTL — 디스크 캐시 추가하지 말 것 (iOS 파리티).
 */
object WeatherManager {
    /** 메모리 캐시 TTL — iOS cacheTTL = 30 * 60초. */
    private const val CACHE_TTL_MS = 30L * 60L * 1000L

    private val _snapshot = MutableStateFlow<WeatherSnapshot?>(null)
    val snapshot: StateFlow<WeatherSnapshot?> = _snapshot

    private val _isFetching = MutableStateFlow(false)
    val isFetching: StateFlow<Boolean> = _isFetching

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError

    // 날씨는 짧은 요청 — 생성 API 의 30분 timeout 을 공유하지 않는다.
    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    private val json = Json { ignoreUnknownKeys = true }

    /** Open-Meteo 일출/일몰 포맷 — 오프셋 없는 위치 로컬 시각 (timezone=auto). */
    private val sunFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm")

    fun hasLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(
            WithuApp.context, Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(
                WithuApp.context, Manifest.permission.ACCESS_FINE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED

    /**
     * 새로고침. force=false 이고 30분 캐시가 살아 있으면 아무것도 안 함.
     * 권한 없음/위치 실패/네트워크 실패는 lastError 에 문구 세팅 (throw 안 함 — iOS 동일).
     */
    suspend fun refresh(force: Boolean = false) {
        val cached = _snapshot.value
        if (!force && cached != null &&
            System.currentTimeMillis() - cached.timestamp < CACHE_TTL_MS
        ) return
        if (_isFetching.value) return   // 중복 진입 방지 (권한 시트 표시 중 등)

        _isFetching.value = true
        _lastError.value = null
        try {
            if (!hasLocationPermission()) {
                // 권한 요청 UI 는 화면(홈) 소관 — 매니저는 상태만 보고
                _lastError.value = WithuApp.context.getString(R.string.weather_err_denied)
                return
            }
            val location = try {
                currentLocation()
            } catch (e: SecurityException) {
                _lastError.value = WithuApp.context.getString(R.string.weather_err_denied)
                return
            } catch (e: Exception) {
                _lastError.value =
                    WithuApp.context.getString(R.string.weather_err_location_failed, e.message ?: "?")
                return
            }
            if (location == null) {
                _lastError.value = WithuApp.context.getString(R.string.weather_err_no_location)
                return
            }
            // 좌표는 소수 2자리(~1km)로 반올림 — 날씨엔 충분하고, 정확한 위치가
            // 기기 밖(타사 API)으로 나가지 않게 (App Privacy: '대략적 위치').
            fetchOpenMeteo(round2(location.latitude), round2(location.longitude))
        } finally {
            _isFetching.value = false
        }
    }

    private fun round2(v: Double): Double = (v * 100).roundToInt() / 100.0

    /** 1회 위치 요청 — km 급 정확도(BALANCED)면 충분. 실패 시 마지막 위치 fallback. */
    private suspend fun currentLocation(): Location? = withContext(Dispatchers.IO) {
        val fused = LocationServices.getFusedLocationProviderClient(WithuApp.context)
        val cts = CancellationTokenSource()
        suspendCancellableCoroutine { cont ->
            cont.invokeOnCancellation { cts.cancel() }
            fused.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, cts.token)
                .addOnSuccessListener { loc ->
                    if (loc != null) {
                        cont.resume(loc)
                    } else {
                        // getCurrentLocation 이 null 을 줄 수 있음 → 캐시된 마지막 위치로 한 번 더
                        fused.lastLocation
                            .addOnSuccessListener { last -> cont.resume(last) }
                            .addOnFailureListener { cont.resume(null) }
                    }
                }
                .addOnFailureListener { e -> if (cont.isActive) cont.resumeWith(Result.failure(e)) }
        }
    }

    private suspend fun fetchOpenMeteo(lat: Double, lon: Double) = withContext(Dispatchers.IO) {
        val url = "https://api.open-meteo.com/v1/forecast" +
            "?latitude=$lat&longitude=$lon" +
            "&current=temperature_2m,weather_code" +
            "&daily=sunrise,sunset&timezone=auto"
        val text = try {
            client.newCall(Request.Builder().url(url).build()).execute().use { resp ->
                if (!resp.isSuccessful) {
                    _lastError.value = WithuApp.context.getString(
                        R.string.weather_err_network, "HTTP ${resp.code}",
                    )
                    return@withContext
                }
                resp.body?.string().orEmpty()
            }
        } catch (e: Exception) {
            _lastError.value =
                WithuApp.context.getString(R.string.weather_err_network, e.message ?: "?")
            return@withContext
        }
        val parsed = try {
            json.decodeFromString<OpenMeteoResponse>(text)
        } catch (e: Exception) {
            _lastError.value =
                WithuApp.context.getString(R.string.weather_err_decoding, e.message ?: "?")
            return@withContext
        }
        _snapshot.value = WeatherSnapshot(
            condition = WeatherCondition.fromWmo(parsed.current.weatherCode),
            temperatureC = parsed.current.temperature2m,
            timestamp = System.currentTimeMillis(),
            sunrise = parseSunTime(parsed.daily?.sunrise?.firstOrNull()),
            sunset = parseSunTime(parsed.daily?.sunset?.firstOrNull()),
        )
        _lastError.value = null
    }

    /**
     * "yyyy-MM-dd'T'HH:mm" (위치 로컬 시각) → epoch millis.
     * timezone=auto 로 요청했으므로 위치 로컬 TZ = 사용자 TZ 라고 가정하고
     * 기기 로컬 TZ 로 파싱 (대부분 케이스 — iOS 동일 가정). 실패 시 null.
     */
    private fun parseSunTime(raw: String?): Long? {
        if (raw == null) return null
        return runCatching {
            LocalDateTime.parse(raw, sunFormatter)
                .atZone(ZoneId.systemDefault())
                .toInstant()
                .toEpochMilli()
        }.getOrNull()
    }

    // MARK: - Open-Meteo 응답 DTO (snake_case 그대로 매핑)

    @Serializable
    private data class OpenMeteoResponse(
        val current: OpenMeteoCurrent,
        val daily: OpenMeteoDaily? = null,
    )

    @Serializable
    private data class OpenMeteoCurrent(
        @SerialName("temperature_2m") val temperature2m: Double,
        @SerialName("weather_code") val weatherCode: Int,
    )

    @Serializable
    private data class OpenMeteoDaily(
        val sunrise: List<String> = emptyList(),
        val sunset: List<String> = emptyList(),
    )
}
