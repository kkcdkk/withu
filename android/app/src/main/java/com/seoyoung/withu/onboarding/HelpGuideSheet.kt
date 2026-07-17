package com.seoyoung.withu.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Cookie
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Watch
import androidx.compose.material.icons.filled.Widgets
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.seoyoung.withu.R
import com.seoyoung.withu.ui.WithuCTAButton
import com.seoyoung.withu.ui.theme.withuPinkText

/**
 * 사용법 안내 — iOS HelpGuideView.swift 포팅 (스펙 06 §1-B).
 *
 * 상태 없음 — onDone 하나로 '확인'(초록 CTA)과 '닫기'(상단) 둘 다 처리.
 * 조건부 노출 없이 항상 5개 스텝 전부 표시. 네비 배선은 Phase I(콜백)이 담당.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HelpGuideSheet(onDone: () -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.help_nav_title)) },
                actions = {
                    TextButton(onClick = onDone) { Text(stringResource(R.string.common_close)) }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Spacer(Modifier.height(4.dp))
            Text(
                stringResource(R.string.help_title),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
            )
            Text(
                stringResource(R.string.help_subtitle),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(2.dp))

            StepCard(
                Icons.Filled.AutoAwesome,
                stringResource(R.string.help_step1_title),
                stringResource(R.string.help_step1_body),
            )
            StepCard(
                Icons.Filled.GridView,
                stringResource(R.string.help_step2_title),
                stringResource(R.string.help_step2_body),
            )
            StepCard(
                Icons.Filled.Widgets,
                stringResource(R.string.help_step3_title),
                stringResource(R.string.help_step3_body),
            )
            StepCard(
                Icons.Filled.Watch,
                stringResource(R.string.help_step4_title),
                stringResource(R.string.help_step4_body),
            )
            StepCard(
                Icons.Filled.Cookie,
                stringResource(R.string.help_step5_title),
                stringResource(R.string.help_step5_body),
            )

            Spacer(Modifier.height(4.dp))
            WithuCTAButton(
                text = stringResource(R.string.common_confirm),
                onClick = onDone,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun StepCard(icon: ImageVector, title: String, body: String) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
        shape = RoundedCornerShape(14.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            Modifier.padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Icon(
                icon,
                contentDescription = null,
                tint = withuPinkText(),
                modifier = Modifier.size(32.dp),
            )
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                Text(
                    body,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
