//
//  PangleRewardAdManager.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
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
    private var completion: ((Bool) -> Void)?
    private var hasCompleted = false
    private var didEarnReward = false

    private override init() {
        super.init()
    }

    func showRewardAd(in rootViewController: UIViewController, completion: @escaping () -> Void) {
        showRewardAd(in: rootViewController) { didComplete in
            if didComplete {
                completion()
            }
        }
    }

    func showRewardAd(in rootViewController: UIViewController, completion: @escaping (Bool) -> Void) {
        guard SpUtil.bool(.agreementAccepted) else {
            completion(false)
            return
        }
        guard !Constants.isCloseAd else {
            completion(true)
            return
        }
        guard PangleAdManager.shared.isSDKInitialized() else {
            PangleAdManager.shared.initialize { [weak self, weak rootViewController] success in
                DispatchQueue.main.async {
                    guard success, let rootViewController else {
                        completion(true)
                        return
                    }
                    self?.showRewardAd(in: rootViewController, completion: completion)
                }
            }
            return
        }

        #if canImport(BUAdSDK)
        self.rootViewController = rootViewController
        self.completion = completion
        hasCompleted = false
        didEarnReward = false

        let model = BURewardedVideoModel()
        model.userId = UIDevice.current.identifierForVendor?.uuidString ?? "ios_user"
        model.rewardName = L10n.t("around.reward_name")
        model.rewardAmount = 1

        let ad = BUNativeExpressRewardedVideoAd(slotID: Constants.rewardedID, rewardedVideoModel: model)
        ad.delegate = self
        ad.loadData()
        rewardAd = ad
        #else
        completion(true)
        #endif
    }

    private func finish(didComplete: Bool) {
        guard !hasCompleted else { return }
        hasCompleted = true
        let handler = completion
        completion = nil
        rootViewController = nil
        didEarnReward = false
        #if canImport(BUAdSDK)
        rewardAd = nil
        #endif
        handler?(didComplete)
    }
}

#if canImport(BUAdSDK)
extension PangleRewardAdManager: BUMNativeExpressRewardedVideoAdDelegate, BUCustomEventProtocol {

    func nativeExpressRewardedVideoAdDidDownLoadVideo(_ rewardedVideoAd: BUNativeExpressRewardedVideoAd) {
        guard let rootViewController else {
            finish(didComplete: true)
            return
        }
        if rewardedVideoAd.mediation?.isReady == false {
            finish(didComplete: true)
            return
        }
        let didShow = rewardedVideoAd.show(fromRootViewController: rootViewController)
        if !didShow {
            finish(didComplete: true)
        }
    }

    func nativeExpressRewardedVideoAd(_ rewardedVideoAd: BUNativeExpressRewardedVideoAd, didFailWithError error: Error?) {
        print("⚠️ 激励视频广告加载失败: \(error?.localizedDescription ?? "未知错误")")
        finish(didComplete: true)
    }

    func nativeExpressRewardedVideoAdDidShowFailed(_ rewardedVideoAd: BUNativeExpressRewardedVideoAd, error: Error) {
        print("⚠️ 激励视频广告展示失败: \(error.localizedDescription)")
        finish(didComplete: true)
    }

    func nativeExpressRewardedVideoAdDidPlayFinish(_ rewardedVideoAd: BUNativeExpressRewardedVideoAd, didFailWithError error: Error?) {
        if error == nil {
            didEarnReward = true
        }
    }

    func nativeExpressRewardedVideoAdServerRewardDidSucceed(_ rewardedVideoAd: BUNativeExpressRewardedVideoAd, verify: Bool) {
        if verify {
            didEarnReward = true
        }
    }

    func nativeExpressRewardedVideoAdDidClose(_ rewardedVideoAd: BUNativeExpressRewardedVideoAd) {
        finish(didComplete: didEarnReward)
    }
}
#endif
