import UIKit

#if canImport(BUAdSDK)
import BUAdSDK
#endif

/// GroMore 720 云景原生信息流广告。该广告位只接受非模板物料，并使用 Canvas 自渲染。
final class PangleDrawFeedAdLoader: NSObject {
    #if canImport(BUAdSDK)
    private var manager: BUNativeAdsManager?
    private var nativeAd: BUNativeAd?
    #endif
    private weak var rootViewController: UIViewController?
    private var completion: ((UIView?) -> Void)?

    func load(rootViewController: UIViewController, adSize: CGSize? = nil, completion: @escaping (UIView?) -> Void) {
        self.rootViewController = rootViewController
        self.completion = completion

        #if canImport(BUAdSDK)
        guard SpUtil.bool(.agreementAccepted), !Constants.isCloseAd else {
            completion(nil)
            return
        }
        guard PangleAdManager.shared.isSDKInitialized() else {
            PangleAdManager.shared.initialize { [weak self, weak rootViewController] success in
                guard let self, let rootViewController, success else {
                    self?.finish(nil)
                    return
                }
                self.load(rootViewController: rootViewController, adSize: adSize, completion: completion)
            }
            return
        }

        let slot = BUAdSlot()
        slot.id = Constants.cloudPanoramaDrawID
        slot.adType = .feed
        slot.position = .feed
        slot.adSize = adSize ?? CGSize(width: UIScreen.main.bounds.width - 32, height: 190)

        // GroMore native mediation validates the material size synchronously in
        // GMNativeAdsManager.initWithSlot. `adSize` is only the rendered view
        // size; native image/video material dimensions must also be non-zero.
        let materialSize = BUSize()
        materialSize.width = 1280
        materialSize.height = 720
        slot.imgSize = materialSize
        slot.imgSizeArray = [materialSize]

        let iconSize = BUSize()
        iconSize.width = 100
        iconSize.height = 100
        slot.iconSize = iconSize

        let manager = BUNativeAdsManager(slot: slot)
        manager.adSize = slot.adSize
        manager.mediation?.rootViewController = rootViewController
        manager.delegate = self
        self.manager = manager
        manager.loadAdData(withCount: 1)
        #else
        completion(nil)
        #endif
    }

    func cancel() {
        #if canImport(BUAdSDK)
        nativeAd?.unregisterView()
        manager?.mediation?.destory()
        nativeAd = nil
        manager = nil
        #endif
        completion = nil
    }

    private func finish(_ view: UIView?) {
        let callback = completion
        completion = nil
        DispatchQueue.main.async { callback?(view) }
    }
}

#if canImport(BUAdSDK)
extension PangleDrawFeedAdLoader: BUMNativeAdsManagerDelegate, BUMNativeAdDelegate, BUCustomEventProtocol {
    func nativeAdsManagerSuccess(toLoad adsManager: BUNativeAdsManager, nativeAds: [BUNativeAd]?) {
        guard let ad = nativeAds?.first,
              let mediation = ad.mediation,
              !mediation.isExpressAd,
              mediation.isReady else {
            finish(nil)
            return
        }
        nativeAd = ad
        ad.rootViewController = rootViewController
        ad.delegate = self

        let canvas = mediation.canvasView
        configure(canvas: canvas)
        ad.registerContainer(canvas, withClickableViews: [canvas, canvas.callToActionBtn])
        canvas.registerClickableViews([canvas, canvas.callToActionBtn])
        finish(canvas)
    }

    func nativeAdsManager(_ adsManager: BUNativeAdsManager, didFailWithError error: Error?) {
        print("⚠️ 720云景原生信息流加载失败: \(error?.localizedDescription ?? "未知错误")")
        finish(nil)
    }

    private func configure(canvas: BUMCanvasView) {
        let data = canvas.data
        canvas.backgroundColor = .black
        canvas.clipsToBounds = true
        canvas.layer.cornerRadius = 10

        canvas.titleLabel.text = data?.adTitle
        canvas.titleLabel.textColor = .white
        canvas.titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        canvas.descLabel.text = data?.adDescription
        canvas.descLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        canvas.descLabel.font = .systemFont(ofSize: 12)
        canvas.descLabel.numberOfLines = 2
        canvas.callToActionBtn.setTitle(data?.buttonText ?? "查看详情", for: .normal)
        canvas.callToActionBtn.backgroundColor = UIColor(named: "ThemeBlue") ?? .systemBlue
        canvas.callToActionBtn.setTitleColor(.white, for: .normal)
        canvas.callToActionBtn.layer.cornerRadius = 6

        let adBadge = UILabel()
        adBadge.text = L10n.t("ad.label")
        adBadge.font = .systemFont(ofSize: 9, weight: .medium)
        adBadge.textColor = .white
        adBadge.textAlignment = .center
        adBadge.backgroundColor = UIColor.black.withAlphaComponent(0.58)
        adBadge.layer.cornerRadius = 3
        adBadge.clipsToBounds = true
        adBadge.isUserInteractionEnabled = false
        adBadge.translatesAutoresizingMaskIntoConstraints = false

        let media = canvas.mediaView ?? canvas.imageView
        [media, canvas.titleLabel, canvas.descLabel, canvas.callToActionBtn].forEach {
            if $0.superview !== canvas { canvas.addSubview($0) }
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        canvas.addSubview(adBadge)
        canvas.imageView.contentMode = .scaleAspectFill
        canvas.imageView.clipsToBounds = true

        NSLayoutConstraint.activate([
            media.topAnchor.constraint(equalTo: canvas.topAnchor),
            media.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            media.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            media.widthAnchor.constraint(equalTo: canvas.widthAnchor, multiplier: 0.58),
            adBadge.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 6),
            adBadge.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 6),
            adBadge.widthAnchor.constraint(equalToConstant: 28),
            adBadge.heightAnchor.constraint(equalToConstant: 16),
            canvas.titleLabel.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 16),
            canvas.titleLabel.leadingAnchor.constraint(equalTo: media.trailingAnchor, constant: 12),
            canvas.titleLabel.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -12),
            canvas.descLabel.topAnchor.constraint(equalTo: canvas.titleLabel.bottomAnchor, constant: 8),
            canvas.descLabel.leadingAnchor.constraint(equalTo: canvas.titleLabel.leadingAnchor),
            canvas.descLabel.trailingAnchor.constraint(equalTo: canvas.titleLabel.trailingAnchor),
            canvas.callToActionBtn.leadingAnchor.constraint(equalTo: canvas.titleLabel.leadingAnchor),
            canvas.callToActionBtn.trailingAnchor.constraint(equalTo: canvas.titleLabel.trailingAnchor),
            canvas.callToActionBtn.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -14),
            canvas.callToActionBtn.heightAnchor.constraint(equalToConstant: 34)
        ])

        if canvas.mediaView == nil,
           let imageURL = data?.imageAry?.first?.imageURL,
           let url = URL(string: imageURL) {
            URLSession.shared.dataTask(with: url) { [weak imageView = canvas.imageView] data, _, _ in
                guard let data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async { imageView?.image = image }
            }.resume()
        }
    }

    func nativeAdWillPresentFullScreenModal(_ nativeAd: BUNativeAd) {}
    func nativeAdExpressViewRenderSuccess(_ nativeAd: BUNativeAd) {}
    func nativeAdExpressViewRenderFail(_ nativeAd: BUNativeAd, error: Error?) {}
    func nativeAdVideo(_ nativeAd: BUNativeAd?, stateDidChanged playerState: BUPlayerPlayState) {}
    func nativeAdVideoDidClick(_ nativeAd: BUNativeAd?) {}
    func nativeAdVideoDidPlayFinish(_ nativeAd: BUNativeAd?) {}
    func nativeAdShakeViewDidDismiss(_ nativeAd: BUNativeAd?) {}
    func nativeAdVideo(_ nativeAdView: BUNativeAd?, rewardDidCountDown countDown: Int) {}
}
#endif
