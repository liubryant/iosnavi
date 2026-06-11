//
//  PangleBannerAdManager.swift
//  beidou
//
//  穿山甲(GroMore) Banner/信息流模板广告管理类。
//  对应 Android MapActivity.loadExpressAd(Constants.BANNER_ID, 300, 250)，
//  在侧边栏 banner_container 中加载展示。
//

import Foundation
import UIKit

#if canImport(BUAdSDK)
import BUAdSDK
#endif

final class PangleBannerAdManager: NSObject {

    static let shared = PangleBannerAdManager()

    #if canImport(BUAdSDK)
    private var bannerView: BUNativeExpressBannerView?
    private weak var containerView: UIView?
    private weak var rootViewController: UIViewController?
    #endif

    private override init() {
        super.init()
    }

    /// 在指定容器中加载并展示Banner广告 (对应 Android Constants.BANNER_ID, 300x250dp)
    func loadAd(in container: UIView, rootViewController: UIViewController) {
        #if canImport(BUAdSDK)
        guard Constants.isInlineTemplateAdEnabled,
              PangleAdManager.shared.isSDKInitialized(),
              !Constants.isCloseAd else { return }

        DispatchQueue.main.async { [weak self, weak container, weak rootViewController] in
            guard let self, let container, let rootViewController else { return }
            self.loadAdAfterLayout(in: container, rootViewController: rootViewController)
        }
        #endif
    }

    private func loadAdAfterLayout(in container: UIView, rootViewController: UIViewController) {
        #if canImport(BUAdSDK)
        container.superview?.layoutIfNeeded()
        container.layoutIfNeeded()

        let width = container.bounds.width > 0 ? container.bounds.width : UIScreen.main.bounds.width - 24
        guard width > 0, container.window != nil else { return }

        container.subviews.forEach { $0.removeFromSuperview() }
        containerView = container
        self.rootViewController = rootViewController

        let adSize = CGSize(width: width, height: 250)
        let slot = BUAdSlot()
        slot.id = Constants.bannerID
        slot.adType = .banner
        slot.position = .bottom
        slot.adSize = adSize

        let banner = BUNativeExpressBannerView(slot: slot, rootViewController: rootViewController, adSize: adSize)
        banner.delegate = self
        banner.frame = container.bounds
        banner.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(banner)
        banner.loadAdData()
        bannerView = banner
        #endif
    }
}

#if canImport(BUAdSDK)
extension PangleBannerAdManager: BUMNativeExpressBannerViewDelegate {

    func nativeExpressBannerAdViewDidLoad(_ bannerAdView: BUNativeExpressBannerView) {
        print("✅ Banner广告加载成功")
    }

    func nativeExpressBannerAdView(_ bannerAdView: BUNativeExpressBannerView, didLoadFailWithError error: Error?) {
        print("⚠️ Banner广告加载失败: \(error?.localizedDescription ?? "未知错误")")
    }

    func nativeExpressBannerAdViewRenderSuccess(_ bannerAdView: BUNativeExpressBannerView) {
        print("✅ Banner广告渲染成功")
    }

    func nativeExpressBannerAdViewRenderFail(_ bannerAdView: BUNativeExpressBannerView, error: Error?) {
        print("⚠️ Banner广告渲染失败: \(error?.localizedDescription ?? "未知错误")")
        bannerAdView.removeFromSuperview()
    }
}
#endif
