//
//  Constants.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  全局常量: 地图SDK Key、广告/统计 占位符ID、业务默认值。
//  对应 Android 项目 cn.navibeidou.beidou.Util.Constants
//

import Foundation

enum Constants {

    // MARK: - 百度地图 (首页地图 BaiduMapKit)
    /// 百度地图 iOS SDK Key (用户提供)
    static let baiduMapAPIKey = "ekdfUl7kfYptiR4tiW1yKeFynpfIwSPR"

    // MARK: - 高德地图 (导航/搜索/定位 AMapKit，用户提供)
    static let amapAPIKey = "797b484030ec43b0209f82ce67fdf98c"
    /// 高德开放平台 - Web服务API Key (与SDK Key类型不同，用于天气等REST接口；暂复用SDK Key，如调用失败需在高德开放平台单独申请"Web服务"类型Key)
    static let amapWebServiceKey = "797b484030ec43b0209f82ce67fdf98c"

    // MARK: - GroMore(穿山甲) 广告位 (用户提供)
    /// 穿山甲 App ID
    static let pangleAppID = "5837829"
    /// 开屏广告位ID (对应 Android Constants.OPEN_ID)
    static let openID = "104126678"
    /// 信息流广告位ID: iosnavi信息流
    static let streamID = "104127544"
    /// 720云景 Draw 信息流广告位ID（GroMore 原生自渲染）
    static let cloudPanoramaDrawID = "104149710"
    /// Banner广告位ID: iosnavibanner
    static let bannerID = "104128385"
    /// 激励视频广告位ID: iosnavi激励
    static let rewardedID = "104128290"

    // MARK: - 友盟统计
    static let umengAppKey = "6a29e92bcbfa69595158af33"
    static let umengChannel = "App Store"

    // MARK: - 法律文档
    /// 隐私政策网页地址
    static let privacyPolicyURL = URL(string: "https://www.cjym123.cn/privacy_navi.html")!

    // MARK: - 业务默认值 (对应 Android Constants.java)
    /// 默认城市
    static var city = "北京"
    /// 是否关闭广告 (后端下发覆盖)
    static var isCloseAd = false
    /// 是否启用页面内模板广告。进入页面后延迟加载，避免页面切换动画期间触发 GroMore 视图崩溃。
    static var isInlineTemplateAdEnabled = true
    /// 信息流/插屏广告定时加载次数
    static var adLoadCount = 3
    /// 信息流/插屏广告定时加载间隔(秒)
    static var adLoadInterval: TimeInterval = 3.0

    // MARK: - App信息
    static var appName: String { L10n.appName }

    // MARK: - 默认坐标 (对应 BaseActivity 测试用经纬度)
    /// 默认终点: 北京国际文化城附近
    static let defaultEndLat = 40.084894
    static let defaultEndLon = 116.603039
    /// 默认起点
    static let defaultStartLat = 39.825934
    static let defaultStartLon = 116.342972
}
