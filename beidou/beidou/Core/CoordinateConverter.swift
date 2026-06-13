//
//  CoordinateConverter.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  GCJ02(高德/国测局坐标系) <-> BD09(百度坐标系) 互转。
//  首页地图为百度地图，但定位/逆地理编码使用高德 SDK (GCJ02)，
//  需转换后才能在 BMKMapView 上正确展示。
//

import Foundation
import CoreLocation

enum CoordinateConverter {

    private static let xPi = Double.pi * 3000.0 / 180.0

    /// GCJ02 (高德) -> BD09 (百度)
    static func gcj02ToBD09(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        let z = sqrt(lon * lon + lat * lat) + 0.00002 * sin(lat * xPi)
        let theta = atan2(lat, lon) + 0.000003 * cos(lon * xPi)
        let bdLon = z * cos(theta) + 0.0065
        let bdLat = z * sin(theta) + 0.006
        return CLLocationCoordinate2D(latitude: bdLat, longitude: bdLon)
    }

    /// BD09 (百度) -> GCJ02 (高德)
    static func bd09ToGCJ02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let bdLat = coordinate.latitude
        let bdLon = coordinate.longitude
        let x = bdLon - 0.0065
        let y = bdLat - 0.006
        let z = sqrt(x * x + y * y) - 0.00002 * sin(y * xPi)
        let theta = atan2(y, x) - 0.000003 * cos(x * xPi)
        let gcjLon = z * cos(theta)
        let gcjLat = z * sin(theta)
        return CLLocationCoordinate2D(latitude: gcjLat, longitude: gcjLon)
    }
}
