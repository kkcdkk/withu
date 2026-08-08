package com.seoyoung.withu.auth

import com.seoyoung.withu.shared.SharedAppState

/**
 * 세션 토큰 저장소 — iOS KeychainStore 대응.
 * 안드로이드는 공유 SharedPreferences 에 둔다(캔디와 같은 저장소). 세션 JWT 는 비밀번호가 아니라
 * 만료(60일) 토큰이라 EncryptedSharedPreferences 없이도 실용상 충분.
 */
object SessionStore {
    private const val TOKEN_KEY = "withu.auth.sessionToken.v1"
    private const val EMAIL_KEY = "withu.auth.email.v1"

    fun sessionToken(): String? = SharedAppState.prefs().getString(TOKEN_KEY, null)

    fun isSignedIn(): Boolean = !sessionToken().isNullOrEmpty()

    fun email(): String? = SharedAppState.prefs().getString(EMAIL_KEY, null)

    fun save(token: String, email: String?) {
        val e = SharedAppState.prefs().edit()
        e.putString(TOKEN_KEY, token)
        if (email != null) e.putString(EMAIL_KEY, email)
        e.apply()
    }

    fun clear() {
        SharedAppState.prefs().edit().remove(TOKEN_KEY).remove(EMAIL_KEY).apply()
    }
}
