package com.seoyoung.withu.net

import com.seoyoung.withu.R
import com.seoyoung.withu.WithuApp
import kotlinx.coroutines.CancellationException
import java.io.IOException
import java.net.ConnectException
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

/**
 * API 에러 분류 — iOS APIError 포팅 (스펙 11).
 * message 는 디버그성 문구 — 사용자 노출은 반드시 koreanized() 를 쓸 것.
 */
sealed class ApiError(message: String) : Exception(message) {
    class InvalidResponse : ApiError("서버 응답 형식이 잘못됐어요.")
    class Server(val status: Int, val detail: String) : ApiError("서버 오류 $status: $detail")
    class Decoding(val reason: String) : ApiError("디코딩 실패: $reason")
    class Transport(override val cause: Throwable) : ApiError("통신 실패: ${cause.message}")
    /** 402 — 무료/크레딧 소진. balance 는 갱신된 잔액(있으면). */
    class PaymentRequired(val balance: Entitlement?) : ApiError("무료 횟수를 다 썼어요.")
}

/**
 * 모든 Throwable 을 사용자 친화 한국어 메시지로 변환 — iOS koreanizedDescription 포팅.
 * 시스템 로컬라이즈 메시지(영문일 수 있음)를 그대로 노출하지 말고 catch 에서 이것만 쓸 것.
 * 문구는 res/values/strings.xml 의 err_* 키 (스펙 11 §2.2 표 전량).
 */
fun Throwable.koreanized(): String {
    val ctx = WithuApp.context
    return when (this) {
        is ApiError.InvalidResponse -> ctx.getString(R.string.err_invalid_response)
        is ApiError.Server -> when {
            status == 429 -> ctx.getString(R.string.err_too_many_requests)
            status >= 500 -> ctx.getString(R.string.err_server_trouble)
            status == 422 -> ctx.getString(R.string.err_unsafe_prompt)
            else -> ctx.getString(R.string.err_server_generic, status)
        }
        is ApiError.Decoding -> ctx.getString(R.string.err_decoding)
        is ApiError.Transport -> cause.koreanized()   // 내부 에러를 재귀적으로 koreanize
        is ApiError.PaymentRequired -> ctx.getString(R.string.err_payment_required)
        // URLError 대응 — OkHttp/자바 네트워크 예외 매핑
        is UnknownHostException -> ctx.getString(R.string.err_no_internet)
        is SocketTimeoutException -> ctx.getString(R.string.err_timed_out)
        is ConnectException -> ctx.getString(R.string.err_cannot_connect)
        is SocketException -> ctx.getString(R.string.err_connection_lost)
        is CancellationException -> ctx.getString(R.string.err_cancelled)
        is IOException -> ctx.getString(R.string.err_network_generic)
        // 기본 — 시스템 메시지보다 깔끔한 한국어 폴백
        else -> ctx.getString(R.string.err_generic)
    }
}
