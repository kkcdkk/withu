package com.seoyoung.withu.shared

import com.seoyoung.withu.character.CharacterState
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow

/**
 * 저장소 변경 알림 — iOS NotificationCenter 대체 (00-PLAN §2-2).
 * Compose 는 LaunchedEffect 에서 collect 로 구독. emit 은 비-suspend 컨텍스트에서도
 * 가능하도록 tryEmit + 버퍼 사용 (구독자 없어도 유실 무해 — 다음 로드에서 파일 버전 캐시 키가 커버).
 */
object StoreEvents {
    /** 활성 슬롯 캐릭터 이미지 변경. null = 전체 broadcast. */
    val characterImageChanged: MutableSharedFlow<CharacterState?> =
        MutableSharedFlow(extraBufferCapacity = 16, onBufferOverflow = BufferOverflow.DROP_OLDEST)

    /** 날씨 배경/데코 변경. */
    val weatherBackgroundChanged: MutableSharedFlow<Unit> =
        MutableSharedFlow(extraBufferCapacity = 16, onBufferOverflow = BufferOverflow.DROP_OLDEST)

    /** 캐릭터 프로필 저장. */
    val characterProfileChanged: MutableSharedFlow<Unit> =
        MutableSharedFlow(extraBufferCapacity = 16, onBufferOverflow = BufferOverflow.DROP_OLDEST)
}
