//
//  UrlConstants.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  后端接口地址常量。对应 Android 项目 cn.navibeidou.beidou.Util.UrlUtil
//

import Foundation

enum UrlConstants {
    /// 广告权限/版本信息查询接口 (注意: http 非 https，已在 Info.plist 中配置 ATS 例外)
    static let permissionInfo = "http://cjym123.cn/api/info"

    /// 高德 Web服务 - 天气查询接口
    static let amapWeather = "https://restapi.amap.com/v3/weather/weatherInfo"

    /// Open-Meteo - 免费天气预报接口，用于火烧云预测
    static let openMeteoForecast = "https://api.open-meteo.com/v1/forecast"

    /// 高德 Web服务 - 关键字POI搜索 (终点搜索)
    static let amapPlaceText = "https://restapi.amap.com/v3/place/text"

    /// 高德 Web服务 - 周边POI搜索
    static let amapPlaceAround = "https://restapi.amap.com/v3/place/around"

    /// 用户反馈页面
    static let feedback = "http://cjym123.cn/h5/feedback.html"

    /// 四创科技 - 台风实时路径专业版 H5
    static let typhoonPath = "https://tf.istrongcloud.com/release/index-sc.html"
}
