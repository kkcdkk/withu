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
    /// URLSession 의 timeoutIntervalForRequest 가 너무 짧으면 iOS 가
    /// "internet offline" 으로 잘못 보고하니 충분히 길게 잡음.
    static let timeout: TimeInterval = 600   // 10분
}
