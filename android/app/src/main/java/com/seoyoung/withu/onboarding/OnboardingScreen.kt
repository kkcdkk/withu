package com.seoyoung.withu.onboarding

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.Crossfade
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoFixHigh
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.MonitorHeart
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.WbCloudy
import androidx.compose.material.icons.filled.Widgets
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.health.connect.client.PermissionController
import com.seoyoung.withu.R
import com.seoyoung.withu.health.HealthManager
import com.seoyoung.withu.notify.NotificationHelper
import com.seoyoung.withu.ui.StatusKind
import com.seoyoung.withu.ui.StatusPill
import com.seoyoung.withu.ui.WithuCTAButton
import com.seoyoung.withu.ui.theme.WithuColors
import com.seoyoung.withu.ui.theme.withuPink
import com.seoyoung.withu.ui.theme.withuPinkBackground
import com.seoyoung.withu.ui.theme.withuPinkText
import com.seoyoung.withu.weather.WeatherManager
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * 온보딩 — iOS OnboardingView.swift 포팅 (스펙 06).
 *
 * 권한 4종(건강·위치·알림·수면)을 한 페이지씩 요청하고, 거절/건너뛰기가 절대 흐름을
 * 막지 않는다 (iOS 원본 설계 의도). 요청 결과 후 0.5초 대기해 pill 이 잠깐 보인 뒤 자동 진행.
 * 뒤로가기 없음 — 스텝은 앞으로만 간다.
 *
 * Android 근사 (스펙 06 §5):
 *  - health → Health Connect 권한. 미설치/미지원 기기면 denied 로 처리하고 진행.
 *  - location → ACCESS_COARSE_LOCATION (반올림 2자리라 coarse 로 충분).
 *  - notification → API 33+ POST_NOTIFICATIONS, 그 이하는 권한 개념 없어 즉시 granted.
 *  - focus → Android 직접 대응물 없음. 수면 감지는 방해 금지(DND) 읽기로 권한 없이 동작하므로
 *    '허용하고 다음으로' 는 곧바로 연결됨 처리한다.
 */

/** 온보딩 스텝 (순서 고정). progressIndex 는 진행 바 캡슐 인덱스(welcome 제외 5칸). */
private enum class OnboardingStep(val progressIndex: Int) {
    WELCOME(-1), HEALTH(0), LOCATION(1), NOTIFICATION(2), FOCUS(3), DONE(4);
}

/** 권한 요청 결과 — StatusPill 매핑에 사용. */
private enum class PermissionResult { PENDING, REQUESTING, GRANTED, DENIED, SKIPPED }

@Composable
fun OnboardingScreen(onComplete: () -> Unit) {
    val scope = rememberCoroutineScope()

    var step by remember { mutableStateOf(OnboardingStep.WELCOME) }
    var healthResult by remember { mutableStateOf(PermissionResult.PENDING) }
    var locationResult by remember { mutableStateOf(PermissionResult.PENDING) }
    var notificationResult by remember { mutableStateOf(PermissionResult.PENDING) }
    var focusResult by remember { mutableStateOf(PermissionResult.PENDING) }

    fun resultOf(s: OnboardingStep): PermissionResult = when (s) {
        OnboardingStep.HEALTH -> healthResult
        OnboardingStep.LOCATION -> locationResult
        OnboardingStep.NOTIFICATION -> notificationResult
        OnboardingStep.FOCUS -> focusResult
        else -> PermissionResult.PENDING
    }

    fun setResult(s: OnboardingStep, r: PermissionResult) {
        when (s) {
            OnboardingStep.HEALTH -> healthResult = r
            OnboardingStep.LOCATION -> locationResult = r
            OnboardingStep.NOTIFICATION -> notificationResult = r
            OnboardingStep.FOCUS -> focusResult = r
            else -> Unit
        }
    }

    fun advance() {
        step = when (step) {
            OnboardingStep.WELCOME -> OnboardingStep.HEALTH
            OnboardingStep.HEALTH -> OnboardingStep.LOCATION
            OnboardingStep.LOCATION -> OnboardingStep.NOTIFICATION
            OnboardingStep.NOTIFICATION -> OnboardingStep.FOCUS
            OnboardingStep.FOCUS -> OnboardingStep.DONE
            OnboardingStep.DONE -> OnboardingStep.DONE // done 은 버튼이 직접 onComplete
        }
    }

    val context = androidx.compose.ui.platform.LocalContext.current
    // Health Connect 권한 요청 — 결과에 필수 권한이 모두 있으면 granted.
    val healthLauncher = rememberLauncherForActivityResult(
        PermissionController.createRequestPermissionResultContract(),
    ) { granted ->
        // 하나라도 허용되면 GRANTED (부분 허용도 동작 — HealthManager.isAuthorized 와 동일 기준).
        val ok = HealthManager.requiredPermissions().any { it in granted }
        setResult(OnboardingStep.HEALTH, if (ok) PermissionResult.GRANTED else PermissionResult.DENIED)
    }
    // 폰 모션 감지 권한(ACTIVITY_RECOGNITION) — 건강 스텝에서 먼저 물어보고, 결과와 무관하게
    // Health Connect 로 이어짐. 허용되면 워치 없이도 산책/달리기/자전거 감지(iOS CoreMotion 대응).
    val motionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) runCatching { com.seoyoung.withu.health.MotionActivityManager.start(context) }
        // 모션 허용 여부와 상관없이 건강(Health Connect) 요청으로 진행.
        if (HealthManager.isAvailable()) healthLauncher.launch(HealthManager.requiredPermissions())
        else setResult(OnboardingStep.HEALTH, PermissionResult.DENIED)
    }
    // 위치 권한 (coarse)
    val locationLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        setResult(OnboardingStep.LOCATION, if (granted) PermissionResult.GRANTED else PermissionResult.DENIED)
        if (granted) scope.launch { runCatching { WeatherManager.refresh(force = true) } }
    }
    // 알림 권한 (API 33+)
    val notificationLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        setResult(OnboardingStep.NOTIFICATION, if (granted) PermissionResult.GRANTED else PermissionResult.DENIED)
        if (granted) NotificationHelper.ensureChannels()
    }

    // 요청 결과가 확정되면 0.5초 뒤 자동 진행 (iOS Task.sleep 0.5 대응).
    LaunchedEffect(step, resultOf(step)) {
        val r = resultOf(step)
        val isPermissionStep = step != OnboardingStep.WELCOME && step != OnboardingStep.DONE
        if (isPermissionStep && (r == PermissionResult.GRANTED || r == PermissionResult.DENIED)) {
            delay(500)
            advance()
        }
    }

    // 스텝별 권한 요청 시작.
    fun request(s: OnboardingStep) {
        setResult(s, PermissionResult.REQUESTING)
        when (s) {
            OnboardingStep.HEALTH -> {
                // 먼저 폰 모션 권한(API29+) → 그 콜백이 Health Connect 로 이어짐 (motionLauncher).
                // API28 이하는 모션이 install-time 권한이라 바로 건강으로.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    motionLauncher.launch(Manifest.permission.ACTIVITY_RECOGNITION)
                } else if (HealthManager.isAvailable()) {
                    healthLauncher.launch(HealthManager.requiredPermissions())
                } else {
                    setResult(s, PermissionResult.DENIED)
                }
            }
            OnboardingStep.LOCATION -> locationLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
            OnboardingStep.NOTIFICATION -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                } else {
                    // API 32 이하 — 런타임 권한 개념 없음 → 즉시 granted.
                    NotificationHelper.ensureChannels()
                    setResult(s, PermissionResult.GRANTED)
                }
            }
            OnboardingStep.FOCUS -> {
                // DND 읽기는 권한 불필요 → 곧바로 연결됨.
                setResult(s, PermissionResult.GRANTED)
            }
            else -> Unit
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(onboardingBackground())
            // edge-to-edge(target 35) — 상단 상태바 인셋만 배경 위에서 소비.
            // 하단 제스처바는 버튼 Column 에서 따로 처리(배경은 끝까지 채우되 버튼만 띄움).
            .statusBarsPadding(),
    ) {
        Column(Modifier.fillMaxSize()) {
            // 진행 바 (welcome 제외)
            if (step != OnboardingStep.WELCOME) {
                ProgressBar(progressIndex = step.progressIndex)
            }

            // 본문 — 스텝 교체 시 opacity 전환 (iOS transition(.opacity)).
            Crossfade(targetState = step, label = "onboardingStep") { s ->
                Column(
                    Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Spacer(Modifier.height(24.dp))
                    when (s) {
                        OnboardingStep.WELCOME -> WelcomeContent()
                        OnboardingStep.HEALTH -> PermissionPage(
                            icon = Icons.Filled.MonitorHeart,
                            tint = WithuColors.systemMint,
                            title = stringResource(R.string.onboarding_health_title),
                            body = stringResource(R.string.onboarding_health_body),
                            details = listOf(
                                stringResource(R.string.onboarding_health_detail1),
                                stringResource(R.string.onboarding_health_detail2),
                                stringResource(R.string.onboarding_health_detail3),
                            ),
                            skipNote = stringResource(R.string.onboarding_health_skip_note),
                            result = resultOf(s),
                        )
                        OnboardingStep.LOCATION -> PermissionPage(
                            icon = Icons.Filled.WbCloudy,
                            tint = WithuColors.systemCyan,
                            title = stringResource(R.string.onboarding_location_title),
                            body = stringResource(R.string.onboarding_location_body),
                            details = listOf(
                                stringResource(R.string.onboarding_location_detail1),
                                stringResource(R.string.onboarding_location_detail2),
                                stringResource(R.string.onboarding_location_detail3),
                            ),
                            skipNote = null,
                            result = resultOf(s),
                        )
                        OnboardingStep.NOTIFICATION -> PermissionPage(
                            icon = Icons.Filled.NotificationsActive,
                            tint = WithuColors.systemOrange,
                            title = stringResource(R.string.onboarding_notification_title),
                            body = stringResource(R.string.onboarding_notification_body),
                            details = listOf(
                                stringResource(R.string.onboarding_notification_detail1),
                                stringResource(R.string.onboarding_notification_detail2),
                            ),
                            skipNote = null,
                            result = resultOf(s),
                        )
                        OnboardingStep.FOCUS -> PermissionPage(
                            icon = Icons.Filled.Bedtime,
                            tint = WithuColors.systemIndigo,
                            title = stringResource(R.string.onboarding_focus_title),
                            body = stringResource(R.string.onboarding_focus_body),
                            details = listOf(
                                stringResource(R.string.onboarding_focus_detail1),
                                stringResource(R.string.onboarding_focus_detail2),
                                stringResource(R.string.onboarding_focus_detail3),
                            ),
                            skipNote = null,
                            result = resultOf(s),
                        )
                        OnboardingStep.DONE -> DoneContent(
                            healthResult = healthResult,
                            locationResult = locationResult,
                            notificationResult = notificationResult,
                            focusResult = focusResult,
                        )
                    }
                    Spacer(Modifier.height(24.dp))
                }
            }
        }

        // 하단 bar — 스텝별 버튼. 제스처바(navigationBars)만큼 띄워 겹침 방지(갤럭시 하단바).
        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 24.dp)
                .padding(bottom = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            when (step) {
                OnboardingStep.WELCOME -> WithuCTAButton(
                    text = stringResource(R.string.onboarding_start),
                    onClick = { advance() },
                    modifier = Modifier.fillMaxWidth(),
                )
                OnboardingStep.DONE -> WithuCTAButton(
                    text = stringResource(R.string.onboarding_finish),
                    onClick = onComplete,
                    modifier = Modifier.fillMaxWidth(),
                )
                else -> {
                    val requesting = resultOf(step) == PermissionResult.REQUESTING
                    WithuCTAButton(
                        text = if (requesting) stringResource(R.string.onboarding_requesting)
                        else stringResource(R.string.onboarding_request_button),
                        onClick = { request(step) },
                        enabled = !requesting,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
            // 건너뛰기 슬롯 — 높이를 항상 예약해 CTA 버튼 위치를 고정한다.
            // (예전엔 pending 일 때만 노출돼서, 버튼 누르면 슬롯이 사라지며 CTA 가 아래로
            //  점프해 순간 잘못 눌리던 버그. 이제 스텝 전환/요청 시작에도 버튼이 안 움직임.)
            Box(Modifier.height(48.dp), contentAlignment = Alignment.Center) {
                val isPermissionStep = step != OnboardingStep.WELCOME && step != OnboardingStep.DONE
                if (isPermissionStep && resultOf(step) == PermissionResult.PENDING) {
                    TextButton(onClick = {
                        setResult(step, PermissionResult.SKIPPED)
                        advance()
                    }) {
                        Text(
                            stringResource(R.string.onboarding_skip),
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

// MARK: - 진행 바

@Composable
private fun ProgressBar(progressIndex: Int) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp)
            .padding(top = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        val pink = withuPink()
        val dim = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.2f)
        repeat(5) { i ->
            Box(
                Modifier
                    .weight(1f)
                    .height(4.dp)
                    .background(if (i <= progressIndex) pink else dim, RoundedCornerShape(2.dp)),
            )
        }
    }
}

// MARK: - welcome

@Composable
private fun WelcomeContent() {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier
                .size(240.dp)
                .background(withuPink().copy(alpha = 0.22f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.Pets,
                contentDescription = null,
                tint = withuPinkText(),
                modifier = Modifier.size(80.dp),
            )
        }
        Spacer(Modifier.height(20.dp))
        Text(
            stringResource(R.string.onboarding_welcome_title),
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
        )
        Spacer(Modifier.height(6.dp))
        Text(
            stringResource(R.string.onboarding_welcome_subtitle),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(28.dp))
        FeatureRow(
            icon = Icons.Filled.AutoFixHigh, tint = withuPink(),
            title = stringResource(R.string.onboarding_feature1_title),
            desc = stringResource(R.string.onboarding_feature1_desc),
        )
        Spacer(Modifier.height(14.dp))
        FeatureRow(
            icon = Icons.Filled.MonitorHeart, tint = WithuColors.systemMint,
            title = stringResource(R.string.onboarding_feature2_title),
            desc = stringResource(R.string.onboarding_feature2_desc),
        )
        Spacer(Modifier.height(14.dp))
        FeatureRow(
            icon = Icons.Filled.Widgets, tint = WithuColors.systemCyan,
            title = stringResource(R.string.onboarding_feature3_title),
            desc = stringResource(R.string.onboarding_feature3_desc),
        )
    }
}

@Composable
private fun FeatureRow(icon: ImageVector, tint: Color, title: String, desc: String) {
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier
                .size(40.dp)
                .background(tint.copy(alpha = 0.18f), RoundedCornerShape(10.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(22.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
            Text(
                desc,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// MARK: - 권한 페이지 (공통 템플릿)

@Composable
private fun PermissionPage(
    icon: ImageVector,
    tint: Color,
    title: String,
    body: String,
    details: List<String>,
    skipNote: String?,
    result: PermissionResult,
) {
    Column(
        Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .size(120.dp)
                .background(tint.copy(alpha = 0.22f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(48.dp))
        }
        Spacer(Modifier.height(20.dp))
        Text(
            title,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(10.dp))
        Text(
            body,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(20.dp))
        Column(
            Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            details.forEach { DetailBullet(it) }
        }
        if (skipNote != null) {
            Spacer(Modifier.height(14.dp))
            Text(
                skipNote,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        // 요청 결과 pill (pending/requesting 은 표시 안 함).
        val kind = when (result) {
            PermissionResult.GRANTED -> StatusKind.OK
            PermissionResult.DENIED -> StatusKind.WARNING
            PermissionResult.SKIPPED -> StatusKind.OFF
            else -> null
        }
        if (kind != null) {
            Spacer(Modifier.height(18.dp))
            val text = if (result == PermissionResult.GRANTED)
                stringResource(R.string.onboarding_status_granted)
            else stringResource(R.string.onboarding_status_later)
            StatusPill(kind = kind, text = text)
        }
    }
}

@Composable
private fun DetailBullet(text: String) {
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            Icons.Filled.CheckCircle,
            contentDescription = null,
            tint = withuPinkText(),
            modifier = Modifier.size(18.dp),
        )
        Text(
            text,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
    }
}

// MARK: - done

@Composable
private fun DoneContent(
    healthResult: PermissionResult,
    locationResult: PermissionResult,
    notificationResult: PermissionResult,
    focusResult: PermissionResult,
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier
                .size(120.dp)
                .background(withuPink().copy(alpha = 0.22f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = withuPinkText(),
                modifier = Modifier.size(48.dp),
            )
        }
        Spacer(Modifier.height(20.dp))
        Text(
            stringResource(R.string.onboarding_done_title),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(Modifier.height(6.dp))
        Text(
            stringResource(R.string.onboarding_done_subtitle),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(24.dp))
        Surface(
            color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                SummaryRow(stringResource(R.string.onboarding_summary_health), healthResult)
                SummaryRow(stringResource(R.string.onboarding_summary_weather), locationResult)
                SummaryRow(stringResource(R.string.onboarding_summary_notification), notificationResult)
                SummaryRow(stringResource(R.string.onboarding_summary_sleep), focusResult)
            }
        }
        Spacer(Modifier.height(14.dp))
        Text(
            stringResource(R.string.onboarding_done_footer),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun SummaryRow(label: String, result: PermissionResult) {
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        // granted→연결됨(OK) / denied→나중에(WARNING) / skipped→나중에(OFF) / pending·requesting→아직(OFF)
        val (kind, text) = when (result) {
            PermissionResult.GRANTED -> StatusKind.OK to stringResource(R.string.onboarding_summary_connected)
            PermissionResult.DENIED -> StatusKind.WARNING to stringResource(R.string.onboarding_summary_later)
            PermissionResult.SKIPPED -> StatusKind.OFF to stringResource(R.string.onboarding_summary_later)
            else -> StatusKind.OFF to stringResource(R.string.onboarding_summary_pending)
        }
        StatusPill(kind = kind, text = text)
    }
}

// MARK: - 배경

/** 온보딩 배경 gradient (스펙 06 §1-A): withuPinkBackground → 시스템 배경. */
@Composable
private fun onboardingBackground(): Brush = Brush.verticalGradient(
    listOf(withuPinkBackground(), MaterialTheme.colorScheme.background),
)
