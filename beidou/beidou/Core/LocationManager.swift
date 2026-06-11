//
//  LocationManager.swift
//  beidou
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
    /// 当前城市 (用于天气/POI接口)
    let city: String
    /// 逆地理编码格式化地址
    let address: String
}

final class LocationManager: NSObject {

    static let shared = LocationManager()

    #if canImport(AMapLocationKit)
    private let manager = AMapLocationManager()
    #endif

    private let clManager = CLLocationManager()

    private override init() {
        super.init()
        #if canImport(AMapLocationKit)
        manager.locationTimeout = 5
        manager.reGeocodeTimeout = 5
        manager.allowsBackgroundLocationUpdates = false
        #endif
    }

    /// 请求系统定位授权
    func requestAuthorization() {
        clManager.requestWhenInUseAuthorization()
    }

    /// 单次定位 + 逆地理编码 (对应 onLocationChanged + onRegeocodeSearched)
    func requestLocation(completion: @escaping (CurrentLocation?) -> Void) {
        #if canImport(AMapLocationKit)
        manager.requestLocation(withReGeocode: true) { location, reGeocode, error in
            guard let location, error == nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let city = reGeocode?.city?.isEmpty == false ? (reGeocode?.city ?? Constants.city) : Constants.city
            let address = reGeocode?.formattedAddress ?? ""
            let result = CurrentLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                city: city,
                address: address
            )
            Self.cache(result)
            DispatchQueue.main.async { completion(result) }
        }
        #else
        DispatchQueue.main.async { completion(nil) }
        #endif
    }

    private static func cache(_ location: CurrentLocation) {
        SpUtil.setDouble(location.latitude, for: .lastLatitude)
        SpUtil.setDouble(location.longitude, for: .lastLongitude)
        SpUtil.setString(location.city, for: .lastCity)
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
            city: SpUtil.string(.lastCity, default: Constants.city),
            address: SpUtil.string(.lastAddress)
        )
    }
}
