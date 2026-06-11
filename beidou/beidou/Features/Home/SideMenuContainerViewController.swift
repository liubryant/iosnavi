//
//  SideMenuContainerViewController.swift
//  beidou
//
//  自定义抽屉容器: 主内容 + 左侧侧边栏，pan手势/点击遮罩开关。
//  对应 Android fragment_map.xml 中的 DrawerLayout。
//

import UIKit

final class SideMenuContainerViewController: UIViewController, UIGestureRecognizerDelegate {

    private let mainViewController: UIViewController
    private let menuViewController: UIViewController

    private let dimmingView = UIView()
    private var menuLeadingConstraint: NSLayoutConstraint!
    private let menuWidthRatio: CGFloat = 0.78

    private(set) var isMenuOpen = false

    init(mainViewController: UIViewController, menuViewController: UIViewController) {
        self.mainViewController = mainViewController
        self.menuViewController = menuViewController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        addChildController(mainViewController, frame: view.bounds, autoresizing: [.flexibleWidth, .flexibleHeight])

        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        dimmingView.alpha = 0
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimmingView)
        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        dimmingView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closeMenu)))

        addChild(menuViewController)
        menuViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(menuViewController.view)
        menuLeadingConstraint = menuViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -view.bounds.width * menuWidthRatio)
        NSLayoutConstraint.activate([
            menuViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            menuViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            menuViewController.view.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: menuWidthRatio),
            menuLeadingConstraint
        ])
        menuViewController.didMove(toParent: self)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
    }

    private func addChildController(_ child: UIViewController, frame: CGRect, autoresizing: UIView.AutoresizingMask) {
        addChild(child)
        child.view.frame = frame
        child.view.autoresizingMask = autoresizing
        view.insertSubview(child.view, at: 0)
        child.didMove(toParent: self)
    }

    // MARK: - 开关抽屉

    func toggleMenu() {
        isMenuOpen ? closeMenu() : openMenu()
    }

    @objc func openMenu() {
        isMenuOpen = true
        menuLeadingConstraint.constant = 0
        animateMenu()
        onMenuOpened?()
    }

    @objc func closeMenu() {
        isMenuOpen = false
        menuLeadingConstraint.constant = -view.bounds.width * menuWidthRatio
        animateMenu()
        onMenuClosed?()
    }

    /// 抽屉打开后回调 (用于触发 Banner 广告加载)
    var onMenuOpened: (() -> Void)?
    /// 抽屉关闭后回调
    var onMenuClosed: (() -> Void)?

    private func animateMenu() {
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut], animations: {
            self.dimmingView.alpha = self.isMenuOpen ? 1 : 0
            self.view.layoutIfNeeded()
        })
    }

    // MARK: - 手势

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else { return true }

        let velocity = panGesture.velocity(in: view)
        guard abs(velocity.x) > abs(velocity.y) else { return false }

        if isMenuOpen {
            return true
        }

        let startX = panGesture.location(in: view).x
        return startX <= view.bounds.width / 3 && velocity.x > 0
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let menuWidth = view.bounds.width * menuWidthRatio
        let translation = gesture.translation(in: view)

        switch gesture.state {
        case .changed:
            let base: CGFloat = isMenuOpen ? 0 : -menuWidth
            var newConstant = base + translation.x
            newConstant = min(0, max(-menuWidth, newConstant))
            menuLeadingConstraint.constant = newConstant
            dimmingView.alpha = 1 - (-newConstant / menuWidth)
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: view).x
            let shouldOpen: Bool
            if abs(velocity) > 300 {
                shouldOpen = velocity > 0
            } else {
                shouldOpen = menuLeadingConstraint.constant > -menuWidth / 2
            }
            shouldOpen ? openMenu() : closeMenu()
        default:
            break
        }
    }
}
