//
//  PangleAdManager.swift
//  beidou
//
//  穿山甲(GroMore)广告SDK管理类。
//
//  合规说明: 根据工信部要求，SDK初始化必须在用户同意隐私政策后进行。
//  initialize() 仅在以下两个时机调用:
//  1. 首次启动: 用户在 AgreementViewController 中点击"同意"后
//  2. 非首次启动: App启动时检查用户已同意隐私政策后自动初始化
//

import Foundation
import UIKit

#if canImport(BUAdSDK)
import BUAdSDK
#endif

final class PangleAdManager {
    static let shared = PangleAdManager()

    let appID = Constants.pangleAppID

    private var isInitialized = false
    private var isInitializing = false
    private var pendingCallbacks: [(Bool) -> Void] = []

    private init() {}

    /// 初始化穿山甲广告SDK (聚合版本)。⚠️ 仅在用户同意隐私政策后调用
    func initialize(completion: ((Bool) -> Void)? = nil) {
        guard SpUtil.bool(.agreementAccepted) else {
            completion?(false)
            return
        }
        guard !isInitialized else {
            completion?(true)
            return
        }

        if let completion {
            pendingCallbacks.append(completion)
        }

        guard !isInitializing else { return }
        isInitializing = true

        #if canImport(BUAdSDK)
        let configuration = BUAdSDKConfiguration()
        configuration.appID = appID
        #if DEBUG
        configuration.sdkdebug = true
        configuration.debugLog = NSNumber(value: 1)
        #endif

        // 聚合模式 (仅可设置一次)
        configuration.useMediation = true

        // 隐私合规配置 (0=不限制/不禁止)
        configuration.mediation.limitPersonalAds = NSNumber(integerLiteral: 0)
        configuration.mediation.limitProgrammaticAds = NSNumber(integerLiteral: 0)
        configuration.mediation.forbiddenIDFA = NSNumber(integerLiteral: 0)

        configuration.themeStatus = NSNumber(integerLiteral: 0)

        BUAdSDKManager.start(asyncCompletionHandler: { [weak self] success, error in
            if success {
                self?.isInitialized = true
                print("✅ 穿山甲广告SDK初始化成功 - AppID: \(self?.appID ?? "")")
            } else {
                print("❌ 穿山甲广告SDK初始化失败: \(error?.localizedDescription ?? "未知错误")")
            }
            self?.finishPendingCallbacks(success: success)
        })
        #else
        print("⚠️ 穿山甲广告SDK未安装，请先执行 pod install")
        finishPendingCallbacks(success: false)
        #endif
    }

    func isSDKInitialized() -> Bool {
        isInitialized
    }

    private func finishPendingCallbacks(success: Bool) {
        isInitializing = false
        let callbacks = pendingCallbacks
        pendingCallbacks.removeAll()
        callbacks.forEach { $0(success) }
    }
}
