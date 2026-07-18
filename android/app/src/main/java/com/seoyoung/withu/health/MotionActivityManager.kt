package com.seoyoung.withu.health

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.DetectedActivity
import com.seoyoung.withu.WithuApp
import com.seoyoung.withu.character.CharacterState
import com.seoyoung.withu.shared.SharedAppState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * 폰 전용 활동 감지 — iOS MotionActivityManager(CoreMotion) 대응.
 * 워치(심박)가 없어도 폰 센서만으로 걷기/달리기/자전거를 감지해 캐릭터 상태를 바꾼다.
 *
 * Play Services Activity Recognition **Transition API** 사용 — ENTER/EXIT 이벤트라 배터리 효율적.
 * 감지된 활동은 prefs 에 저장(앱 재시작에도 유지). EXIT 이 유실될 때 대비 staleMax(2시간) 안전망.
 *
 * resolver 는 이 값을 워치 HR·수면 신호가 없을 때만 반영 (phoneWorkoutState, 스펙 08 §1.5).
 */
object MotionActivityManager {

    private const val KEY_STATE = "withu.phoneActivity.state.v1"   // CharacterState.raw
    private const val KEY_AT = "withu.phoneActivity.at.v1"        // epochMillis
    private const val STALE_MAX_MS = 2 * 60 * 60 * 1000L          // 2시간 — EXIT 유실 안전망

    private val _current = MutableStateFlow(loadPersisted())
    /** 지금 감지된 폰 활동 상태 (workout 계열) 또는 null. */
    val current: StateFlow<CharacterState?> = _current

    private fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(
            WithuApp.context, Manifest.permission.ACTIVITY_RECOGNITION,
        ) == PackageManager.PERMISSION_GRANTED

    private fun transitionPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, MotionTransitionReceiver::class.java)
            .setAction(MotionTransitionReceiver.ACTION)
        return PendingIntent.getBroadcast(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
    }

    /** 감지 시작 — 권한 있으면 걷기/달리기/자전거 ENTER·EXIT 전환 구독. 권한 없으면 no-op. */
    fun start(context: Context) {
        if (!hasPermission()) return
        val activities = listOf(
            DetectedActivity.WALKING, DetectedActivity.RUNNING, DetectedActivity.ON_BICYCLE,
        )
        val directions = listOf(
            ActivityTransition.ACTIVITY_TRANSITION_ENTER, ActivityTransition.ACTIVITY_TRANSITION_EXIT,
        )
        val transitions = ArrayList<ActivityTransition>()
        for (act in activities) for (dir in directions) {
            transitions.add(
                ActivityTransition.Builder().setActivityType(act).setActivityTransition(dir).build(),
            )
        }
        val request = ActivityTransitionRequest(transitions)
        runCatching {
            ActivityRecognition.getClient(context)
                .requestActivityTransitionUpdates(request, transitionPendingIntent(context))
        }
    }

    /** 리시버가 전환 이벤트 수신 시 호출 — ENTER 면 설정, EXIT(현재와 일치)면 해제. */
    internal fun onTransition(activityType: Int, isEnter: Boolean) {
        val state = mapActivity(activityType) ?: return
        if (isEnter) {
            persist(state)
            _current.value = state
        } else if (_current.value == state) {
            persist(null)
            _current.value = null
        }
    }

    /** resolver 에 넘길 값 — 오래된(안전망 초과) 감지는 무시. */
    fun phoneWorkoutState(): CharacterState? {
        val at = SharedAppState.prefs().getLong(KEY_AT, 0L)
        if (at == 0L || System.currentTimeMillis() - at > STALE_MAX_MS) return null
        return _current.value
    }

    private fun mapActivity(type: Int): CharacterState? = when (type) {
        DetectedActivity.WALKING -> CharacterState.WALKING
        DetectedActivity.RUNNING -> CharacterState.RUNNING
        DetectedActivity.ON_BICYCLE -> CharacterState.CYCLING
        else -> null
    }

    private fun persist(state: CharacterState?) {
        val e = SharedAppState.prefs().edit()
        if (state == null) e.remove(KEY_STATE).remove(KEY_AT)
        else e.putString(KEY_STATE, state.raw).putLong(KEY_AT, System.currentTimeMillis())
        e.apply()
    }

    private fun loadPersisted(): CharacterState? {
        val at = SharedAppState.prefs().getLong(KEY_AT, 0L)
        if (at == 0L || System.currentTimeMillis() - at > STALE_MAX_MS) return null
        return SharedAppState.prefs().getString(KEY_STATE, null)?.let { CharacterState.fromRaw(it) }
    }
}
