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

private enum DriveNavigationMode {
    private static var simulationEnabledForCurrentNavigation = false

    static var isSimulationEnabled: Bool {
        get { simulationEnabledForCurrentNavigation }
        set { simulationEnabledForCurrentNavigation = newValue }
    }

    static func resetToGPSNavigation() {
        simulationEnabledForCurrentNavigation = false
        UserDefaults.standard.removeObject(forKey: "navi.drive.simulation.enabled")
        UserDefaults.standard.removeObject(forKey: "navi.drive.simulation.speed")
    }

}

private struct DriveRouteOption {
    let routeID: Int
    let title: String
    let duration: Int
    let distance: Int
    let tollCost: Int

    var detailText: String {
        let tollText = tollCost > 0 ? "预计收费 ¥\(tollCost)" : "预计无收费"
        return "\(Self.durationText(duration))\n\(Self.distanceText(distance))\n\(tollText)"
    }

    private static func durationText(_ seconds: Int) -> String {
        let minutes = max(Int(ceil(Double(max(seconds, 0)) / 60.0)), 1)
        guard minutes >= 60 else { return "\(minutes)分钟" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)小时" : "\(hours)小时\(remainingMinutes)分钟"
    }

    private static func distanceText(_ meters: Int) -> String {
        let safeMeters = max(meters, 0)
        guard safeMeters >= 1_000 else { return "\(safeMeters)米" }
        let kilometers = Double(safeMeters) / 1_000.0
        if kilometers >= 100 || kilometers.rounded() == kilometers {
            return "\(Int(kilometers.rounded()))公里"
        }
        return String(format: "%.1f公里", kilometers)
    }
}

private final class DriveRouteOptionControl: UIControl {
    private let gradientLayer = CAGradientLayer()
    private let routeTitleLabel = UILabel()
    private let routeDetailLabel = UILabel()

    override var isSelected: Bool {
        didSet { refreshAppearance() }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.97, y: 0.97)
                    : .identity
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 110)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with option: DriveRouteOption) {
        routeTitleLabel.text = option.title
        routeDetailLabel.text = option.detailText
        accessibilityLabel = "\(option.title)，\(option.detailText.replacingOccurrences(of: "\n", with: "，"))"
    }

    func refreshAppearance() {
        backgroundColor = .clear
        gradientLayer.colors = (isSelected
            ? RouteActionGradient.primaryColors
            : RouteActionGradient.paleBlueColors).map(\.cgColor)
        routeTitleLabel.textColor = isSelected ? .white : .label
        routeDetailLabel.textColor = isSelected
            ? UIColor.white.withAlphaComponent(0.86)
            : RouteActionGradient.paleBlueForeground
        layer.borderWidth = 0
        layer.shadowColor = isSelected
            ? UIColor(red: 0.12, green: 0.38, blue: 0.94, alpha: 1).cgColor
            : UIColor(red: 0.33, green: 0.63, blue: 0.90, alpha: 1).cgColor
        layer.shadowOpacity = isSelected ? 0.24 : 0.10
        layer.shadowOffset = CGSize(width: 0, height: isSelected ? 5 : 3)
        layer.shadowRadius = isSelected ? 8 : 5
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        refreshAppearance()
    }

    private func setupView() {
        layer.cornerRadius = 13
        layer.cornerCurve = .continuous
        layer.masksToBounds = false

        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.cornerRadius = 13
        layer.insertSublayer(gradientLayer, at: 0)

        routeTitleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        routeTitleLabel.textAlignment = .center
        routeTitleLabel.adjustsFontSizeToFitWidth = true
        routeTitleLabel.minimumScaleFactor = 0.78

        routeDetailLabel.font = .systemFont(ofSize: 13.5, weight: .medium)
        routeDetailLabel.textAlignment = .center
        routeDetailLabel.numberOfLines = 3

        let stack = UIStackView(arrangedSubviews: [routeTitleLabel, routeDetailLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 7
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        refreshAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
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
    private let navigationScaleBarView = NavigationMapScaleBarView()
    private let routeNoticeToastView = UIView()
    private let routeNoticeToastTitleLabel = UILabel()
    private let routeNoticeToastDetailLabel = UILabel()
    private var routeNoticeToastDismissWorkItem: DispatchWorkItem?
    private var lastRouteSwitchNoticeDate = Date.distantPast
    private let routeSelectionTopBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let routeSelectionBackButton = UIButton(type: .system)
    private let routeSelectionTopTitleLabel = UILabel()
    private let routeSelectionPanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let routeSelectionTitleLabel = UILabel()
    private let routeRefreshButton = UIButton(type: .system)
    private let routeLocateButton = UIButton(type: .system)
    private let routeOptionsStack = UIStackView()
    private let confirmRouteButton = UIButton(type: .system)
    private var driveRouteOptions: [DriveRouteOption] = []
    private var routeOptionControls: [DriveRouteOptionControl] = []
    private var selectedDriveRouteID: Int?
    private var isRefreshingDriveRoutes = false
    private var hasStartedNavigation = false
    private var isExitingNavigation = false
    private var preservesClosingSpeechOnDeinit = false
    private var nightModeRefreshTimer: Timer?
    private var scaleBarRefreshTimer: Timer?
    private var currentNavigationLatitude: Double

    #if canImport(AMapNaviKit)
    private var driveView: AMapNaviDriveView?
    private var walkView: AMapNaviWalkView?
    private var rideView: AMapNaviRideView?
    #endif

    init(start: SelectedPOI?, end: SelectedPOI?, mode: NaviMode) {
        self.start = start
        self.end = end
        self.mode = mode
        self.currentNavigationLatitude = start?.latitude ?? Constants.defaultStartLat
        DriveNavigationMode.resetToGPSNavigation()
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
        scheduleScaleBarRefresh()
        startCalculateRoute()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateNavigationScaleBar()
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
        scheduleScaleBarRefresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("NaviViewController")
        nightModeRefreshTimer?.invalidate()
        nightModeRefreshTimer = nil
        scaleBarRefreshTimer?.invalidate()
        scaleBarRefreshTimer = nil
    }

    deinit {
        nightModeRefreshTimer?.invalidate()
        scaleBarRefreshTimer?.invalidate()
        routeNoticeToastDismissWorkItem?.cancel()
        NavigationRuntimeState.shared.clearNavigating()
        #if canImport(AMapNaviKit)
        switch mode {
        case .drive, .truck:
            let manager = AMapNaviDriveManager.sharedInstance()
            manager.stopNavi()
            manager.setMultipleRouteNaviMode(false)
            manager.delegate = nil
        case .walk:
            let manager = AMapNaviWalkManager.sharedInstance()
            manager.stopNavi()
            manager.delegate = nil
        case .ride:
            let manager = AMapNaviRideManager.sharedInstance()
            manager.stopNavi()
            manager.delegate = nil
        }
        #endif
        if !preservesClosingSpeechOnDeinit {
            TTSController.shared.stop()
        }
    }

    // MARK: - 导航视图 (对应 Android AmapNaviView)

    private func setupNaviView() {
        #if canImport(AMapNaviKit)
        switch mode {
        case .drive, .truck:
            let viewConfig = AMapNaviDriveViewConfig()
            // 路线选择由本页面自己的底部面板承载。这里保持导航视图状态，避免
            // SDK 的行前规划起终点栏、返回/添加途经点和地图控件与自定义 UI 重叠。
            viewConfig.state = AMapNaviDriveViewState(rawValue: 2)!
            viewConfig.drivingStrategy = mode == .drive
                ? .drivingStrategyMultipleDefault
                : .drivingStrategySingleAvoidCongestion
            viewConfig.showNaviPopTips = mode != .drive
            viewConfig.showDrivingStrategyPreferenceView = false
            let driveView = AMapNaviDriveView(frame: view.bounds, viewConfig: viewConfig)
            driveView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            driveView.delegate = self
            driveView.showUIElements = mode != .drive
            view.addSubview(driveView)
            self.driveView = driveView

            let manager = AMapNaviDriveManager.sharedInstance()
            manager.delegate = self
            manager.addDataRepresentative(driveView)
            manager.addDataRepresentative(self)
            if mode == .drive {
                manager.setMultipleRouteNaviMode(true)
                driveView.showBackupRoute = true
            } else {
                manager.setMultipleRouteNaviMode(false)
            }

        case .walk:
            let walkView = AMapNaviWalkView(frame: view.bounds)
            walkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            walkView.delegate = self
            view.addSubview(walkView)
            self.walkView = walkView

            let manager = AMapNaviWalkManager.sharedInstance()
            manager.delegate = self
            manager.addDataRepresentative(walkView)
            manager.addDataRepresentative(self)

        case .ride:
            let rideView = AMapNaviRideView(frame: view.bounds)
            rideView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            rideView.delegate = self
            view.addSubview(rideView)
            self.rideView = rideView

            let manager = AMapNaviRideManager.sharedInstance()
            manager.delegate = self
            manager.addDataRepresentative(rideView)
            manager.addDataRepresentative(self)
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

        if mode == .drive {
            titleLabel.isHidden = true
            closeButton.isHidden = true
            setupDriveRouteSelectionPanel()
        }
    }

    private func setupDriveRouteSelectionPanel() {
        setupDriveRouteSelectionTopBar()

        routeSelectionPanel.layer.cornerRadius = 20
        routeSelectionPanel.layer.cornerCurve = .continuous
        routeSelectionPanel.clipsToBounds = true
        routeSelectionPanel.layer.borderWidth = 0.8
        routeSelectionPanel.layer.borderColor = UIColor.white.withAlphaComponent(0.32).cgColor
        routeSelectionPanel.translatesAutoresizingMaskIntoConstraints = false
        routeSelectionPanel.alpha = 0
        routeSelectionPanel.isHidden = true
        view.addSubview(routeSelectionPanel)

        routeSelectionTitleLabel.text = "选择驾车路线"
        routeSelectionTitleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        routeSelectionTitleLabel.textColor = .label

        configureRoutePanelActionButton(
            routeRefreshButton,
            symbolName: "arrow.clockwise",
            accessibilityLabel: "刷新路线",
            action: #selector(refreshDriveRoutes)
        )
        configureRoutePanelActionButton(
            routeLocateButton,
            symbolName: "location.fill",
            accessibilityLabel: "定位路线",
            action: #selector(locateDriveRoute)
        )

        let actionStack = UIStackView(arrangedSubviews: [routeRefreshButton, routeLocateButton])
        actionStack.axis = .horizontal
        actionStack.alignment = .center
        actionStack.spacing = 8

        let headerSpacer = UIView()
        let headerStack = UIStackView(arrangedSubviews: [routeSelectionTitleLabel, headerSpacer, actionStack])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = 8
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        routeOptionsStack.axis = .horizontal
        routeOptionsStack.alignment = .fill
        routeOptionsStack.distribution = .fillEqually
        routeOptionsStack.spacing = 8
        routeOptionsStack.translatesAutoresizingMaskIntoConstraints = false

        var configuration = UIButton.Configuration.plain()
        configuration.title = "开始导航"
        configuration.baseForegroundColor = .white
        configuration.background.image = RouteActionGradient.image
        configuration.background.imageContentMode = .scaleToFill
        configuration.cornerStyle = .fixed
        configuration.background.cornerRadius = 13
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 16, weight: .semibold)
            return outgoing
        }
        confirmRouteButton.configuration = configuration
        confirmRouteButton.layer.cornerRadius = 13
        confirmRouteButton.layer.cornerCurve = .continuous
        confirmRouteButton.layer.masksToBounds = false
        confirmRouteButton.layer.shadowColor = UIColor(red: 0.12, green: 0.38, blue: 0.94, alpha: 1).cgColor
        confirmRouteButton.layer.shadowOpacity = 0.24
        confirmRouteButton.layer.shadowOffset = CGSize(width: 0, height: 6)
        confirmRouteButton.layer.shadowRadius = 10
        confirmRouteButton.addTarget(self, action: #selector(confirmSelectedDriveRoute), for: .touchUpInside)
        confirmRouteButton.translatesAutoresizingMaskIntoConstraints = false

        let contentView = routeSelectionPanel.contentView
        contentView.addSubview(headerStack)
        contentView.addSubview(routeOptionsStack)
        contentView.addSubview(confirmRouteButton)

        let preferredWidth = routeSelectionPanel.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -24)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            routeSelectionPanel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            routeSelectionPanel.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            routeSelectionPanel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            // 面板背景一直铺到屏幕底部，交互内容仍停在安全区上方。
            routeSelectionPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            routeSelectionPanel.widthAnchor.constraint(lessThanOrEqualToConstant: 620),
            preferredWidth,

            headerStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 15),
            headerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            routeRefreshButton.widthAnchor.constraint(equalToConstant: 30),
            routeRefreshButton.heightAnchor.constraint(equalToConstant: 30),
            routeLocateButton.widthAnchor.constraint(equalToConstant: 30),
            routeLocateButton.heightAnchor.constraint(equalToConstant: 30),

            routeOptionsStack.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 11),
            routeOptionsStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            routeOptionsStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            routeOptionsStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 110),
            confirmRouteButton.topAnchor.constraint(equalTo: routeOptionsStack.bottomAnchor, constant: 12),
            confirmRouteButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            confirmRouteButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            confirmRouteButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            confirmRouteButton.heightAnchor.constraint(equalToConstant: 46)
        ])
    }

    private func configureRoutePanelActionButton(
        _ button: UIButton,
        symbolName: String,
        accessibilityLabel: String,
        action: Selector
    ) {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbolName)
        configuration.baseForegroundColor = RouteActionGradient.paleBlueForeground
        configuration.background.image = RouteActionGradient.paleBlueImage
        configuration.background.imageContentMode = .scaleToFill
        configuration.background.cornerRadius = 15
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        button.configuration = configuration
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func setupDriveRouteSelectionTopBar() {
        routeSelectionTopBar.effect = nil
        routeSelectionTopBar.backgroundColor = .clear
        routeSelectionTopBar.layer.cornerRadius = 16
        routeSelectionTopBar.layer.cornerCurve = .continuous
        routeSelectionTopBar.clipsToBounds = true
        routeSelectionTopBar.layer.borderWidth = 0
        routeSelectionTopBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(routeSelectionTopBar)

        var backConfiguration = UIButton.Configuration.plain()
        backConfiguration.image = UIImage(systemName: "chevron.left")
        backConfiguration.baseForegroundColor = RouteActionGradient.paleBlueForeground
        backConfiguration.background.backgroundColor = UIColor.white.withAlphaComponent(0.76)
        backConfiguration.background.cornerRadius = 22
        backConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        routeSelectionBackButton.configuration = backConfiguration
        routeSelectionBackButton.layer.cornerRadius = 22
        routeSelectionBackButton.layer.cornerCurve = .continuous
        routeSelectionBackButton.layer.borderWidth = 0.8
        routeSelectionBackButton.layer.borderColor = UIColor.white.withAlphaComponent(0.72).cgColor
        routeSelectionBackButton.accessibilityLabel = "返回"
        routeSelectionBackButton.addTarget(self, action: #selector(tapClose), for: .touchUpInside)
        routeSelectionBackButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(routeSelectionBackButton)

        routeSelectionTopTitleLabel.text = "驾车导航"
        routeSelectionTopTitleLabel.textColor = .label
        routeSelectionTopTitleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        routeSelectionTopTitleLabel.textAlignment = .center
        routeSelectionTopTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let contentView = routeSelectionTopBar.contentView
        contentView.addSubview(routeSelectionTopTitleLabel)

        NSLayoutConstraint.activate([
            routeSelectionTopBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            routeSelectionTopBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            routeSelectionTopBar.widthAnchor.constraint(equalToConstant: 156),
            routeSelectionTopBar.heightAnchor.constraint(equalToConstant: 44),

            routeSelectionBackButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            routeSelectionBackButton.centerYAnchor.constraint(equalTo: routeSelectionTopBar.centerYAnchor),
            routeSelectionBackButton.widthAnchor.constraint(equalToConstant: 44),
            routeSelectionBackButton.heightAnchor.constraint(equalToConstant: 44),

            routeSelectionTopTitleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            routeSelectionTopTitleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            routeSelectionTopTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
            routeSelectionTopTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16)
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
        navigationScaleBarView.isHidden = true
        navigationScaleBarView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigationScaleBarView)
        setupRouteNoticeToast()

        NSLayoutConstraint.activate([
            brandOverlayView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            brandOverlayView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -65),
            brandOverlayView.heightAnchor.constraint(equalToConstant: 28),

            navigationScaleBarView.leadingAnchor.constraint(equalTo: brandOverlayView.leadingAnchor),
            navigationScaleBarView.bottomAnchor.constraint(equalTo: brandOverlayView.topAnchor, constant: -50),
            navigationScaleBarView.widthAnchor.constraint(equalToConstant: 112),
            navigationScaleBarView.heightAnchor.constraint(equalToConstant: 32),

            stack.leadingAnchor.constraint(equalTo: brandOverlayView.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: brandOverlayView.trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: brandOverlayView.centerYAnchor),

            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor)
        ])
    }

    private func scheduleScaleBarRefresh() {
        scaleBarRefreshTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateNavigationScaleBar()
        }
        scaleBarRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        DispatchQueue.main.async { [weak self] in
            self?.updateNavigationScaleBar()
        }
    }

    private func setNavigationScaleBarVisible(_ isVisible: Bool) {
        navigationScaleBarView.isHidden = !isVisible
        guard isVisible else { return }
        view.bringSubviewToFront(navigationScaleBarView)
        view.bringSubviewToFront(brandOverlayView)
        updateNavigationScaleBar()
    }

    /// 使用导航地图当前缩放级别与实时纬度，计算横向 96pt 所代表的地表距离。
    /// 导航 SDK 自动缩放或用户切换全览时，由定时刷新同步更新显示。
    private func updateNavigationScaleBar() {
        guard !navigationScaleBarView.isHidden,
              let zoomLevel = currentNavigationMapZoomLevel,
              zoomLevel.isFinite,
              zoomLevel > 0 else { return }

        let maximumWidth: CGFloat = 96
        let latitude = min(max(currentNavigationLatitude, -85), 85)
        let latitudeRadians = latitude * .pi / 180
        let earthCircumference = 40_075_016.686
        let metersPerPoint = cos(latitudeRadians) * earthCircumference /
            (256 * pow(2, Double(zoomLevel)))
        let maximumDistance = metersPerPoint * Double(maximumWidth)
        guard maximumDistance.isFinite, maximumDistance > 0 else { return }

        let distance = niceNavigationScaleDistance(notExceeding: maximumDistance)
        let lineWidth = maximumWidth * CGFloat(distance / maximumDistance)
        navigationScaleBarView.update(distanceMeters: distance, lineWidth: lineWidth)
    }

    private var currentNavigationMapZoomLevel: CGFloat? {
        #if canImport(AMapNaviKit)
        switch mode {
        case .drive, .truck: return driveView?.mapZoomLevel
        case .walk: return walkView?.mapZoomLevel
        case .ride: return rideView?.mapZoomLevel
        }
        #else
        return nil
        #endif
    }

    private func niceNavigationScaleDistance(notExceeding distance: CLLocationDistance) -> CLLocationDistance {
        let magnitude = pow(10.0, floor(log10(distance)))
        let normalized = distance / magnitude
        let step: Double
        if normalized >= 5 {
            step = 5
        } else if normalized >= 2 {
            step = 2
        } else {
            step = 1
        }
        return step * magnitude
    }

    #if canImport(AMapNaviKit)
    private func updateNavigationLatitude(from location: AMapNaviLocation?) {
        guard let latitude = location?.coordinate.latitude,
              latitude.isFinite,
              (-90...90).contains(latitude) else { return }
        currentNavigationLatitude = Double(latitude)
        updateNavigationScaleBar()
    }
    #endif

    private func setupRouteNoticeToast() {
        routeNoticeToastView.layer.cornerRadius = 12
        routeNoticeToastView.layer.cornerCurve = .continuous
        routeNoticeToastView.clipsToBounds = true
        routeNoticeToastView.translatesAutoresizingMaskIntoConstraints = false
        routeNoticeToastView.alpha = 0
        routeNoticeToastView.isHidden = true

        let backgroundImageView = UIImageView(image: RouteActionGradient.image)
        backgroundImageView.contentMode = .scaleToFill
        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        routeNoticeToastTitleLabel.textColor = .white
        routeNoticeToastTitleLabel.font = .systemFont(ofSize: 15.5, weight: .semibold)
        routeNoticeToastTitleLabel.numberOfLines = 1

        routeNoticeToastDetailLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        routeNoticeToastDetailLabel.font = .systemFont(ofSize: 12.5, weight: .regular)
        routeNoticeToastDetailLabel.numberOfLines = 1
        routeNoticeToastDetailLabel.lineBreakMode = .byTruncatingTail

        let textStack = UIStackView(arrangedSubviews: [routeNoticeToastTitleLabel, routeNoticeToastDetailLabel])
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false

        routeNoticeToastView.addSubview(backgroundImageView)
        routeNoticeToastView.addSubview(iconView)
        routeNoticeToastView.addSubview(textStack)
        view.addSubview(routeNoticeToastView)

        NSLayoutConstraint.activate([
            routeNoticeToastView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            routeNoticeToastView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            routeNoticeToastView.bottomAnchor.constraint(equalTo: brandOverlayView.topAnchor, constant: -8),
            routeNoticeToastView.heightAnchor.constraint(greaterThanOrEqualToConstant: 62),

            backgroundImageView.leadingAnchor.constraint(equalTo: routeNoticeToastView.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: routeNoticeToastView.trailingAnchor),
            backgroundImageView.topAnchor.constraint(equalTo: routeNoticeToastView.topAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: routeNoticeToastView.bottomAnchor),

            iconView.leadingAnchor.constraint(equalTo: routeNoticeToastView.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: routeNoticeToastView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: routeNoticeToastView.trailingAnchor, constant: -14),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: routeNoticeToastView.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: routeNoticeToastView.bottomAnchor, constant: -10),
            textStack.centerYAnchor.constraint(equalTo: routeNoticeToastView.centerYAnchor)
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
        routeOptionControls.forEach { $0.refreshAppearance() }

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
            manager.setMultipleRouteNaviMode(true)
            let accepted = manager.calculateDriveRoute(
                withStart: [startPoint],
                end: [endPoint],
                wayPoints: nil,
                drivingStrategy: .drivingStrategyMultipleDefault
            )
            if !accepted, isRefreshingDriveRoutes {
                finishDriveRouteRefresh()
                showMessage("路线刷新失败，请稍后重试。")
            }

        case .truck:
            let manager = AMapNaviDriveManager.sharedInstance()
            manager.setMultipleRouteNaviMode(false)
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

    private func makeDriveRouteOptions(from manager: AMapNaviDriveManager) -> [DriveRouteOption] {
        var routeIDs = manager.naviRouteIDs?.map(\.intValue) ?? []
        let routes = manager.naviRoutes ?? [:]
        if routeIDs.isEmpty {
            routeIDs = routes.keys.map(\.intValue).sorted()
        }
        if routeIDs.isEmpty, manager.naviRoute != nil {
            routeIDs = [manager.naviRouteID]
        }

        var seenRouteIDs = Set<Int>()
        let uniqueRouteIDs = routeIDs.filter { seenRouteIDs.insert($0).inserted }
        return uniqueRouteIDs.prefix(3).enumerated().compactMap { index, routeID in
            let route = routes[NSNumber(value: routeID)] ?? (routeID == manager.naviRouteID ? manager.naviRoute : nil)
            guard let route else { return nil }
            let routeLabel = route.routeLabels?
                .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty && $0.count <= 10 })
            let fallbackTitle = index == 0 ? "推荐路线" : "备选路线 \(index)"
            return DriveRouteOption(
                routeID: routeID,
                title: routeLabel ?? fallbackTitle,
                duration: route.routeTime,
                distance: route.routeLength,
                tollCost: route.routeTollCost
            )
        }
    }

    private func beginDriveNavigation(using manager: AMapNaviDriveManager) {
        guard !hasStartedNavigation else { return }

        let started: Bool
        if DriveNavigationMode.isSimulationEnabled {
            manager.setEmulatorNaviSpeed(120)
            started = manager.startEmulatorNavi()
        } else {
            started = manager.startGPSNavi()
        }
        guard started else {
            showMessage("导航启动失败，请重新选择路线后再试。")
            return
        }

        hasStartedNavigation = true
        NavigationRuntimeState.shared.markNavigating()
        setNavigationScaleBarVisible(true)
        hideDriveRouteSelectionPanel(animated: true)
        routeSelectionTopBar.isHidden = true
        routeSelectionBackButton.isHidden = true
        titleLabel.isHidden = false
        closeButton.isHidden = false
        driveView?.showUIElements = true
        driveView?.showRoute = true
        driveView?.showBackupRoute = true
        driveView?.showMode = AMapNaviDriveViewShowMode(rawValue: 1)!
        prewarmCurrentDriveRoute(using: manager)
    }

    private func showDriveRouteOverview() {
        guard mode == .drive, let driveView else { return }
        driveView.showUIElements = false
        driveView.showRoute = true
        driveView.showBackupRoute = true
        driveView.showMode = AMapNaviDriveViewShowMode(rawValue: 2)!

        updateDriveRouteOverviewVisualRange()
    }

    private func updateDriveRouteOverviewVisualRange() {
        // 路线图层与地图相机并非同一帧更新，下一帧及短延迟后各校正一次可视范围。
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.driveView?.showMode.rawValue == 2 else { return }
            self.driveView?.updateRoutePolylineInTheVisualRangeWhenTheShowModeIsOverview()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self,
                  self.driveView?.showMode.rawValue == 2 else { return }
            self.driveView?.updateRoutePolylineInTheVisualRangeWhenTheShowModeIsOverview()
        }
    }

    private func showRouteNoticeToast(title: String, detail: String) {
        guard hasStartedNavigation else { return }
        routeNoticeToastDismissWorkItem?.cancel()
        routeNoticeToastTitleLabel.text = title
        routeNoticeToastDetailLabel.text = detail
        routeNoticeToastView.accessibilityLabel = "\(title)，\(detail)"
        view.bringSubviewToFront(routeNoticeToastView)
        view.bringSubviewToFront(brandOverlayView)

        routeNoticeToastView.isHidden = false
        routeNoticeToastView.transform = CGAffineTransform(translationX: 0, y: 12)
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.routeNoticeToastView.alpha = 1
            self.routeNoticeToastView.transform = .identity
        }

        let dismissWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            UIView.animate(
                withDuration: 0.2,
                animations: {
                    self.routeNoticeToastView.alpha = 0
                    self.routeNoticeToastView.transform = CGAffineTransform(translationX: 0, y: 8)
                },
                completion: { _ in
                    self.routeNoticeToastView.isHidden = true
                    self.routeNoticeToastView.transform = .identity
                }
            )
        }
        routeNoticeToastDismissWorkItem = dismissWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: dismissWorkItem)
    }

    #if canImport(AMapNaviKit)
    private func routeSummary(for routeID: Int) -> String {
        let manager = AMapNaviDriveManager.sharedInstance()
        let route = manager.naviRoutes?[NSNumber(value: routeID)] ?? manager.naviRoute
        var seenNames = Set<String>()
        let roadNames = route?.guideGroups.compactMap { group -> String? in
            guard let name = group.groupName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  seenNames.insert(name).inserted else { return nil }
            return name
        } ?? []
        let summary = roadNames.prefix(3).joined(separator: "–")
        return summary.isEmpty ? "已切换至更合适的路线" : "途经 \(summary)"
    }
    #endif

    @objc private func refreshDriveRoutes() {
        guard mode == .drive, !hasStartedNavigation, !isRefreshingDriveRoutes else { return }
        isRefreshingDriveRoutes = true
        updateDriveRouteRefreshAppearance()
        routeOptionControls.forEach { $0.isEnabled = false }
        confirmRouteButton.isEnabled = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        startCalculateRoute()
    }

    @objc private func locateDriveRoute() {
        guard mode == .drive, !hasStartedNavigation else { return }
        showDriveRouteOverview()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func finishDriveRouteRefresh() {
        guard isRefreshingDriveRoutes else { return }
        isRefreshingDriveRoutes = false
        updateDriveRouteRefreshAppearance()
        routeOptionControls.forEach { $0.isEnabled = true }
        confirmRouteButton.isEnabled = selectedDriveRouteID != nil
    }

    private func updateDriveRouteRefreshAppearance() {
        guard var configuration = routeRefreshButton.configuration else { return }
        configuration.showsActivityIndicator = isRefreshingDriveRoutes
        configuration.image = isRefreshingDriveRoutes ? nil : UIImage(systemName: "arrow.clockwise")
        routeRefreshButton.configuration = configuration
        routeRefreshButton.isEnabled = !isRefreshingDriveRoutes
        routeLocateButton.isEnabled = !isRefreshingDriveRoutes
    }

    private func prewarmCurrentDriveRoute(using manager: AMapNaviDriveManager) {
        // 立即复制为纯 Swift 字符串数组，不把高德 SDK 的桥接集合带入异步任务。
        let routeTexts: [String] = manager.naviRoute?.guideGroups.flatMap { group in
            group.guideSegments.compactMap { $0.detailedDescription }
        } ?? []
        TTSController.shared.prewarmDriveVoice(routeTexts)
    }
    #endif

    private func showDriveRouteSelectionPanel(options: [DriveRouteOption], selectedRouteID: Int?) {
        guard !options.isEmpty else { return }
        driveRouteOptions = options
        self.selectedDriveRouteID = options.contains(where: { $0.routeID == selectedRouteID })
            ? selectedRouteID
            : options.first?.routeID
        routeOptionsStack.arrangedSubviews.forEach { view in
            routeOptionsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        routeOptionControls = options.enumerated().map { index, option in
            let control = DriveRouteOptionControl()
            control.tag = index
            control.configure(with: option)
            control.isSelected = option.routeID == self.selectedDriveRouteID
            control.addTarget(self, action: #selector(selectDriveRoute(_:)), for: .touchUpInside)
            routeOptionsStack.addArrangedSubview(control)
            return control
        }

        confirmRouteButton.isEnabled = self.selectedDriveRouteID != nil
        confirmRouteButton.accessibilityHint = "使用当前选中的路线开始驾车导航"
        brandOverlayView.isHidden = true
        view.bringSubviewToFront(routeSelectionPanel)
        view.bringSubviewToFront(routeSelectionTopBar)
        view.bringSubviewToFront(routeSelectionBackButton)

        guard routeSelectionPanel.isHidden else { return }
        routeSelectionPanel.isHidden = false
        routeSelectionPanel.transform = CGAffineTransform(translationX: 0, y: 32)
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.3,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.routeSelectionPanel.alpha = 1
            self.routeSelectionPanel.transform = .identity
        }
    }

    @objc private func selectDriveRoute(_ sender: UIControl) {
        guard sender.tag >= 0, sender.tag < driveRouteOptions.count else { return }
        let option = driveRouteOptions[sender.tag]

        #if canImport(AMapNaviKit)
        let manager = AMapNaviDriveManager.sharedInstance()
        let selected = manager.naviRouteID == option.routeID || manager.selectNaviRoute(withRouteID: option.routeID)
        guard selected else {
            showMessage("路线切换失败，请重新选择。")
            return
        }
        showDriveRouteOverview()
        #endif

        selectedDriveRouteID = option.routeID
        routeOptionControls.enumerated().forEach { index, control in
            control.isSelected = driveRouteOptions[index].routeID == option.routeID
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @objc private func confirmSelectedDriveRoute() {
        guard mode == .drive, let selectedDriveRouteID else { return }

        #if canImport(AMapNaviKit)
        let manager = AMapNaviDriveManager.sharedInstance()
        let selected = manager.naviRouteID == selectedDriveRouteID ||
            manager.selectNaviRoute(withRouteID: selectedDriveRouteID)
        guard selected else {
            showMessage("所选路线暂时不可用，请选择其他路线。")
            return
        }
        beginDriveNavigation(using: manager)
        #endif
    }

    private func hideDriveRouteSelectionPanel(animated: Bool) {
        guard !routeSelectionPanel.isHidden else {
            brandOverlayView.isHidden = false
            return
        }
        let completion: (Bool) -> Void = { _ in
            self.routeSelectionPanel.isHidden = true
            self.routeSelectionPanel.transform = .identity
            self.brandOverlayView.isHidden = false
        }
        guard animated else {
            routeSelectionPanel.alpha = 0
            completion(true)
            return
        }
        UIView.animate(
            withDuration: 0.2,
            animations: {
                self.routeSelectionPanel.alpha = 0
                self.routeSelectionPanel.transform = CGAffineTransform(translationX: 0, y: 24)
            },
            completion: completion
        )
    }

    private func showInitialRouteFailureAlert() {
        guard !isExitingNavigation, presentedViewController == nil else { return }
        hideDriveRouteSelectionPanel(animated: false)
        let alert = UIAlertController(
            title: "路线规划失败",
            message: "暂时无法获取可用路线，请检查网络后重试。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "返回", style: .cancel) { [weak self] _ in
            self?.tapClose()
        })
        alert.addAction(UIAlertAction(title: "重新规划", style: .default) { [weak self] _ in
            self?.startCalculateRoute()
        })
        present(alert, animated: true)
    }

    // MARK: - 退出导航 (对应 Android onNaviCancel -> finish())

    @objc private func tapClose() {
        guard !isExitingNavigation else { return }
        let shouldPlayDriveEnd = hasStartedNavigation && (mode == .drive || mode == .truck)
        isExitingNavigation = true
        preservesClosingSpeechOnDeinit = shouldPlayDriveEnd
        NavigationRuntimeState.shared.clearNavigating()
        // 先清空当前转向播报，并阻断 stopNavi 产生的“退出导航”短提示。
        TTSController.shared.stop()
        #if canImport(AMapNaviKit)
        switch mode {
        case .drive, .truck:
            let manager = AMapNaviDriveManager.sharedInstance()
            manager.delegate = nil
            manager.stopNavi()
            manager.setMultipleRouteNaviMode(false)
        case .walk:
            let manager = AMapNaviWalkManager.sharedInstance()
            manager.delegate = nil
            manager.stopNavi()
        case .ride:
            let manager = AMapNaviRideManager.sharedInstance()
            manager.delegate = nil
            manager.stopNavi()
        }
        #endif

        if let nav = navigationController, nav.viewControllers.first !== self {
            nav.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
        if shouldPlayDriveEnd {
            // 等退出动画基本完成再播放；deinit 不再停止这段独立收尾语。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                TTSController.shared.speakDriveClosing()
            }
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
        if mode == .drive || mode == .truck {
            let prefix = DriveNavigationMode.isSimulationEnabled ? "✓ " : ""
            alert.addAction(UIAlertAction(title: "\(prefix)模拟驾车导航（补充语音包）", style: .default) { [weak self] _ in
                self?.toggleDriveSimulation()
            })
        }
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

    private func toggleDriveSimulation() {
        let willEnable = !DriveNavigationMode.isSimulationEnabled
        DriveNavigationMode.isSimulationEnabled = willEnable

        #if canImport(AMapNaviKit)
        let manager = AMapNaviDriveManager.sharedInstance()
        manager.stopNavi()
        let started: Bool
        if willEnable {
            // 高德 SDK 最大模拟速度，便于快速跑完整条路线并补充语音包。
            manager.setEmulatorNaviSpeed(120)
            started = manager.startEmulatorNavi()
        } else {
            started = manager.startGPSNavi()
        }
        if !started {
            DriveNavigationMode.isSimulationEnabled.toggle()
            showMessage(willEnable ? "模拟导航启动失败，请重新规划路线后再试。" : "GPS 导航启动失败，请重新规划路线后再试。")
            return
        }
        #endif

        let message = willEnable
            ? "已开启模拟驾车导航。路线播报会自动补充当前个人语音包，真实导航不会等待生成。"
            : "已关闭模拟驾车导航，已切换为 GPS 实时导航。"
        showMessage(message)
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    private func showNavigationVoiceSettings() {
        let tts = TTSController.shared
        let voices = tts.availableChineseVoices
        let personalVoicePacks = tts.availablePersonalVoicePacks
        let alert = UIAlertController(
            title: "播报声音",
            message: voices.isEmpty
                ? "\n当前设备没有可用的中文系统语音"
                : "\n选择导航语音角色，个人语音包显示在系统声音下方",
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

        if !personalVoicePacks.isEmpty {
            let section = UIAlertAction(title: "— 个人语音包 —", style: .default)
            section.isEnabled = false
            alert.addAction(section)

            personalVoicePacks.forEach { pack in
                let prefix = pack.id == tts.currentPersonalVoicePackID ? "✓ " : ""
                alert.addAction(UIAlertAction(title: "\(prefix)\(pack.name)", style: .default) { _ in
                    guard tts.selectPersonalVoicePack(id: pack.id) else { return }
                    if let phrase = PersonalVoicePackStore.shared.generatedPhrases(for: pack.id).first {
                        tts.speakDrive(phrase.text)
                    }
                })
            }
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

    fileprivate func speakNaviText(_ text: String, usesPersonalVoice: Bool = false) {
        guard !isExitingNavigation else { return }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        // The navigation SDK may send service/quota errors through the same
        // callback as turn instructions. They are not actionable while driving
        // and must not be shown or spoken as navigation guidance.
        guard !isRouteServiceFailureMessage(trimmedText) else { return }

        // 驾车导航允许在导航过程中即时切换系统声音与个人语音包。
        // SDK 回调标记只表示该导航类型支持个人语音，实际是否启用以当前语音包为准。
        let shouldUsePersonalVoice = usesPersonalVoice && TTSController.shared.isUsingPersonalVoice

        switch NaviBroadcastMode.current {
        case .muted:
            TTSController.shared.stop()
        case .detailed:
            shouldUsePersonalVoice ? TTSController.shared.speakDrive(trimmedText) : TTSController.shared.speak(trimmedText)
        case .standard:
            guard !isLowPriorityBroadcast(trimmedText) else {
                if shouldUsePersonalVoice { TTSController.shared.collectDriveVoiceForCache(trimmedText) }
                return
            }
            shouldUsePersonalVoice ? TTSController.shared.speakDrive(trimmedText) : TTSController.shared.speak(trimmedText)
        case .concise:
            guard isKeyBroadcast(trimmedText) else {
                if shouldUsePersonalVoice { TTSController.shared.collectDriveVoiceForCache(trimmedText) }
                return
            }
            shouldUsePersonalVoice ? TTSController.shared.speakDrive(trimmedText) : TTSController.shared.speak(trimmedText)
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
        finishDriveRouteRefresh()

        // 导航中重新算路只更新语音缓存，不再次打断用户弹出路线选择。
        if hasStartedNavigation {
            prewarmCurrentDriveRoute(using: driveManager)
            return
        }

        if mode == .drive {
            let options = makeDriveRouteOptions(from: driveManager)
            guard !options.isEmpty else {
                // 极少数情况下 SDK 只返回当前路线而没有路线集合，继续原来的直接导航流程。
                beginDriveNavigation(using: driveManager)
                return
            }
            showDriveRouteSelectionPanel(
                options: options,
                selectedRouteID: driveManager.naviRouteID
            )
            showDriveRouteOverview()
            return
        }

        // 货车仍为单路线，算路成功后直接开始导航。
        beginDriveNavigation(using: driveManager)
    }

    func driveManager(_ driveManager: AMapNaviDriveManager, onCalculateRouteFailure error: Error) {
        finishDriveRouteRefresh()
        if !hasStartedNavigation {
            NavigationRuntimeState.shared.clearNavigating()
            showInitialRouteFailureAlert()
        }
    }

    func driveManager(_ driveManager: AMapNaviDriveManager, postRouteNotification notifyData: AMapNaviRouteNotifyData) {
        guard mode == .drive, hasStartedNavigation else { return }

        let detailCandidates = [notifyData.subTitle, notifyData.reason, notifyData.roadName]
        let detail = detailCandidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "请按导航提示继续行驶"

        switch notifyData.type.rawValue {
        case 1:
            showRouteNoticeToast(title: "前方限行提示", detail: detail)
        case 2:
            showRouteNoticeToast(title: "前方禁行提示", detail: detail)
        case 3:
            showRouteNoticeToast(title: "前方道路封闭", detail: detail)
        case 4:
            showRouteNoticeToast(title: "前方拥堵提示", detail: detail)
        case 5:
            showRouteNoticeToast(title: "路线调度提示", detail: detail)
        case 20:
            guard Date().timeIntervalSince(lastRouteSwitchNoticeDate) > 1 else { return }
            lastRouteSwitchNoticeDate = Date()
            showRouteNoticeToast(
                title: notifyData.success ? "已为您切换新路线" : "路线切换未成功",
                detail: notifyData.success ? routeSummary(for: driveManager.naviRouteID) : detail
            )
        case 21:
            showRouteNoticeToast(title: "卫星定位信号较弱", detail: detail)
        default:
            break
        }
    }

    /// 语音播报文本回调 (对应 Android TTSController.onGetNavigationText)
    func driveManager(_ driveManager: AMapNaviDriveManager, playNaviSound soundString: String, soundStringType: AMapNaviSoundType) {
        speakNaviText(soundString, usesPersonalVoice: true)
    }

    func driveManagerIsNaviSoundPlaying(_ driveManager: AMapNaviDriveManager) -> Bool {
        TTSController.shared.isSpeaking
    }

    func driveManager(onArrivedDestination driveManager: AMapNaviDriveManager) {
        NavigationRuntimeState.shared.clearNavigating()
        speakNaviText(L10n.t("navi.arrived"), usesPersonalVoice: true)
    }
}

extension NaviViewController: AMapNaviDriveViewDelegate {
    func driveViewCloseButtonClicked(_ driveView: AMapNaviDriveView) {
        tapClose()
    }

    func driveViewMoreButtonClicked(_ driveView: AMapNaviDriveView) {
        showNaviSettings()
    }

    func driveView(_ driveView: AMapNaviDriveView, didChange showMode: AMapNaviDriveViewShowMode) {
        guard mode == .drive, showMode.rawValue == 2 else { return }

        // 导航中的“全览”需要重新打开备选路线。备选路线可直接在地图上点击切换，
        // 高德 SDK 会通过 onRouteHighlightChange 回调同步当前主路线。
        driveView.showRoute = true
        driveView.showBackupRoute = true
        updateDriveRouteOverviewVisualRange()
    }

    func driveViewEdgePadding(_ driveView: AMapNaviDriveView) -> UIEdgeInsets {
        guard mode == .drive, !hasStartedNavigation else { return .zero }
        return UIEdgeInsets(top: 88, left: 20, bottom: 250, right: 20)
    }

    func driveView(_ driveView: AMapNaviDriveView, onRouteHighlightChange pathId: Int, triggerType: Int) {
        if hasStartedNavigation {
            guard Date().timeIntervalSince(lastRouteSwitchNoticeDate) > 1 else { return }
            lastRouteSwitchNoticeDate = Date()
            showRouteNoticeToast(title: "已为您切换新路线", detail: routeSummary(for: pathId))
            return
        }

        guard mode == .drive,
              driveRouteOptions.contains(where: { $0.routeID == pathId }) else { return }
        selectedDriveRouteID = pathId
        routeOptionControls.enumerated().forEach { index, control in
            control.isSelected = driveRouteOptions[index].routeID == pathId
        }
    }
}

// MARK: - 步行导航 (AMapNaviWalkManagerDelegate)

extension NaviViewController: AMapNaviWalkManagerDelegate {

    func walkManager(onCalculateRouteSuccess walkManager: AMapNaviWalkManager) {
        hasStartedNavigation = true
        NavigationRuntimeState.shared.markNavigating()
        setNavigationScaleBarVisible(true)
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
        setNavigationScaleBarVisible(true)
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

// MARK: - 导航位置数据（用于动态比例尺纬度修正）

extension NaviViewController: AMapNaviDriveDataRepresentable {
    func driveManager(_ driveManager: AMapNaviDriveManager, update naviLocation: AMapNaviLocation?) {
        updateNavigationLatitude(from: naviLocation)
    }
}

extension NaviViewController: AMapNaviWalkDataRepresentable {
    func walkManager(_ walkManager: AMapNaviWalkManager, update naviLocation: AMapNaviLocation?) {
        updateNavigationLatitude(from: naviLocation)
    }
}

extension NaviViewController: AMapNaviRideDataRepresentable {
    func rideManager(_ rideManager: AMapNaviRideManager, update naviLocation: AMapNaviLocation?) {
        updateNavigationLatitude(from: naviLocation)
    }
}

#endif

/// 导航地图白色比例尺。样式与首页一致，两端竖线与横线对应标签中的实际距离。
private final class NavigationMapScaleBarView: UIView {
    private let distanceLabel = UILabel()
    private let scaleLayer = CAShapeLayer()
    private var currentLineWidth: CGFloat = 96

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        distanceLabel.textColor = .white
        distanceLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        distanceLabel.textAlignment = .center
        distanceLabel.layer.shadowColor = UIColor.black.cgColor
        distanceLabel.layer.shadowOpacity = 0.9
        distanceLabel.layer.shadowRadius = 2
        distanceLabel.layer.shadowOffset = .zero
        addSubview(distanceLabel)

        scaleLayer.strokeColor = UIColor.white.cgColor
        scaleLayer.fillColor = UIColor.clear.cgColor
        scaleLayer.lineWidth = 2
        scaleLayer.lineCap = .square
        scaleLayer.shadowColor = UIColor.black.cgColor
        scaleLayer.shadowOpacity = 0.85
        scaleLayer.shadowRadius = 1.5
        scaleLayer.shadowOffset = .zero
        layer.addSublayer(scaleLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(distanceMeters: CLLocationDistance, lineWidth: CGFloat) {
        distanceLabel.text = Self.distanceText(distanceMeters)
        currentLineWidth = min(96, max(24, lineWidth))
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        distanceLabel.frame = CGRect(x: 0, y: 0, width: currentLineWidth, height: 18)

        let originX: CGFloat = 0
        let baselineY = bounds.height - 4
        let path = UIBezierPath()
        path.move(to: CGPoint(x: originX, y: baselineY - 6))
        path.addLine(to: CGPoint(x: originX, y: baselineY))
        path.addLine(to: CGPoint(x: originX + currentLineWidth, y: baselineY))
        path.addLine(to: CGPoint(x: originX + currentLineWidth, y: baselineY - 6))
        scaleLayer.path = path.cgPath
    }

    private static func distanceText(_ meters: CLLocationDistance) -> String {
        if meters >= 1_000 {
            let kilometers = meters / 1_000
            return kilometers.rounded() == kilometers
                ? String(format: "%.0f km", kilometers)
                : String(format: "%.1f km", kilometers)
        }
        if meters >= 1 {
            return String(format: "%.0f m", meters)
        }
        return String(format: "%.1f m", meters)
    }
}
