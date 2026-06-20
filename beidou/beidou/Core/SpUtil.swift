//
//  SpUtil.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  UserDefaults 轻封装。对应 Android 项目 cn.navibeidou.beidou.Util.SpUtil
//

import Foundation

enum SpUtil {

    enum Key: String {
        /// 是否已同意隐私协议/用户协议
        case agreementAccepted = "agreement_accepted"
        /// 上次定位纬度
        case lastLatitude = "last_latitude"
        /// 上次定位经度
        case lastLongitude = "last_longitude"
        /// 上次定位城市
        case lastCity = "last_city"
        /// 上次定位行政区划编码
        case lastAdcode = "last_adcode"
        /// 上次定位地址描述
        case lastAddress = "last_address"
        /// 当前地图类型 (普通图/卫星图/路况图)
        case mapType = "map_type"
        /// 是否开启路况图层
        case trafficEnabled = "traffic_enabled"
        /// 上次广告加载时间戳
        case lastAdLoadTime = "last_ad_load_time"
        /// 首次进入首页的 720 云景推荐弹窗是否已展示
        case cloudPanoramaWelcomeShown = "cloud_panorama_welcome_shown"
    }

    private static let defaults = UserDefaults.standard

    static func bool(_ key: Key, default defaultValue: Bool = false) -> Bool {
        defaults.object(forKey: key.rawValue) == nil ? defaultValue : defaults.bool(forKey: key.rawValue)
    }

    static func setBool(_ value: Bool, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    static func double(_ key: Key, default defaultValue: Double = 0) -> Double {
        defaults.object(forKey: key.rawValue) == nil ? defaultValue : defaults.double(forKey: key.rawValue)
    }

    static func setDouble(_ value: Double, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    static func string(_ key: Key, default defaultValue: String = "") -> String {
        defaults.string(forKey: key.rawValue) ?? defaultValue
    }

    static func setString(_ value: String, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    static func integer(_ key: Key, default defaultValue: Int = 0) -> Int {
        defaults.object(forKey: key.rawValue) == nil ? defaultValue : defaults.integer(forKey: key.rawValue)
    }

    static func setInteger(_ value: Int, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
}
