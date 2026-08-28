//
//  PangleSplashAdManager.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  穿山甲(GroMore)开屏广告管理类。对应 Android SplashActivity 的开屏Ad加载逻辑。
//
//  注意事项:
//  1. 需要在SDK初始化成功后再发起广告请求
//  2. 融合场景下仅支持自渲染开屏
//  3. 加载成功(loadSuccess)回调中调用show展示广告
//

import Foundation
import UIKit

#if canImport(BUAdSDK)
import BUAdSDK
#endif

final class PangleSplashAdManager: NSObject {

    static let shared = PangleSplashAdManager()

    /// 开屏广告位ID (对应 Android Constants.OPEN_ID)
    static let defaultSplashSlotID = Constants.openID

    #if canImport(BUAdSDK)
    private var splashAd: BUSplashAd?
    #endif

    private var isLoading = false
    private var didRequestSplashThisSession = false
    private var completionHandler: ((Bool, Error?) -> Void)?

    /// 广告关闭后回调 (无论用户点击/倒计时结束)，用于跳转主页面
    var onClose: (() -> Void)?

    var shouldRequestSplashThisSession: Bool {
        !didRequestSplashThisSession && !isLoading
    }

    private override init() {
        super.init()
    }

    func loadAndShowDefaultSplashAd(completion: ((Bool, Error?) -> Void)? = nil) {
        loadAndShowSplashAd(slotID: Self.defaultSplashSlotID, completion: completion)
    }

    func resetSplashRequestState() {
        didRequestSplashThisSession = false
    }

    func cancelSplashAd() {
        isLoading = false
        completionHandler = nil
        onClose = nil
        #if canImport(BUAdSDK)
        splashAd?.mediation?.destoryAd()
        splashAd = nil
        #endif
    }

    /// 加载并展示开屏广告
    /// - Parameters:
    ///   - slotID: 广告位ID
    ///   - tolerateTimeout: 超时时间(秒)，默认3秒(对应 Android AD_TIME_OUT=3000ms)
    ///   - completion: 完成回调，true表示已展示广告，false表示无广告/失败(应直接进入主页)
    func loadAndShowSplashAd(
        slotID: String,
        tolerateTimeout: TimeInterval = 3.0,
        completion: ((Bool, Error?) -> Void)? = nil
    ) {
        #if canImport(BUAdSDK)
        guard SpUtil.bool(.agreementAccepted) else {
            completion?(false, nil)
            return
        }
        guard shouldRequestSplashThisSession else {
            completion?(false, nil)
            return
        }
        guard !Constants.shouldCloseSplashAd else {
            didRequestSplashThisSession = true
            completion?(false, nil)
            return
        }

        guard PangleAdManager.shared.isSDKInitialized() else {
            PangleAdManager.shared.initialize { [weak self] success in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if success {
                        self.loadAndShowSplashAd(slotID: slotID, tolerateTimeout: tolerateTimeout, completion: completion)
                    } else {
                        let error = NSError(domain: "PangleSplashAdManager", code: -1,
                                             userInfo: [NSLocalizedDescriptionKey: "广告SDK初始化失败"])
                        completion?(false, error)
                    }
                }
            }
            return
        }

        guard !isLoading else { return }
        didRequestSplashThisSession = true
        isLoading = true
        self.completionHandler = completion

        let slotAd = BUAdSlot()
        slotAd.id = slotID

        splashAd = BUSplashAd(slot: slotAd, adSize: UIScreen.main.bounds.size)
        splashAd?.delegate = self
        splashAd?.tolerateTimeout = tolerateTimeout
        splashAd?.loadData()
        #else
        didRequestSplashThisSession = true
        let error = NSError(domain: "PangleSplashAdManager", code: -2,
                             userInfo: [NSLocalizedDescriptionKey: "穿山甲SDK未安装"])
        completion?(false, error)
        #endif
    }

    private func getRootViewController() -> UIViewController? {
        let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        return windowScene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    }
}

// MARK: - BUMSplashAdDelegate

#if canImport(BUAdSDK)
extension PangleSplashAdManager: BUMSplashAdDelegate {

    func splashAdLoadSuccess(_ splashAd: BUSplashAd) {
        guard let rootViewController = getRootViewController() else {
            isLoading = false
            let error = NSError(domain: "PangleSplashAdManager", code: -3,
                                 userInfo: [NSLocalizedDescriptionKey: "未找到 rootViewController"])
            completionHandler?(false, error)
            completionHandler = nil
            return
        }
        splashAd.showSplashView(inRootViewController: rootViewController)
    }

    func splashAdLoadFail(_ splashAd: BUSplashAd, error: BUAdError?) {
        isLoading = false
        logMediationLoadInfo(for: splashAd, stage: "loadFail")
        let nsError = NSError(domain: "PangleSplashAdManager", code: Int(error?.code ?? -1),
                               userInfo: [NSLocalizedDescriptionKey: error?.localizedDescription ?? "未知错误"])
        completionHandler?(false, nsError)
        completionHandler = nil
    }

    func splashAdRenderSuccess(_ splashAd: BUSplashAd) {}

    func splashAdRenderFail(_ splashAd: BUSplashAd, error: BUAdError?) {
        isLoading = false
        logMediationLoadInfo(for: splashAd, stage: "renderFail")
        completionHandler?(false, error)
        completionHandler = nil
    }

    func splashAdWillShow(_ splashAd: BUSplashAd) {}

    func splashAdDidShow(_ splashAd: BUSplashAd) {
        isLoading = false
        completionHandler?(true, nil)
        completionHandler = nil
    }

    func splashAdDidClick(_ splashAd: BUSplashAd) {}

    func splashAdDidClose(_ splashAd: BUSplashAd, closeType: BUSplashAdCloseType) {
        isLoading = false
        splashAd.mediation?.destoryAd()
        self.splashAd = nil
        onClose?()
    }

    func splashAdViewControllerDidClose(_ splashAd: BUSplashAd) {}

    func splashDidCloseOtherController(_ splashAd: BUSplashAd, interactionType: BUInteractionType) {}

    func splashVideoAdDidPlayFinish(_ splashAd: BUSplashAd, didFailWithError error: Error?) {}

    func splashAdDidShowFailed(_ splashAd: BUSplashAd, error: Error) {
        isLoading = false
        logMediationLoadInfo(for: splashAd, stage: "showFail")
        completionHandler?(false, error)
        completionHandler = nil
        onClose?()
    }

    private func logMediationLoadInfo(for splashAd: BUSplashAd, stage: String) {
        guard let mediation = splashAd.mediation else {
            print("❌ GroMore开屏广告失败[\(stage)]: 无 mediation 信息")
            return
        }

        let loadInfos = mediation.getAdLoadInfoList()
        if loadInfos.isEmpty {
            print("❌ GroMore开屏广告失败[\(stage)]: getAdLoadInfoList 为空")
        } else {
            print("❌ GroMore开屏广告失败[\(stage)] ADN详情 begin")
            loadInfos.enumerated().forEach { index, info in
                let customName = info.customAdnName ?? "-"
                print("  [\(index)] adn=\(info.adnName), custom=\(customName), rit=\(info.mediationRit), code=\(info.errCode), msg=\(info.errMsg), userInfo=\(info.errUserInfo ?? [:])")
            }
            print("❌ GroMore开屏广告失败[\(stage)] ADN详情 end")
        }

        let waterfallMessages = mediation.waterfallFillFailMessages()
        if !waterfallMessages.isEmpty {
            print("❌ GroMore开屏广告 waterfallFillFailMessages: \(waterfallMessages)")
        }
    }
}
#endif
