//
//  MapViewController.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  主页地图 (对应 Android MapActivity + fragment_map.xml)。
//  百度地图全屏展示 + 顶部搜索栏 + 左右悬浮按钮 + 底部地图类型标注。
//  定位/逆地理编码使用高德 SDK (GCJ02)，转换为 BD09 后展示在百度地图上。
//

import UIKit
import CoreLocation

#if canImport(BaiduMapAPI_Map)
import BaiduMapAPI_Map
#endif
#if canImport(BaiduMapAPI_Base)
import BaiduMapAPI_Base
#endif

final class MapViewController: UIViewController {

    private static var didShowCloudPanoramaWelcomeThisLaunch = false

    /// 抽屉容器，由 RootViewController 创建后注入
    weak var sideMenuContainer: SideMenuContainerViewController?

    private let sideMenuVC: SideMenuViewController

    #if canImport(BaiduMapAPI_Map)
    private let mapView = BMKMapView()
    #else
    private let mapView = UIView()
    #endif

    private let searchBar = UIView()
    private let searchLabel = UILabel()
    private let cloudPanoramaButton = UIButton(type: .system)
    private let bottomLabel = UILabel()
    private let trafficButton = UIButton(type: .system)
    private let northButton = UIButton(type: .system)
    private let bottomSearchSheet = UIView()
    private let bottomSheetBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let bottomSheetMaterialOverlay = UIView()
    private let bottomSheetGrabber = UIView()
    private let bottomSheetSearchRow = UIView()
    private let bottomSheetSearchTextLabel = UILabel()
    private let bottomSheetAppIconContainer = UIView()
    private let bottomSheetAppIconView = UIImageView()
    private let bottomSheetWeatherBadge = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let bottomSheetWeatherIconView = UIImageView()
    private let bottomSheetTemperatureLabel = UILabel()
    private let bottomSheetHistoryStack = UIStackView()
    private let bottomSheetShortcutStack = UIStackView()
    private let bottomSheetSecondaryShortcutStack = UIStackView()
    private var bottomSheetHeightConstraint: NSLayoutConstraint?
    private var isBottomSheetExpanded = false
    private var isDraggingBottomSheet = false
    private var bottomSheetHistorySignature: String?
    private var lastBottomSheetWeatherCity: String?

    private var currentMapType: MapDisplayType = .satellite
    private var currentLocation: CurrentLocation?
    private var cloudWelcomeWorkItem: DispatchWorkItem?
    private var hasCenteredInitialLocation = false
    private var userDidMoveMap = false
    private let defaultZoomLevel: Float = 18
    private let headingManager = CLLocationManager()
    private var currentHeading: CLLocationDirection = 0

    #if canImport(BaiduMapAPI_Map)
    private var currentLocationAnnotation: BMKPointAnnotation?
    private weak var currentLocationAnnotationView: HeadingLocationAnnotationView?
    #endif

    init(sideMenuViewController: SideMenuViewController) {
        self.sideMenuVC = sideMenuViewController
        super.init(nibName: nil, bundle: nil)
        sideMenuViewController.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        setupMapView()
        setupTopBar()
        setupRightButtons()
        setupLeftButtons()
        setupBottomLabel()
        setupBottomSearchSheet()
        setupHeadingUpdates()

        applyMapType(.satellite)
        refreshLocation(shouldCenterMap: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        #if canImport(BaiduMapAPI_Map)
        mapView.delegate = self
        mapView.viewWillAppear()
        #endif
        startHeadingUpdates()
        UMengAnalytics.shared.pageBegin("MapViewController")
        reloadBottomSheetHistory()
        applyCachedBottomSheetWeather()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshLocationWhenPageAppears()
        scheduleCloudPanoramaWelcomeIfNeeded()
        ReviewPromptManager.requestSystemReviewIfEligibleAfterCloudScenes(in: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isDraggingBottomSheet else { return }
        bottomSheetHeightConstraint?.constant = isBottomSheetExpanded ? bottomSheetExpandedHeight : bottomSheetCollapsedHeight
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cloudWelcomeWorkItem?.cancel()
        cloudWelcomeWorkItem = nil
        #if canImport(BaiduMapAPI_Map)
        mapView.viewWillDisappear()
        mapView.delegate = nil
        #endif
        headingManager.stopUpdatingHeading()
        UMengAnalytics.shared.pageEnd("MapViewController")
    }

    private func scheduleCloudPanoramaWelcomeIfNeeded(after delay: TimeInterval = 5) {
        guard !Self.didShowCloudPanoramaWelcomeThisLaunch,
              cloudWelcomeWorkItem == nil,
              canShowCloudPanoramaWelcomeToday() else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.cloudWelcomeWorkItem = nil
            guard self.viewIfLoaded?.window != nil,
                  self.presentedViewController == nil,
                  self.sideMenuContainer?.isMenuOpen != true else {
                self.scheduleCloudPanoramaWelcomeIfNeeded(after: 1)
                return
            }
            self.showCloudPanoramaWelcome()
        }
        cloudWelcomeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func showCloudPanoramaWelcome() {
        guard !Self.didShowCloudPanoramaWelcomeThisLaunch,
              canShowCloudPanoramaWelcomeToday(),
              let item = randomCloudPanoramaWelcomeItem() else {
            return
        }
        Self.didShowCloudPanoramaWelcomeThisLaunch = true
        recordCloudPanoramaWelcomeShown()
        SpUtil.setString(item.id, for: .lastCloudPanoramaWelcomeID)
        let popup = CloudPanoramaWelcomeViewController(item: item)
        popup.onOpenFeatured = { [weak self] in
            self?.navigationController?.pushViewController(
                CloudPanoramaWebViewController(title: item.title, url: item.url),
                animated: true
            )
        }
        popup.onViewMore = { [weak self] in
            self?.navigationController?.pushViewController(CloudPanoramaListViewController(), animated: true)
        }
        present(popup, animated: true)
    }

    private func canShowCloudPanoramaWelcomeToday(now: Date = Date()) -> Bool {
        let timestamp = SpUtil.double(.cloudPanoramaWelcomeLastShownAt)
        guard timestamp > 0 else { return true }
        let lastShownAt = Date(timeIntervalSince1970: timestamp)
        guard Calendar.current.isDate(lastShownAt, inSameDayAs: now) else { return true }
        return SpUtil.integer(.cloudPanoramaWelcomeDailyCount) < 3
    }

    private func recordCloudPanoramaWelcomeShown(now: Date = Date()) {
        let timestamp = SpUtil.double(.cloudPanoramaWelcomeLastShownAt)
        let lastShownAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        let isSameDay = lastShownAt.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? false
        let count = isSameDay ? SpUtil.integer(.cloudPanoramaWelcomeDailyCount) : 0
        SpUtil.setInteger(count + 1, for: .cloudPanoramaWelcomeDailyCount)
        SpUtil.setDouble(now.timeIntervalSince1970, for: .cloudPanoramaWelcomeLastShownAt)
    }

    private func randomCloudPanoramaWelcomeItem() -> CloudScenicItem? {
        let items = CloudScenicItem.all
        guard !items.isEmpty else { return nil }

        let lastID = SpUtil.string(.lastCloudPanoramaWelcomeID)
        let candidates = items.filter { $0.id != lastID }
        return (candidates.isEmpty ? items : candidates).randomElement()
    }

    // MARK: - 地图

    private func setupMapView() {
        mapView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(mapView, at: 0)
        pinMapViewToEdges()
        #if canImport(BaiduMapAPI_Map)
        mapView.delegate = self
        mapView.zoomLevel = defaultZoomLevel
        let center = CoordinateConverter.gcj02ToBD09(
            CLLocationCoordinate2D(latitude: Constants.defaultStartLat, longitude: Constants.defaultStartLon)
        )
        mapView.setCenter(center, animated: false)
        #else
        mapView.backgroundColor = .systemGray5
        let label = UILabel()
        label.text = Constants.appName
        label.font = .boldSystemFont(ofSize: 22)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: mapView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: mapView.centerYAnchor)
        ])
        #endif
    }

    private func pinMapViewToEdges() {
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// 切换地图类型: 卫星图 / 普通图 / 路况图 (对应侧边栏地图类型选择)
    private func applyMapType(_ type: MapDisplayType) {
        currentMapType = type
        #if canImport(BaiduMapAPI_Map)
        switch type {
        case .satellite:
            mapView.mapType = .satellite
            mapView.isTrafficEnabled = false
        case .normal:
            mapView.mapType = .standard
            mapView.isTrafficEnabled = false
        case .traffic:
            mapView.mapType = .standard
            mapView.isTrafficEnabled = true
        }
        trafficButton.tintColor = mapView.isTrafficEnabled ? .systemBlue : .label
        #endif
        sideMenuVC.highlightMapType(type)
    }

    // MARK: - 顶部搜索栏 + 抽屉按钮

    private func setupTopBar() {
        let menuButton = UIButton(type: .system)
        menuButton.setImage(UIImage(systemName: "line.3.horizontal"), for: .normal)
        menuButton.tintColor = .label
        menuButton.backgroundColor = .systemBackground
        menuButton.layer.cornerRadius = 22
        applyShadow(to: menuButton)
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.addTarget(self, action: #selector(tapMenu), for: .touchUpInside)

        searchBar.backgroundColor = .systemBackground
        searchBar.layer.cornerRadius = 22
        applyShadow(to: searchBar)
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.isUserInteractionEnabled = true
        searchBar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapSearch)))

        let searchIcon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        searchIcon.tintColor = .secondaryLabel
        searchIcon.contentMode = .scaleAspectFit
        searchIcon.translatesAutoresizingMaskIntoConstraints = false

        searchLabel.text = L10n.t("home.search_placeholder")
        searchLabel.font = .systemFont(ofSize: 15)
        searchLabel.textColor = .secondaryLabel
        searchLabel.adjustsFontSizeToFitWidth = true
        searchLabel.minimumScaleFactor = 0.72
        searchLabel.translatesAutoresizingMaskIntoConstraints = false

        configureCloudPanoramaButton()

        searchBar.addSubview(searchIcon)
        searchBar.addSubview(searchLabel)
        view.addSubview(menuButton)
        view.addSubview(searchBar)
        view.addSubview(cloudPanoramaButton)

        NSLayoutConstraint.activate([
            menuButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            menuButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            menuButton.widthAnchor.constraint(equalToConstant: 44),
            menuButton.heightAnchor.constraint(equalToConstant: 44),

            searchBar.centerYAnchor.constraint(equalTo: menuButton.centerYAnchor),
            searchBar.leadingAnchor.constraint(equalTo: menuButton.trailingAnchor, constant: 12),
            searchBar.trailingAnchor.constraint(equalTo: cloudPanoramaButton.leadingAnchor, constant: -8),
            searchBar.heightAnchor.constraint(equalToConstant: 44),

            cloudPanoramaButton.centerYAnchor.constraint(equalTo: menuButton.centerYAnchor),
            cloudPanoramaButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            cloudPanoramaButton.widthAnchor.constraint(equalTo: menuButton.widthAnchor, multiplier: 2),
            cloudPanoramaButton.heightAnchor.constraint(equalToConstant: 44),

            searchIcon.leadingAnchor.constraint(equalTo: searchBar.leadingAnchor, constant: 16),
            searchIcon.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 18),
            searchIcon.heightAnchor.constraint(equalToConstant: 18),

            searchLabel.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 10),
            searchLabel.trailingAnchor.constraint(lessThanOrEqualTo: searchBar.trailingAnchor, constant: -12),
            searchLabel.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor)
        ])
    }

    private func configureCloudPanoramaButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.title = L10n.t("home.cloud_panorama")
        configuration.image = UIImage(systemName: "photo")
        configuration.imagePadding = 4
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .systemBackground
        configuration.baseForegroundColor = UIColor.label.withAlphaComponent(0.78)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 13, weight: .medium)
            return outgoing
        }
        cloudPanoramaButton.configuration = configuration
        cloudPanoramaButton.layer.cornerRadius = 22
        cloudPanoramaButton.layer.cornerCurve = .continuous
        cloudPanoramaButton.layer.masksToBounds = false
        applyShadow(to: cloudPanoramaButton)
        cloudPanoramaButton.translatesAutoresizingMaskIntoConstraints = false
        cloudPanoramaButton.addTarget(self, action: #selector(tapCloudPanorama), for: .touchUpInside)
    }

    // MARK: - 右侧悬浮按钮: 周边 / 天气 / 台风 / 路况

    private func setupRightButtons() {
        let aroundButton = makeFloatingButton(icon: "mappin.and.ellipse", action: #selector(tapAround))
        let weatherButton = makeFloatingButton(icon: "cloud.sun", action: #selector(tapWeather))
        let typhoonButton = makeFloatingButton(icon: "tropicalstorm", action: #selector(tapTyphoon))
        let cloudButton = makeFloatingTextButton(title: "720", action: #selector(tapCloudPanorama))
        trafficButton.setImage(UIImage(systemName: "car"), for: .normal)
        styleFloatingButton(trafficButton)
        trafficButton.addTarget(self, action: #selector(tapTraffic), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [aroundButton, weatherButton, typhoonButton, trafficButton, cloudButton])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 40)
        ])
    }

    // MARK: - 左侧悬浮按钮: 全景 / 世界景点全景 / 地铁 / 指南针(北)

    private func setupLeftButtons() {
        let panoramaButton = makeFloatingButton(icon: "view.3d", action: #selector(tapPanorama))
        let worldPanoramaButton = makeFloatingButton(icon: "globe.europe.africa.fill", action: #selector(tapWorldPanorama))
        let metroButton = makeFloatingButton(icon: "tram", action: #selector(tapMetro))
        northButton.setImage(UIImage(systemName: "location.north.fill"), for: .normal)
        styleFloatingButton(northButton)
        northButton.addTarget(self, action: #selector(tapNorth), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [panoramaButton, worldPanoramaButton, metroButton, northButton])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 40)
        ])
    }

    // MARK: - 底部地图类型标注

    private func setupBottomLabel() {
        bottomLabel.text = L10n.t("home.bottom_label")
        bottomLabel.isHidden = true
        bottomLabel.font = .systemFont(ofSize: 12)
        bottomLabel.textColor = UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)
        bottomLabel.backgroundColor = UIColor.white.withAlphaComponent(0.94)
        bottomLabel.textAlignment = .center
        bottomLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomLabel)
        NSLayoutConstraint.activate([
            bottomLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomLabel.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    // MARK: - 底部搜索抽屉

    private func setupBottomSearchSheet() {
        bottomSearchSheet.backgroundColor = .clear
        bottomSearchSheet.layer.cornerRadius = 22
        bottomSearchSheet.layer.cornerCurve = .continuous
        applyShadow(to: bottomSearchSheet)
        bottomSearchSheet.translatesAutoresizingMaskIntoConstraints = false

        bottomSheetBlurView.layer.cornerRadius = 22
        bottomSheetBlurView.layer.cornerCurve = .continuous
        bottomSheetBlurView.clipsToBounds = true
        bottomSheetBlurView.alpha = 0.92
        bottomSheetBlurView.translatesAutoresizingMaskIntoConstraints = false

        bottomSheetMaterialOverlay.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.10)
        bottomSheetMaterialOverlay.layer.cornerRadius = 22
        bottomSheetMaterialOverlay.layer.cornerCurve = .continuous
        bottomSheetMaterialOverlay.clipsToBounds = true
        bottomSheetMaterialOverlay.translatesAutoresizingMaskIntoConstraints = false
        bottomSheetMaterialOverlay.isUserInteractionEnabled = false

        bottomSheetGrabber.backgroundColor = UIColor.systemGray.withAlphaComponent(0.95)
        bottomSheetGrabber.layer.cornerRadius = 2
        bottomSheetGrabber.translatesAutoresizingMaskIntoConstraints = false

        bottomSheetSearchRow.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.68)
        bottomSheetSearchRow.layer.cornerRadius = 18
        bottomSheetSearchRow.layer.cornerCurve = .continuous
        bottomSheetSearchRow.layer.borderWidth = 0.5
        bottomSheetSearchRow.layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor
        bottomSheetSearchRow.translatesAutoresizingMaskIntoConstraints = false
        bottomSheetSearchRow.isUserInteractionEnabled = true
        bottomSheetSearchRow.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapBottomSearchRow)))

        let searchIcon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        searchIcon.tintColor = .secondaryLabel
        searchIcon.contentMode = .scaleAspectFit
        searchIcon.translatesAutoresizingMaskIntoConstraints = false

        bottomSheetSearchTextLabel.text = bottomSheetSearchTitle()
        bottomSheetSearchTextLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        bottomSheetSearchTextLabel.textColor = .secondaryLabel
        bottomSheetSearchTextLabel.lineBreakMode = .byTruncatingTail
        bottomSheetSearchTextLabel.numberOfLines = 1
        bottomSheetSearchTextLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bottomSheetSearchTextLabel.translatesAutoresizingMaskIntoConstraints = false

        bottomSheetAppIconContainer.backgroundColor = .clear
        bottomSheetAppIconContainer.layer.cornerRadius = 18
        bottomSheetAppIconContainer.layer.cornerCurve = .continuous
        bottomSheetAppIconContainer.layer.borderWidth = 0
        bottomSheetAppIconContainer.layer.borderColor = nil
        bottomSheetAppIconContainer.translatesAutoresizingMaskIntoConstraints = false

        bottomSheetAppIconView.image = UIImage(named: "AppLogo") ?? UIImage(named: "AppIcon") ?? UIImage(systemName: "location.north.circle.fill")
        bottomSheetAppIconView.contentMode = .scaleAspectFit
        bottomSheetAppIconView.clipsToBounds = true
        bottomSheetAppIconView.layer.cornerRadius = 10
        bottomSheetAppIconView.layer.cornerCurve = .continuous
        bottomSheetAppIconView.translatesAutoresizingMaskIntoConstraints = false

        bottomSheetWeatherBadge.layer.cornerRadius = 16
        bottomSheetWeatherBadge.layer.cornerCurve = .continuous
        bottomSheetWeatherBadge.clipsToBounds = true
        bottomSheetWeatherBadge.alpha = 0.96
        bottomSheetWeatherBadge.translatesAutoresizingMaskIntoConstraints = false

        bottomSheetWeatherIconView.image = UIImage(systemName: "cloud.sun.fill")
        bottomSheetWeatherIconView.tintColor = .systemOrange
        bottomSheetWeatherIconView.contentMode = .scaleAspectFit
        bottomSheetWeatherIconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        bottomSheetWeatherIconView.translatesAutoresizingMaskIntoConstraints = false

        bottomSheetTemperatureLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        bottomSheetTemperatureLabel.text = "--°"
        bottomSheetTemperatureLabel.textColor = .label
        bottomSheetTemperatureLabel.textAlignment = .right
        bottomSheetTemperatureLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        bottomSheetTemperatureLabel.translatesAutoresizingMaskIntoConstraints = false

        bottomSheetSearchRow.addSubview(searchIcon)
        bottomSheetSearchRow.addSubview(bottomSheetSearchTextLabel)
        bottomSheetAppIconContainer.addSubview(bottomSheetAppIconView)
        bottomSheetWeatherBadge.contentView.addSubview(bottomSheetWeatherIconView)
        bottomSheetWeatherBadge.contentView.addSubview(bottomSheetTemperatureLabel)

        bottomSheetHistoryStack.axis = .vertical
        bottomSheetHistoryStack.spacing = 0
        bottomSheetHistoryStack.translatesAutoresizingMaskIntoConstraints = false

        bottomSheetShortcutStack.axis = .horizontal
        bottomSheetShortcutStack.distribution = .fillEqually
        bottomSheetShortcutStack.spacing = 12
        bottomSheetShortcutStack.translatesAutoresizingMaskIntoConstraints = false
        bottomSheetSecondaryShortcutStack.axis = .horizontal
        bottomSheetSecondaryShortcutStack.distribution = .fillEqually
        bottomSheetSecondaryShortcutStack.spacing = 12
        bottomSheetSecondaryShortcutStack.translatesAutoresizingMaskIntoConstraints = false

        let cloudShortcut = makeBottomSheetShortcut(
            icon: "photo.on.rectangle.angled",
            title: L10n.t("home.cloud_panorama"),
            colors: [
                UIColor(red: 0.14, green: 0.55, blue: 0.94, alpha: 1),
                UIColor(red: 0.27, green: 0.78, blue: 0.78, alpha: 1)
            ],
            action: #selector(tapCloudPanorama)
        )
        let typhoonShortcut = makeBottomSheetShortcut(
            icon: "tropicalstorm",
            title: L10n.t("weather.typhoon_monitor_title"),
            colors: [
                UIColor(red: 0.20, green: 0.37, blue: 0.96, alpha: 1),
                UIColor(red: 0.54, green: 0.34, blue: 0.94, alpha: 1)
            ],
            action: #selector(tapTyphoon)
        )
        let sunsetShortcut = makeBottomSheetShortcut(
            icon: "sunset.fill",
            title: L10n.t("home.sunset_glow"),
            colors: [
                UIColor(red: 1.00, green: 0.43, blue: 0.23, alpha: 1),
                UIColor(red: 0.96, green: 0.70, blue: 0.20, alpha: 1)
            ],
            action: #selector(tapSunsetGlow)
        )
        bottomSheetShortcutStack.addArrangedSubview(cloudShortcut)
        bottomSheetShortcutStack.addArrangedSubview(typhoonShortcut)
        bottomSheetShortcutStack.addArrangedSubview(sunsetShortcut)

        let earthquakeShortcut = makeBottomSheetShortcut(
            icon: "waveform.path.ecg.rectangle.fill",
            title: L10n.t("home.earthquake_report"),
            colors: [
                UIColor(red: 0.14, green: 0.48, blue: 0.91, alpha: 1),
                UIColor(red: 0.27, green: 0.70, blue: 0.88, alpha: 1)
            ],
            action: #selector(tapEarthquakeReport)
        )
        bottomSheetSecondaryShortcutStack.addArrangedSubview(earthquakeShortcut)
        let moonShortcut = makeBottomSheetShortcut(
            icon: "moon.stars.fill",
            title: L10n.t("home.moon_phase"),
            colors: [
                UIColor(red: 0.25, green: 0.32, blue: 0.68, alpha: 1),
                UIColor(red: 0.48, green: 0.38, blue: 0.82, alpha: 1)
            ],
            action: #selector(tapMoonPhase)
        )
        bottomSheetSecondaryShortcutStack.addArrangedSubview(moonShortcut)
        let moreToolsShortcut = makeBottomSheetShortcut(
            icon: "square.grid.2x2.fill",
            title: L10n.t("home.more_tools"),
            colors: [
                UIColor(red: 0.91, green: 0.24, blue: 0.27, alpha: 1),
                UIColor(red: 0.98, green: 0.49, blue: 0.25, alpha: 1)
            ],
            action: #selector(tapMoreTools)
        )
        bottomSheetSecondaryShortcutStack.addArrangedSubview(moreToolsShortcut)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleBottomSheetPan(_:)))
        bottomSearchSheet.addGestureRecognizer(panGesture)

        view.addSubview(bottomSearchSheet)
        bottomSearchSheet.addSubview(bottomSheetBlurView)
        bottomSearchSheet.addSubview(bottomSheetMaterialOverlay)
        bottomSearchSheet.addSubview(bottomSheetWeatherBadge)
        bottomSearchSheet.addSubview(bottomSheetGrabber)
        bottomSearchSheet.addSubview(bottomSheetSearchRow)
        bottomSearchSheet.addSubview(bottomSheetAppIconContainer)
        bottomSearchSheet.addSubview(bottomSheetHistoryStack)
        bottomSearchSheet.addSubview(bottomSheetShortcutStack)
        bottomSearchSheet.addSubview(bottomSheetSecondaryShortcutStack)

        let height = bottomSearchSheet.heightAnchor.constraint(equalToConstant: bottomSheetCollapsedHeight)
        bottomSheetHeightConstraint = height
        NSLayoutConstraint.activate([
            bottomSearchSheet.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            bottomSearchSheet.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            bottomSearchSheet.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 10),
            height,

            bottomSheetBlurView.topAnchor.constraint(equalTo: bottomSearchSheet.topAnchor),
            bottomSheetBlurView.leadingAnchor.constraint(equalTo: bottomSearchSheet.leadingAnchor),
            bottomSheetBlurView.trailingAnchor.constraint(equalTo: bottomSearchSheet.trailingAnchor),
            bottomSheetBlurView.bottomAnchor.constraint(equalTo: bottomSearchSheet.bottomAnchor),

            bottomSheetMaterialOverlay.topAnchor.constraint(equalTo: bottomSearchSheet.topAnchor),
            bottomSheetMaterialOverlay.leadingAnchor.constraint(equalTo: bottomSearchSheet.leadingAnchor),
            bottomSheetMaterialOverlay.trailingAnchor.constraint(equalTo: bottomSearchSheet.trailingAnchor),
            bottomSheetMaterialOverlay.bottomAnchor.constraint(equalTo: bottomSearchSheet.bottomAnchor),

            bottomSheetWeatherBadge.trailingAnchor.constraint(equalTo: bottomSearchSheet.trailingAnchor, constant: -4),
            bottomSheetWeatherBadge.bottomAnchor.constraint(equalTo: bottomSearchSheet.topAnchor, constant: -8),
            bottomSheetWeatherBadge.heightAnchor.constraint(equalToConstant: 32),
            bottomSheetWeatherBadge.widthAnchor.constraint(equalToConstant: 82),

            bottomSheetWeatherIconView.leadingAnchor.constraint(equalTo: bottomSheetWeatherBadge.contentView.leadingAnchor, constant: 10),
            bottomSheetWeatherIconView.centerYAnchor.constraint(equalTo: bottomSheetWeatherBadge.contentView.centerYAnchor),
            bottomSheetWeatherIconView.widthAnchor.constraint(equalToConstant: 18),
            bottomSheetWeatherIconView.heightAnchor.constraint(equalToConstant: 18),

            bottomSheetTemperatureLabel.leadingAnchor.constraint(equalTo: bottomSheetWeatherIconView.trailingAnchor, constant: 2),
            bottomSheetTemperatureLabel.trailingAnchor.constraint(equalTo: bottomSheetWeatherBadge.contentView.trailingAnchor, constant: -10),
            bottomSheetTemperatureLabel.centerYAnchor.constraint(equalTo: bottomSheetWeatherBadge.contentView.centerYAnchor),

            bottomSheetGrabber.topAnchor.constraint(equalTo: bottomSearchSheet.topAnchor, constant: 8),
            bottomSheetGrabber.centerXAnchor.constraint(equalTo: bottomSearchSheet.centerXAnchor),
            bottomSheetGrabber.widthAnchor.constraint(equalToConstant: 40),
            bottomSheetGrabber.heightAnchor.constraint(equalToConstant: 4),

            bottomSheetSearchRow.topAnchor.constraint(equalTo: bottomSheetGrabber.bottomAnchor, constant: 8),
            bottomSheetSearchRow.leadingAnchor.constraint(equalTo: bottomSearchSheet.leadingAnchor, constant: 16),
            bottomSheetSearchRow.trailingAnchor.constraint(equalTo: bottomSheetAppIconContainer.leadingAnchor, constant: -6),
            bottomSheetSearchRow.heightAnchor.constraint(equalToConstant: 40),

            bottomSheetAppIconContainer.trailingAnchor.constraint(equalTo: bottomSearchSheet.trailingAnchor, constant: -16),
            bottomSheetAppIconContainer.centerYAnchor.constraint(equalTo: bottomSheetSearchRow.centerYAnchor),
            bottomSheetAppIconContainer.widthAnchor.constraint(equalToConstant: 40),
            bottomSheetAppIconContainer.heightAnchor.constraint(equalToConstant: 40),

            bottomSheetAppIconView.centerXAnchor.constraint(equalTo: bottomSheetAppIconContainer.centerXAnchor),
            bottomSheetAppIconView.centerYAnchor.constraint(equalTo: bottomSheetAppIconContainer.centerYAnchor),
            bottomSheetAppIconView.widthAnchor.constraint(equalToConstant: 30),
            bottomSheetAppIconView.heightAnchor.constraint(equalToConstant: 30),

            searchIcon.leadingAnchor.constraint(equalTo: bottomSheetSearchRow.leadingAnchor, constant: 14),
            searchIcon.centerYAnchor.constraint(equalTo: bottomSheetSearchRow.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 18),
            searchIcon.heightAnchor.constraint(equalToConstant: 18),

            bottomSheetSearchTextLabel.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 10),
            bottomSheetSearchTextLabel.trailingAnchor.constraint(lessThanOrEqualTo: bottomSheetSearchRow.trailingAnchor, constant: -14),
            bottomSheetSearchTextLabel.centerYAnchor.constraint(equalTo: bottomSheetSearchRow.centerYAnchor),

            bottomSheetHistoryStack.topAnchor.constraint(equalTo: bottomSheetSearchRow.bottomAnchor, constant: 16),
            bottomSheetHistoryStack.leadingAnchor.constraint(equalTo: bottomSearchSheet.leadingAnchor, constant: 16),
            bottomSheetHistoryStack.trailingAnchor.constraint(equalTo: bottomSearchSheet.trailingAnchor, constant: -16),

            bottomSheetShortcutStack.topAnchor.constraint(equalTo: bottomSheetHistoryStack.bottomAnchor, constant: 16),
            bottomSheetShortcutStack.leadingAnchor.constraint(equalTo: bottomSearchSheet.leadingAnchor, constant: 16),
            bottomSheetShortcutStack.trailingAnchor.constraint(equalTo: bottomSearchSheet.trailingAnchor, constant: -16),
            bottomSheetShortcutStack.heightAnchor.constraint(equalToConstant: 58),

            bottomSheetSecondaryShortcutStack.topAnchor.constraint(equalTo: bottomSheetShortcutStack.bottomAnchor, constant: 12),
            bottomSheetSecondaryShortcutStack.leadingAnchor.constraint(equalTo: bottomSearchSheet.leadingAnchor, constant: 16),
            bottomSheetSecondaryShortcutStack.trailingAnchor.constraint(equalTo: bottomSearchSheet.trailingAnchor, constant: -16),
            bottomSheetSecondaryShortcutStack.heightAnchor.constraint(equalToConstant: 58)
        ])

        reloadBottomSheetHistory()
        applyCachedBottomSheetWeather()
        updateBottomSearchSheet(animated: false)
    }

    private var bottomSheetCollapsedHeight: CGFloat {
        71 + view.safeAreaInsets.bottom
    }

    private var bottomSheetExpandedHeight: CGFloat {
        min(430 + view.safeAreaInsets.bottom, view.bounds.height * 0.68)
    }

    private func makeBottomSheetShortcut(icon: String, title: String, colors: [UIColor], action: Selector) -> UIControl {
        let control = GradientShortcutControl(icon: icon, title: title, colors: colors)
        control.addTarget(self, action: action, for: .touchUpInside)
        return control
    }

    private func reloadBottomSheetHistory() {
        bottomSheetSearchTextLabel.text = bottomSheetSearchTitle()

        let items = Array(POIHistoryStore.load().prefix(3))
        let signature = items
            .map { "\($0.name)|\($0.address)|\($0.latitude)|\($0.longitude)" }
            .joined(separator: ";;")
        guard signature != bottomSheetHistorySignature else { return }
        bottomSheetHistorySignature = signature

        UIView.performWithoutAnimation {
            bottomSheetHistoryStack.arrangedSubviews.forEach { view in
                bottomSheetHistoryStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }

            let titleLabel = UILabel()
            titleLabel.text = L10n.t("search.history")
            titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            titleLabel.textColor = .secondaryLabel
            bottomSheetHistoryStack.addArrangedSubview(titleLabel)

            if items.isEmpty {
                let emptyLabel = UILabel()
                emptyLabel.text = L10n.t("search.no_history")
                emptyLabel.font = .systemFont(ofSize: 14)
                emptyLabel.textColor = .tertiaryLabel
                emptyLabel.heightAnchor.constraint(equalToConstant: 44).isActive = true
                bottomSheetHistoryStack.addArrangedSubview(emptyLabel)
                bottomSheetHistoryStack.layoutIfNeeded()
                return
            }

            items.enumerated().forEach { index, poi in
                let button = makeHistoryButton(for: poi, index: index)
                bottomSheetHistoryStack.addArrangedSubview(button)
            }
            bottomSheetHistoryStack.layoutIfNeeded()
        }
    }

    private func makeHistoryButton(for poi: SelectedPOI, index: Int) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "clock.arrow.circlepath")
        configuration.title = poi.name
        configuration.subtitle = poi.address.isEmpty ? String(format: "%.6f, %.6f", poi.latitude, poi.longitude) : poi.address
        configuration.imagePadding = 10
        configuration.titleAlignment = .leading
        // History items are supporting content; keep the icon and text slightly
        // quieter than the primary search controls above them.
        configuration.baseForegroundColor = UIColor.label.withAlphaComponent(0.68)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
        button.tag = index
        button.heightAnchor.constraint(equalToConstant: 52).isActive = true
        button.addTarget(self, action: #selector(tapBottomSheetHistory(_:)), for: .touchUpInside)
        return button
    }

    private func updateBottomSearchSheet(animated: Bool) {
        bottomSheetHeightConstraint?.constant = isBottomSheetExpanded ? bottomSheetExpandedHeight : bottomSheetCollapsedHeight
        let expandedAlpha: CGFloat = isBottomSheetExpanded ? 1 : 0
        let changes = {
            self.applyBottomSheetExpansionProgress(expandedAlpha)
            self.view.layoutIfNeeded()
        }
        if animated {
            UIView.animate(
                withDuration: 0.38,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0.55,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: changes
            )
        } else {
            changes()
        }
    }

    private func setBottomSearchSheetExpanded(_ expanded: Bool, animated: Bool) {
        isBottomSheetExpanded = expanded
        if expanded {
            reloadBottomSheetHistory()
        }
        updateBottomSearchSheet(animated: animated)
    }

    private func applyBottomSheetExpansionProgress(_ progress: CGFloat) {
        let alpha = min(max(progress, 0), 1)
        bottomSheetHistoryStack.alpha = alpha
        bottomSheetShortcutStack.alpha = alpha
        bottomSheetSecondaryShortcutStack.alpha = alpha
    }

    private func bottomSheetExpansionProgress(for height: CGFloat) -> CGFloat {
        (height - bottomSheetCollapsedHeight) / max(1, bottomSheetExpandedHeight - bottomSheetCollapsedHeight)
    }

    private func bottomSheetSearchTitle() -> String {
        let name = POIHistoryStore.load().first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? L10n.t("home.search_here") : name
    }

    // MARK: - 按钮样式

    private func makeFloatingButton(icon: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: icon) ?? UIImage(systemName: "circle"), for: .normal)
        styleFloatingButton(button)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makeFloatingTextButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        styleFloatingButton(button)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func styleFloatingButton(_ button: UIButton) {
        button.tintColor = .label
        button.backgroundColor = .systemBackground
        button.layer.cornerRadius = 22
        applyShadow(to: button)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    private func applyShadow(to view: UIView) {
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.15
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        view.layer.shadowRadius = 3
    }

    // MARK: - 定位

    private func setupHeadingUpdates() {
        guard CLLocationManager.headingAvailable() else { return }
        headingManager.delegate = self
        headingManager.headingFilter = 1
        updateHeadingOrientation()
    }

    private func startHeadingUpdates() {
        guard CLLocationManager.headingAvailable() else { return }
        updateHeadingOrientation()
        headingManager.startUpdatingHeading()
    }

    private func updateHeadingOrientation() {
        guard let orientation = view.window?.windowScene?.interfaceOrientation else {
            headingManager.headingOrientation = .portrait
            return
        }
        switch orientation {
        case .portrait:
            headingManager.headingOrientation = .portrait
        case .portraitUpsideDown:
            headingManager.headingOrientation = .portraitUpsideDown
        case .landscapeLeft:
            headingManager.headingOrientation = .landscapeLeft
        case .landscapeRight:
            headingManager.headingOrientation = .landscapeRight
        default:
            headingManager.headingOrientation = .portrait
        }
    }

    private func updateLocationHeading(animated: Bool) {
        #if canImport(BaiduMapAPI_Map)
        let mapRelativeHeading = currentHeading - CLLocationDirection(mapView.rotation)
        currentLocationAnnotationView?.setHeading(mapRelativeHeading, animated: animated)
        #endif
    }

    private func refreshLocation(shouldCenterMap: Bool, forceCenter: Bool = false, useCachedLocation: Bool = true) {
        LocationManager.shared.requestAuthorization()

        if useCachedLocation, let cached = LocationManager.shared.lastKnownLocation {
            updateCurrentLocation(cached, shouldCenterMap: shouldCenterMap, forceCenter: forceCenter)
        }

        LocationManager.shared.requestLocation { [weak self] location in
            guard let self, let location else { return }
            self.updateCurrentLocation(
                location,
                shouldCenterMap: shouldCenterMap,
                forceCenter: forceCenter || (shouldCenterMap && !self.userDidMoveMap)
            )
        }
    }

    private func refreshLocationWhenPageAppears() {
        if currentLocation == nil || !hasCenteredInitialLocation {
            refreshLocation(shouldCenterMap: true)
        } else {
            // 从导航等二级页面返回时重新获取当前位置，更新首页定位标记。
            refreshLocation(shouldCenterMap: false, useCachedLocation: false)
        }
    }

    private func updateCurrentLocation(_ location: CurrentLocation, shouldCenterMap: Bool, forceCenter: Bool = false) {
        currentLocation = location
        sideMenuVC.updateCurrentLocation(displayLocation(for: location))
        loadBottomSheetWeatherIfNeeded(for: location)

        #if canImport(BaiduMapAPI_Map)
        let bd09 = bd09Coordinate(for: location)
        let canCenterMap = forceCenter || (!hasCenteredInitialLocation && !userDidMoveMap)
        if shouldCenterMap && canCenterMap {
            mapView.setCenter(bd09, animated: true)
            hasCenteredInitialLocation = true
        }
        resetCurrentLocationAnnotation(at: bd09)
        #endif
    }

    private func displayLocation(for location: CurrentLocation) -> String {
        let address = location.address.isEmpty ? location.city : location.address
        let altitudeText = location.altitude.map { L10n.f("home.altitude_value_format", $0) } ?? "--"
        return String(
            format: L10n.t("home.coordinate_format"),
            address,
            location.latitude,
            location.longitude,
            altitudeText
        )
    }

    private func loadBottomSheetWeatherIfNeeded(for location: CurrentLocation) {
        let candidates = weatherCityCandidates(for: location)
        let requestKey = candidates.joined(separator: "|")
        guard !candidates.isEmpty, requestKey != lastBottomSheetWeatherCity else { return }
        lastBottomSheetWeatherCity = requestKey
        requestBottomSheetWeather(candidates: candidates, index: 0)
    }

    private func requestBottomSheetWeather(candidates: [String], index: Int) {
        guard index < candidates.count else { return }

        ApiClient.fetchWeatherDetail(city: candidates[index]) { [weak self] result in
            guard let self,
                  let live = (result.json?["lives"] as? [[String: Any]])?.first else {
                self?.requestBottomSheetWeather(candidates: candidates, index: index + 1)
                return
            }

            let weather = live["weather"] as? String ?? ""
            let temperature = live["temperature"] as? String ?? ""
            guard !weather.isEmpty || !temperature.isEmpty else {
                self.requestBottomSheetWeather(candidates: candidates, index: index + 1)
                return
            }

            let icon = self.bottomSheetWeatherIcon(for: weather)
            let cachedWeather = SpUtil.string(.lastLiveWeather)
            let cachedTemperature = SpUtil.string(.lastLiveTemperature)
            if weather != cachedWeather || temperature != cachedTemperature {
                SpUtil.setString(weather, for: .lastLiveWeather)
                SpUtil.setString(temperature, for: .lastLiveTemperature)
                self.bottomSheetWeatherIconView.image = UIImage(systemName: icon.name)
                self.bottomSheetWeatherIconView.tintColor = icon.color
                self.bottomSheetTemperatureLabel.text = temperature.isEmpty ? "--°" : "\(temperature)°"
            }
        }
    }

    private func applyCachedBottomSheetWeather() {
        let weather = SpUtil.string(.lastLiveWeather)
        let temperature = SpUtil.string(.lastLiveTemperature)
        guard !weather.isEmpty || !temperature.isEmpty else { return }

        let icon = bottomSheetWeatherIcon(for: weather)
        bottomSheetWeatherIconView.image = UIImage(systemName: icon.name)
        bottomSheetWeatherIconView.tintColor = icon.color
        bottomSheetTemperatureLabel.text = temperature.isEmpty ? "--°" : "\(temperature)°"
    }

    private func weatherCityCandidates(for location: CurrentLocation) -> [String] {
        [
            cityLevelAdcode(from: location.adcode),
            location.adcode,
            location.city,
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

    private func bottomSheetWeatherIcon(for weather: String) -> (name: String, color: UIColor) {
        let value = weather.lowercased()

        if value.contains("冰雹") || value.contains("雹") || value.contains("hail") {
            return ("cloud.hail.fill", UIColor(red: 0.34, green: 0.64, blue: 0.94, alpha: 1))
        }
        if value.contains("雷") || value.contains("thunder") || value.contains("storm") {
            return ("cloud.bolt.rain.fill", UIColor(red: 0.93, green: 0.68, blue: 0.18, alpha: 1))
        }
        if value.contains("暴雨") || value.contains("大暴雨") || value.contains("特大暴雨") || value.contains("heavy rain") {
            return ("cloud.heavyrain.fill", UIColor(red: 0.16, green: 0.48, blue: 0.90, alpha: 1))
        }
        if value.contains("雨夹雪") || value.contains("sleet") {
            return ("cloud.sleet.fill", UIColor(red: 0.23, green: 0.58, blue: 0.84, alpha: 1))
        }
        if value.contains("雪") || value.contains("snow") {
            return ("cloud.snow.fill", UIColor(red: 0.20, green: 0.70, blue: 0.78, alpha: 1))
        }
        if value.contains("大雨") || value.contains("中雨") || value.contains("阵雨") || value.contains("雨") || value.contains("rain") {
            return ("cloud.rain.fill", UIColor(red: 0.18, green: 0.53, blue: 0.90, alpha: 1))
        }
        if value.contains("雾") || value.contains("霾") || value.contains("沙") || value.contains("尘") || value.contains("fog") || value.contains("haze") {
            return ("cloud.fog.fill", .systemGray)
        }
        if value.contains("阴") || value.contains("cloudy") {
            return ("cloud.fill", .systemGray)
        }
        if value.contains("多云") || value.contains("少云") || value.contains("partly") {
            return ("cloud.sun.fill", UIColor(red: 0.95, green: 0.58, blue: 0.18, alpha: 1))
        }
        if value.contains("晴") || value.contains("clear") || value.contains("sun") {
            return ("sun.max.fill", UIColor(red: 0.96, green: 0.66, blue: 0.14, alpha: 1))
        }

        return ("cloud.sun.fill", UIColor(red: 0.95, green: 0.58, blue: 0.18, alpha: 1))
    }

    private func centerMap(on location: CurrentLocation) {
        updateCurrentLocation(location, shouldCenterMap: true, forceCenter: true)
    }

    private func resetCurrentLocationAnnotation(at coordinate: CLLocationCoordinate2D) {
        #if canImport(BaiduMapAPI_Map)
        if let annotation = currentLocationAnnotation {
            annotation.coordinate = coordinate
            return
        }

        let annotation = BMKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = L10n.t("common.my_location")
        currentLocationAnnotation = annotation
        mapView.addAnnotation(annotation)
        #endif
    }

    private func bd09Coordinate(for location: CurrentLocation) -> CLLocationCoordinate2D {
        CoordinateConverter.gcj02ToBD09(CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude))
    }

    /// 当前定位的 BD09 坐标 (无定位时退化为默认起点)
    private func currentBD09Coordinate() -> CLLocationCoordinate2D {
        if let location = currentLocation {
            return bd09Coordinate(for: location)
        }
        return CoordinateConverter.gcj02ToBD09(
            CLLocationCoordinate2D(latitude: Constants.defaultStartLat, longitude: Constants.defaultStartLon)
        )
    }

    // MARK: - 事件

    @objc private func tapMenu() {
        sideMenuContainer?.toggleMenu()
    }

    @objc private func tapSearch() {
        navigationController?.pushViewController(RoutePlanViewController(startLocation: currentLocation), animated: true)
    }

    @objc private func tapBottomSearchRow() {
        if isBottomSheetExpanded {
            tapSearch()
        } else {
            setBottomSearchSheetExpanded(true, animated: true)
        }
    }

    @objc private func tapBottomSheetHistory(_ sender: UIButton) {
        let items = Array(POIHistoryStore.load().prefix(3))
        guard sender.tag >= 0, sender.tag < items.count else { return }
        navigationController?.pushViewController(
            RoutePlanViewController(startLocation: currentLocation, destinationPOI: items[sender.tag]),
            animated: true
        )
    }

    @objc private func handleBottomSheetPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .began:
            isDraggingBottomSheet = true
        case .changed:
            let baseHeight = isBottomSheetExpanded ? bottomSheetExpandedHeight : bottomSheetCollapsedHeight
            let targetHeight = baseHeight - translation.y
            let clampedHeight = min(max(targetHeight, bottomSheetCollapsedHeight), bottomSheetExpandedHeight)
            bottomSheetHeightConstraint?.constant = clampedHeight
            applyBottomSheetExpansionProgress(bottomSheetExpansionProgress(for: clampedHeight))
            view.layoutIfNeeded()
        case .ended, .cancelled, .failed:
            isDraggingBottomSheet = false
            if abs(velocity.y) > 250 {
                setBottomSearchSheetExpanded(velocity.y < 0, animated: true)
            } else {
                let currentHeight = bottomSheetHeightConstraint?.constant ?? bottomSheetCollapsedHeight
                let midpoint = (bottomSheetCollapsedHeight + bottomSheetExpandedHeight) / 2
                setBottomSearchSheetExpanded(currentHeight > midpoint, animated: true)
            }
        default:
            break
        }
    }

    @objc private func tapCloudPanorama() {
        navigationController?.pushViewController(CloudPanoramaListViewController(), animated: true)
    }

    @objc private func tapAround() {
        navigationController?.pushViewController(PoiAroundSearchViewController(location: currentLocation), animated: true)
    }

    @objc private func tapWeather() {
        navigationController?.pushViewController(WeatherViewController(location: currentLocation), animated: true)
    }

    @objc private func tapSunsetGlow() {
        navigationController?.pushViewController(WeatherViewController(location: currentLocation), animated: true)
    }

    @objc private func tapTyphoon() {
        guard let url = URL(string: UrlConstants.typhoonPath) else { return }
        let controller = WebViewController(
            title: L10n.t("weather.typhoon_monitor_title"),
            content: .remoteURL(url),
            fullScreen: true,
            showsFullScreenTitle: false
        )
        controller.modalPresentationStyle = .fullScreen
        controller.modalPresentationCapturesStatusBarAppearance = true
        controller.modalTransitionStyle = .crossDissolve
        present(controller, animated: true)
    }

    @objc private func tapEarthquakeReport() {
        navigationController?.pushViewController(EarthquakeViewController(), animated: true)
    }

    @objc private func tapMoonPhase() {
        navigationController?.pushViewController(MoonPhaseViewController(), animated: true)
    }

    @objc private func tapMoreTools(_ sender: UIControl) {
        let sheet = UIAlertController(
            title: L10n.t("home.more_tools"),
            message: nil,
            preferredStyle: .actionSheet
        )
        let tideAction = UIAlertAction(title: L10n.t("tide.today_title"), style: .default) { [weak self] _ in
            self?.navigationController?.pushViewController(TodayTideViewController(), animated: true)
        }
        tideAction.setValue(UIImage(systemName: "water.waves"), forKey: "image")
        sheet.addAction(tideAction)

        let weatherAction = UIAlertAction(title: "天气查询", style: .default) { [weak self] _ in
            guard let self else { return }
            self.navigationController?.pushViewController(
                WeatherViewController(location: self.currentLocation),
                animated: true
            )
        }
        weatherAction.setValue(UIImage(systemName: "cloud.sun.fill"), forKey: "image")
        sheet.addAction(weatherAction)

        let metroAction = UIAlertAction(title: "世界地铁", style: .default) { [weak self] _ in
            self?.navigationController?.pushViewController(MetroViewController(), animated: true)
        }
        metroAction.setValue(UIImage(systemName: "tram.fill"), forKey: "image")
        sheet.addAction(metroAction)

        let panoramaAction = UIAlertAction(title: "全景街景", style: .default) { [weak self] _ in
            guard let self else { return }
            let coordinate = self.currentBD09Coordinate()
            self.navigationController?.pushViewController(
                PanoramaViewController(latitude: coordinate.latitude, longitude: coordinate.longitude),
                animated: true
            )
        }
        panoramaAction.setValue(UIImage(systemName: "binoculars.fill"), forKey: "image")
        sheet.addAction(panoramaAction)
        sheet.addAction(UIAlertAction(title: L10n.t("common.cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }
        present(sheet, animated: true)
    }

    @objc private func tapTraffic() {
        #if canImport(BaiduMapAPI_Map)
        let newState = !mapView.isTrafficEnabled
        mapView.isTrafficEnabled = newState
        trafficButton.tintColor = newState ? .systemBlue : .label
        #endif
    }

    @objc private func tapPanorama() {
        let coordinate = currentBD09Coordinate()
        navigationController?.pushViewController(
            PanoramaViewController(latitude: coordinate.latitude, longitude: coordinate.longitude),
            animated: true
        )
    }

    @objc private func tapWorldPanorama() {
        navigationController?.pushViewController(WorldPanoramaListViewController(), animated: true)
    }

    @objc private func tapMetro() {
        navigationController?.pushViewController(MetroViewController(), animated: true)
    }

    @objc private func tapNorth() {
        #if canImport(BaiduMapAPI_Map)
        mapView.rotation = 0
        #endif
        // 先给用户即时反馈，再强制请求一次新位置；不能只使用旧的内存缓存。
        if let currentLocation {
            centerMap(on: currentLocation)
        } else if let cached = LocationManager.shared.lastKnownLocation {
            updateCurrentLocation(cached, shouldCenterMap: true, forceCenter: true)
        }
        userDidMoveMap = false
        refreshLocation(shouldCenterMap: true, forceCenter: true, useCachedLocation: false)
    }
}

// MARK: - SideMenuViewControllerDelegate

extension MapViewController: SideMenuViewControllerDelegate {

    func sideMenuDidSelectPanorama(_ menu: SideMenuViewController) {
        sideMenuContainer?.closeMenu()
        let coordinate = currentBD09Coordinate()
        navigationController?.pushViewController(
            PanoramaViewController(latitude: coordinate.latitude, longitude: coordinate.longitude),
            animated: true
        )
    }

    func sideMenuDidSelectWeather(_ menu: SideMenuViewController) {
        sideMenuContainer?.closeMenu()
        navigationController?.pushViewController(WeatherViewController(location: currentLocation), animated: true)
    }

    func sideMenuDidSelectServiceAgreement(_ menu: SideMenuViewController) {
        sideMenuContainer?.closeMenu()
        navigationController?.pushViewController(
            WebViewController(title: L10n.t("legal.service_agreement"), content: .localText(resourceName: "user_agreement")),
            animated: true
        )
    }

    func sideMenuDidSelectPrivacyPolicy(_ menu: SideMenuViewController) {
        sideMenuContainer?.closeMenu()
        navigationController?.pushViewController(
            WebViewController(title: L10n.t("legal.privacy_policy"), content: .remoteURL(Constants.privacyPolicyURL)),
            animated: true
        )
    }

    func sideMenuDidSelectFeedback(_ menu: SideMenuViewController) {
        sideMenuContainer?.closeMenu()
        navigationController?.pushViewController(FeedbackViewController(), animated: true)
    }

    func sideMenuDidSelectRating(_ menu: SideMenuViewController) {
        sideMenuContainer?.closeMenu()
        ReviewPromptManager.openAppStoreReviewPage()
    }

    func sideMenuDidSelectClearCache(_ menu: SideMenuViewController) {
        sideMenuContainer?.closeMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.presentClearCacheConfirmation()
        }
    }

    private func presentClearCacheConfirmation() {
        let size = AppCacheManager.formattedApproximateSize
        let alert = UIAlertController(
            title: L10n.t("cache.confirm_title"),
            message: String(format: L10n.t("cache.confirm_message"), size),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.t("common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.t("cache.clear_action"), style: .destructive) { [weak self] _ in
            AppCacheManager.clear { [weak self] in
                guard let self else { return }
                let result = UIAlertController(title: nil, message: L10n.t("cache.success"), preferredStyle: .alert)
                result.addAction(UIAlertAction(title: L10n.t("common.ok"), style: .default))
                self.present(result, animated: true)
            }
        })
        present(alert, animated: true)
    }

    func sideMenu(_ menu: SideMenuViewController, didSelectMapType type: MapDisplayType) {
        applyMapType(type)
        sideMenuContainer?.closeMenu()
    }
}

// MARK: - BMKMapViewDelegate

#if canImport(BaiduMapAPI_Map)
extension MapViewController: BMKMapViewDelegate {
    func mapView(_ mapView: BMKMapView, regionWillChangeAnimated animated: Bool, reason: BMKRegionChangeReason) {
        if reason == BMKRegionChangeReasonGesture {
            userDidMoveMap = true
        }
    }

    func mapView(_ mapView: BMKMapView, regionDidChangeAnimated animated: Bool, reason: BMKRegionChangeReason) {
        updateLocationHeading(animated: animated)
    }

    func mapView(_ mapView: BMKMapView, viewFor annotation: BMKAnnotation) -> BMKAnnotationView? {
        guard let currentLocationAnnotation,
              annotation as AnyObject === currentLocationAnnotation else {
            return nil
        }

        let identifier = "currentLocation"
        var annotationView = mapView.dequeueReusableAnnotationView(
            withIdentifier: identifier
        ) as? HeadingLocationAnnotationView
        if annotationView == nil {
            annotationView = HeadingLocationAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        } else {
            annotationView?.annotation = annotation
        }

        currentLocationAnnotationView = annotationView
        annotationView?.setHeading(
            currentHeading - CLLocationDirection(mapView.rotation),
            animated: false
        )
        return annotationView
    }
}

private final class HeadingLocationAnnotationView: BMKAnnotationView {
    private let directionFadeLayers: [CAShapeLayer] = (0..<32).map { _ in CAShapeLayer() }
    private let borderLayer = CAShapeLayer()
    private let dotLayer = CAShapeLayer()
    private var displayedHeading: CGFloat = 0

    override init!(annotation: BMKAnnotation!, reuseIdentifier: String!) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        bounds = CGRect(x: 0, y: 0, width: 104, height: 104)
        backgroundColor = .clear
        isUserInteractionEnabled = false

        for (index, fadeLayer) in directionFadeLayers.enumerated() {
            let progress = CGFloat(index) / CGFloat(directionFadeLayers.count - 1)
            let alpha = 0.76 * pow(1 - progress, 1.35)
            fadeLayer.fillColor = UIColor.systemBlue.withAlphaComponent(alpha).cgColor
            layer.addSublayer(fadeLayer)
        }

        borderLayer.fillColor = UIColor.white.cgColor
        borderLayer.shadowColor = UIColor.black.cgColor
        borderLayer.shadowOpacity = 0.22
        borderLayer.shadowRadius = 2
        borderLayer.shadowOffset = CGSize(width: 0, height: 1)
        layer.addSublayer(borderLayer)

        dotLayer.fillColor = UIColor.systemBlue.cgColor
        layer.addSublayer(dotLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let startAngle = -CGFloat.pi * 0.65
        let endAngle = -CGFloat.pi * 0.35
        let innerRadius: CGFloat = 7
        let outerRadius: CGFloat = 49
        let ringWidth = (outerRadius - innerRadius) / CGFloat(directionFadeLayers.count)
        for (index, fadeLayer) in directionFadeLayers.enumerated() {
            fadeLayer.frame = bounds
            let ringInnerRadius = innerRadius + CGFloat(index) * ringWidth
            let ringOuterRadius = ringInnerRadius + ringWidth + 0.35
            let path = UIBezierPath()
            path.addArc(
                withCenter: center,
                radius: ringOuterRadius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: true
            )
            path.addArc(
                withCenter: center,
                radius: ringInnerRadius,
                startAngle: endAngle,
                endAngle: startAngle,
                clockwise: false
            )
            path.close()
            fadeLayer.path = path.cgPath
        }

        borderLayer.path = UIBezierPath(
            ovalIn: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20)
        ).cgPath
        dotLayer.path = UIBezierPath(
            ovalIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)
        ).cgPath
    }

    func setHeading(_ heading: CLLocationDirection, animated: Bool) {
        let target = CGFloat(heading * .pi / 180)
        var delta = target - displayedHeading
        while delta > .pi { delta -= .pi * 2 }
        while delta < -.pi { delta += .pi * 2 }
        displayedHeading += delta

        let changes = {
            self.transform = CGAffineTransform(rotationAngle: self.displayedHeading)
        }
        if animated {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction],
                animations: changes
            )
        } else {
            changes()
        }
    }
}
#endif

extension MapViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        currentHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        updateLocationHeading(animated: true)
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false
    }
}

private final class GradientShortcutControl: UIControl {
    private let gradientLayer = CAGradientLayer()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    init(icon: String, title: String, colors: [UIColor]) {
        super.init(frame: .zero)

        gradientLayer.colors = colors.map(\.cgColor)
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradientLayer, at: 0)
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        clipsToBounds = true

        iconView.image = UIImage(systemName: icon)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = title
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.96)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.72
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 3),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.16) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
                self.alpha = self.isHighlighted ? 0.86 : 1
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
}
