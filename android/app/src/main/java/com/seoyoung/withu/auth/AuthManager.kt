package com.seoyoung.withu.auth

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.seoyoung.withu.net.ApiClient
import com.seoyoung.withu.quota.GenerationQuota
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Google 로그인 매니저 — iOS AuthManager 대응.
 *
 * Credential Manager 로 Google ID 토큰을 받아 서버 `/auth/google` 로 세션을 발급받고,
 * 세션을 저장 + 서버 캔디를 로컬로 끌어올린다(`syncCreditsUp`, iOS 파리티).
 * **캔디 권위는 여전히 로컬** — 서버 잔액은 max 로 끌어올리기만(로컬 적립분 안 덮음).
 */
object AuthManager {
    // Web 클라이언트 ID(공개값). 서버 wrangler.toml 의 GOOGLE_CLIENT_ID 와 반드시 동일해야
    // ID 토큰의 aud 검증이 통과한다.
    private const val WEB_CLIENT_ID =
        "864550333990-tgnnsngh8i74b7uimfs9o9338ffsl58r.apps.googleusercontent.com"

    private val _signedIn = MutableStateFlow(SessionStore.isSignedIn())
    val signedIn: StateFlow<Boolean> = _signedIn.asStateFlow()

    private val _email = MutableStateFlow(SessionStore.email())
    val email: StateFlow<String?> = _email.asStateFlow()

    /**
     * Google 로그인 실행. 시스템 계정 선택 UI 가 뜨므로 **Activity Context** 필요.
     * 성공 시 세션 저장 + 캔디 동기화. 실패(사용자 취소 포함)는 예외 throw → 호출부에서 안내.
     */
    suspend fun signInWithGoogle(activityContext: Context) {
        val googleIdOption = GetGoogleIdOption.Builder()
            .setServerClientId(WEB_CLIENT_ID)
            .setFilterByAuthorizedAccounts(false)   // 이미 승인된 계정 외 새 계정 선택도 허용
            .setAutoSelectEnabled(false)
            .build()
        val request = GetCredentialRequest.Builder()
            .addCredentialOption(googleIdOption)
            .build()

        val credentialManager = CredentialManager.create(activityContext)
        val response = credentialManager.getCredential(activityContext, request)

        val cred = response.credential
        if (cred !is CustomCredential ||
            cred.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
        ) {
            throw IllegalStateException("예상치 못한 자격 증명 형식")
        }
        val googleCred = GoogleIdTokenCredential.createFrom(cred.data)

        val resp = ApiClient.authGoogle(googleCred.idToken)
        SessionStore.save(resp.sessionToken, googleCred.id)
        resp.entitlement?.let { GenerationQuota.syncCreditsUp(it.credits) }

        _email.value = googleCred.id
        _signedIn.value = true
    }

    /** 로그아웃 — 세션만 지운다(로컬 캔디/갤러리는 유지, iOS 파리티). */
    fun signOut() {
        SessionStore.clear()
        _signedIn.value = false
        _email.value = null
    }
}
