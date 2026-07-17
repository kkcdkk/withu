package com.seoyoung.withu

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.seoyoung.withu.camera.CameraScreen
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.gallery.BatchGroupScreen
import com.seoyoung.withu.gallery.GalleryLandingScreen
import com.seoyoung.withu.gallery.StateFolderScreen
import com.seoyoung.withu.gen.BatchGenScreen
import com.seoyoung.withu.gen.SingleGenScreen
import com.seoyoung.withu.home.DiagnosticsScreen
import com.seoyoung.withu.home.HomeScreen
import com.seoyoung.withu.notify.NotificationHelper
import com.seoyoung.withu.onboarding.HelpGuideSheet
import com.seoyoung.withu.onboarding.OnboardingScreen
import com.seoyoung.withu.profile.ProfileScreen
import com.seoyoung.withu.shared.AppPrefs
import com.seoyoung.withu.ui.theme.WithuTheme

/**
 * 앱 진입점 — 전체 nav graph + 온보딩 게이트 + 알림 딥링크 (00-PLAN §4 Phase I).
 * 화면들은 서로 직접 호출하지 않고, 이동은 전부 여기 콜백으로 배선한다 (§2-12).
 */
class MainActivity : ComponentActivity() {

    // 알림 탭 딥링크(EXTRA_OPEN_BATCH) — cold/warm start 모두 compose 로 전달.
    private val openBatchFromNotification = mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        openBatchFromNotification.value =
            intent?.getBooleanExtra(NotificationHelper.EXTRA_OPEN_BATCH, false) == true
        setContent {
            WithuTheme {
                WithuApp(
                    openBatchFromNotification = openBatchFromNotification.value,
                    onConsumedBatch = { openBatchFromNotification.value = false },
                )
            }
        }
    }

    // launchMode=singleTop → 실행 중 알림 재탭 시 새 인스턴스 대신 여기로 전달.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(NotificationHelper.EXTRA_OPEN_BATCH, false)) {
            openBatchFromNotification.value = true
        }
    }
}

/**
 * 온보딩 게이트 + NavHost.
 * - `!onboarded` → OnboardingScreen (완료 시 onboarded=true).
 * - `onboarded && !seenGuide` → HomeScreen 진입 시 자체적으로 사용법 안내를 1회 표시(onShowHelp).
 */
@Composable
private fun WithuApp(
    openBatchFromNotification: Boolean,
    onConsumedBatch: () -> Unit,
) {
    var onboarded by remember { mutableStateOf(AppPrefs.onboarded) }

    if (!onboarded) {
        OnboardingScreen(
            onComplete = {
                AppPrefs.onboarded = true
                onboarded = true
            },
        )
        return
    }

    WithuNav(
        openBatchFromNotification = openBatchFromNotification,
        onConsumedBatch = onConsumedBatch,
        onReonboard = {
            // '처음 안내 다시 보기' — onboarded=false 처리는 호출측(I) 책임 (§2-12).
            AppPrefs.onboarded = false
            onboarded = false
        },
    )
}

@Composable
private fun WithuNav(
    openBatchFromNotification: Boolean,
    onConsumedBatch: () -> Unit,
    onReonboard: () -> Unit,
) {
    val nav = rememberNavController()

    // 딥링크 플래그 소비 — HomeScreen 이 LaunchedEffect 로 배치 진입을 처리하므로
    // 여기선 다음 재탭이 다시 트리거되도록 플래그만 리셋한다.
    LaunchedEffect(openBatchFromNotification) {
        if (openBatchFromNotification) onConsumedBatch()
    }

    NavHost(navController = nav, startDestination = "home") {
        composable("home") {
            HomeScreen(
                onOpenSingleGen = { nav.navigate("gen/single") },
                onOpenBatchGen = { nav.navigate("gen/batch") },
                onOpenCamera = { nav.navigate("camera") },
                onOpenGallery = { nav.navigate("gallery") },
                onOpenProfile = { nav.navigate("profile") },
                onOpenDiagnostics = { nav.navigate("diagnostics") },
                onShowHelp = { nav.navigate("help") },
                onReonboard = onReonboard,
                openBatchFromNotification = openBatchFromNotification,
            )
        }
        composable("gen/single") {
            SingleGenScreen(onOpenBatch = { nav.navigate("gen/batch") })
        }
        composable("gen/batch") {
            BatchGenScreen(onClose = { nav.popBackStack() })
        }
        composable("gallery") {
            GalleryLandingScreen(
                onOpenStateFolder = { nav.navigate("gallery/state/${it.raw}") },
                onOpenBatchGroup = { nav.navigate("gallery/batch/$it") },
                onOpenLegacy = { nav.navigate("gallery/legacy") },
            )
        }
        composable("gallery/state/{raw}") { backStackEntry ->
            val raw = backStackEntry.arguments?.getString("raw")
            val state = CharacterState.fromRaw(raw ?: "") ?: CharacterState.IDLE
            StateFolderScreen(
                state = state,
                onOpenSingleGen = { nav.navigate("gen/single") },
            )
        }
        composable("gallery/batch/{batchId}") { backStackEntry ->
            BatchGroupScreen(batchId = backStackEntry.arguments?.getString("batchId") ?: "")
        }
        composable("gallery/legacy") {
            // legacy 폴더 = batchId "" 규약 (§2-12).
            BatchGroupScreen(batchId = "")
        }
        composable("profile") {
            ProfileScreen(onOpenStateFolder = { nav.navigate("gallery/state/${it.raw}") })
        }
        composable("camera") {
            CameraScreen()
        }
        composable("diagnostics") {
            DiagnosticsScreen()
        }
        composable("help") {
            HelpGuideSheet(onDone = { nav.popBackStack() })
        }
    }
}
