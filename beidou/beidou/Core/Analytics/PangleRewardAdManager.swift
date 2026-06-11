//
//  PangleRewardAdManager.swift
//  beidou
//
//  GroMore 激励视频广告管理。
//

import Foundation
import UIKit

#if canImport(BUAdSDK)
import BUAdSDK
#endif

final class PangleRewardAdManager: NSObject {

    static let shared = PangleRewardAdManager()

    #if canImport(BUAdSDK)
    private var rewardAd: BUNativeExpressRewardedVideoAd?
    #endif

    private weak var rootViewController: UIViewController?
    private var completion: (() -> Void)?
    private var hasCompleted = false

    private override init() {
        super.init()
    }

    func showRewardAd(in rootViewController: UIViewController, completion: @escaping () -> Void) {
        guard !Constants.isCloseAd, PangleAdManager.shared.isSDKInitialized() else {
            completion()
            return
        }

        #if canImport(BUAdSDK)
        self.rootViewController = rootViewController
        self.completion = completion
        hasCompleted = false

        let model = BURewardedVideoModel()
        model.userId = UIDevice.current.identifierForVendor?.uuidString ?? "ios_user"
        model.rewardName = "周边搜索"
        model.rewardAmount = 1

        let ad = BUNativeExpressRewardedVideoAd(slotID: Constants.rewardedID, rewardedVideoModel: model)
        ad.delegate = self
        ad.loadData()
        rewardAd = ad
        #else
        completion()
        #endif
    }

    private func finish() {
        guard !hasCompleted else { return }
        hasCompleted = true
        let handler = completion
        completion = nil
        rewardAd = nil
        handler?()
    }
}

#if canImport(BUAdSDK)
extension PangleRewardAdManager: BUMNativeExpressRewardedVideoAdDelegate, BUCustomEventProtocol {

    func nativeExpressRewardedVideoAdDidDownLoadVideo(_ rewardedVideoAd: BUNativeExpressRewardedVideoAd) {
        guard let rootViewController else {
            finish()
            return
        }
        if rewardedVideoAd.mediation?.isReady == false {
            finish()
            return
        }
        let didShow = rewardedVideoAd.show(fromRootViewController: rootViewController)
        if !didShow {
            finish()
        }
    }

    func nativeExpressRewardedVideoAd(_ rewardedVideoAd: BUNativeExpressRewardedVideoAd, didFailWithError error: Error?) {
        print("⚠️ 激励视频广告加载失败: \(error?.localizedDescription ?? "未知错误")")
        finish()
    }

    func nativeExpressRewardedVideoAdDidShowFailed(_ rewardedVideoAd: BUNativeExpressRewardedVideoAd, error: Error) {
        print("⚠️ 激励视频广告展示失败: \(error.localizedDescription)")
        finish()
    }

    func nativeExpressRewardedVideoAdDidClose(_ rewardedVideoAd: BUNativeExpressRewardedVideoAd) {
        finish()
    }
}
#endif
