//
//  RoutePlanViewController.swift
//  beidou
//
//  路线规划页 (对应 Android IndexActivity + activity_index.xml)。
//  起终点输入 + 驾车/步行/骑行/货车 四种出行方式 + 开始导航/附近街景。
//

import UIKit
import CoreLocation

final class RoutePlanViewController: UIViewController {

    private let startLocation: CurrentLocation?
    private var destinationPOI: SelectedPOI?
    private var routeSwapped = false
    private var naviMode: NaviMode = .drive
    private var didLoadFeedAd = false
    private var feedAdHeightConstraint: NSLayoutConstraint?

    // UI
    private let startLabel = UILabel()
    private let destinationLabel = UILabel()
    private var modeButtons: [NaviMode: UIButton] = [:]
    private let feedAdContainer = UIView()

    init(startLocation: CurrentLocation? = nil, endLocation: CurrentLocation? = nil) {
        self.startLocation = startLocation
        super.init(nibName: nil, bundle: nil)
        self.title = L10n.t("route.title")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        setupCloseButton()
        let card = setupInputCard()
        let modeRow = setupModeButtons()
        let actionRow = setupActionButtons()
        setupFeedAdContainer()

        let stack = UIStackView(arrangedSubviews: [card, modeRow, actionRow])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(22, after: modeRow)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 62),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])

        updateLabels()
        updateModeButtons()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("RoutePlanViewController")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        loadFeedAdIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("RoutePlanViewController")
    }

    // MARK: - 顶部返回按钮

    private func setupCloseButton() {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "chevron.left")
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.52)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        button.configuration = configuration
        button.accessibilityLabel = L10n.t("common.back")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(tapClose), for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            button.widthAnchor.constraint(equalToConstant: 42),
            button.heightAnchor.constraint(equalToConstant: 42)
        ])

        let titleLabel = UILabel()
        titleLabel.text = L10n.t("search.destination_satellite_title")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: button.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12)
        ])
    }

    // MARK: - 起终点输入卡片

    private func setupInputCard() -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false

        // 我的位置 行
        let startDot = UIView()
        startDot.backgroundColor = .systemGreen
        startDot.layer.cornerRadius = 5

        startLabel.font = .systemFont(ofSize: 15)
        startLabel.textColor = .label

        let startRow = UIStackView(arrangedSubviews: [makeDotContainer(startDot), startLabel])
        startRow.axis = .horizontal
        startRow.spacing = 10
        startRow.alignment = .center

        // 中间分隔线 + 交换按钮
        let separator = UIView()
        separator.backgroundColor = .separator

        let swapButton = UIButton(type: .system)
        swapButton.setImage(UIImage(systemName: "arrow.up.arrow.down.circle.fill"), for: .normal)
        swapButton.tintColor = .systemBlue
        swapButton.translatesAutoresizingMaskIntoConstraints = false
        swapButton.addTarget(self, action: #selector(tapSwap), for: .touchUpInside)
        swapButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        swapButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let middleRow = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        middleRow.addSubview(separator)
        middleRow.addSubview(swapButton)
        NSLayoutConstraint.activate([
            middleRow.heightAnchor.constraint(equalToConstant: 26),
            separator.heightAnchor.constraint(equalToConstant: 1),
            separator.leadingAnchor.constraint(equalTo: middleRow.leadingAnchor, constant: 32),
            separator.trailingAnchor.constraint(equalTo: swapButton.leadingAnchor, constant: -8),
            separator.centerYAnchor.constraint(equalTo: middleRow.centerYAnchor),
            swapButton.trailingAnchor.constraint(equalTo: middleRow.trailingAnchor),
            swapButton.centerYAnchor.constraint(equalTo: middleRow.centerYAnchor)
        ])

        // 终点 行
        let endDot = UIView()
        endDot.backgroundColor = .systemRed
        endDot.layer.cornerRadius = 5

        destinationLabel.font = .systemFont(ofSize: 15)

        let endRow = UIStackView(arrangedSubviews: [makeDotContainer(endDot), destinationLabel])
        endRow.axis = .horizontal
        endRow.spacing = 10
        endRow.alignment = .center
        endRow.isUserInteractionEnabled = true
        endRow.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapDestination)))

        let outerStack = UIStackView(arrangedSubviews: [startRow, middleRow, endRow])
        outerStack.axis = .vertical
        outerStack.spacing = 4
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            outerStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            outerStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            outerStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            startRow.heightAnchor.constraint(equalToConstant: 32),
            endRow.heightAnchor.constraint(equalToConstant: 32)
        ])
        return card
    }

    private func makeDotContainer(_ dot: UIView) -> UIView {
        let container = UIView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(dot)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 24),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),
            dot.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    // MARK: - 出行方式选择: 驾车/步行/骑行/货车

    private func setupModeButtons() -> UIView {
        let drive = makeModeButton(mode: .drive, icon: "car.fill", title: L10n.t("route.drive"))
        let walk = makeModeButton(mode: .walk, icon: "figure.walk", title: L10n.t("route.walk"))
        let ride = makeModeButton(mode: .ride, icon: "bicycle", title: L10n.t("route.ride"))
        let truck = makeModeButton(mode: .truck, icon: "shippingbox.fill", title: L10n.t("route.truck"))

        let stack = UIStackView(arrangedSubviews: [drive, walk, ride, truck])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 8
        return stack
    }

    private func makeModeButton(mode: NaviMode, icon: String, title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: icon), for: .normal)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.8
        button.layer.cornerRadius = 8
        button.heightAnchor.constraint(equalToConstant: 56).isActive = true

        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.plain()
            config.imagePlacement = .top
            config.imagePadding = 3
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 4, bottom: 5, trailing: 4)
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            button.configuration = config
        } else {
            button.imageView?.contentMode = .scaleAspectFit
        }

        button.tag = modeIndex(for: mode)
        button.addTarget(self, action: #selector(tapMode(_:)), for: .touchUpInside)
        modeButtons[mode] = button
        return button
    }

    private func modeIndex(for mode: NaviMode) -> Int {
        switch mode {
        case .drive: return 0
        case .walk: return 1
        case .ride: return 2
        case .truck: return 3
        }
    }

    private func mode(forIndex index: Int) -> NaviMode {
        switch index {
        case 1: return .walk
        case 2: return .ride
        case 3: return .truck
        default: return .drive
        }
    }

    private func updateModeButtons() {
        for (mode, button) in modeButtons {
            let selected = mode == naviMode
            button.backgroundColor = selected ? .systemBlue : .systemGray5
            button.tintColor = selected ? .white : UIColor(red: 0.30, green: 0.39, blue: 0.53, alpha: 1)
            button.setTitleColor(selected ? .white : UIColor(red: 0.30, green: 0.39, blue: 0.53, alpha: 1), for: .normal)
        }
    }

    // MARK: - 附近街景 / 开始导航

    private func setupActionButtons() -> UIView {
        let nearButton = UIButton(type: .system)
        nearButton.setTitle(L10n.t("route.near_panorama"), for: .normal)
        nearButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        nearButton.titleLabel?.adjustsFontSizeToFitWidth = true
        nearButton.titleLabel?.minimumScaleFactor = 0.82
        nearButton.backgroundColor = .systemBlue
        nearButton.setTitleColor(.white, for: .normal)
        nearButton.layer.cornerRadius = 8
        nearButton.heightAnchor.constraint(equalToConstant: 40).isActive = true
        nearButton.addTarget(self, action: #selector(tapNearPanorama), for: .touchUpInside)

        let naviButton = UIButton(type: .system)
        naviButton.setTitle(L10n.t("route.start_navigation"), for: .normal)
        naviButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        naviButton.titleLabel?.adjustsFontSizeToFitWidth = true
        naviButton.titleLabel?.minimumScaleFactor = 0.82
        naviButton.backgroundColor = .systemBlue
        naviButton.setTitleColor(.white, for: .normal)
        naviButton.layer.cornerRadius = 8
        naviButton.heightAnchor.constraint(equalToConstant: 40).isActive = true
        naviButton.addTarget(self, action: #selector(tapStartNavi), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [nearButton, naviButton])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 12
        return stack
    }

    // MARK: - 信息流广告容器

    private func setupFeedAdContainer() {
        feedAdContainer.translatesAutoresizingMaskIntoConstraints = false
        feedAdContainer.isHidden = !Constants.isInlineTemplateAdEnabled
        view.addSubview(feedAdContainer)
        let height = feedAdContainer.heightAnchor.constraint(equalToConstant: Constants.isInlineTemplateAdEnabled ? 250 : 0)
        feedAdHeightConstraint = height
        NSLayoutConstraint.activate([
            feedAdContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            feedAdContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            feedAdContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            height
        ])
    }

    private func loadFeedAdIfNeeded() {
        guard Constants.isInlineTemplateAdEnabled, !didLoadFeedAd else { return }
        didLoadFeedAd = true
        guard view.window != nil else { return }
        PangleFeedAdManager.shared.loadFeedAd(in: feedAdContainer, rootViewController: self)
    }

    // MARK: - 数据

    private func updateLabels() {
        if routeSwapped, let destination = destinationPOI {
            startLabel.text = destination.name
            destinationLabel.text = L10n.t("route.original_start")
            destinationLabel.textColor = .label
        } else {
            startLabel.text = L10n.t("common.my_location")
            if let destination = destinationPOI {
                destinationLabel.text = destination.name
                destinationLabel.textColor = .label
            } else {
                destinationLabel.text = L10n.t("route.input_destination")
                destinationLabel.textColor = .placeholderText
            }
        }
    }

    /// 当前位置 (GCJ02)，无定位时退化为默认起点
    private func currentLocationPOI(name: String? = nil) -> SelectedPOI {
        let displayName = name ?? L10n.t("common.my_location")
        if let location = startLocation {
            return SelectedPOI(name: displayName, address: "", latitude: location.latitude, longitude: location.longitude)
        }
        if let cached = LocationManager.shared.lastKnownLocation {
            return SelectedPOI(name: displayName, address: "", latitude: cached.latitude, longitude: cached.longitude)
        }
        return SelectedPOI(name: displayName, address: "", latitude: Constants.defaultStartLat, longitude: Constants.defaultStartLon)
    }

    private func currentBD09Coordinate() -> CLLocationCoordinate2D {
        let poi = currentLocationPOI()
        return CoordinateConverter.gcj02ToBD09(CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude))
    }

    // MARK: - 事件

    @objc private func tapClose() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func tapSwap() {
        guard destinationPOI != nil else {
            showAlert(message: L10n.t("route.need_destination"))
            return
        }
        routeSwapped.toggle()
        updateLabels()
    }

    @objc private func tapDestination() {
        let city = startLocation?.city ?? Constants.city
        let searchVC = PoiKeywordSearchViewController(city: city, location: startLocation)
        searchVC.onSelect = { [weak self] poi in
            self?.destinationPOI = poi
            self?.routeSwapped = false
            self?.updateLabels()
        }
        navigationController?.pushViewController(searchVC, animated: true)
    }

    @objc private func tapMode(_ sender: UIButton) {
        naviMode = mode(forIndex: sender.tag)
        updateModeButtons()
    }

    @objc private func tapNearPanorama() {
        let coordinate = currentBD09Coordinate()
        navigationController?.pushViewController(
            PanoramaViewController(latitude: coordinate.latitude, longitude: coordinate.longitude),
            animated: true
        )
    }

    @objc private func tapStartNavi() {
        guard let destinationPOI else {
            showAlert(message: L10n.t("route.need_destination"))
            return
        }

        var start: SelectedPOI?
        var end: SelectedPOI?

        if routeSwapped {
            start = destinationPOI
            end = currentLocationPOI(name: L10n.t("route.original_start"))
        } else {
            start = currentLocationPOI()
            end = destinationPOI
        }

        POIHistoryStore.save(destinationPOI)
        navigationController?.pushViewController(NaviViewController(start: start, end: end, mode: naviMode), animated: true)
    }

    private func showAlert(message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.t("common.ok"), style: .default))
        present(alert, animated: true)
    }
}
