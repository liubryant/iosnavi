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

private enum NaviBroadcastMode: String, CaseIterable {
    case concise
    case standard
    case detailed
    case muted

    private static let storageKey = "navi.broadcast.mode"

    var title: String {
        switch self {
        case .concise: return "简洁播报"
        case .standard: return "标准播报"
        case .detailed: return "详细播报"
        case .muted: return "静音模式"
        }
    }

    var description: String {
        switch self {
        case .concise: return "只播转向、上下匝道、到达等关键提示"
        case .standard: return "播报常规导航提示"
        case .detailed: return "播报全部导航、路况和安全提示"
        case .muted: return "关闭导航语音播报"
        }
    }

    static var current: NaviBroadcastMode {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: storageKey),
                  let mode = NaviBroadcastMode(rawValue: rawValue) else {
                return .standard
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
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
    private let brandOverlayView = UIView()
    private let brandNameLabel = UILabel()
    private var hasStartedNavigation = false
    private var nightModeRefreshTimer: Timer?

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

        setupNaviView()
        setupOverlay()
        applyInterfaceStyle()
        scheduleNightModeRefresh()
        startCalculateRoute()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        applyInterfaceStyle()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("NaviViewController")
        applyInterfaceStyle()
        scheduleNightModeRefresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("NaviViewController")
        nightModeRefreshTimer?.invalidate()
        nightModeRefreshTimer = nil
    }

    deinit {
        nightModeRefreshTimer?.invalidate()
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
        titleLabel.font = .boldSystemFont(ofSize: 18)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(tapClose), for: .touchUpInside)

        view.addSubview(titleLabel)
        view.addSubview(closeButton)
        setupBrandOverlay()
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 2),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 64),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -64),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor, constant: 13),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func setupBrandOverlay() {
        brandOverlayView.backgroundColor = UIColor(white: 1, alpha: 0.92)
        brandOverlayView.layer.cornerRadius = 4
        brandOverlayView.layer.cornerCurve = .continuous
        brandOverlayView.layer.shadowColor = UIColor.black.cgColor
        brandOverlayView.layer.shadowOpacity = 0.24
        brandOverlayView.layer.shadowOffset = CGSize(width: 0, height: 2)
        brandOverlayView.layer.shadowRadius = 7
        brandOverlayView.isUserInteractionEnabled = false
        brandOverlayView.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(named: "AppLogo") ?? UIImage(named: "AppIcon-1024"))
        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 4
        iconView.translatesAutoresizingMaskIntoConstraints = false

        brandNameLabel.text = "卫星导航地图"
        brandNameLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        brandNameLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [iconView, brandNameLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false

        brandOverlayView.addSubview(stack)
        view.addSubview(brandOverlayView)

        NSLayoutConstraint.activate([
            brandOverlayView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            brandOverlayView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -67),
            brandOverlayView.heightAnchor.constraint(equalToConstant: 28),

            stack.leadingAnchor.constraint(equalTo: brandOverlayView.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: brandOverlayView.trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: brandOverlayView.centerYAnchor),

            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor)
        ])
    }

    private func applyInterfaceStyle() {
        let shouldForceNightMode = shouldUseNavigationNightMode()
        overrideUserInterfaceStyle = shouldForceNightMode ? .dark : .unspecified
        let isDark = shouldForceNightMode || traitCollection.userInterfaceStyle == .dark
        view.backgroundColor = isDark ? .black : .systemBackground
        titleLabel.textColor = .white
        closeButton.tintColor = .white
        brandOverlayView.backgroundColor = isDark
            ? UIColor(white: 0.08, alpha: 0.90)
            : UIColor(white: 1, alpha: 0.92)
        brandOverlayView.layer.shadowColor = UIColor.black.cgColor
        brandNameLabel.textColor = isDark
            ? UIColor(white: 0.96, alpha: 1)
            : UIColor(red: 0.10, green: 0.13, blue: 0.18, alpha: 1)

        #if canImport(AMapNaviKit)
        let mapMode = AMapNaviViewMapModeType(rawValue: isDark ? 1 : 0) ?? AMapNaviViewMapModeType(rawValue: 0)!
        driveView?.mapViewModeType = mapMode
        walkView?.mapViewModeType = mapMode
        rideView?.mapViewModeType = mapMode
        #endif
    }

    private func shouldUseNavigationNightMode(now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let minutesSinceMidnight = hour * 60 + minute
        let nightStartMinutes = 18 * 60 + 50
        let nightEndMinutes = 6 * 60

        return minutesSinceMidnight >= nightStartMinutes || minutesSinceMidnight < nightEndMinutes
    }

    private func scheduleNightModeRefresh() {
        nightModeRefreshTimer?.invalidate()

        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let minutesSinceMidnight = hour * 60 + minute
        let nightStartMinutes = 18 * 60 + 50
        let nightEndMinutes = 6 * 60

        let nextTransition: Date?
        if minutesSinceMidnight < nightEndMinutes {
            nextTransition = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: now)
        } else if minutesSinceMidnight < nightStartMinutes {
            nextTransition = calendar.date(bySettingHour: 18, minute: 50, second: 0, of: now)
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
            nextTransition = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: tomorrow)
        } else {
            nextTransition = nil
        }

        guard let nextTransition else { return }
        nightModeRefreshTimer = Timer(
            fire: nextTransition,
            interval: 0,
            repeats: false
        ) { [weak self] _ in
            self?.handleNightModeRefreshTimer()
        }
        if let nightModeRefreshTimer {
            RunLoop.main.add(nightModeRefreshTimer, forMode: .common)
        }
    }

    private func handleNightModeRefreshTimer() {
        applyInterfaceStyle()
        scheduleNightModeRefresh()
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
        // 高德导航过程中可能回调补充路线规划失败，但 GPS 导航仍可继续工作。
        // 产品侧不展示该提示，避免用户误点确认后退出导航。
    }

    fileprivate func showNaviSettings() {
        let currentBroadcastMode = NaviBroadcastMode.current
        let alert = UIAlertController(
            title: L10n.t("navi.settings"),
            message: "当前播报模式：\(currentBroadcastMode.title)",
            preferredStyle: .actionSheet
        )

        #if canImport(AMapNaviKit)
        if let driveView {
            let trafficTitle = driveView.mapShowTraffic ? L10n.t("navi.close_traffic") : L10n.t("navi.open_traffic")
            alert.addAction(UIAlertAction(title: trafficTitle, style: .default) { _ in
                driveView.mapShowTraffic.toggle()
            })
        }
        #endif

        alert.addAction(UIAlertAction(title: "播报模式：\(currentBroadcastMode.title)", style: .default) { [weak self] _ in
            self?.showBroadcastModeSettings()
        })
        alert.addAction(UIAlertAction(title: "播报声音：\(TTSController.shared.currentVoiceName)", style: .default) { [weak self] _ in
            self?.showNavigationVoiceSettings()
        })
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

    private func showNavigationVoiceSettings() {
        let tts = TTSController.shared
        let voices = tts.availableChineseVoices
        let alert = UIAlertController(
            title: "播报声音",
            message: voices.isEmpty ? "\n当前设备没有可用的中文系统语音" : "\n选择导航语音角色，已下载的系统声音会显示在这里",
            preferredStyle: .actionSheet
        )

        let automaticPrefix = tts.isUsingAutomaticVoice ? "✓ " : ""
        alert.addAction(UIAlertAction(title: "\(automaticPrefix)系统默认（黎潋优先）", style: .default) { _ in
            tts.useAutomaticVoice()
            tts.speak("已切换为系统默认导航语音，祝您一路平安。")
        })

        voices.forEach { voice in
            let prefix = !tts.isUsingAutomaticVoice && voice.identifier == tts.currentVoiceIdentifier ? "✓ " : ""
            alert.addAction(UIAlertAction(title: "\(prefix)\(voice.displayName)", style: .default) { _ in
                tts.selectVoice(identifier: voice.identifier)
                tts.speak("已切换为\(voice.name)，祝您一路平安。")
            })
        }

        alert.addAction(UIAlertAction(title: L10n.t("common.cancel"), style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.safeAreaInsets.top + 44, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }

        present(alert, animated: true)
    }

    private func showBroadcastModeSettings() {
        let alert = UIAlertController(title: "播报模式", message: "选择导航语音播报频率", preferredStyle: .actionSheet)
        let currentMode = NaviBroadcastMode.current

        NaviBroadcastMode.allCases.forEach { mode in
            let prefix = mode == currentMode ? "✓ " : ""
            alert.addAction(UIAlertAction(title: "\(prefix)\(mode.title) - \(mode.description)", style: .default) { _ in
                NaviBroadcastMode.current = mode
                if mode == .muted {
                    TTSController.shared.stop()
                }
            })
        }

        alert.addAction(UIAlertAction(title: L10n.t("common.cancel"), style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.safeAreaInsets.top + 44, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }

        present(alert, animated: true)
    }

    fileprivate func speakNaviText(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        // The navigation SDK may send service/quota errors through the same
        // callback as turn instructions. They are not actionable while driving
        // and must not be shown or spoken as navigation guidance.
        guard !isRouteServiceFailureMessage(trimmedText) else { return }

        switch NaviBroadcastMode.current {
        case .muted:
            TTSController.shared.stop()
        case .detailed:
            TTSController.shared.speak(trimmedText)
        case .standard:
            guard !isLowPriorityBroadcast(trimmedText) else { return }
            TTSController.shared.speak(trimmedText)
        case .concise:
            guard isKeyBroadcast(trimmedText) else { return }
            TTSController.shared.speak(trimmedText)
        }
    }

    private func isRouteServiceFailureMessage(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let blockedPhrases = [
            "算路失败", "路线规划失败", "路径规划失败",
            "请求超出配额", "超出配额", "配额不足", "quota exceeded"
        ]
        return blockedPhrases.contains { normalized.contains($0.lowercased()) }
    }

    private func isLowPriorityBroadcast(_ text: String) -> Bool {
        let keywords = ["电子眼", "摄像头", "限速", "路况", "拥堵", "缓行", "服务区", "加油站"]
        return keywords.contains { text.contains($0) }
    }

    private func isKeyBroadcast(_ text: String) -> Bool {
        let keywords = ["左转", "右转", "掉头", "直行", "靠左", "靠右", "匝道", "出口", "入口", "到达", "终点", "目的地", "重新规划"]
        return keywords.contains { text.contains($0) }
    }
}

#if canImport(AMapNaviKit)

// MARK: - 驾车/货车导航 (AMapNaviDriveManagerDelegate)，对应 Android AMapNaviListener

extension NaviViewController: AMapNaviDriveManagerDelegate {

    func driveManager(onCalculateRouteSuccess driveManager: AMapNaviDriveManager) {
        // 对应 Android mAMapNavi.startNavi(NaviType.GPS)
        hasStartedNavigation = true
        NavigationRuntimeState.shared.markNavigating()
        driveManager.startGPSNavi()
    }

    func driveManager(_ driveManager: AMapNaviDriveManager, onCalculateRouteFailure error: Error) {
        if !hasStartedNavigation {
            NavigationRuntimeState.shared.clearNavigating()
        }
    }

    /// 语音播报文本回调 (对应 Android TTSController.onGetNavigationText)
    func driveManager(_ driveManager: AMapNaviDriveManager, playNaviSound soundString: String, soundStringType: AMapNaviSoundType) {
        speakNaviText(soundString)
    }

    func driveManager(onArrivedDestination driveManager: AMapNaviDriveManager) {
        NavigationRuntimeState.shared.clearNavigating()
        speakNaviText(L10n.t("navi.arrived"))
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
        hasStartedNavigation = true
        NavigationRuntimeState.shared.markNavigating()
        walkManager.startGPSNavi()
    }

    func walkManager(_ walkManager: AMapNaviWalkManager, onCalculateRouteFailure error: Error) {
        if !hasStartedNavigation {
            NavigationRuntimeState.shared.clearNavigating()
        }
    }

    func walkManager(_ walkManager: AMapNaviWalkManager, playNaviSound soundString: String, soundStringType: AMapNaviSoundType) {
        speakNaviText(soundString)
    }

    func walkManager(onArrivedDestination walkManager: AMapNaviWalkManager) {
        NavigationRuntimeState.shared.clearNavigating()
        speakNaviText(L10n.t("navi.arrived"))
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
        hasStartedNavigation = true
        NavigationRuntimeState.shared.markNavigating()
        rideManager.startGPSNavi()
    }

    func rideManager(_ rideManager: AMapNaviRideManager, onCalculateRouteFailure error: Error) {
        if !hasStartedNavigation {
            NavigationRuntimeState.shared.clearNavigating()
        }
    }

    func rideManager(_ rideManager: AMapNaviRideManager, playNaviSound soundString: String, soundStringType: AMapNaviSoundType) {
        speakNaviText(soundString)
    }

    func rideManager(onArrivedDestination rideManager: AMapNaviRideManager) {
        NavigationRuntimeState.shared.clearNavigating()
        speakNaviText(L10n.t("navi.arrived"))
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
