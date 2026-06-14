//
//  WeatherManager.swift
//  withu (iOS)
//

import Foundation
import CoreLocation

enum WeatherError: LocalizedError {
    case locationDenied
    case noLocation
    case network(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .locationDenied:   return "위치 권한이 없어요. 설정에서 켜주세요."
        case .noLocation:       return "현재 위치를 찾지 못했어요."
        case .network(let e):   return "날씨 통신 실패: \(e.localizedDescription)"
        case .decoding(let e):  return "날씨 응답 해석 실패: \(e.localizedDescription)"
        }
    }
}

/// 사용자 위치 → Open-Meteo 무료 API → 날씨 스냅샷.
/// 30분 캐시. 권한 안 받았을 땐 처음 호출에 한해 권한 요청.
@Observable
@MainActor
final class WeatherManager: NSObject {
    static let shared = WeatherManager()

    private(set) var snapshot: WeatherSnapshot?
    private(set) var isFetching: Bool = false
    private(set) var lastError: String?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    @ObservationIgnored private let locationManager: CLLocationManager
    @ObservationIgnored private static let cacheTTL: TimeInterval = 30 * 60

    private override init() {
        self.locationManager = CLLocationManager()
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        self.authorizationStatus = self.locationManager.authorizationStatus
    }

    /// 캐시 유효하면 skip. 아니면 위치 → API 흐름 시작.
    func refresh(force: Bool = false) {
        if !force,
           let last = snapshot,
           Date().timeIntervalSince(last.timestamp) < Self.cacheTTL {
            return
        }
        isFetching = true
        lastError = nil

        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            // 권한 시트 응답 → locationManagerDidChangeAuthorization
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .denied, .restricted:
            isFetching = false
            lastError = WeatherError.locationDenied.errorDescription
        @unknown default:
            isFetching = false
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension WeatherManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                self.isFetching = false
                self.lastError = WeatherError.locationDenied.errorDescription
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        let lat = loc.coordinate.latitude
        let lon = loc.coordinate.longitude
        Task { @MainActor in
            await self.fetchOpenMeteo(lat: lat, lon: lon)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            self.isFetching = false
            self.lastError = "위치 조회 실패: \(error.localizedDescription)"
        }
    }
}

// MARK: - Open-Meteo

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
    }
    struct Daily: Decodable {
        let time: [String]?
        let sunrise: [String]?
        let sunset: [String]?
    }
    let current: Current
    let daily: Daily?
}

extension WeatherManager {
    /// Open-Meteo 의 일출/일몰은 "yyyy-MM-dd'T'HH:mm" (위치 local TZ, no offset).
    /// `timezone=auto` 로 요청했으니 위치 로컬 시각. user TZ 와 같다고 가정 (대부분 케이스).
    private static let openMeteoLocalFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func fetchOpenMeteo(lat: Double, lon: Double) async {
        defer { isFetching = false }
        let urlString =
            "https://api.open-meteo.com/v1/forecast" +
            "?latitude=\(lat)&longitude=\(lon)" +
            "&current=temperature_2m,weather_code" +
            "&daily=sunrise,sunset&timezone=auto"

        guard let url = URL(string: urlString) else {
            lastError = "URL 생성 실패"
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let sunriseStr = decoded.daily?.sunrise?.first
            let sunsetStr = decoded.daily?.sunset?.first
            let snap = WeatherSnapshot(
                condition: WeatherCondition(wmoCode: decoded.current.weather_code),
                temperatureC: decoded.current.temperature_2m,
                timestamp: Date(),
                sunrise: sunriseStr.flatMap { Self.openMeteoLocalFormatter.date(from: $0) },
                sunset: sunsetStr.flatMap { Self.openMeteoLocalFormatter.date(from: $0) }
            )
            self.snapshot = snap
            self.lastError = nil
        } catch let urlError as URLError {
            self.lastError = WeatherError.network(urlError).errorDescription
        } catch {
            self.lastError = WeatherError.decoding(error).errorDescription
        }
    }
}
