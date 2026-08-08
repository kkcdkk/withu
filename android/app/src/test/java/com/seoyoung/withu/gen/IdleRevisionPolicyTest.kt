package com.seoyoung.withu.gen

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * 기준 모습(idle) 다듬기 무료 정책 — iOS BatchCharacterGenView 파리티.
 * 1번째 다듬기 무료, 2번째부터 캔디. 재진입 복원 시 '무료'가 다시 뜨지 않아야 한다.
 */
class IdleRevisionPolicyTest {

    @Test
    fun `첫 다듬기는 무료`() {
        assertEquals(0, IdleRevisionPolicy.cost(used = 0, unitCost = 1))
        assertEquals(0, IdleRevisionPolicy.cost(used = 0, unitCost = 3))
    }

    @Test
    fun `두 번째부터는 퀄리티 단가 그대로 차감`() {
        assertEquals(1, IdleRevisionPolicy.cost(used = 1, unitCost = 1))
        assertEquals(3, IdleRevisionPolicy.cost(used = 2, unitCost = 3))
    }

    @Test
    fun `이력 없으면 복원해도 0회 - 무료 유지`() {
        // 저장된 idle 이력 자체가 없으면 restoredUsed 를 호출하지 않지만,
        // 원본 1장만 있는(다듬기 0회) 이력이어도 무료는 그대로여야 한다.
        assertEquals(0, IdleRevisionPolicy.restoredUsed(current = 0, versionCount = 1))
        assertEquals(0, IdleRevisionPolicy.cost(IdleRevisionPolicy.restoredUsed(0, 1), unitCost = 1))
    }

    @Test
    fun `한 번 다듬은 뒤 재진입하면 무료로 오표시되지 않는다`() {
        // versions = [원본, 다듬음1] → 이미 1회 사용
        val restored = IdleRevisionPolicy.restoredUsed(current = 0, versionCount = 2)
        assertEquals(1, restored)
        assertEquals(1, IdleRevisionPolicy.cost(restored, unitCost = 1))
    }

    @Test
    fun `복원은 메모리 값을 낮추지 않는다`() {
        // 메모리 카운터가 이력보다 앞서 있으면(예: 다듬은 뒤 이력을 '취소') 큰 쪽을 유지 — 보수적.
        assertEquals(3, IdleRevisionPolicy.restoredUsed(current = 3, versionCount = 2))
        assertEquals(2, IdleRevisionPolicy.restoredUsed(current = 0, versionCount = 3))
    }
}
