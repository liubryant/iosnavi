//
//  UMengAnalytics.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  友盟统计管理类。
//
//  合规说明: 根据工信部要求，SDK初始化必须在用户同意隐私政策后进行。
//  initialize() 仅在以下两个时机调用:
//  1. 首次启动: 用户在 AgreementViewController 中点击"同意"后
//  2. 非首次启动: App启动时检查用户已同意隐私政策后自动初始化
//

import Foundation

#if canImport(UMCommon)
import UMCommon
#endif

final class UMengAnalytics {
    static let shared = UMengAnalytics()

    private let appKey = Constants.umengAppKey
    private let channel = Constants.umengChannel
    private var isInitialized = false

    private init() {}

    /// 初始化友盟统计 (⚠️ 仅在用户同意隐私政策后调用)
    func initialize() {
        guard SpUtil.bool(.agreementAccepted) else { return }
        guard !isInitialized else { return }

        #if canImport(UMCommon)
        UMConfigure.initWithAppkey(appKey, channel: channel)
        #if DEBUG
        UMConfigure.setLogEnabled(true)
        #else
        UMConfigure.setLogEnabled(false)
        #endif
        isInitialized = true
        print("✅ 友盟统计初始化成功 - AppKey: \(appKey)")
        #else
        print("⚠️ 友盟统计SDK未安装，请先执行 pod install")
        #endif
    }

    /// 记录事件
    func logEvent(_ eventId: String, attributes: [String: Any]? = nil) {
        guard SpUtil.bool(.agreementAccepted), isInitialized else { return }

        #if canImport(UMCommon)
        if let attributes {
            MobClick.event(eventId, attributes: attributes)
        } else {
            MobClick.event(eventId)
        }
        #endif
    }

    /// 页面开始统计
    func pageBegin(_ pageName: String) {
        guard SpUtil.bool(.agreementAccepted), isInitialized else { return }

        #if canImport(UMCommon)
        MobClick.beginLogPageView(pageName)
        #endif
    }

    /// 页面结束统计
    func pageEnd(_ pageName: String) {
        guard SpUtil.bool(.agreementAccepted), isInitialized else { return }

        #if canImport(UMCommon)
        MobClick.endLogPageView(pageName)
        #endif
    }
}
