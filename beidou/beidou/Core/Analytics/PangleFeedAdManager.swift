//
//  PangleFeedAdManager.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  穿山甲(GroMore) 插屏/信息流广告管理类。
//  对应 Android Constants.java 中 adLoadCount(=3)/adLoadInterval(=3000ms) 的
//  定时重试加载逻辑：插屏广告加载失败时按间隔重试，最多 adLoadCount 次。
//

import Foundation
import UIKit

#if canImport(BUAdSDK)
import BUAdSDK
#endif

final class PangleFeedAdManager: NSObject {

    static let shared = PangleFeedAdManager()

    #if canImport(BUAdSDK)
    private var feedAdManager: BUNativeExpressAdManager?
    private weak var feedContainerView: UIView?
    private var feedHeightDidChange: ((CGFloat) -> Void)?
    #endif

    private weak var rootViewController: UIViewController?

    private override init() {
        super.init()
    }

    /// 加载信息流广告，渲染成功后铺满容器。
    func loadFeedAd(in container: UIView, rootViewController: UIViewController, heightDidChange: ((CGFloat) -> Void)? = nil) {
        #if canImport(BUAdSDK)
        guard SpUtil.bool(.agreementAccepted),
              Constants.isInlineTemplateAdEnabled,
              !Constants.isCloseAd else { return }

        guard PangleAdManager.shared.isSDKInitialized() else {
            PangleAdManager.shared.initialize { [weak self, weak container, weak rootViewController] success in
                guard success, let container, let rootViewController else { return }
                self?.loadFeedAd(in: container, rootViewController: rootViewController, heightDidChange: heightDidChange)
            }
            return
        }

        DispatchQueue.main.async { [weak self, weak container, weak rootViewController] in
            guard let self, let container, let rootViewController else { return }
            self.feedHeightDidChange = heightDidChange
            self.loadFeedAdAfterLayout(in: container, rootViewController: rootViewController)
        }
        #endif
    }

    private func loadFeedAdAfterLayout(in container: UIView, rootViewController: UIViewController) {
        #if canImport(BUAdSDK)
        container.superview?.layoutIfNeeded()
        container.layoutIfNeeded()

        let width = container.bounds.width > 0 ? container.bounds.width : UIScreen.main.bounds.width - 24
        guard width > 0, container.window != nil else { return }

        container.subviews.forEach { $0.removeFromSuperview() }
        feedContainerView = container

        // 信息流模板通常高于旧的固定 250pt，按容器宽度申请完整素材区域。
        let adSize = CGSize(width: width, height: max(300, width * 0.8))
        let imageSize = BUSize()
        imageSize.width = max(Int(adSize.width * UIScreen.main.scale), 1)
        imageSize.height = max(Int(adSize.height * UIScreen.main.scale), 1)

        let slot = BUAdSlot()
        slot.id = Constants.streamID
        slot.adType = .feed
        slot.position = .feed
        slot.adSize = adSize
        slot.imgSize = imageSize
        slot.imgSizeArray = [imageSize]

        self.rootViewController = rootViewController
        let manager = BUNativeExpressAdManager(slot: slot, adSize: adSize)
        manager.mediation?.rootViewController = rootViewController
        manager.delegate = self
        manager.loadAdData(withCount: 1)
        feedAdManager = manager
        #endif
    }
}

#if canImport(BUAdSDK)
// MARK: - 信息流广告回调

extension PangleFeedAdManager: BUMNativeExpressAdViewDelegate, BUCustomEventProtocol {

    func nativeExpressAdSuccess(toLoad nativeExpressAdManager: BUNativeExpressAdManager, views: [BUNativeExpressAdView]) {
        guard let adView = views.first, let container = feedContainerView else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        adView.rootViewController = rootViewController
        adView.frame = CGRect(origin: .zero, size: CGSize(width: container.bounds.width, height: max(container.bounds.height, adView.bounds.height)))
        adView.autoresizingMask = [.flexibleWidth]
        container.addSubview(adView)
        adView.render()
    }

    func nativeExpressAdFail(toLoad nativeExpressAdManager: BUNativeExpressAdManager, error: Error?) {
        print("⚠️ 信息流广告加载失败: \(error?.localizedDescription ?? "未知错误")")
    }

    func nativeExpressAdViewRenderSuccess(_ nativeExpressAdView: BUNativeExpressAdView) {
        guard let container = feedContainerView else { return }
        let renderedHeight = max(nativeExpressAdView.bounds.height, nativeExpressAdView.frame.height)
        guard renderedHeight > 0 else { return }
        feedHeightDidChange?(renderedHeight)
        nativeExpressAdView.frame = CGRect(x: 0, y: 0, width: container.bounds.width, height: renderedHeight)
    }

    func nativeExpressAdViewRenderFail(_ nativeExpressAdView: BUNativeExpressAdView, error: Error?) {
        print("⚠️ 信息流广告渲染失败: \(error?.localizedDescription ?? "未知错误")")
        nativeExpressAdView.removeFromSuperview()
    }
}
#endif
