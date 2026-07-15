//
//  RoutePlanViewController.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  路线规划页 (对应 Android IndexActivity + activity_index.xml)。
//  起终点输入 + 驾车/步行/骑行/货车 四种出行方式 + 开始导航/附近街景。
//

import UIKit
import CoreLocation

#if canImport(AMapSearchKit)
import AMapSearchKit
#endif

final class RoutePlanViewController: UIViewController {

    private let startLocation: CurrentLocation?
    private var destinationPOI: SelectedPOI?
    private var routeSwapped = false
    private var naviMode: NaviMode = .drive
    private var didLoadFeedAd = false
    #if canImport(AMapSearchKit)
    private let searchAPI = AMapSearchAPI()
    private var weatherCandidates: [String] = []
    private var activeWeatherCity: String?
    #endif

    // UI
    private let backgroundView = WeatherAnimatedBackgroundView()
    private let startLabel = UILabel()
    private let destinationLabel = UILabel()
    private let pageTitleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let topWeatherIconView = UIImageView()
    private var modeButtons: [NaviMode: UIButton] = [:]
    private let feedAdContainer = UIView()

    init(startLocation: CurrentLocation? = nil, endLocation: CurrentLocation? = nil, destinationPOI: SelectedPOI? = nil) {
        self.startLocation = startLocation
        super.init(nibName: nil, bundle: nil)
        if let destinationPOI {
            self.destinationPOI = destinationPOI
        } else if let endLocation {
            self.destinationPOI = SelectedPOI(
                name: endLocation.address.isEmpty ? endLocation.city : endLocation.address,
                address: endLocation.address,
                latitude: endLocation.latitude,
                longitude: endLocation.longitude
            )
        } else {
            self.destinationPOI = POIHistoryStore.load().first
        }
        self.title = L10n.t("route.title")
        #if canImport(AMapSearchKit)
        searchAPI?.delegate = self
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupWeatherBackground()

        setupWeatherIcon()
        setupCloseButton()
        let card = setupInputCard()
        let modeRow = setupModeButtons()
        let actionRow = setupActionButtons()
        setupFeedAdContainer()

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stack = UIStackView(arrangedSubviews: [card, modeRow, actionRow, feedAdContainer])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(22, after: modeRow)
        stack.setCustomSpacing(30, after: actionRow)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 62),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])

        updateLabels()
        updateModeButtons()
        applyInterfaceStyle()
        loadWeatherStyle()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        applyInterfaceStyle()
    }

    private func setupWeatherBackground() {
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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
        let button = closeButton
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

        pageTitleLabel.text = L10n.t("search.destination_satellite_title")
        pageTitleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        pageTitleLabel.textAlignment = .center
        pageTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageTitleLabel)
        NSLayoutConstraint.activate([
            pageTitleLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            pageTitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: button.trailingAnchor, constant: 8),
            pageTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: topWeatherIconView.leadingAnchor, constant: -8)
        ])
    }

    private func setupWeatherIcon() {
        topWeatherIconView.contentMode = .scaleAspectFit
        topWeatherIconView.tintColor = .systemOrange
        topWeatherIconView.image = UIImage(systemName: "cloud.sun.fill")
        topWeatherIconView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topWeatherIconView)
        NSLayoutConstraint.activate([
            topWeatherIconView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            topWeatherIconView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            topWeatherIconView.widthAnchor.constraint(equalToConstant: 30),
            topWeatherIconView.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    // MARK: - 起终点输入卡片

    private func setupInputCard() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.62)
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 0.5
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.7).cgColor
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
        let isDark = traitCollection.userInterfaceStyle == .dark
        let normalBackground = isDark
            ? UIColor(white: 0.10, alpha: 0.82)
            : UIColor.systemGray5.withAlphaComponent(0.92)
        let normalForeground = isDark
            ? UIColor(white: 0.88, alpha: 1)
            : UIColor(red: 0.30, green: 0.39, blue: 0.53, alpha: 1)

        for (mode, button) in modeButtons {
            let selected = mode == naviMode
            button.backgroundColor = selected ? .systemBlue : normalBackground
            button.tintColor = selected ? .white : normalForeground
            button.setTitleColor(selected ? .white : normalForeground, for: .normal)
            if var configuration = button.configuration {
                configuration.baseForegroundColor = selected ? .white : normalForeground
                button.configuration = configuration
            }
        }
    }

    private func applyInterfaceStyle() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        view.backgroundColor = isDark
            ? UIColor(red: 0.04, green: 0.06, blue: 0.09, alpha: 1)
            : UIColor(red: 0.92, green: 0.97, blue: 1.0, alpha: 1.0)

        pageTitleLabel.textColor = isDark ? .black : .label
        topWeatherIconView.tintColor = isDark ? UIColor(red: 1.0, green: 0.73, blue: 0.32, alpha: 1) : .systemOrange

        var configuration = closeButton.configuration ?? UIButton.Configuration.filled()
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = isDark
            ? UIColor(white: 1, alpha: 0.16)
            : UIColor.black.withAlphaComponent(0.52)
        closeButton.configuration = configuration

        updateModeButtons()
    }

    // MARK: - 附近街景 / 开始导航

    private func setupActionButtons() -> UIView {
        let nearButton = UIButton(type: .system)
        nearButton.setTitle(L10n.t("route.near_panorama"), for: .normal)
        nearButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        nearButton.titleLabel?.adjustsFontSizeToFitWidth = true
        nearButton.titleLabel?.minimumScaleFactor = 0.82
        nearButton.backgroundColor = .systemBlue
        nearButton.setTitleColor(.white, for: .normal)
        nearButton.layer.cornerRadius = 10
        nearButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        nearButton.addTarget(self, action: #selector(tapNearPanorama), for: .touchUpInside)

        let naviButton = UIButton(type: .system)
        naviButton.setTitle(L10n.t("route.start_navigation"), for: .normal)
        naviButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        naviButton.titleLabel?.adjustsFontSizeToFitWidth = true
        naviButton.titleLabel?.minimumScaleFactor = 0.82
        naviButton.backgroundColor = .systemBlue
        naviButton.setTitleColor(.white, for: .normal)
        naviButton.layer.cornerRadius = 10
        naviButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
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
        feedAdContainer.backgroundColor = .secondarySystemGroupedBackground
        feedAdContainer.layer.cornerRadius = 12
        feedAdContainer.layer.cornerCurve = .continuous
        feedAdContainer.clipsToBounds = true
        feedAdContainer.isHidden = !Constants.isInlineTemplateAdEnabled
        feedAdContainer.heightAnchor.constraint(equalToConstant: Constants.isInlineTemplateAdEnabled ? 250 : 0).isActive = true
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

    private func weatherCityCandidates() -> [String] {
        let location = startLocation ?? LocationManager.shared.lastKnownLocation
        return [
            cityLevelAdcode(from: location?.adcode),
            location?.adcode,
            location?.city,
            Constants.city,
            "110000"
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .reduce(into: [String]()) { result, value in
            if !result.contains(value) {
                result.append(value)
            }
        }
    }

    private func cityLevelAdcode(from adcode: String?) -> String? {
        guard let adcode = adcode?.trimmingCharacters(in: .whitespacesAndNewlines),
              adcode.count == 6,
              adcode.allSatisfy(\.isNumber) else {
            return nil
        }

        let provincePrefix = String(adcode.prefix(2))
        if ["11", "12", "31", "50"].contains(provincePrefix) {
            return "\(provincePrefix)0000"
        }

        let cityPrefix = String(adcode.prefix(4))
        return "\(cityPrefix)00"
    }

    private func loadWeatherStyle() {
        #if canImport(AMapSearchKit)
        weatherCandidates = weatherCityCandidates()
        requestNextWeatherCandidate()
        #else
        loadCurrentWeatherStyle()
        #endif
    }

    #if canImport(AMapSearchKit)
    private func requestNextWeatherCandidate() {
        guard let city = weatherCandidates.first else {
            loadCurrentWeatherStyle(candidates: weatherCityCandidates())
            return
        }

        activeWeatherCity = city
        let request = AMapWeatherSearchRequest()
        request.city = city
        request.type = .live
        searchAPI?.aMapWeatherSearch(request)
    }

    private func retryNextWeatherCandidate() {
        guard !weatherCandidates.isEmpty else {
            loadCurrentWeatherStyle(candidates: weatherCityCandidates())
            return
        }
        weatherCandidates.removeFirst()
        requestNextWeatherCandidate()
    }
    #endif

    private func loadCurrentWeatherStyle(candidates: [String]? = nil) {
        let values = candidates ?? weatherCityCandidates()
        guard let city = values.first else { return }
        ApiClient.fetchWeatherDetail(city: city) { [weak self] result in
            guard let self else { return }
            guard let live = (result.json?["lives"] as? [[String: Any]])?.first,
                  let weather = live["weather"] as? String,
                  !weather.isEmpty else {
                self.loadCurrentWeatherStyle(candidates: Array(values.dropFirst()))
                return
            }
            self.applyWeatherStyle(weather)
        }
    }

    private func applyWeatherStyle(_ weather: String) {
        let icon = weatherIcon(for: weather)
        topWeatherIconView.image = UIImage(systemName: icon.name)
        topWeatherIconView.tintColor = icon.color
        backgroundView.apply(scene: weatherScene(for: weather))
    }

    private func weatherIcon(for weather: String) -> (name: String, color: UIColor) {
        let value = weather.lowercased()

        if value.contains("暴雨") || value.contains("大暴雨") || value.contains("特大暴雨") || value.contains("heavy rain") {
            return ("cloud.heavyrain.fill", .systemBlue)
        }
        if value.contains("大雨") || value.contains("中雨") || value.contains("阵雨") || value.contains("雨") || value.contains("rain") {
            return ("cloud.rain.fill", .systemBlue)
        }
        if value.contains("雷") || value.contains("thunder") || value.contains("storm") {
            return ("cloud.bolt.rain.fill", .systemYellow)
        }
        if value.contains("雪") || value.contains("snow") {
            return ("cloud.snow.fill", .systemTeal)
        }
        if value.contains("雾") || value.contains("霾") || value.contains("沙") || value.contains("尘") || value.contains("fog") || value.contains("haze") {
            return ("cloud.fog.fill", .systemGray)
        }
        if value.contains("阴") || value.contains("cloudy") {
            return ("cloud.fill", .systemGray)
        }
        if value.contains("多云") || value.contains("少云") || value.contains("partly") {
            return ("cloud.sun.fill", .systemOrange)
        }
        if value.contains("晴") || value.contains("clear") || value.contains("sun") {
            return ("sun.max.fill", .systemYellow)
        }

        return ("cloud.sun.fill", .systemOrange)
    }

    private func weatherScene(for weather: String) -> WeatherAnimatedBackgroundView.Scene {
        let value = weather.lowercased()

        if value.contains("暴雨") || value.contains("大暴雨") || value.contains("特大暴雨") || value.contains("heavy rain") {
            return .heavyRain
        }
        if value.contains("大雨") || value.contains("中雨") || value.contains("阵雨") || value.contains("雨") || value.contains("rain") {
            return .rain
        }
        if value.contains("雷") || value.contains("thunder") || value.contains("storm") {
            return .storm
        }
        if value.contains("雪") || value.contains("snow") {
            return .snow
        }
        if value.contains("雾") || value.contains("霾") || value.contains("沙") || value.contains("尘") || value.contains("fog") || value.contains("haze") {
            return .haze
        }
        if value.contains("阴") || value.contains("cloudy") {
            return .cloudy
        }
        if value.contains("多云") || value.contains("少云") || value.contains("partly") {
            return .partlyCloudy
        }
        if value.contains("晴") || value.contains("clear") || value.contains("sun") {
            return .sunny
        }

        return .partlyCloudy
    }

    private func startNavigation(to poi: SelectedPOI) {
        destinationPOI = poi
        routeSwapped = false
        updateLabels()
        POIHistoryStore.save(poi)
        let naviVC = NaviViewController(start: currentLocationPOI(), end: poi, mode: naviMode)
        guard let navigationController else { return }
        if navigationController.topViewController === self {
            navigationController.pushViewController(naviVC, animated: true)
            return
        }

        if let currentIndex = navigationController.viewControllers.firstIndex(where: { $0 === self }) {
            var viewControllers = Array(navigationController.viewControllers.prefix(through: currentIndex))
            viewControllers.append(naviVC)
            navigationController.setViewControllers(viewControllers, animated: true)
        } else {
            navigationController.pushViewController(naviVC, animated: true)
        }
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
        searchVC.onSelectHistory = { [weak self] poi in
            self?.startNavigation(to: poi)
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

#if canImport(AMapSearchKit)
extension RoutePlanViewController: AMapSearchDelegate {
    func onWeatherSearchDone(_ request: AMapWeatherSearchRequest, response: AMapWeatherSearchResponse) {
        guard request.city == activeWeatherCity else { return }

        guard let live = response.lives.first,
              let weather = live.weather,
              !weather.isEmpty else {
            retryNextWeatherCandidate()
            return
        }

        applyWeatherStyle(weather)
    }

    func aMapSearchRequest(_ request: Any, didFailWithError error: Error) {
        guard let weatherRequest = request as? AMapWeatherSearchRequest,
              weatherRequest.city == activeWeatherCity else {
            return
        }

        retryNextWeatherCandidate()
    }
}
#endif
