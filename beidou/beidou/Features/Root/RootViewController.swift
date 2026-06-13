//
//  RootViewController.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  App根容器: 控制 隐私协议弹窗 → SDK初始化 → 启动页 → 主页面 的流程。
//  对应 Android SplashActivity.firstRun() + CommonStartDialog 的整体编排。
//

import UIKit
import AppTrackingTransparency

final class RootViewController: UIViewController {

    private var currentChild: UIViewController?
    private var didStartSplashFlow = false
    private var didStartInitialFlow = false
    private var backgroundEnteredAt: Date?
    private var isShowingHotSplash = false

    private let hotSplashMinimumBackgroundInterval: TimeInterval = 60

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        observeAppLifecycle()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startInitialFlowIfNeeded()
    }

    private func startInitialFlowIfNeeded() {
        guard !didStartInitialFlow else { return }
        didStartInitialFlow = true
        if SpUtil.bool(.agreementAccepted) {
            initializeSDKsAndShowSplash()
        } else {
            showAgreement()
        }
    }

    // MARK: - 隐私协议

    private func showAgreement() {
        let vc = AgreementViewController()
        vc.onAgree = { [weak self] in
            SpUtil.setBool(true, for: .agreementAccepted)
            self?.initializeSDKsAndShowSplash()
        }
        switchTo(vc)
    }

    // MARK: - SDK初始化

    private func initializeSDKsAndShowSplash() {
        PrivacyCompliance.agreeAll()
        UMengAnalytics.shared.initialize()

        requestTrackingAuthorizationIfNeeded { [weak self] in
            guard let self else { return }
            self.didStartSplashFlow = false
            PangleAdManager.shared.initialize { _ in
                DispatchQueue.main.async {
                    self.showSplashIfNeeded()
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.showSplashIfNeeded()
            }
        }
    }

    // MARK: - App Tracking Transparency

    /// 在SDK初始化(含穿山甲广告，可能读取IDFA)前请求ATT授权。
    /// 仅在状态为 .notDetermined 时弹窗，已处理过则直接回调，避免重复弹窗。
    private func requestTrackingAuthorizationIfNeeded(completion: @escaping () -> Void) {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            completion()
            return
        }
        ATTrackingManager.requestTrackingAuthorization { _ in
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func observeAppLifecycle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        backgroundEnteredAt = Date()
    }

    @objc private func appDidBecomeActive() {
        guard SpUtil.bool(.agreementAccepted),
              let backgroundEnteredAt,
              Date().timeIntervalSince(backgroundEnteredAt) >= hotSplashMinimumBackgroundInterval,
              !(currentChild is AgreementViewController),
              !(currentChild is SplashViewController),
              !isShowingHotSplash else {
            return
        }
        self.backgroundEnteredAt = nil
        showHotSplash()
    }

    // MARK: - 启动页

    private func showSplash() {
        let vc = SplashViewController()
        vc.onFinish = { [weak self] in
            self?.isShowingHotSplash = false
            self?.showMain()
        }
        switchTo(vc)
    }

    private func showHotSplash() {
        isShowingHotSplash = true
        didStartSplashFlow = false
        PangleSplashAdManager.shared.resetSplashRequestState()

        PangleAdManager.shared.initialize { [weak self] _ in
            DispatchQueue.main.async {
                self?.showSplashIfNeeded()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.showSplashIfNeeded()
        }
    }

    private func showSplashIfNeeded() {
        guard !didStartSplashFlow else { return }
        didStartSplashFlow = true
        showSplash()
    }

    // MARK: - 主页面

    private func showMain() {
        let sideMenuVC = SideMenuViewController()
        let mapVC = MapViewController(sideMenuViewController: sideMenuVC)
        let container = SideMenuContainerViewController(mainViewController: mapVC, menuViewController: sideMenuVC)
        mapVC.sideMenuContainer = container

        container.onMenuOpened = { [weak sideMenuVC, weak container] in
            guard Constants.isInlineTemplateAdEnabled else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard let sideMenuVC, let container else { return }
                PangleBannerAdManager.shared.loadAd(in: sideMenuVC.bannerContainer, rootViewController: container)
            }
        }

        let nav = SwipeBackNavigationController(rootViewController: container)
        nav.setNavigationBarHidden(true, animated: false)
        switchTo(nav)
    }

    // MARK: - 子控制器切换

    private func switchTo(_ child: UIViewController) {
        if let current = currentChild {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }

        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(child.view)
        child.didMove(toParent: self)
        currentChild = child
    }
}

private final class SwipeBackNavigationController: UINavigationController, UIGestureRecognizerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
        interactivePopGestureRecognizer?.isEnabled = true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
