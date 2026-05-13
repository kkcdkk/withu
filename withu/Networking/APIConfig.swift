//
//  APIConfig.swift
//  withu
//

import Foundation

enum APIConfig {
    // 시뮬레이터에선 localhost로 호스트 맥에 직접 접근 가능 (로컬네트워크 권한 불필요).
    // 실기기 테스트할 땐 LAN IP로 바꿔야 함 (예: "http://172.30.1.78:8000").
    static let baseURL = URL(string: "http://127.0.0.1:8000")!
    static let timeout: TimeInterval = 60
}
