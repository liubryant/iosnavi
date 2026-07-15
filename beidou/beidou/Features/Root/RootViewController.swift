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
            CloudPanoramaNotificationManager.shared.requestAuthorizationAndScheduleIfNeeded()
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appShortcutNavigateLastDestination),
            name: AppShortcutManager.navigateLastDestinationNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appShortcutCloudPanorama),
            name: AppShortcutManager.cloudPanoramaNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudPanoramaNotificationOpenScenic),
            name: CloudPanoramaNotificationManager.openScenicNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        backgroundEnteredAt = Date()
    }

    @objc private func appDidBecomeActive() {
        handlePendingShortcutIfPossible()
        handlePendingCloudPanoramaNotificationIfPossible()

        guard SpUtil.bool(.agreementAccepted),
              let backgroundEnteredAt,
              Date().timeIntervalSince(backgroundEnteredAt) >= hotSplashMinimumBackgroundInterval,
              !(currentChild is AgreementViewController),
              !(currentChild is SplashViewController),
              !isShowingHotSplash else {
            return
        }

        if isNavigationProtectedFromHotSplash {
            self.backgroundEnteredAt = nil
            return
        }

        self.backgroundEnteredAt = nil
        showHotSplash()
    }

    @objc private func appShortcutNavigateLastDestination() {
        handlePendingShortcutIfPossible()
    }

    @objc private func appShortcutCloudPanorama() {
        handlePendingShortcutIfPossible()
    }

    @objc private func cloudPanoramaNotificationOpenScenic() {
        handlePendingCloudPanoramaNotificationIfPossible()
    }

    private var isNavigationProtectedFromHotSplash: Bool {
        if NavigationRuntimeState.shared.isNavigating {
            return true
        }

        if currentChild is NaviViewController {
            return true
        }

        if let navigationController = currentChild as? UINavigationController {
            return navigationController.viewControllers.contains { $0 is NaviViewController }
        }

        return false
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
        PangleSplashAdManager.shared.resetSplashRequestState()
        PangleSplashAdManager.shared.onClose = { [weak self] in
            self?.isShowingHotSplash = false
        }

        PangleAdManager.shared.initialize { [weak self] _ in
            DispatchQueue.main.async {
                self?.loadHotSplashAd()
            }
        }
    }

    private func loadHotSplashAd() {
        PangleSplashAdManager.shared.loadAndShowDefaultSplashAd { [weak self] success, _ in
            if !success {
                self?.isShowingHotSplash = false
            }
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
        DispatchQueue.main.async { [weak self] in
            self?.handlePendingShortcutIfPossible()
            self?.handlePendingCloudPanoramaNotificationIfPossible()
        }
    }

    private func handlePendingCloudPanoramaNotificationIfPossible() {
        guard SpUtil.bool(.agreementAccepted) else { return }
        guard !(currentChild is AgreementViewController),
              !(currentChild is SplashViewController),
              !isShowingHotSplash else {
            return
        }
        guard let navigationController = currentChild as? UINavigationController,
              let scenicID = CloudPanoramaNotificationManager.shared.consumePendingScenicID(),
              let item = CloudScenicItem.all.first(where: { $0.id == scenicID }) else {
            return
        }

        pushCloudPanoramaScenic(item, on: navigationController)
    }

    private func handlePendingShortcutIfPossible() {
        guard AppShortcutManager.hasPendingNavigateLastDestination || AppShortcutManager.hasPendingCloudPanorama else { return }
        guard SpUtil.bool(.agreementAccepted) else { return }
        guard !(currentChild is AgreementViewController),
              !(currentChild is SplashViewController),
              !isShowingHotSplash else {
            return
        }

        if let navigationController = currentChild as? UINavigationController {
            if AppShortcutManager.hasPendingCloudPanorama {
                AppShortcutManager.consumePendingCloudPanorama()
                pushCloudPanorama(on: navigationController)
                return
            }

            guard let destination = POIHistoryStore.load().first else {
                AppShortcutManager.consumePendingNavigateLastDestination()
                AppShortcutManager.configureShortcutItems()
                return
            }
            AppShortcutManager.consumePendingNavigateLastDestination()
            pushLastDestinationNavigation(on: navigationController, destination: destination)
        }
    }

    private func pushCloudPanorama(on navigationController: UINavigationController) {
        var viewControllers = navigationController.viewControllers.filter {
            !($0 is CloudPanoramaListViewController) && !($0 is CloudPanoramaWebViewController)
        }
        if viewControllers.isEmpty {
            viewControllers = navigationController.viewControllers
        }
        viewControllers.append(CloudPanoramaListViewController())
        navigationController.setViewControllers(viewControllers, animated: true)
    }

    private func pushCloudPanoramaScenic(_ item: CloudScenicItem, on navigationController: UINavigationController) {
        var viewControllers = navigationController.viewControllers.filter {
            !($0 is CloudPanoramaListViewController) && !($0 is CloudPanoramaWebViewController)
        }
        if viewControllers.isEmpty {
            viewControllers = navigationController.viewControllers
        }
        viewControllers.append(CloudPanoramaWebViewController(title: item.title, url: item.url))
        navigationController.setViewControllers(viewControllers, animated: true)
    }

    private func pushLastDestinationNavigation(on navigationController: UINavigationController, destination: SelectedPOI) {
        NavigationRuntimeState.shared.clearNavigating()
        let start = currentLocationPOI()
        let naviVC = NaviViewController(start: start, end: destination, mode: .drive)
        var viewControllers = navigationController.viewControllers.filter { !($0 is NaviViewController) }
        if viewControllers.isEmpty {
            viewControllers = navigationController.viewControllers
        }
        viewControllers.append(naviVC)
        navigationController.setViewControllers(viewControllers, animated: true)
    }

    private func currentLocationPOI() -> SelectedPOI {
        if let cached = LocationManager.shared.lastKnownLocation {
            return SelectedPOI(
                name: L10n.t("common.my_location"),
                address: cached.address,
                latitude: cached.latitude,
                longitude: cached.longitude
            )
        }
        return SelectedPOI(
            name: L10n.t("common.my_location"),
            address: "",
            latitude: Constants.defaultStartLat,
            longitude: Constants.defaultStartLon
        )
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
