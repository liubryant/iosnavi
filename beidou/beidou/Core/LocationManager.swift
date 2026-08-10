//
//  LocationManager.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  高德定位+逆地理编码封装。对应 Android MapActivity 中 AMapLocationClient +
//  GeocodeSearch.OnGeocodeSearchListener 的定位/逆地理编码逻辑。
//

import Foundation
import CoreLocation

#if canImport(AMapLocationKit)
import AMapLocationKit
#endif

struct CurrentLocation {
    let latitude: Double
    let longitude: Double
    /// 海拔高度，单位米。CoreLocation 在 verticalAccuracy 无效时不展示。
    let altitude: Double?
    /// 当前城市 (用于天气/POI接口)
    let city: String
    /// 行政区划编码 (用于高德天气 Web API)
    let adcode: String?
    /// 逆地理编码格式化地址
    let address: String
}

final class LocationManager: NSObject {

    static let shared = LocationManager()

    #if canImport(AMapLocationKit)
    private let manager = AMapLocationManager()
    #endif

    private let clManager = CLLocationManager()
    private var pendingLocationCompletions: [(CurrentLocation?) -> Void] = []
    private var authorizedLocationCompletions: [(CurrentLocation?) -> Void] = []
    private var isLocationRequestInFlight = false

    private override init() {
        super.init()
        clManager.delegate = self
        #if canImport(AMapLocationKit)
        manager.locationTimeout = 5
        manager.reGeocodeTimeout = 5
        manager.allowsBackgroundLocationUpdates = false
        #endif
    }

    /// 请求系统定位授权
    func requestAuthorization() {
        guard SpUtil.bool(.agreementAccepted) else { return }
        clManager.requestWhenInUseAuthorization()
    }

    /// 单次定位 + 逆地理编码 (对应 onLocationChanged + onRegeocodeSearched)
    func requestLocation(completion: @escaping (CurrentLocation?) -> Void) {
        guard SpUtil.bool(.agreementAccepted) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        switch authorizationStatus {
        case .notDetermined:
            pendingLocationCompletions.append(completion)
            clManager.requestWhenInUseAuthorization()
            return
        case .restricted, .denied:
            DispatchQueue.main.async { completion(nil) }
            return
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            DispatchQueue.main.async { completion(nil) }
            return
        }
        requestAuthorizedLocation(completion: completion)
    }

    private var authorizationStatus: CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return clManager.authorizationStatus
        }
        return CLLocationManager.authorizationStatus()
    }

    private func requestAuthorizedLocation(completion: @escaping (CurrentLocation?) -> Void) {
        authorizedLocationCompletions.append(completion)
        guard !isLocationRequestInFlight else { return }
        isLocationRequestInFlight = true

        #if canImport(AMapLocationKit)
        let accepted = manager.requestLocation(withReGeocode: true) { [weak self] location, reGeocode, error in
            guard let self else { return }
            guard let location, error == nil else {
                self.finishAuthorizedLocationRequest(with: nil)
                return
            }
            let city = reGeocode?.city?.isEmpty == false ? (reGeocode?.city ?? Constants.city) : Constants.city
            let adcode = reGeocode?.adcode?.isEmpty == false ? reGeocode?.adcode : nil
            let address = reGeocode?.formattedAddress ?? ""
            let altitude = location.verticalAccuracy >= 0 ? location.altitude : nil
            let result = CurrentLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: altitude,
                city: city,
                adcode: adcode,
                address: address
            )
            Self.cache(result)
            self.finishAuthorizedLocationRequest(with: result)
        }
        if !accepted {
            finishAuthorizedLocationRequest(with: nil)
        }
        #else
        finishAuthorizedLocationRequest(with: nil)
        #endif
    }

    private func finishAuthorizedLocationRequest(with location: CurrentLocation?) {
        DispatchQueue.main.async {
            self.isLocationRequestInFlight = false
            let completions = self.authorizedLocationCompletions
            self.authorizedLocationCompletions.removeAll()
            completions.forEach { $0(location) }
        }
    }

    private func flushPendingLocationRequestsIfNeeded(status: CLAuthorizationStatus) {
        guard !pendingLocationCompletions.isEmpty else { return }
        let completions = pendingLocationCompletions
        pendingLocationCompletions.removeAll()

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            completions.forEach { requestAuthorizedLocation(completion: $0) }
        case .restricted, .denied:
            completions.forEach { completion in
                DispatchQueue.main.async { completion(nil) }
            }
        case .notDetermined:
            pendingLocationCompletions.append(contentsOf: completions)
        @unknown default:
            completions.forEach { completion in
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    private static func cache(_ location: CurrentLocation) {
        SpUtil.setDouble(location.latitude, for: .lastLatitude)
        SpUtil.setDouble(location.longitude, for: .lastLongitude)
        if let altitude = location.altitude {
            SpUtil.setDouble(altitude, for: .lastAltitude)
        } else {
            SpUtil.remove(.lastAltitude)
        }
        SpUtil.setString(location.city, for: .lastCity)
        SpUtil.setString(location.adcode ?? "", for: .lastAdcode)
        SpUtil.setString(location.address, for: .lastAddress)
        Constants.city = location.city
    }

    /// 上次缓存的定位结果 (定位失败/SDK未安装时的兜底)
    var lastKnownLocation: CurrentLocation? {
        let lat = SpUtil.double(.lastLatitude)
        let lon = SpUtil.double(.lastLongitude)
        guard lat != 0, lon != 0 else { return nil }
        return CurrentLocation(
            latitude: lat,
            longitude: lon,
            altitude: SpUtil.optionalDouble(.lastAltitude),
            city: SpUtil.string(.lastCity, default: Constants.city),
            adcode: {
                let value = SpUtil.string(.lastAdcode)
                return value.isEmpty ? nil : value
            }(),
            address: SpUtil.string(.lastAddress)
        )
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = manager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        flushPendingLocationRequestsIfNeeded(status: status)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        flushPendingLocationRequestsIfNeeded(status: status)
    }
}
