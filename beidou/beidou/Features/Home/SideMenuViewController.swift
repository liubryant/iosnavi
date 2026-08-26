//
//  SideMenuViewController.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  侧边栏内容。对应 Android left_menu.xml:
//  头部(图标+名称+版本) / 全景 / 天气 / 服务协议 / 隐私政策 / 用户反馈 /
//  地图类型(卫星图/普通图/路况图) / 当前位置 / Banner广告位
//

import UIKit

/// 主页地图展示类型，对应 Android AMap.MAP_TYPE_SATELLITE / NORMAL / BUS
enum MapDisplayType {
    case satellite
    case normal
    case traffic
}

protocol SideMenuViewControllerDelegate: AnyObject {
    func sideMenuDidSelectPanorama(_ menu: SideMenuViewController)
    func sideMenuDidSelectWeather(_ menu: SideMenuViewController)
    func sideMenuDidSelectServiceAgreement(_ menu: SideMenuViewController)
    func sideMenuDidSelectPrivacyPolicy(_ menu: SideMenuViewController)
    func sideMenuDidSelectFeedback(_ menu: SideMenuViewController)
    func sideMenuDidSelectRating(_ menu: SideMenuViewController)
    func sideMenuDidSelectClearCache(_ menu: SideMenuViewController)
    func sideMenu(_ menu: SideMenuViewController, didSelectMapType type: MapDisplayType)
}

final class SideMenuViewController: UIViewController {

    weak var delegate: SideMenuViewControllerDelegate?

    /// Banner广告容器，由 PangleBannerAdManager 填充
    let bannerContainer = UIView()

    private let currentLocationLabel = UILabel()
    private var mapTypeIcons: [MapDisplayType: UIImageView] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        // Let a small amount of the map remain visible through the drawer while
        // preserving enough contrast for all menu content.
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.94)
        view.isOpaque = false
        view.layer.cornerRadius = 24
        view.layer.cornerCurve = .continuous
        view.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        view.layer.masksToBounds = true

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        stack.addArrangedSubview(buildHeader())
        stack.addArrangedSubview(buildRow(icon: "view.3d", title: L10n.t("menu.panorama"), action: #selector(tapPanorama)))
        stack.addArrangedSubview(buildDivider())
        stack.addArrangedSubview(buildRow(icon: "cloud.sun", title: L10n.t("menu.weather"), action: #selector(tapWeather)))
        stack.addArrangedSubview(buildDivider())
        stack.addArrangedSubview(buildRow(icon: "doc.text", title: L10n.t("menu.service_agreement"), action: #selector(tapServiceAgreement)))
        stack.addArrangedSubview(buildDivider())
        stack.addArrangedSubview(buildRow(icon: "hand.raised", title: L10n.t("menu.privacy_policy"), action: #selector(tapPrivacyPolicy)))
        stack.addArrangedSubview(buildDivider())
        stack.addArrangedSubview(buildRow(icon: "envelope", title: L10n.t("menu.feedback"), action: #selector(tapFeedback)))
        stack.addArrangedSubview(buildDivider())
        stack.addArrangedSubview(buildRow(icon: "star", title: L10n.t("menu.rating"), action: #selector(tapRating)))
        stack.addArrangedSubview(buildDivider())
        stack.addArrangedSubview(buildRow(icon: "trash", title: L10n.t("menu.clear_cache"), action: #selector(tapClearCache)))
        stack.addArrangedSubview(buildDivider())
        stack.addArrangedSubview(buildRow(icon: "map", title: L10n.t("menu.map_type"), action: nil))
        stack.addArrangedSubview(buildMapTypeSelector())
        stack.addArrangedSubview(buildDivider(topMargin: 10))
        stack.addArrangedSubview(buildRow(icon: "location", title: L10n.t("menu.current_location"), action: nil))
        stack.addArrangedSubview(buildCurrentLocationLabel())
        stack.addArrangedSubview(buildBannerContainer())
    }

    // MARK: - 头部

    private func buildHeader() -> UIView {
        let container = UIView()
        container.heightAnchor.constraint(equalToConstant: 106).isActive = true

        let iconView = UIImageView(image: UIImage(named: "AppLogo") ?? UIImage(named: "AppIcon") ?? UIImage(systemName: "location.north.circle.fill"))
        iconView.contentMode = .scaleAspectFit
        iconView.layer.cornerRadius = 12
        iconView.clipsToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        titleLabel.text = "\(Constants.appName) V\(version)"
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 54),
            iconView.heightAnchor.constraint(equalToConstant: 54),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 5),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        ])
        return container
    }

    // MARK: - 通用行

    private func buildRow(icon: String, title: String, action: Selector?) -> UIView {
        let container = UIView()

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = .label
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 14)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(label)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 36),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        if let action {
            container.isUserInteractionEnabled = true
            container.addGestureRecognizer(UITapGestureRecognizer(target: self, action: action))
        }
        return container
    }

    private func buildDivider(topMargin: CGFloat = 0) -> UIView {
        let wrapper = UIView()
        let line = UIView()
        line.backgroundColor = UIColor.systemGray.withAlphaComponent(0.3)
        line.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(line)
        NSLayoutConstraint.activate([
            wrapper.heightAnchor.constraint(equalToConstant: max(1, topMargin) + 1),
            line.heightAnchor.constraint(equalToConstant: 1),
            line.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 25),
            line.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -25)
        ])
        return wrapper
    }

    // MARK: - 地图类型选择 (卫星图/普通图/路况图)

    private func buildMapTypeSelector() -> UIView {
        let container = UIView()
        container.heightAnchor.constraint(equalToConstant: 68).isActive = true

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20)
        ])

        stack.addArrangedSubview(buildMapTypeOption(type: .satellite, icon: "globe.asia.australia.fill", title: L10n.t("menu.satellite_map"), action: #selector(tapSatellite)))
        stack.addArrangedSubview(buildMapTypeOption(type: .normal, icon: "map.fill", title: L10n.t("menu.normal_map"), action: #selector(tapNormal)))
        stack.addArrangedSubview(buildMapTypeOption(type: .traffic, icon: "car.fill", title: L10n.t("menu.traffic_map"), action: #selector(tapTraffic)))

        return container
    }

    private func buildMapTypeOption(type: MapDisplayType, icon: String, title: String, action: Selector) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 1
        stack.isUserInteractionEnabled = true
        stack.addGestureRecognizer(UITapGestureRecognizer(target: self, action: action))

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = .label
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 22).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 12)
        label.textColor = .label

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        mapTypeIcons[type] = iconView
        return stack
    }

    /// 高亮当前选中的地图类型
    func highlightMapType(_ type: MapDisplayType) {
        for (key, iconView) in mapTypeIcons {
            iconView.tintColor = key == type ? .systemBlue : .label
        }
    }

    // MARK: - 当前位置

    private func buildCurrentLocationLabel() -> UIView {
        let container = UIView()
        currentLocationLabel.font = .systemFont(ofSize: 12)
        currentLocationLabel.textColor = .label
        currentLocationLabel.numberOfLines = 0
        currentLocationLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(currentLocationLabel)
        NSLayoutConstraint.activate([
            currentLocationLabel.topAnchor.constraint(equalTo: container.topAnchor),
            currentLocationLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            currentLocationLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            currentLocationLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20)
        ])
        return container
    }

    func updateCurrentLocation(_ text: String) {
        currentLocationLabel.text = text
    }

    // MARK: - Banner容器

    private func buildBannerContainer() -> UIView {
        bannerContainer.backgroundColor = .systemBackground
        bannerContainer.translatesAutoresizingMaskIntoConstraints = false
        bannerContainer.isHidden = !Constants.isInlineTemplateAdEnabled
        bannerContainer.heightAnchor.constraint(equalToConstant: Constants.isInlineTemplateAdEnabled ? 250 : 0).isActive = true

        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(bannerContainer)
        NSLayoutConstraint.activate([
            bannerContainer.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 10),
            bannerContainer.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            bannerContainer.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 5),
            bannerContainer.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -5)
        ])
        return wrapper
    }

    // MARK: - 事件

    @objc private func tapPanorama() { delegate?.sideMenuDidSelectPanorama(self) }
    @objc private func tapWeather() { delegate?.sideMenuDidSelectWeather(self) }
    @objc private func tapServiceAgreement() { delegate?.sideMenuDidSelectServiceAgreement(self) }
    @objc private func tapPrivacyPolicy() { delegate?.sideMenuDidSelectPrivacyPolicy(self) }
    @objc private func tapFeedback() { delegate?.sideMenuDidSelectFeedback(self) }
    @objc private func tapRating() { delegate?.sideMenuDidSelectRating(self) }
    @objc private func tapClearCache() { delegate?.sideMenuDidSelectClearCache(self) }
    @objc private func tapSatellite() { delegate?.sideMenu(self, didSelectMapType: .satellite) }
    @objc private func tapNormal() { delegate?.sideMenu(self, didSelectMapType: .normal) }
    @objc private func tapTraffic() { delegate?.sideMenu(self, didSelectMapType: .traffic) }
}
