package com.seoyoung.withu.home

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.repeatOnLifecycle
import com.seoyoung.withu.R
import com.seoyoung.withu.character.CharacterHero
import com.seoyoung.withu.character.CharacterProfile
import com.seoyoung.withu.character.CharacterProfileStore
import com.seoyoung.withu.health.HealthManager
import com.seoyoung.withu.notify.NotificationHelper
import com.seoyoung.withu.shared.AppPrefs
import com.seoyoung.withu.shared.CharacterImageStore
import com.seoyoung.withu.shared.StoreEvents
import com.seoyoung.withu.shared.WeatherBackgroundCondition
import com.seoyoung.withu.sync.SyncCoordinator
import com.seoyoung.withu.ui.ActionLinkRow
import com.seoyoung.withu.ui.RefreshIconButton
import com.seoyoung.withu.ui.rememberBackgroundGradient
import com.seoyoung.withu.ui.theme.WithuColors
import com.seoyoung.withu.ui.theme.withuGreen
import com.seoyoung.withu.ui.theme.withuHeroPink
import com.seoyoung.withu.weather.WeatherCondition
import com.seoyoung.withu.weather.WeatherManager
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.roundToInt

/** 프로필 브라운 (iOS systemBrown) — Theme 에 없어 홈/설정에서만 쓰는 로컬 상수. */
private val ProfileBrown = Color(0xFFA2845E)

// 파일-로컬 헬퍼 (모듈 충돌 방지 위해 private) --------------------------------

@Composable
private fun stringRes(id: Int): String = stringResource(id)

@Composable
private fun stringRes(id: Int, vararg args: Any): String = stringResource(id, *args)

@Composable
private fun <T> StateFlow<T>.collectAsStateCompat(): State<T> = collectAsState()

/** epoch millis → 짧은 시각 (현지). */
private fun formatTimeShort(epochMillis: Long): String {
    val t = Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault()).toLocalTime()
    return t.format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT))
}

/**
 * 홈 화면 — iOS ContentView 대응 (스펙 01).
 * 세로 스크롤: 권한배너 · 날씨헤더 · 캐릭터히어로 · 오늘활동 카드 · 액션버튼 4 · 마지막갱신 푸터.
 * 워치 카드는 SCOPE 제외. 네비게이션은 전부 콜백.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    onOpenSingleGen: () -> Unit,
    onOpenBatchGen: () -> Unit,
    onOpenCamera: () -> Unit,
    onOpenGallery: () -> Unit,
    onOpenProfile: () -> Unit,
    onOpenDiagnostics: () -> Unit,
    onShowHelp: () -> Unit,
    onReonboard: () -> Unit,
    openBatchFromNotification: Boolean = false,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val lifecycleOwner = LocalLifecycleOwner.current

    // --- 저장소/매니저 상태 구독 ---
    val weather by WeatherManager.snapshot.collectAsStateCompat()
    val isFetchingWeather by WeatherManager.isFetching.collectAsStateCompat()
    val profile by CharacterProfileStore.profileFlow.collectAsStateCompat()
    val override by SyncCoordinator.overrideState.collectAsStateCompat()
    val isHealthAuthorized by HealthManager.isAuthorized.collectAsStateCompat()
    val todaySteps by HealthManager.todaySteps.collectAsStateCompat()
    val todayMinutes by HealthManager.todayActiveMinutes.collectAsStateCompat()
    val todayKcal by HealthManager.todayActiveKcal.collectAsStateCompat()
    val sleep by HealthManager.sleep.collectAsStateCompat()
    val recentWorkouts by HealthManager.recentWorkouts.collectAsStateCompat()
    val isInBed by HealthManager.isInBedSchedule.collectAsStateCompat()

    // --- 메모리 상태 ---
    var showSettings by remember { mutableStateOf(false) }
    var imageRefreshKey by remember { mutableIntStateOf(0) }
    var activityMessage by remember { mutableStateOf("") }
    var showWeather by remember { mutableStateOf(AppPrefs.showWeatherDecoration) }
    // 권한 배너/캐릭터 상태 재계산 트리거 (동기 API·DND·시간 반영)
    var tick by remember { mutableIntStateOf(0) }

    // 캐릭터 상태 — override 우선, 없으면 현재 신호 전부로 resolve (SyncCoordinator.currentState 재사용)
    val characterState = remember(override, profile, sleep, recentWorkouts, isInBed, tick) {
        SyncCoordinator.currentState()
    }

    // 날씨 데코 조건 (야간 우선) — showWeather 켜졌을 때만 히어로에 오버레이
    val decoration = remember(weather, profile, tick, showWeather) {
        if (!showWeather) null else weatherBackgroundCondition(weather, profile)
    }

    // 진입: 날씨 + 건강 일괄 로드 → 활동 메시지 계산 → sync
    LaunchedEffect(Unit) {
        HealthManager.refreshAuthorizationStatus()
        NotificationHelper.ensureChannels()
        scope.launch { WeatherManager.refresh() }
        HealthManager.loadAll()
        activityMessage = computeActivityMessage(context)
        SyncCoordinator.syncNow()
        // 첫 실행 사용법 안내 (onboarded 는 게이트에서 이미 통과) — 1회만
        if (!AppPrefs.seenGuide) {
            AppPrefs.seenGuide = true
            onShowHelp()
        }
    }

    // 알림 탭 cold start → 배치 화면 진입 (1회)
    LaunchedEffect(openBatchFromNotification) {
        if (openBatchFromNotification) onOpenBatchGen()
    }

    // 이미지 변경 브로드캐스트 → 히어로 강제 재로드
    LaunchedEffect(Unit) {
        StoreEvents.characterImageChanged.collect { imageRefreshKey++ }
    }

    // 30초 폴링 (STARTED 동안만) — Health Connect 재조회 + 운동 추론 + sync (iOS 30초 타이머 이식)
    LaunchedEffect(Unit) {
        lifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (isActive) {
                delay(30_000)
                // 일일 지표(걸음/kcal/활동분/수면) 재조회 — 세션 중 프리즈 방지 + step-goal 알림 발화 (iOS 30초 타이머 이식)
                HealthManager.loadAll()
                HealthManager.fetchInBedSchedule()
                HealthManager.refreshWorkoutInference()
                tick++
                SyncCoordinator.syncNow()
            }
        }
    }

    // 화면 복귀 시 권한/상태 재확인
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                tick++
                scope.launch { HealthManager.refreshAuthorizationStatus() }
                // 복귀 시 일일 지표도 재조회 (세션 중 프리즈 방지)
                scope.launch { HealthManager.loadAll() }
                scope.launch { WeatherManager.refresh() }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    // 상태/걸음/운동 변경 → sync + 알림 (iOS onChange 대응)
    LaunchedEffect(characterState) { SyncCoordinator.syncNow() }
    LaunchedEffect(todaySteps) { todaySteps?.let { NotificationHelper.scheduleStepGoalIfNeeded(it) } }
    LaunchedEffect(recentWorkouts) { NotificationHelper.scheduleWorkoutEndedIfNeeded(recentWorkouts.firstOrNull()) }

    val gradient = rememberBackgroundGradient(characterState)

    // 권한 배너 목록
    val denied = buildList {
        if (!isHealthAuthorized) add(context.getString(R.string.home_perm_health))
        if (!WeatherManager.hasLocationPermission()) add(context.getString(R.string.home_perm_location))
        if (!NotificationHelper.hasPermission()) add(context.getString(R.string.home_perm_notifications))
        // tick 을 참조해 resume/폴링 때 재계산되도록
        if (tick < 0) add("")
    }

    Scaffold(
        containerColor = Color.Transparent,
        topBar = {
            CenterAlignedTopAppBar(
                title = {
                    Text(
                        text = stringRes(R.string.home_title),
                        fontWeight = FontWeight.SemiBold,
                    )
                },
                actions = {
                    IconButton(onClick = { showSettings = true }) {
                        Icon(Icons.Filled.Settings, contentDescription = stringRes(R.string.settings_title))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
            )
        },
        modifier = Modifier.background(gradient),
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(top = 8.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            if (denied.isNotEmpty()) {
                PermissionBanner(names = denied, onClick = { openAppSettings(context) })
            }
            WeatherHeader(
                condition = weather?.condition,
                temperatureC = weather?.temperatureC,
                isFetching = isFetchingWeather,
                showWeather = showWeather,
                onToggleWeather = {
                    showWeather = it
                    AppPrefs.showWeatherDecoration = it
                },
                onRefresh = { scope.launch { WeatherManager.refresh(force = true) } },
            )
            CharacterHero(
                state = characterState,
                refreshKey = imageRefreshKey,
                decoration = decoration,
            )
            MetricsCard(
                steps = todaySteps,
                minutes = todayMinutes,
                kcal = todayKcal,
                sleepHours = sleep?.takeIf { it.totalAsleepSeconds > 0 }?.let { it.totalAsleepSeconds / 3600.0 },
                activityMessage = activityMessage,
                onRefresh = {
                    HealthManager.loadAll()
                    activityMessage = computeActivityMessage(context)
                    SyncCoordinator.syncNow()
                },
            )
            ActionButtons(
                onOpenSingleGen = onOpenSingleGen,
                onOpenCamera = onOpenCamera,
                onOpenGallery = onOpenGallery,
                onOpenProfile = onOpenProfile,
            )
            LastUpdateFooter(tick)
        }
    }

    if (showSettings) {
        SettingsSheet(
            onClose = { showSettings = false },
            onOpenProfile = { showSettings = false; onOpenProfile() },
            onOpenDiagnostics = { showSettings = false; onOpenDiagnostics() },
            onShowHelp = { showSettings = false; onShowHelp() },
            onReonboard = { showSettings = false; onReonboard() },
        )
    }
}

// MARK: - 권한 배너

@Composable
private fun PermissionBanner(names: List<String>, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .background(WithuColors.systemOrange.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(
            Icons.Filled.Warning,
            contentDescription = null,
            tint = WithuColors.systemOrange,
            modifier = Modifier.size(20.dp),
        )
        Column(Modifier.weight(1f)) {
            Text(
                text = stringRes(R.string.home_perm_title, names.joinToString(" · ")),
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = stringRes(R.string.home_perm_sub),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(16.dp),
        )
    }
}

// MARK: - 날씨 헤더

@Composable
private fun WeatherHeader(
    condition: WeatherCondition?,
    temperatureC: Double?,
    isFetching: Boolean,
    showWeather: Boolean,
    onToggleWeather: (Boolean) -> Unit,
    onRefresh: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (condition != null && temperatureC != null) {
            Text(
                text = "${condition.emoji} ${condition.caption}",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
            )
            Text("·", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                text = "${temperatureC.roundToInt()}°",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            Text(
                text = stringRes(R.string.home_weather_loading),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.weight(1f))
        // 접근성 라벨 — iOS labelsHidden Toggle 의 '날씨 표시' 라벨 대응
        val weatherToggleLabel = stringRes(R.string.home_weather_toggle)
        Switch(
            checked = showWeather,
            onCheckedChange = onToggleWeather,
            modifier = Modifier.semantics { contentDescription = weatherToggleLabel },
        )
        Spacer(Modifier.width(4.dp))
        if (isFetching) {
            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
        } else {
            IconButton(onClick = onRefresh, modifier = Modifier.size(28.dp)) {
                Icon(
                    Icons.Filled.Refresh,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(16.dp),
                )
            }
        }
    }
}

// MARK: - 오늘 활동 카드

@Composable
private fun MetricsCard(
    steps: Double?,
    minutes: Double?,
    kcal: Double?,
    sleepHours: Double?,
    activityMessage: String,
    onRefresh: suspend () -> Unit,
) {
    val shape = RoundedCornerShape(18.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.72f), shape)
            .padding(vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = stringRes(R.string.home_metrics_title),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.weight(1f))
            RefreshIconButton(action = onRefresh)
        }
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            MetricItem("👟", steps?.let { it.toInt().toString() } ?: "-", stringRes(R.string.home_metric_steps), Modifier.weight(1f))
            MetricDivider()
            MetricItem("🏃", minutes?.let { it.toInt().toString() } ?: "-", stringRes(R.string.home_metric_minutes), Modifier.weight(1f))
            MetricDivider()
            MetricItem("🔥", kcal?.let { it.toInt().toString() } ?: "-", stringRes(R.string.home_metric_kcal), Modifier.weight(1f))
            MetricDivider()
            MetricItem("💤", sleepHours?.let { "%.1fh".format(it) } ?: "-", stringRes(R.string.home_metric_sleep), Modifier.weight(1f))
        }
        if (activityMessage.isNotEmpty()) {
            Text(
                text = activityMessage,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 14.dp),
            )
        }
    }
}

@Composable
private fun MetricItem(emoji: String, value: String, label: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(emoji, style = MaterialTheme.typography.bodyMedium)
        Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun MetricDivider() {
    Box(
        Modifier
            .width(1.dp)
            .height(32.dp)
            .background(MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)),
    )
}

// MARK: - 액션 버튼 4개

@Composable
private fun ActionButtons(
    onOpenSingleGen: () -> Unit,
    onOpenCamera: () -> Unit,
    onOpenGallery: () -> Unit,
    onOpenProfile: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ActionLinkRow(
            tint = withuHeroPink(),
            icon = Icons.Filled.AutoAwesome,
            title = stringRes(R.string.home_btn_gen_title),
            subtitle = stringRes(R.string.home_btn_gen_sub),
            onClick = onOpenSingleGen,
        )
        ActionLinkRow(
            tint = withuGreen(),
            icon = Icons.Filled.PhotoCamera,
            title = stringRes(R.string.home_btn_camera_title),
            subtitle = stringRes(R.string.home_btn_camera_sub),
            onClick = onOpenCamera,
        )
        ActionLinkRow(
            tint = WithuColors.systemMint,
            icon = Icons.Filled.PhotoLibrary,
            title = stringRes(R.string.home_btn_gallery_title),
            subtitle = stringRes(R.string.home_btn_gallery_sub),
            onClick = onOpenGallery,
        )
        ActionLinkRow(
            tint = ProfileBrown,
            icon = Icons.Filled.AccountCircle,
            title = stringRes(R.string.home_btn_profile_title),
            subtitle = stringRes(R.string.home_btn_profile_sub),
            onClick = onOpenProfile,
        )
    }
}

// MARK: - 마지막 갱신 푸터

@Composable
private fun LastUpdateFooter(tick: Int) {
    // tick(폴링/복귀 시 증가) 마다 재조회 — iOS 매 렌더 계산되는 computed property 대응
    val bgAt = remember(tick) { AppPrefs.lastBackgroundRefreshAt }
    val text = if (bgAt != null) {
        stringRes(R.string.home_footer_last_update, formatTimeShort(bgAt))
    } else {
        stringRes(R.string.home_footer_waiting)
    }
    Text(
        text = text,
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
        modifier = Modifier.fillMaxWidth(),
        fontWeight = FontWeight.Normal,
    )
}

// MARK: - 순수 헬퍼 (composable 아님)

/** 활동 메시지 계산 — iOS computeActivityMessage 이식 (진입/새로고침 시점에만 랜덤 확정). */
private fun computeActivityMessage(context: Context): String {
    val hour = LocalDateTime.now().hour
    val kcal = (HealthManager.todayActiveKcal.value ?: 0.0).toInt()
    val steps = (HealthManager.todaySteps.value ?: 0.0).toInt()
    val minutes = (HealthManager.todayActiveMinutes.value ?: 0.0).toInt()
    if (hour < 11 && kcal < 100) {
        val ids = listOf(
            R.string.home_msg_morning_1, R.string.home_msg_morning_2,
            R.string.home_msg_morning_3, R.string.home_msg_morning_4,
        )
        return context.getString(ids.random())
    }
    if (kcal >= 400 || minutes >= 60 || steps >= 10000) return context.getString(R.string.home_msg_active)
    if (kcal >= 150 || steps >= 4000) return context.getString(R.string.home_msg_normal, steps)
    return context.getString(R.string.home_msg_lazy)
}

/** 현재 시각 + 날씨 → 배경 condition (야간 우선). iOS weatherBackgroundCondition 이식. */
private fun weatherBackgroundCondition(
    weather: com.seoyoung.withu.weather.WeatherSnapshot?,
    profile: CharacterProfile,
): WeatherBackgroundCondition? {
    val now = LocalDateTime.now()
    val nowMin = now.hour * 60 + now.minute
    val sunriseMin = weather?.sunrise?.let { minuteOfDay(it) }
    val sunsetMin = weather?.sunset?.let { minuteOfDay(it) }
    val isNight = CharacterImageStore.isCurrentlyNight(
        nowMinuteOfDay = nowMin,
        sunriseMinuteOfDay = sunriseMin,
        sunsetMinuteOfDay = sunsetMin,
        fallbackStartMinute = profile.effectiveNightFallbackStart,
        fallbackEndMinute = profile.effectiveNightFallbackEnd,
    )
    if (isNight) return WeatherBackgroundCondition.NIGHT
    return when (weather?.condition) {
        WeatherCondition.SUNNY -> WeatherBackgroundCondition.SUNNY
        WeatherCondition.CLOUDY -> WeatherBackgroundCondition.CLOUDY
        WeatherCondition.RAINY, WeatherCondition.THUNDER -> WeatherBackgroundCondition.RAINY
        WeatherCondition.SNOWY -> WeatherBackgroundCondition.SNOWY
        else -> null
    }
}

private fun minuteOfDay(epochMillis: Long): Int {
    val t = Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault()).toLocalTime()
    return t.hour * 60 + t.minute
}

private fun openAppSettings(context: Context) {
    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
        data = Uri.fromParts("package", context.packageName, null)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    runCatching { context.startActivity(intent) }
}
