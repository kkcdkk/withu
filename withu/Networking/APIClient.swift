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
    /// 402 — 무료/크레딧 소진. balance 는 갱신된 잔액(있으면).
    case paymentRequired(balance: Entitlement?)

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
        case .paymentRequired:
            return "무료 횟수를 다 썼어요."
        }
    }
}

/// 모든 Error 를 사용자 친화 한국어 메시지로 변환.
/// catch 블록의 `error.localizedDescription` 대신 사용.
extension Error {
    var koreanizedDescription: String {
        if let api = self as? APIError {
            switch api {
            case .invalidResponse:
                return "서버 응답이 이상해요. 잠시 후 다시 시도해 주세요."
            case .server(let status, _):
                if status == 429 { return "요청이 너무 많아요. 잠시 후 다시 시도해 주세요." }
                if status >= 500 { return "서버에 문제가 생겼어요. 잠시 후 다시 시도해 주세요." }
                if status == 422 { return "프롬프트가 안전 정책에 걸렸어요. 단어를 살짝 바꿔서 다시 시도해 주세요." }
                return "서버 오류 (\(status)). 잠시 후 다시 시도해 주세요."
            case .decoding:
                return "결과를 읽을 수 없어요. 다시 시도해 주세요."
            case .transport(let inner):
                return (inner as Error).koreanizedDescription
            case .paymentRequired:
                return "무료 횟수를 다 썼어요. 충전하거나 구독해 주세요."
            }
        }
        if let urlErr = self as? URLError {
            switch urlErr.code {
            case .notConnectedToInternet:
                return "인터넷에 연결돼 있지 않아요. Wi-Fi 또는 셀룰러를 확인해 주세요."
            case .timedOut:
                return "응답이 너무 오래 걸려요. 잠시 후 다시 시도해 주세요."
            case .cannotConnectToHost, .cannotFindHost:
                return "서버에 연결할 수 없어요. 네트워크 또는 서버 상태를 확인해 주세요."
            case .networkConnectionLost:
                return "연결이 끊겼어요. 다시 시도해 주세요."
            case .cancelled:
                return "요청이 취소됐어요."
            default:
                return "네트워크 오류가 발생했어요. 다시 시도해 주세요."
            }
        }
        // 기본 — 시스템 로컬라이즈된 메시지 (영문일 수 있음) 보다 깔끔한 한국어 폴백
        return "오류가 발생했어요. 잠시 후 다시 시도해 주세요."
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

    // MARK: - 인증 (Phase 2)

    /// Sign in with Apple identityToken 으로 서버 세션 발급.
    func authenticateApple(identityToken: String) async throws -> AppleAuthResponse {
        let url = APIConfig.baseURL.appendingPathComponent("/auth/apple")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(AppleAuthRequest(identityToken: identityToken))
        return try await send(req, decode: AppleAuthResponse.self)
    }

    /// 계정 삭제 (Bearer 필요). 서버의 이 사용자 데이터 전체 삭제.
    func deleteAccount() async throws {
        let url = APIConfig.baseURL.appendingPathComponent("/me")
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 30   // 삭제는 짧게 — 생성용 session 의 30분 timeout 상속 방지
        if let sessionToken = KeychainStore.sessionToken() {
            req.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
        try await sendDiscardingBody(req)
    }

    /// 서버 권리 스냅샷 (Bearer 필요).
    func fetchMe() async throws -> Entitlement {
        let url = APIConfig.baseURL.appendingPathComponent("/me")
        var req = URLRequest(url: url)
        if let sessionToken = KeychainStore.sessionToken() {
            req.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
        return try await send(req, decode: MeResponse.self).entitlement
    }

    /// StoreKit 결제 JWS 를 서버에 제출해 멱등 적립 (Bearer 필요).
    func verifyPurchase(signedTransaction: String) async throws -> Entitlement {
        let url = APIConfig.baseURL.appendingPathComponent("/iap/verify")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let sessionToken = KeychainStore.sessionToken() {
            req.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try encoder.encode(IapVerifyRequest(signedTransaction: signedTransaction))
        return try await send(req, decode: MeResponse.self).entitlement
    }

    /// 할인코드 적용 (Bearer 필요).
    func redeem(code: String) async throws -> Entitlement {
        try await postCode(path: "/redeem", body: RedeemRequest(code: code))
    }

    /// 친구 추천코드 적용 (Bearer 필요).
    func applyReferral(code: String) async throws -> Entitlement {
        try await postCode(path: "/referral/apply", body: ReferralRequest(code: code))
    }

    private func postCode<B: Encodable>(path: String, body: B) async throws -> Entitlement {
        let url = APIConfig.baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let sessionToken = KeychainStore.sessionToken() {
            req.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try encoder.encode(body)
        return try await send(req, decode: MeResponse.self).entitlement
    }

    /// 공통 요청 → 본문 무시 (성공 status 만 확인). 계정 삭제 등 빈 응답용.
    private func sendDiscardingBody(_ request: URLRequest) async throws {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let detail = (try? decoder.decode(APIErrorDetail.self, from: data))?.detail
                    ?? String(data: data, encoding: .utf8) ?? ""
                throw APIError.server(status: http.statusCode, detail: detail)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error)
        }
    }

    /// 공통 요청 → 디코드.
    private func send<T: Decodable>(_ request: URLRequest, decode: T.Type) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let detail = (try? decoder.decode(APIErrorDetail.self, from: data))?.detail
                    ?? String(data: data, encoding: .utf8) ?? ""
                throw APIError.server(status: http.statusCode, detail: detail)
            }
            do { return try decoder.decode(T.self, from: data) }
            catch { throw APIError.decoding(error) }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error)
        }
    }

    /// 이미지 생성. kind: "single"|"batch" (서버 무료 버킷 구분), batchId: 일괄 세션 묶음.
    func generateImage(_ request: GenerateImageRequest,
                       kind: String = "single",
                       batchId: String? = nil) async throws -> GenerateImageResponse {
        let url = APIConfig.baseURL.appendingPathComponent("/generate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = APIConfig.apiToken, !token.isEmpty {
            req.setValue(token, forHTTPHeaderField: "X-Withu-Token")
        }
        if let sessionToken = KeychainStore.sessionToken() {
            req.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
        // 재시도 이중차감 방지 키 + 무료 버킷 구분
        req.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        req.setValue(kind, forHTTPHeaderField: "X-Withu-Kind")
        if let batchId {
            req.setValue(batchId, forHTTPHeaderField: "X-Withu-Batch")
        }
        req.httpBody = try encoder.encode(request)

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            // 402 — 무료/크레딧 소진
            if http.statusCode == 402 {
                let balance = (try? decoder.decode(PaymentRequiredResponse.self, from: data))?.balance
                throw APIError.paymentRequired(balance: balance)
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
