//
//  RootViewController.swift
//  beidou
//
//  App根容器: 控制 隐私协议弹窗 → SDK初始化 → 启动页 → 主页面 的流程。
//  对应 Android SplashActivity.firstRun() + CommonStartDialog 的整体编排。
//

import UIKit

final class RootViewController: UIViewController {

    private var currentChild: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

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
        PangleAdManager.shared.initialize { [weak self] _ in
            DispatchQueue.main.async {
                self?.showSplash()
            }
        }
    }

    // MARK: - 启动页

    private func showSplash() {
        let vc = SplashViewController()
        vc.onFinish = { [weak self] in
            self?.showMain()
        }
        switchTo(vc)
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
