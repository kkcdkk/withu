package com.seoyoung.withu.paywall

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import com.seoyoung.withu.R
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.net.ApiClient
import com.seoyoung.withu.net.koreanized
import com.seoyoung.withu.quota.GenerationQuota
import com.seoyoung.withu.shared.SharedAppState
import com.seoyoung.withu.ui.CapsuleToast
import com.seoyoung.withu.ui.FrostedCard
import com.seoyoung.withu.ui.HelperFooter
import com.seoyoung.withu.ui.SectionHeader
import com.seoyoung.withu.ui.WithuCTAButton
import com.seoyoung.withu.ui.WithuTopBarTitle
import com.seoyoung.withu.ui.pixelInputField
import com.seoyoung.withu.ui.rememberBackgroundGradient
import com.seoyoung.withu.ui.theme.withuPink
import com.seoyoung.withu.ui.theme.withuPinkText
import com.seoyoung.withu.ui.withuInputColors
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * 페이월 — iOS PaywallView.swift 포팅 (스펙 07).
 * Play Billing 실결제는 후속 (SCOPE) — 팩은 정적 4종 표시, 구매 탭은 '준비 중' 토스트.
 * 테스트 캔디 코드(CANDY20, DEBUG 전용)가 결제 없는 빌드의 유일한 충전 수단이자 QA 경로.
 * 전체화면 다이얼로그로 표시 — 닫힐 때 호출측이 remainingGenerations 갱신 (00-PLAN §2-11).
 */

/** 캔디 팩 정적 데이터 — StoreManager.ProductID 대응. 가격은 결제 미연동이라 '준비 중' 표시. */
private data class CandyPack(
    val id: String,
    val name: String,
    val amount: Int,
    val recommended: Boolean = false,
)

private val packs = listOf(
    CandyPack("credits10", "미니 팩", 10),
    CandyPack("credits30", "포켓 팩", 30),
    // 추천 = 50개 팩 하나만 — "4팩이 다 같아 보이면 고르기 어려움, 중간 팩 하나만 살짝 강조"
    CandyPack("credits50", "파우치 팩", 50, recommended = true),
    CandyPack("credits100", "파티 팩", 100),
)

private const val TERMS_URL = "https://kkcdkk.github.io/withu/TERMS_OF_SERVICE.html"
private const val PRIVACY_URL = "https://kkcdkk.github.io/withu/PRIVACY_POLICY.html"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaywallSheet(onClose: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var candy by remember { mutableIntStateOf(GenerationQuota.displayedCandy()) }
    var redeemInput by remember { mutableStateOf("") }
    var redeemMessage by remember { mutableStateOf<String?>(null) }
    var isRedeeming by remember { mutableStateOf(false) }
    var referralInput by remember { mutableStateOf("") }
    var referralMessage by remember { mutableStateOf<String?>(null) }
    var isApplyingReferral by remember { mutableStateOf(false) }
    var toastText by remember { mutableStateOf<String?>(null) }

    val comingSoon = stringResource(R.string.paywall_coming_soon)
    fun showComingSoon() {
        scope.launch {
            toastText = comingSoon
            delay(1600)
            toastText = null
        }
    }

    // 배경 톤 — 현재 적용 중인 캐릭터 state 기반 그라디언트 (홈과 동일 규칙)
    val bgState = remember {
        SharedAppState.loadMessage()?.characterState ?: CharacterState.IDLE
    }
    val gradient = rememberBackgroundGradient(bgState)

    Scaffold(
        containerColor = Color.Transparent,
        topBar = {
            TopAppBar(
                title = { WithuTopBarTitle(stringResource(R.string.paywall_title)) },
                actions = {
                    TextButton(onClick = onClose) {
                        Text(stringResource(R.string.common_close))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
            )
        },
        // Dialog 창은 배경이 투명 — fillMaxSize + 불투명 베이스로 뒤 화면이 안 비치게.
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .background(gradient),
    ) { padding ->
        Box(
            Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                // 1) 헤더 카드 — 잔액
                FrostedCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 18.dp) {
                    Text(
                        text = stringResource(R.string.paywall_balance, candy),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = stringResource(R.string.paywall_balance_sub),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                // 2) 캔디 충전 — 정적 팩 4종 (실결제 후속 — 탭은 '준비 중')
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    SectionHeader(stringResource(R.string.paywall_section_packs))
                    for (pack in packs) {
                        PackRow(pack = pack, onClick = { showComingSoon() })
                    }
                }

                // 3) 할인코드
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    SectionHeader(stringResource(R.string.paywall_section_redeem))
                    FrostedCard(modifier = Modifier.fillMaxWidth()) {
                        CodeInputRow(
                            value = redeemInput,
                            onValueChange = { redeemInput = it },
                            placeholder = stringResource(R.string.paywall_code_placeholder),
                            isBusy = isRedeeming,
                            onApply = {
                                val trimmed = redeemInput.trim()
                                if (trimmed.isEmpty()) return@CodeInputRow
                                // 테스트 캔디 코드 — 서버 안 감, 로컬 +20 (DEBUG 전용, 스펙 07 §3.1)
                                if (GenerationQuota.allowsTestCandyCode &&
                                    trimmed.uppercase() == GenerationQuota.testCandyCode
                                ) {
                                    GenerationQuota.addCredits(GenerationQuota.testCandyAmount)
                                    candy = GenerationQuota.displayedCandy()
                                    redeemMessage = context.getString(
                                        R.string.paywall_test_code_success,
                                        GenerationQuota.testCandyAmount,
                                    )
                                    redeemInput = ""
                                    return@CodeInputRow
                                }
                                scope.launch {
                                    isRedeeming = true
                                    try {
                                        val ent = ApiClient.redeem(trimmed)
                                        GenerationQuota.syncCreditsUp(ent.credits)
                                        candy = GenerationQuota.displayedCandy()
                                        redeemMessage =
                                            context.getString(R.string.paywall_redeem_success)
                                        redeemInput = ""
                                    } catch (e: Exception) {
                                        // 로그인 제외 범위 — 서버가 401 을 줄 수 있음, 문구 그대로 노출
                                        redeemMessage = e.koreanized()
                                    } finally {
                                        isRedeeming = false
                                    }
                                }
                            },
                        )
                    }
                    redeemMessage?.let {
                        Text(
                            text = it,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 4.dp),
                        )
                    }
                    if (GenerationQuota.allowsTestCandyCode) {
                        Text(
                            text = stringResource(
                                R.string.paywall_test_code_hint,
                                GenerationQuota.testCandyCode,
                                GenerationQuota.testCandyAmount,
                            ),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 4.dp),
                        )
                    }
                }

                // 4) 친구 초대 — '내 초대 코드' 카드는 로그인/entitlement 도입 후 노출 (지금은 조건 미충족)
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    SectionHeader(stringResource(R.string.paywall_section_referral))
                    FrostedCard(modifier = Modifier.fillMaxWidth()) {
                        CodeInputRow(
                            value = referralInput,
                            onValueChange = { referralInput = it },
                            placeholder = stringResource(R.string.paywall_referral_placeholder),
                            isBusy = isApplyingReferral,
                            onApply = {
                                val trimmed = referralInput.trim()
                                if (trimmed.isEmpty()) return@CodeInputRow
                                scope.launch {
                                    isApplyingReferral = true
                                    try {
                                        val ent = ApiClient.applyReferral(trimmed)
                                        GenerationQuota.syncCreditsUp(ent.credits)
                                        candy = GenerationQuota.displayedCandy()
                                        referralMessage =
                                            context.getString(R.string.paywall_referral_success)
                                        referralInput = ""
                                    } catch (e: Exception) {
                                        referralMessage = e.koreanized()
                                    } finally {
                                        isApplyingReferral = false
                                    }
                                }
                            },
                        )
                    }
                    Text(
                        text = stringResource(R.string.paywall_referral_desc),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 4.dp),
                    )
                    referralMessage?.let {
                        Text(
                            text = it,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 4.dp),
                        )
                    }
                }

                // 5) 법적 링크 — "링크는 글자, 파스텔은 안 읽혀서 진한 로즈"
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center,
                ) {
                    val linkColor = withuPinkText()
                    Text(
                        text = stringResource(R.string.paywall_terms),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = linkColor,
                        modifier = Modifier.clickable {
                            context.startActivity(Intent(Intent.ACTION_VIEW, TERMS_URL.toUri()))
                        },
                    )
                    Text(
                        text = " · ",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = stringResource(R.string.paywall_privacy),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = linkColor,
                        modifier = Modifier.clickable {
                            context.startActivity(Intent(Intent.ACTION_VIEW, PRIVACY_URL.toUri()))
                        },
                    )
                }

                // 6) 푸터
                HelperFooter(stringResource(R.string.paywall_footer))
                Spacer(Modifier.height(24.dp))
            }

            CapsuleToast(
                text = toastText,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 40.dp),
            )
        }
    }
}

/** 팩 행 — 44 아이콘 + 이름/설명 + 우측 '준비 중'. 추천 팩만 핑크 외곽선 강조. */
@Composable
private fun PackRow(pack: CandyPack, onClick: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    val pink = withuPink()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.72f))
            .then(
                if (pack.recommended) {
                    Modifier.border(1.5.dp, pink.copy(alpha = 0.45f), shape)
                } else {
                    Modifier.border(
                        0.5.dp,
                        MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                        shape,
                    )
                },
            )
            .clickable(onClick = onClick)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            Modifier
                .size(44.dp)
                .background(pink.copy(alpha = 0.18f), RoundedCornerShape(12.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = withuPinkText())
        }
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = pack.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                )
                if (pack.recommended) {
                    Spacer(Modifier.width(6.dp))
                    Text(
                        text = stringResource(R.string.paywall_pack_popular),
                        style = MaterialTheme.typography.labelSmall,
                        color = withuPinkText(),
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(pink.copy(alpha = 0.18f))
                            .padding(horizontal = 8.dp, vertical = 2.dp),
                    )
                }
            }
            Spacer(Modifier.height(2.dp))
            Text(
                text = stringResource(R.string.paywall_pack_desc, pack.amount),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        // 가격 자리 — Play 연동 전까지 하드코딩 원화 금지, '준비 중' 라벨 (스펙 07 §5)
        Text(
            text = stringResource(R.string.paywall_price_pending),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** 코드 입력 + 적용 버튼 공통 행 — 자동 대문자, 진행 중 스피너, 공백/진행 중 비활성. */
@Composable
private fun CodeInputRow(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    isBusy: Boolean,
    onApply: () -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            placeholder = { Text(placeholder, style = MaterialTheme.typography.bodySmall) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.Characters,
                autoCorrectEnabled = false,
            ),
            colors = withuInputColors(),
            modifier = Modifier.weight(1f).pixelInputField(),
        )
        WithuCTAButton(
            text = stringResource(R.string.paywall_apply),
            onClick = onApply,
            enabled = value.trim().isNotEmpty() && !isBusy,
            loading = isBusy,
        )
    }
}
