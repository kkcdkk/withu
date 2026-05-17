//
//  APIConfig.swift
//  withu
//

import Foundation

enum APIConfig {
    // 실기기/시뮬레이터 둘 다 같은 와이파이에 붙어 있는 맥의 LAN IP를 가리킴.
    // 시뮬레이터만 단독 테스트할 땐 "http://127.0.0.1:8000" 으로 바꿔도 됨.
    // 맥 LAN IP 확인: 터미널 `ipconfig getifaddr en0`
    static let baseURL = URL(string: "http://127.0.0.1:8000")!

    /// AI 이미지 생성은 medium 1~3분, high 2~5분 정도 걸림.
    /// idle / 전체 transfer 둘 다 넉넉히 잡음. 짧은 timeout 으로
    /// iOS 가 "internet offline" 잘못 보고하던 것 방지.
    static let timeout: TimeInterval = 1800              // 30분 (request idle)
    static let resourceTimeout: TimeInterval = 3600      // 60분 (전체 transfer)
}
