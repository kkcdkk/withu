package com.seoyoung.withu.gen

import android.graphics.Bitmap
import java.util.UUID

/**
 * 단건 생성 화면 모델 — iOS CharacterGenView.swift 의 GenerationMode/PendingAction/ResultVersion
 * 포팅 (스펙 02 §3). 라벨 문구는 strings_gen.xml (enum rawValue 하드코딩 금지 — Android 는 리소스).
 */

/** 생성 모드 — AI 생성 vs 내 이미지 사용. */
enum class GenerationMode { AI_GENERATE, IMPORT_PHOTO }

/**
 * 만들기/다듬기 버튼은 즉시 실행하지 않고 캔디 안내 팝업을 먼저 띄운다 —
 * 확인해야 실행 (iOS pendingAction 동일).
 */
sealed class PendingAction {
    data object NewGeneration : PendingAction()
    /** frame: 보고 있는 프레임만 다듬음 (0=기본, 1=움직임). */
    data class Refine(val frame: Int) : PendingAction()
}

/**
 * 결과 버전 이력 항목 — [0] = 처음 만든 원본, 이후는 다듬은 버전.
 * 버전을 탭해 선택하면 그 버전이 현재 결과(적용 대상)가 된다.
 */
class ResultVersion(
    /** 결과 슬롯(128px) 이미지. */
    val small: Bitmap,
    /** 움직임 프레임 (있으면). */
    val frame2: Bitmap?,
    /** frame1 앵커용 원본(1024px). */
    val fullRes: Bitmap?,
    val isRefined: Boolean,
    /** 자동 저장된 갤러리 항목 id — '적용' 시 이 항목을 재사용해 중복 저장을 막음. */
    val galleryId: String? = null,
) {
    val id: String = UUID.randomUUID().toString()
}

/**
 * 사진 선택 직후 강제 정사각 크롭 요청 — SquareCropView 풀스크린에 전달.
 * onDone 은 크롭 결과의 사용처(참고사진 대입 / import 처리)를 들고 있는 콜백.
 */
class CropRequest(
    val source: Bitmap,
    val onDone: (Bitmap) -> Unit,
)
