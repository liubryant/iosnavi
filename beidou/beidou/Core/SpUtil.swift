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
        /// 上次定位海拔
        case lastAltitude = "last_altitude"
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
        /// 上次首页 720 云景推荐弹窗展示的景区标识，用于下次冷启动尽量换一项
        case lastCloudPanoramaWelcomeID = "last_cloud_panorama_welcome_id"
        /// 首页 720 云景推荐最近一次展示时间，用于按自然日限制次数
        case cloudPanoramaWelcomeLastShownAt = "cloud_panorama_welcome_last_shown_at"
        /// 首页 720 云景推荐当天累计展示次数
        case cloudPanoramaWelcomeDailyCount = "cloud_panorama_welcome_daily_count"
        /// 上次火烧云预测结果 JSON 缓存
        case sunsetPredictionCache = "sunset_prediction_cache"
        /// 上次实时天气描述，用于首页底部天气胶囊复用天气页内容
        case lastLiveWeather = "last_live_weather"
        /// 上次实时天气温度，用于首页底部天气胶囊复用天气页内容
        case lastLiveTemperature = "last_live_temperature"
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

    static func optionalDouble(_ key: Key) -> Double? {
        guard defaults.object(forKey: key.rawValue) != nil else { return nil }
        return defaults.double(forKey: key.rawValue)
    }

    static func remove(_ key: Key) {
        defaults.removeObject(forKey: key.rawValue)
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

    static func stringArray(_ key: Key) -> [String] {
        defaults.stringArray(forKey: key.rawValue) ?? []
    }

    static func setStringArray(_ value: [String], for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    static func data(_ key: Key) -> Data? {
        defaults.data(forKey: key.rawValue)
    }

    static func setData(_ value: Data, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
}
