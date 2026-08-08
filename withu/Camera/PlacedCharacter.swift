//
//  PlacedCharacter.swift
//  withu
//
//  카메라 화면에 배치된 캐릭터 한 마리.
//  좌표 / 사이즈는 화면 사이즈로 정규화된 값 (0~1).
//

import Foundation
import CoreGraphics

struct PlacedCharacter: Identifiable, Equatable {
    let id: UUID
    var state: CharacterState
    /// 정규화 중심 좌표 (0~1, (0.5, 0.5) = 화면 정중앙)
    var position: CGPoint
    /// 정규화 사이즈 (정사각). 0.35 면 화면 너비의 35%
    var size: CGFloat
    /// 회전 (라디안). 시계방향 +.
    var rotation: CGFloat

    init(id: UUID = UUID(),
         state: CharacterState,
         position: CGPoint = CGPoint(x: 0.5, y: 0.55),
         size: CGFloat = 0.35,
         rotation: CGFloat = 0) {
        self.id = id
        self.state = state
        self.position = position
        self.size = size
        self.rotation = rotation
    }

    /// 정규화 좌표를 실제 pixel/point 좌표계로 변환
    func rect(in containerSize: CGSize) -> CGRect {
        let w = size * containerSize.width
        let h = w   // 정사각
        let x = position.x * containerSize.width - w / 2
        let y = position.y * containerSize.height - h / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
