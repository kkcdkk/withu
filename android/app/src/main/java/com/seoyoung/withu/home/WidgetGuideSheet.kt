package com.seoyoung.withu.home

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.seoyoung.withu.R
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.ui.rememberBackgroundGradient
import com.seoyoung.withu.ui.theme.WithuColors

/**
 * 위젯 안내 시트 — iOS WidgetGuideView 대응 (스펙 01 §1.3).
 * Android 는 홈 화면 위젯 카드 1개만 (잠금 화면·시계 카드 SCOPE 제외).
 * 단계 문구는 Android 절차 대체안 (strings §2.4).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WidgetGuideSheet(onClose: () -> Unit) {
    Dialog(
        onDismissRequest = onClose,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        val gradient = rememberBackgroundGradient(CharacterState.IDLE)
        Scaffold(
            containerColor = Color.Transparent,
            topBar = {
                CenterAlignedTopAppBar(
                    title = { Text(stringResource(R.string.widget_guide_title), fontWeight = FontWeight.SemiBold) },
                    actions = {
                        TextButton(onClick = onClose) { Text(stringResource(R.string.common_close)) }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
                )
            },
            modifier = Modifier
                .fillMaxSize()
                // Dialog 창은 배경이 투명 — 불투명 베이스를 먼저 깔아 뒤 화면이 안 비치게.
                .background(MaterialTheme.colorScheme.background)
                .background(gradient),
        ) { padding ->
            Column(
                modifier = Modifier
                    .padding(padding)
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                GuideCard(
                    icon = Icons.Filled.Smartphone,
                    tint = WithuColors.systemCyan,
                    title = stringResource(R.string.widget_guide_home_title),
                    steps = listOf(
                        stringResource(R.string.widget_guide_step_1),
                        stringResource(R.string.widget_guide_step_2),
                        stringResource(R.string.widget_guide_step_3),
                        stringResource(R.string.widget_guide_step_4),
                    ),
                )
            }
        }
    }
}

@Composable
private fun GuideCard(icon: ImageVector, tint: Color, title: String, steps: List<String>) {
    val shape = RoundedCornerShape(16.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.72f), shape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier
                    .size(40.dp)
                    .background(tint.copy(alpha = 0.18f), RoundedCornerShape(10.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, contentDescription = null, tint = tint)
            }
            Spacer(Modifier.width(10.dp))
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Column(
            modifier = Modifier.padding(start = 50.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            steps.forEachIndexed { i, step ->
                Row(verticalAlignment = Alignment.Top) {
                    Text(
                        text = stringResource(R.string.widget_guide_step_num, i + 1),
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = tint,
                        modifier = Modifier.width(24.dp),
                    )
                    Text(text = step, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }
}
