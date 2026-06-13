//
//  SplashViewController.swift
//  beidou
//
//  启动页: 展示穿山甲开屏广告(对应 Android SplashActivity loadSplashAd)，
//  广告关闭/超时/无广告填充时进入主页面。
//

import UIKit

final class SplashViewController: UIViewController {

    /// 启动页结束(广告关闭/超时/无广告)后回调，进入主页面
    var onFinish: (() -> Void)?

    private var didFinish = false
    private var didStartShowingAd = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupBranding()
        loadSplashAd()
    }

    private func setupBranding() {
        let iconView = UIImageView(image: UIImage(named: "AppLogo") ?? UIImage(named: "AppIcon"))
        iconView.contentMode = .scaleAspectFit
        iconView.layer.cornerRadius = 24
        iconView.clipsToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 112),
            iconView.heightAnchor.constraint(equalToConstant: 112)
        ])
    }

    private func loadSplashAd() {
        PangleSplashAdManager.shared.onClose = { [weak self] in
            self?.finish()
        }

        PangleSplashAdManager.shared.loadAndShowDefaultSplashAd { [weak self] success, _ in
            // 广告加载失败/无填充 -> 直接进入主页面；加载成功则等待 onClose 回调
            if success {
                self?.didStartShowingAd = true
            } else {
                self?.finish()
            }
        }

        // 兜底超时保护，避免开屏页无法跳转
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard self?.didStartShowingAd == false else { return }
            self?.finish()
        }
    }

    private func finish() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.finish()
            }
            return
        }
        guard !didFinish else { return }
        didFinish = true
        PangleSplashAdManager.shared.cancelSplashAd()
        onFinish?()
    }
}
