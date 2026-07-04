//
//  NaviViewController.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  高德导航页 (对应 Android navi/ 包下 BaseActivity + xxxRouteCalculateActivity)。
//  按 mode 持有对应的 AMapNaviDriveManager/WalkManager/RideManager + 对应导航视图,
//  计算路线 -> 开始GPS导航 -> 语音播报回调接入 TTSController。
//
//  注意: 本文件中标注"需对照SDK头文件核对"的代理方法签名/类型/属性名是基于
//  AMapNaviKit 常见版本的接口编写,pod install 后如编译报错,请在 Xcode 中
//  对照 AMapNaviDriveManager.h / AMapNaviWalkManager.h / AMapNaviRideManager.h /
//  AMapNaviTruckInfo.h 头文件核对并修正对应签名。
//

import UIKit
import CoreLocation

#if canImport(AMapFoundationKit)
import AMapFoundationKit
#endif
#if canImport(AMapNaviKit)
import AMapNaviKit
#endif

/// 出行方式 (对应 Android IndexActivity naviType: 1驾车 2步行 3骑行 4货车)
enum NaviMode {
    case drive
    case walk
    case ride
    case truck

    var displayName: String {
        switch self {
        case .drive: return L10n.t("navi.drive")
        case .walk: return L10n.t("navi.walk")
        case .ride: return L10n.t("navi.ride")
        case .truck: return L10n.t("navi.truck")
        }
    }
}

final class NavigationRuntimeState {
    static let shared = NavigationRuntimeState()

    private init() {}

    private(set) var isNavigating = false

    func markNavigating() {
        isNavigating = true
    }

    func clearNavigating() {
        isNavigating = false
    }
}

final class NaviViewController: UIViewController {

    private let start: SelectedPOI?
    private let end: SelectedPOI?
    private let mode: NaviMode

    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    #if canImport(AMapNaviKit)
    private var driveView: AMapNaviDriveView?
    private var walkView: AMapNaviWalkView?
    private var rideView: AMapNaviRideView?
    #endif

    init(start: SelectedPOI?, end: SelectedPOI?, mode: NaviMode) {
        self.start = start
        self.end = end
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupNaviView()
        setupOverlay()
        startCalculateRoute()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("NaviViewController")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("NaviViewController")
    }

    deinit {
        NavigationRuntimeState.shared.clearNavigating()
        #if canImport(AMapNaviKit)
        switch mode {
        case .drive, .truck:
            AMapNaviDriveManager.sharedInstance().stopNavi()
            AMapNaviDriveManager.sharedInstance().delegate = nil
        case .walk:
            AMapNaviWalkManager.sharedInstance().stopNavi()
            AMapNaviWalkManager.sharedInstance().delegate = nil
        case .ride:
            AMapNaviRideManager.sharedInstance().stopNavi()
            AMapNaviRideManager.sharedInstance().delegate = nil
        }
        #endif
        TTSController.shared.stop()
    }

    // MARK: - 导航视图 (对应 Android AmapNaviView)

    private func setupNaviView() {
        #if canImport(AMapNaviKit)
        switch mode {
        case .drive, .truck:
            let driveView = AMapNaviDriveView(frame: view.bounds)
            driveView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            driveView.delegate = self
            view.addSubview(driveView)
            self.driveView = driveView

            let manager = AMapNaviDriveManager.sharedInstance()
            manager.delegate = self
            manager.addDataRepresentative(driveView)

        case .walk:
            let walkView = AMapNaviWalkView(frame: view.bounds)
            walkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            walkView.delegate = self
            view.addSubview(walkView)
            self.walkView = walkView

            let manager = AMapNaviWalkManager.sharedInstance()
            manager.delegate = self
            manager.addDataRepresentative(walkView)

        case .ride:
            let rideView = AMapNaviRideView(frame: view.bounds)
            rideView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            rideView.delegate = self
            view.addSubview(rideView)
            self.rideView = rideView

            let manager = AMapNaviRideManager.sharedInstance()
            manager.delegate = self
            manager.addDataRepresentative(rideView)
        }
        #else
        let label = UILabel()
        label.text = L10n.f("navi.placeholder", mode.displayName)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 16)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
        #endif
    }

    // MARK: - 顶部标题 + 退出按钮

    private func setupOverlay() {
        titleLabel.text = mode.displayName
        titleLabel.textColor = .white
        titleLabel.font = .boldSystemFont(ofSize: 16)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(tapClose), for: .touchUpInside)

        view.addSubview(titleLabel)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    // MARK: - 路线计算 (对应 BaseActivity 默认坐标 + xxxRouteCalculateActivity.calculateXxxRoute)

    private func startCalculateRoute() {
        #if canImport(AMapNaviKit)
        let startPoint = naviPoint(for: start, defaultLat: Constants.defaultStartLat, defaultLon: Constants.defaultStartLon)
        let endPoint = naviPoint(for: end, defaultLat: Constants.defaultEndLat, defaultLon: Constants.defaultEndLon)

        switch mode {
        case .drive:
            let manager = AMapNaviDriveManager.sharedInstance()
            // 对应 Android strategyConvert(避免拥堵=true, 不走高速=false, 避免收费=false, 高速优先=false, 多路径=false)
            manager.calculateDriveRoute(withStart: [startPoint], end: [endPoint], wayPoints: nil, drivingStrategy: .drivingStrategySingleAvoidCongestion)

        case .truck:
            let manager = AMapNaviDriveManager.sharedInstance()
            configureTruckInfo(on: manager)
            manager.calculateDriveRoute(withStart: [startPoint], end: [endPoint], wayPoints: nil, drivingStrategy: .drivingStrategySingleAvoidCongestion)

        case .walk:
            let manager = AMapNaviWalkManager.sharedInstance()
            manager.calculateWalkRoute(withStart: [startPoint], end: [endPoint])

        case .ride:
            let manager = AMapNaviRideManager.sharedInstance()
            manager.calculateRideRoute(withStart: startPoint, end: endPoint)
        }
        #endif
    }

    #if canImport(AMapNaviKit)
    private func naviPoint(for poi: SelectedPOI?, defaultLat: Double, defaultLon: Double) -> AMapNaviPoint {
        if let poi = poi {
            return AMapNaviPoint.location(withLatitude: CGFloat(poi.latitude), longitude: CGFloat(poi.longitude))
        }
        return AMapNaviPoint.location(withLatitude: CGFloat(defaultLat), longitude: CGFloat(defaultLon))
    }

    /// 货车导航参数 (对应 Android TruckRouteCalculateActivity 中车辆信息配置)
    private func configureTruckInfo(on manager: AMapNaviDriveManager) {
        let vehicleInfo = AMapNaviVehicleInfo()
        vehicleInfo.type = 1            // 货车类型: 1=燃油货车
        vehicleInfo.size = 4             // 货车大小: 4=重型货车
        vehicleInfo.weight = 99          // 总重(吨)
        vehicleInfo.height = 4           // 高度(米)
        vehicleInfo.width = 2            // 宽度(米)
        vehicleInfo.length = 16          // 长度(米)
        vehicleInfo.vehicleId = "京A12345" // 车牌号
        manager.setVehicleInfo(vehicleInfo)
    }
    #endif

    // MARK: - 退出导航 (对应 Android onNaviCancel -> finish())

    @objc private func tapClose() {
        NavigationRuntimeState.shared.clearNavigating()
        #if canImport(AMapNaviKit)
        switch mode {
        case .drive, .truck:
            AMapNaviDriveManager.sharedInstance().stopNavi()
        case .walk:
            AMapNaviWalkManager.sharedInstance().stopNavi()
        case .ride:
            AMapNaviRideManager.sharedInstance().stopNavi()
        }
        #endif
        TTSController.shared.stop()

        if let nav = navigationController, nav.viewControllers.first !== self {
            nav.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    fileprivate func showRouteFailureAlert() {
        let alert = UIAlertController(title: nil, message: L10n.t("navi.route_failed"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.t("common.ok"), style: .default) { [weak self] _ in
            self?.tapClose()
        })
        present(alert, animated: true)
    }

    fileprivate func showNaviSettings() {
        let alert = UIAlertController(title: L10n.t("navi.settings"), message: nil, preferredStyle: .actionSheet)

        #if canImport(AMapNaviKit)
        if let driveView {
            let trafficTitle = driveView.mapShowTraffic ? L10n.t("navi.close_traffic") : L10n.t("navi.open_traffic")
            alert.addAction(UIAlertAction(title: trafficTitle, style: .default) { _ in
                driveView.mapShowTraffic.toggle()
            })
        }
        #endif

        alert.addAction(UIAlertAction(title: L10n.t("navi.exit"), style: .destructive) { [weak self] _ in
            self?.tapClose()
        })
        alert.addAction(UIAlertAction(title: L10n.t("common.cancel"), style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.safeAreaInsets.top + 44, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }

        present(alert, animated: true)
    }
}

#if canImport(AMapNaviKit)

// MARK: - 驾车/货车导航 (AMapNaviDriveManagerDelegate)，对应 Android AMapNaviListener

extension NaviViewController: AMapNaviDriveManagerDelegate {

    func driveManager(onCalculateRouteSuccess driveManager: AMapNaviDriveManager) {
        // 对应 Android mAMapNavi.startNavi(NaviType.GPS)
        NavigationRuntimeState.shared.markNavigating()
        driveManager.startGPSNavi()
    }

    func driveManager(_ driveManager: AMapNaviDriveManager, onCalculateRouteFailure error: Error) {
        NavigationRuntimeState.shared.clearNavigating()
        showRouteFailureAlert()
    }

    /// 语音播报文本回调 (对应 Android TTSController.onGetNavigationText)
    func driveManager(_ driveManager: AMapNaviDriveManager, playNaviSound soundString: String, soundStringType: AMapNaviSoundType) {
        TTSController.shared.speak(soundString)
    }

    func driveManager(onArrivedDestination driveManager: AMapNaviDriveManager) {
        NavigationRuntimeState.shared.clearNavigating()
        TTSController.shared.speak(L10n.t("navi.arrived"))
    }
}

extension NaviViewController: AMapNaviDriveViewDelegate {
    func driveViewCloseButtonClicked(_ driveView: AMapNaviDriveView) {
        tapClose()
    }

    func driveViewMoreButtonClicked(_ driveView: AMapNaviDriveView) {
        showNaviSettings()
    }
}

// MARK: - 步行导航 (AMapNaviWalkManagerDelegate)

extension NaviViewController: AMapNaviWalkManagerDelegate {

    func walkManager(onCalculateRouteSuccess walkManager: AMapNaviWalkManager) {
        NavigationRuntimeState.shared.markNavigating()
        walkManager.startGPSNavi()
    }

    func walkManager(_ walkManager: AMapNaviWalkManager, onCalculateRouteFailure error: Error) {
        NavigationRuntimeState.shared.clearNavigating()
        showRouteFailureAlert()
    }

    func walkManager(_ walkManager: AMapNaviWalkManager, playNaviSound soundString: String, soundStringType: AMapNaviSoundType) {
        TTSController.shared.speak(soundString)
    }

    func walkManager(onArrivedDestination walkManager: AMapNaviWalkManager) {
        NavigationRuntimeState.shared.clearNavigating()
        TTSController.shared.speak(L10n.t("navi.arrived"))
    }
}

extension NaviViewController: AMapNaviWalkViewDelegate {
    func walkViewCloseButtonClicked(_ walkView: AMapNaviWalkView) {
        tapClose()
    }

    func walkViewMoreButtonClicked(_ walkView: AMapNaviWalkView) {
        showNaviSettings()
    }
}

// MARK: - 骑行导航 (AMapNaviRideManagerDelegate)

extension NaviViewController: AMapNaviRideManagerDelegate {

    func rideManager(onCalculateRouteSuccess rideManager: AMapNaviRideManager) {
        NavigationRuntimeState.shared.markNavigating()
        rideManager.startGPSNavi()
    }

    func rideManager(_ rideManager: AMapNaviRideManager, onCalculateRouteFailure error: Error) {
        NavigationRuntimeState.shared.clearNavigating()
        showRouteFailureAlert()
    }

    func rideManager(_ rideManager: AMapNaviRideManager, playNaviSound soundString: String, soundStringType: AMapNaviSoundType) {
        TTSController.shared.speak(soundString)
    }

    func rideManager(onArrivedDestination rideManager: AMapNaviRideManager) {
        NavigationRuntimeState.shared.clearNavigating()
        TTSController.shared.speak(L10n.t("navi.arrived"))
    }
}

extension NaviViewController: AMapNaviRideViewDelegate {
    func rideViewCloseButtonClicked(_ rideView: AMapNaviRideView) {
        tapClose()
    }

    func rideViewMoreButtonClicked(_ rideView: AMapNaviRideView) {
        showNaviSettings()
    }
}

#endif
