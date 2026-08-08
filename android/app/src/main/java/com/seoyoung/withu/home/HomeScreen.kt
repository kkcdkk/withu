package com.seoyoung.withu.home

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.annotation.DrawableRes
import androidx.compose.foundation.Image
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
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
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.minimumInteractiveComponentSize
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
import com.seoyoung.withu.ui.PixelIcon
import com.seoyoung.withu.ui.PixelIconSet
import com.seoyoung.withu.ui.PixelToggle
import com.seoyoung.withu.ui.RefreshIconButton
import com.seoyoung.withu.ui.WithuTopBarTitle
import com.seoyoung.withu.ui.pixelCardSurface
import com.seoyoung.withu.ui.rememberBackgroundGradient
import com.seoyoung.withu.ui.theme.DungGeunMo
import com.seoyoung.withu.ui.theme.WithuColors
import com.seoyoung.withu.ui.theme.withuCardFill
import com.seoyoung.withu.ui.theme.withuPinkSoft
import com.seoyoung.withu.ui.theme.withuPinkText
import com.seoyoung.withu.ui.theme.withuPixelOutline
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

// 파일-로컬 헬퍼 (모듈 충돌 방지 위해 private) --------------------------------

/**
 * 손그림 픽셀 PNG — 컬러라 tint 를 씌우면 안 되므로 Icon 이 아니라 Image.
 * FilterQuality.None = iOS `.interpolation(.none)` (확대해도 도트가 뭉개지지 않음).
 */
@Composable
private fun PixelImage(@DrawableRes resId: Int, size: Dp, modifier: Modifier = Modifier) {
    Image(
        bitmap = ImageBitmap.imageResource(resId),
        contentDescription = null,
        modifier = modifier.size(size),
        filterQuality = FilterQuality.None,
    )
}

/** 활동 메시지 = 문구 + 옆에 붙는 손그림 아이콘 (iOS ContentView.swift ActivityMessage struct). */
private data class ActivityMessage(val text: String, @DrawableRes val asset: Int?)

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
    var activityMessage by remember { mutableStateOf(ActivityMessage("", null)) }
    var showWeather by remember { mutableStateOf(AppPrefs.showWeatherDecoration) }
    // 권한 배너/캐릭터 상태 재계산 트리거 (동기 API·DND·시간 반영)
    var tick by remember { mutableIntStateOf(0) }

    // 캐릭터 상태 — override 우선, 없으면 현재 신호 전부로 resolve (SyncCoordinator.currentState 재사용)
    val characterState = remember(override, profile, sleep, recentWorkouts, isInBed, tick) {
        SyncCoordinator.currentState()
    }

    // 날씨 조건 (야간 우선). 헤더 아이콘은 항상 이 값을 쓰고, 캐릭터 옆 데코만 showWeather 로 끈다
    // (iOS ContentView.swift:347 — showWeather 는 WeatherDecorationView 에만 걸린다).
    val weatherCondition = remember(weather, profile, tick) {
        weatherBackgroundCondition(weather, profile)
    }
    val decoration = if (showWeather) weatherCondition else null

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
                title = { WithuTopBarTitle(stringRes(R.string.home_title)) },
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
                iconCondition = weatherCondition,
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
                fontWeight = FontWeight.Bold,
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
    iconCondition: WeatherBackgroundCondition?,
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
            // 이모지 대신 캐릭터 옆 장식과 같은 픽셀 날씨 PNG (야간 판정 포함).
            // drawable 이름 해석은 WeatherDecoration.kt 와 같은 규칙 — weather_<raw>.
            val context = LocalContext.current
            val assetId = remember(iconCondition) {
                iconCondition?.let {
                    context.resources.getIdentifier("weather_${it.raw}", "drawable", context.packageName)
                } ?: 0
            }
            if (assetId != 0) PixelImage(assetId, 20.dp)
            Text(
                text = condition.caption,
                fontFamily = DungGeunMo,
                fontSize = 13.sp,
            )
            Text("·", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                text = "${temperatureC.roundToInt()}°",
                fontFamily = DungGeunMo,
                fontSize = 13.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            Text(
                text = stringRes(R.string.home_weather_loading),
                fontFamily = DungGeunMo,
                fontSize = 13.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.weight(1f))
        // 접근성 라벨 — iOS labelsHidden Toggle 의 '날씨 표시' 라벨 대응
        val weatherToggleLabel = stringRes(R.string.home_weather_toggle)
        PixelToggle(
            checked = showWeather,
            onCheckedChange = onToggleWeather,
            contentDescription = weatherToggleLabel,
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
    activityMessage: ActivityMessage,
    onRefresh: suspend () -> Unit,
) {
    // 갈색 바가 카드 최상단에 딱 붙도록 안쪽 padding 은 바 '아래' 컨텐츠에만
    // (iOS ContentView.swift:383-431 = VStack(spacing:0) + 바깥 pixelCardSurface).
    Column(modifier = Modifier.fillMaxWidth().pixelCardSurface()) {
        CardHeaderBar(title = stringRes(R.string.home_metrics_title)) {
            // 아이콘은 16dp 그대로, 터치 타깃만 최소 48dp 확보 (M3 접근성 기준)
            RefreshIconButton(
                action = onRefresh,
                modifier = Modifier.minimumInteractiveComponentSize(),
                tint = withuCardFill(),
            )
        }
        Column(
            modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                MetricItem(
                    value = steps?.let { it.toInt().toString() } ?: "-",
                    label = stringRes(R.string.home_metric_steps),
                    dim = (steps ?: 0.0).toInt() == 0,
                    modifier = Modifier.weight(1f),
                ) { PixelImage(R.drawable.metric_steps, 20.dp) }
                MetricDivider()
                MetricItem(
                    value = minutes?.let { it.toInt().toString() } ?: "-",
                    label = stringRes(R.string.home_metric_minutes),
                    dim = (minutes ?: 0.0).toInt() == 0,
                    modifier = Modifier.weight(1f),
                ) { PixelIcon(PixelIconSet.clock, withuPixelOutline(), size = 18.dp) }
                MetricDivider()
                MetricItem(
                    value = kcal?.let { it.toInt().toString() } ?: "-",
                    label = stringRes(R.string.home_metric_kcal),
                    dim = (kcal ?: 0.0).toInt() == 0,
                    modifier = Modifier.weight(1f),
                ) { PixelIcon(PixelIconSet.flame, withuPixelOutline(), size = 18.dp) }
                MetricDivider()
                MetricItem(
                    value = sleepHours?.let { "%.1fh".format(it) } ?: "-",
                    label = stringRes(R.string.home_metric_sleep),
                    dim = sleepHours == null,
                    modifier = Modifier.weight(1f),
                ) { PixelIcon(PixelIconSet.moon, withuPixelOutline(), size = 18.dp) }
            }
            if (activityMessage.text.isNotEmpty()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
                ) {
                    if (activityMessage.asset != null) PixelImage(activityMessage.asset, 18.dp)
                    Text(
                        text = activityMessage.text,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
    }
}

/** 카드 상단 갈색 바 — 크림 제목 + (선택) 우측 요소. iOS ContentView.swift:434-448 cardHeaderBar. */
@Composable
private fun CardHeaderBar(title: String, trailing: @Composable () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(withuPixelOutline())
            .padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = title,
            fontFamily = DungGeunMo,
            fontSize = 12.sp,
            color = withuCardFill(),
        )
        Spacer(Modifier.weight(1f))
        trailing()
    }
}

/** dim = 값이 0/없음 → 흐리고 작게. 의미값은 크고 또렷하게 (iOS ContentView.swift:458-473). */
@Composable
private fun MetricItem(
    value: String,
    label: String,
    dim: Boolean,
    modifier: Modifier = Modifier,
    icon: @Composable () -> Unit,
) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Box(Modifier.alpha(if (dim) 0.3f else 0.9f)) { icon() }
        Text(
            text = value,
            fontFamily = DungGeunMo,
            fontSize = if (dim) 15.sp else 19.sp,
            color = if (dim) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
        )
        Text(
            text = label,
            fontFamily = DungGeunMo,
            fontSize = 10.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
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

// MARK: - 액션 버튼 (히어로 1 + 2열 그리드 3)

/**
 * iOS ContentView.swift:515-580 대응 — 핵심 액션은 연초록 히어로 카드, 보조 3개는 2열 그리드.
 * LazyColumn/LazyVerticalGrid 중첩(스크롤 충돌)을 피해 Row 2줄로 흘린다 (iOS 도 3개 → 2행).
 */
@Composable
private fun ActionButtons(
    onOpenSingleGen: () -> Unit,
    onOpenCamera: () -> Unit,
    onOpenGallery: () -> Unit,
    onOpenProfile: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        HeroActionCard(
            asset = R.drawable.menu_wand,
            title = stringRes(R.string.home_btn_gen_title),
            subtitle = stringRes(R.string.home_btn_gen_sub),
            onClick = onOpenSingleGen,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            GridActionCard(
                asset = R.drawable.menu_camera,
                title = stringRes(R.string.home_btn_camera_title),
                subtitle = stringRes(R.string.home_btn_camera_sub),
                modifier = Modifier.weight(1f),
                onClick = onOpenCamera,
            )
            GridActionCard(
                asset = R.drawable.menu_gallery,
                title = stringRes(R.string.home_btn_gallery_title),
                subtitle = stringRes(R.string.home_btn_gallery_sub),
                modifier = Modifier.weight(1f),
                onClick = onOpenGallery,
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            GridActionCard(
                asset = R.drawable.menu_settings,
                title = stringRes(R.string.home_btn_profile_title),
                subtitle = stringRes(R.string.home_btn_profile_sub),
                modifier = Modifier.weight(1f),
                onClick = onOpenProfile,
            )
            // 3개가 2열이라 마지막 칸은 비움 (iOS LazyVGrid 와 같은 흐름)
            Spacer(Modifier.weight(1f))
        }
    }
}

@Composable
private fun HeroActionCard(
    @DrawableRes asset: Int,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .pixelCardSurface(fill = withuPinkSoft())
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        PixelImage(asset, 34.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(text = title, fontFamily = DungGeunMo, fontSize = 16.sp)
            Text(
                text = subtitle,
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = withuPinkText(),
            modifier = Modifier.size(16.dp),
        )
    }
}

@Composable
private fun GridActionCard(
    @DrawableRes asset: Int,
    title: String,
    subtitle: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Column(
        modifier = modifier
            .heightIn(min = 96.dp)
            .pixelCardSurface()
            .clickable(onClick = onClick)
            .padding(13.dp),
        horizontalAlignment = Alignment.Start,
        verticalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        PixelImage(asset, 30.dp)
        Text(text = title, fontFamily = DungGeunMo, fontSize = 13.sp, maxLines = 1)
        Text(
            text = subtitle,
            fontSize = 11.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 2,
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
        // 마지막 갱신 푸터 = Pretendard Light 10sp (iOS ContentView.swift:631)
        style = MaterialTheme.typography.labelSmall,
        fontSize = 10.sp,
        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
        modifier = Modifier.fillMaxWidth(),
        fontWeight = FontWeight.Light,
    )
}

// MARK: - 순수 헬퍼 (composable 아님)

/** 활동 메시지 계산 — iOS computeActivityMessage 이식 (진입/새로고침 시점에만 랜덤 확정). */
private fun computeActivityMessage(context: Context): ActivityMessage {
    val hour = LocalDateTime.now().hour
    val kcal = (HealthManager.todayActiveKcal.value ?: 0.0).toInt()
    val steps = (HealthManager.todaySteps.value ?: 0.0).toInt()
    val minutes = (HealthManager.todayActiveMinutes.value ?: 0.0).toInt()
    if (hour < 11 && kcal < 100) {
        val morning = listOf(
            R.string.home_msg_morning_1 to R.drawable.msg_sun,
            R.string.home_msg_morning_2 to R.drawable.msg_leaf,
            R.string.home_msg_morning_3 to R.drawable.msg_stretch,
            R.string.home_msg_morning_4 to R.drawable.msg_water,
        )
        val (id, asset) = morning.random()
        return ActivityMessage(context.getString(id), asset)
    }
    if (kcal >= 400 || minutes >= 60 || steps >= 10000) {
        return ActivityMessage(context.getString(R.string.home_msg_active), R.drawable.msg_stretch)
    }
    if (kcal >= 150 || steps >= 4000) {
        return ActivityMessage(context.getString(R.string.home_msg_normal, steps), R.drawable.msg_leaf)
    }
    return ActivityMessage(context.getString(R.string.home_msg_lazy), R.drawable.msg_leaf)
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
