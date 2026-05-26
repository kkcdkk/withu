//
//  APIClient.swift
//  withu
//

import Foundation

enum APIError: Error, LocalizedError {
    case invalidResponse
    case server(status: Int, detail: String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "서버 응답 형식이 잘못됐어요."
        case .server(let status, let detail):
            return "서버 오류 \(status): \(detail)"
        case .decoding(let err):
            return "디코딩 실패: \(err.localizedDescription)"
        case .transport(let err):
            return "통신 실패: \(err.localizedDescription)"
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.timeout
        config.timeoutIntervalForResource = APIConfig.resourceTimeout
        config.waitsForConnectivity = true   // 잠깐 끊기면 죽이지 말고 기다리기
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase

        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func ping() async throws -> Bool {
        let url = APIConfig.baseURL.appendingPathComponent("/health")
        do {
            let (_, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            return (200..<300).contains(http.statusCode)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error)
        }
    }

    /// 빠른 reachability 체크 — 5초 timeout, 별도 ephemeral session.
    /// 기존 `session` 은 30분 timeout + waitsForConnectivity 라서 연결 끊김 시 한참 매달림.
    /// generate 전에 이 메서드로 먼저 확인하면 연결 안 됐을 때 즉시 에러.
    func preflightPing() async throws {
        let url = APIConfig.baseURL.appendingPathComponent("/health")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        config.waitsForConnectivity = false
        let fastSession = URLSession(configuration: config)
        do {
            let (_, response) = try await fastSession.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw APIError.invalidResponse
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error)
        }
    }

    func generateImage(_ request: GenerateImageRequest) async throws -> GenerateImageResponse {
        let url = APIConfig.baseURL.appendingPathComponent("/generate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(request)

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard (200..<300).contains(http.statusCode) else {
                let detail = (try? decoder.decode(APIErrorDetail.self, from: data))?.detail
                    ?? String(data: data, encoding: .utf8)
                    ?? ""
                throw APIError.server(status: http.statusCode, detail: detail)
            }

            do {
                return try decoder.decode(GenerateImageResponse.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error)
        }
    }
}
