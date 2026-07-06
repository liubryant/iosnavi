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

    private var currentMapType: MapDisplayType = .satellite
    private var currentLocation: CurrentLocation?
    private var cloudWelcomeWorkItem: DispatchWorkItem?
    private let defaultZoomLevel: Float = 18
    private let minimumValidZoomLevel: Float = 3
    private let maximumValidZoomLevel: Float = 21

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

        applyMapType(.satellite)
        refreshLocation()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        #if canImport(BaiduMapAPI_Map)
        mapView.delegate = self
        mapView.viewWillAppear()
        recoverMapRenderingIfNeeded()
        #endif
        UMengAnalytics.shared.pageBegin("MapViewController")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleCloudPanoramaWelcomeIfNeeded()
        ReviewPromptManager.requestSystemReviewIfEligibleAfterCloudScenes(in: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cloudWelcomeWorkItem?.cancel()
        cloudWelcomeWorkItem = nil
        #if canImport(BaiduMapAPI_Map)
        mapView.viewWillDisappear()
        mapView.delegate = nil
        #endif
        UMengAnalytics.shared.pageEnd("MapViewController")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func scheduleCloudPanoramaWelcomeIfNeeded(after delay: TimeInterval = 5) {
        guard !Self.didShowCloudPanoramaWelcomeThisLaunch, cloudWelcomeWorkItem == nil else { return }
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
              let item = randomCloudPanoramaWelcomeItem() else {
            return
        }
        Self.didShowCloudPanoramaWelcomeThisLaunch = true
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
        view.addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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

    @objc private func applicationDidBecomeActive() {
        #if canImport(BaiduMapAPI_Map)
        recoverMapRenderingIfNeeded()
        #endif
    }

    private func recoverMapRenderingIfNeeded() {
        #if canImport(BaiduMapAPI_Map)
        guard viewIfLoaded?.window != nil else { return }
        view.layoutIfNeeded()

        let normalizedZoom = min(max(mapView.zoomLevel, minimumValidZoomLevel), maximumValidZoomLevel)
        if normalizedZoom != mapView.zoomLevel {
            mapView.zoomLevel = defaultZoomLevel
        } else {
            mapView.zoomLevel = normalizedZoom
        }

        if let currentLocation {
            mapView.setCenter(bd09Coordinate(for: currentLocation), animated: false)
        } else {
            mapView.setCenter(
                CoordinateConverter.gcj02ToBD09(
                    CLLocationCoordinate2D(latitude: Constants.defaultStartLat, longitude: Constants.defaultStartLon)
                ),
                animated: false
            )
        }
        applyMapType(currentMapType)
        #endif
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
        configuration.baseForegroundColor = .label
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

    // MARK: - 右侧悬浮按钮: 周边 / 天气 / 路况

    private func setupRightButtons() {
        let aroundButton = makeFloatingButton(icon: "mappin.and.ellipse", action: #selector(tapAround))
        let weatherButton = makeFloatingButton(icon: "cloud.sun", action: #selector(tapWeather))
        let cloudButton = makeFloatingTextButton(title: "720", action: #selector(tapCloudPanorama))
        trafficButton.setImage(UIImage(systemName: "car"), for: .normal)
        styleFloatingButton(trafficButton)
        trafficButton.addTarget(self, action: #selector(tapTraffic), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [aroundButton, weatherButton, trafficButton, cloudButton])
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

    // MARK: - 按钮样式

    private func makeFloatingButton(icon: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: icon), for: .normal)
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

    private func refreshLocation() {
        LocationManager.shared.requestAuthorization()

        if let cached = LocationManager.shared.lastKnownLocation {
            currentLocation = cached
            sideMenuVC.updateCurrentLocation(displayLocation(for: cached))
            centerMap(on: cached)
        }

        LocationManager.shared.requestLocation { [weak self] location in
            guard let self, let location else { return }
            self.currentLocation = location
            self.sideMenuVC.updateCurrentLocation(self.displayLocation(for: location))
            self.centerMap(on: location)
        }
    }

    private func displayLocation(for location: CurrentLocation) -> String {
        let address = location.address.isEmpty ? location.city : location.address
        return String(
            format: L10n.t("home.coordinate_format"),
            address,
            location.latitude,
            location.longitude
        )
    }

    private func centerMap(on location: CurrentLocation) {
        #if canImport(BaiduMapAPI_Map)
        let bd09 = bd09Coordinate(for: location)
        mapView.setCenter(bd09, animated: true)
        if let annotations = mapView.annotations {
            mapView.removeAnnotations(annotations)
        }
        let annotation = BMKPointAnnotation()
        annotation.coordinate = bd09
        annotation.title = L10n.t("common.my_location")
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

    @objc private func tapCloudPanorama() {
        navigationController?.pushViewController(CloudPanoramaListViewController(), animated: true)
    }

    @objc private func tapAround() {
        navigationController?.pushViewController(PoiAroundSearchViewController(location: currentLocation), animated: true)
    }

    @objc private func tapWeather() {
        navigationController?.pushViewController(WeatherViewController(location: currentLocation), animated: true)
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
        if let currentLocation {
            centerMap(on: currentLocation)
            return
        }
        if let cached = LocationManager.shared.lastKnownLocation {
            currentLocation = cached
            sideMenuVC.updateCurrentLocation(displayLocation(for: cached))
            centerMap(on: cached)
            return
        }
        refreshLocation()
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
    func mapView(_ mapView: BMKMapView, viewFor annotation: BMKAnnotation) -> BMKAnnotationView? {
        guard annotation is BMKPointAnnotation else { return nil }
        let identifier = "currentLocation"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? BMKPinAnnotationView
        if annotationView == nil {
            annotationView = BMKPinAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        } else {
            annotationView?.annotation = annotation
        }
        annotationView?.pinColor = UInt(BMKPinAnnotationColorPurple)
        annotationView?.animatesDrop = false
        return annotationView
    }
}
#endif
