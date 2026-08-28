import UIKit
import SwiftUI

final class CloudPanoramaListViewController: UIViewController {
    private enum Entry: Hashable {
        case scenic(CloudScenicItem)
        case ad(Int)
    }

    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let searchBar = UISearchBar()
    private let categoryScrollView = UIScrollView()
    private let categoryStackView = UIStackView()
    private let emptyLabel = UILabel()
    private var categoryButtons: [UIButton] = []
    private var selectedCategory = CloudScenicItem.categories[0]
    private var entries: [Entry] = []

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 24, right: 16)
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .systemGroupedBackground
        view.keyboardDismissMode = .onDrag
        view.dataSource = self
        view.delegate = self
        view.register(CloudScenicCell.self, forCellWithReuseIdentifier: CloudScenicCell.reuseIdentifier)
        view.register(CloudDrawAdCell.self, forCellWithReuseIdentifier: CloudDrawAdCell.reuseIdentifier)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.t("world.source_title")
        view.backgroundColor = .systemGroupedBackground
        setupHeader()
        setupCollectionView()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accountStateDidChange),
            name: .naviAccountStateDidChange,
            object: nil
        )
        applyFilter()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("CloudPanoramaListViewController")
        applyFilter()
        NaviAccountSession.shared.refreshMembershipSilently()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ReviewPromptManager.requestSystemReviewIfEligibleAfterCloudScenes(in: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("CloudPanoramaListViewController")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        applyHeaderTitleStyle()
    }

    private func setupHeader() {
        var backConfig = UIButton.Configuration.filled()
        backConfig.image = UIImage(systemName: "chevron.left")
        backConfig.baseForegroundColor = .white
        backConfig.baseBackgroundColor = UIColor.black.withAlphaComponent(0.16)
        backConfig.cornerStyle = .capsule
        backConfig.contentInsets = .zero
        backButton.configuration = backConfig
        backButton.accessibilityLabel = L10n.t("common.back")
        backButton.addTarget(self, action: #selector(tapBack), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = L10n.t("world.cloud_panorama_title")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        searchBar.placeholder = L10n.t("cloud.search_placeholder")
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.translatesAutoresizingMaskIntoConstraints = false

        categoryScrollView.showsHorizontalScrollIndicator = false
        categoryScrollView.translatesAutoresizingMaskIntoConstraints = false
        categoryStackView.axis = .horizontal
        categoryStackView.spacing = 8
        categoryStackView.alignment = .center
        categoryStackView.translatesAutoresizingMaskIntoConstraints = false

        CloudScenicItem.categories.enumerated().forEach { index, category in
            let button = UIButton(type: .system)
            button.setTitle(localizedCategory(category), for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            button.contentEdgeInsets = UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
            button.layer.cornerRadius = 15
            button.tag = index
            button.addTarget(self, action: #selector(tapCategory(_:)), for: .touchUpInside)
            categoryButtons.append(button)
            categoryStackView.addArrangedSubview(button)
        }
        updateCategoryButtons()

        [backButton, titleLabel, searchBar, categoryScrollView].forEach(view.addSubview)
        categoryScrollView.addSubview(categoryStackView)
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            backButton.widthAnchor.constraint(equalToConstant: 42),
            backButton.heightAnchor.constraint(equalToConstant: 42),
            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -62),
            searchBar.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 2),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            categoryScrollView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            categoryScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            categoryScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            categoryScrollView.heightAnchor.constraint(equalToConstant: 44),
            categoryStackView.topAnchor.constraint(equalTo: categoryScrollView.topAnchor, constant: 5),
            categoryStackView.bottomAnchor.constraint(equalTo: categoryScrollView.bottomAnchor, constant: -5),
            categoryStackView.leadingAnchor.constraint(equalTo: categoryScrollView.leadingAnchor, constant: 16),
            categoryStackView.trailingAnchor.constraint(equalTo: categoryScrollView.trailingAnchor, constant: -16),
            categoryStackView.heightAnchor.constraint(equalTo: categoryScrollView.heightAnchor, constant: -10)
        ])
        applyHeaderTitleStyle()
    }

    private func applyHeaderTitleStyle() {
        titleLabel.textColor = traitCollection.userInterfaceStyle == .dark ? .black : .label
    }

    private func setupCollectionView() {
        emptyLabel.text = L10n.t("cloud.empty")
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: categoryScrollView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor)
        ])
    }

    private func applyFilter() {
        let query = searchBar.text ?? ""
        let favorites = CloudPanoramaFavorites.ids
        let filtered = CloudScenicItem.all.filter { item in
            guard item.matches(query) else { return false }
            switch selectedCategory {
            case "全部": return true
            case "收藏": return favorites.contains(item.id)
            default: return item.category == selectedCategory
            }
        }

        entries.removeAll(keepingCapacity: true)
        for (index, item) in filtered.enumerated() {
            entries.append(.scenic(item))
            if (index + 1).isMultiple(of: 6) { entries.append(.ad(index / 6)) }
        }
        emptyLabel.isHidden = !filtered.isEmpty
        collectionView.isHidden = filtered.isEmpty
        collectionView.reloadData()
    }

    private func localizedCategory(_ category: String) -> String {
        guard Locale.current.languageCode != "zh" else { return category }
        return ["全部": "All", "收藏": "Favorites", "海外": "Overseas", "北京": "Beijing",
                "上海": "Shanghai", "深圳": "Shenzhen", "云南": "Yunnan", "山海": "Nature",
                "湖泊": "Lakes", "文博": "Culture", "5A": "5A"][category] ?? category
    }

    private func updateCategoryButtons() {
        for (index, button) in categoryButtons.enumerated() {
            let selected = CloudScenicItem.categories[index] == selectedCategory
            button.backgroundColor = selected ? (UIColor(named: "ThemeBlue") ?? .systemBlue) : .secondarySystemBackground
            button.setTitleColor(selected ? .white : .label, for: .normal)
        }
    }

    @objc private func tapBack() { navigationController?.popViewController(animated: true) }

    @objc private func accountStateDidChange() {
        collectionView.reloadData()
    }

    /// 供列表点击和通知直达共用，避免通过其他入口绕过 VIP 权限。
    func presentVIPUpgradePrompt(for item: CloudScenicItem) {
        guard item.requiresVIP,
              !NaviAccountSession.shared.isVipActive,
              presentedViewController == nil else { return }

        weak var promptController: UIViewController?
        let prompt = CloudVIPUpgradeSheet(
            scenicTitle: item.title,
            onUpgrade: { [weak self] in
                promptController?.dismiss(animated: true) { [weak self] in
                    guard let self, self.presentedViewController == nil else { return }
                    NaviMembershipPresentation.show(from: self)
                }
            },
            onCancel: {
                promptController?.dismiss(animated: true)
            }
        )
        let controller = UIHostingController(rootView: prompt)
        promptController = controller
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            if #available(iOS 16.0, *) {
                let identifier = UISheetPresentationController.Detent.Identifier("cloud.vip.upgrade")
                sheet.detents = [
                    .custom(identifier: identifier) { context in
                        min(390, context.maximumDetentValue)
                    }
                ]
            } else {
                sheet.detents = [.medium()]
            }
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        present(controller, animated: true)
    }

    @objc private func tapCategory(_ sender: UIButton) {
        selectedCategory = CloudScenicItem.categories[sender.tag]
        updateCategoryButtons()
        applyFilter()
        collectionView.setContentOffset(.zero, animated: false)
    }
}

extension CloudPanoramaListViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { applyFilter() }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }
}

extension CloudPanoramaListViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { entries.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch entries[indexPath.item] {
        case .scenic(let item):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CloudScenicCell.reuseIdentifier, for: indexPath) as! CloudScenicCell
            cell.configure(
                item: item,
                isFavorite: CloudPanoramaFavorites.contains(item.id),
                requiresVIP: item.requiresVIP,
                isLocked: item.requiresVIP && !NaviAccountSession.shared.isVipActive
            ) { [weak self] in
                CloudPanoramaFavorites.toggle(item.id)
                self?.applyFilter()
            }
            return cell
        case .ad(let slot):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CloudDrawAdCell.reuseIdentifier, for: indexPath) as! CloudDrawAdCell
            cell.load(slot: slot, rootViewController: self) { [weak self] in
                self?.removeAdEntry(slot: slot)
            }
            return cell
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard case .scenic(let item) = entries[indexPath.item] else { return }
        if item.requiresVIP && !NaviAccountSession.shared.isVipActive {
            presentVIPUpgradePrompt(for: item)
            return
        }
        navigationController?.pushViewController(CloudPanoramaWebViewController(title: item.title, url: item.url), animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        // reloadData may ask for item sizes before the first layout pass, when
        // collectionView.bounds.width is still zero. Never return a negative size.
        let availableWidth = max(collectionView.bounds.width, view.bounds.width, UIScreen.main.bounds.width)
        let width = max(1, floor((availableWidth - 44) / 2))
        switch entries[indexPath.item] {
        case .scenic: return CGSize(width: width, height: width * 0.72 + 46)
        case .ad: return CGSize(width: max(1, availableWidth - 32), height: 190)
        }
    }

    private func removeAdEntry(slot: Int) {
        guard let index = entries.firstIndex(of: .ad(slot)) else { return }
        entries.remove(at: index)
        collectionView.performBatchUpdates {
            collectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
        }
    }
}

private final class CloudScenicCell: UICollectionViewCell {
    static let reuseIdentifier = "CloudScenicCell"
    private let imageView = UIImageView()
    private let vipBadge = CloudVIPBadgeView()
    private let titleLabel = UILabel()
    private let favoriteButton = UIButton(type: .system)
    private var favoriteAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.layer.cornerRadius = 9
        contentView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        vipBadge.isHidden = true
        vipBadge.isUserInteractionEnabled = false
        vipBadge.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        favoriteButton.tintColor = .systemRed
        favoriteButton.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        favoriteButton.layer.cornerRadius = 16
        favoriteButton.addTarget(self, action: #selector(toggleFavorite), for: .touchUpInside)
        favoriteButton.translatesAutoresizingMaskIntoConstraints = false
        [imageView, titleLabel, vipBadge, favoriteButton].forEach(contentView.addSubview)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.72),
            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 7),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            vipBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            vipBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 7),
            vipBadge.widthAnchor.constraint(equalToConstant: 54),
            vipBadge.heightAnchor.constraint(equalToConstant: 24),
            favoriteButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            favoriteButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -7),
            favoriteButton.widthAnchor.constraint(equalToConstant: 32),
            favoriteButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        vipBadge.isHidden = true
        favoriteAction = nil
    }

    func configure(
        item: CloudScenicItem,
        isFavorite: Bool,
        requiresVIP: Bool,
        isLocked: Bool,
        favoriteAction: @escaping () -> Void
    ) {
        titleLabel.text = item.title
        if let url = item.coverImageURL { imageView.image = UIImage(contentsOfFile: url.path) }
        if imageView.image == nil { imageView.image = UIImage(systemName: "photo.on.rectangle.angled") }
        vipBadge.isHidden = !requiresVIP
        favoriteButton.setImage(UIImage(systemName: isFavorite ? "heart.fill" : "heart"), for: .normal)
        isAccessibilityElement = true
        accessibilityLabel = isLocked ? "\(item.title)，VIP 专享景区" : item.title
        accessibilityTraits = .button
        self.favoriteAction = favoriteAction
    }

    @objc private func toggleFavorite() { favoriteAction?() }
}

private final class CloudVIPBadgeView: UIView {
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradientLayer.colors = [
            UIColor(red: 0.23, green: 0.12, blue: 0.05, alpha: 1).cgColor,
            UIColor(red: 0.42, green: 0.23, blue: 0.12, alpha: 1).cgColor,
            UIColor(red: 0.23, green: 0.12, blue: 0.05, alpha: 1).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.insertSublayer(gradientLayer, at: 0)
        layer.cornerRadius = 7
        layer.cornerCurve = .continuous
        layer.masksToBounds = true

        let icon = UIImageView(image: UIImage(systemName: "crown.fill"))
        icon.tintColor = UIColor(red: 0.96, green: 0.84, blue: 0.62, alpha: 1)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "VIP"
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = UIColor(red: 0.96, green: 0.84, blue: 0.62, alpha: 1)
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 12),
            icon.heightAnchor.constraint(equalToConstant: 12),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -5)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
}

/// 与 AgentClaw 额度不足提示保持一致的紧凑会员引导弹窗。
private struct CloudVIPUpgradeSheet: View {
    let scenicTitle: String
    let onUpgrade: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("VIP 专享景区")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(red: 0.10, green: 0.10, blue: 0.18))

            Text("“\(scenicTitle)”需要开通会员后观看")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            benefitRow(
                icon: "view.3d",
                title: "720° 全景景区",
                freeText: "普通用户：前 12 个",
                vipText: "VIP：全部解锁"
            )
            benefitRow(
                icon: "crown.fill",
                title: "会员专享体验",
                freeText: "免费景区畅看",
                vipText: "专享景区畅看"
            )

            Button(action: onUpgrade) {
                Text("立即开通会员")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.40, green: 0.31, blue: 0.96),
                                Color(red: 0.61, green: 0.48, blue: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)

            Button("稍后再说", action: onCancel)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }

    private func benefitRow(icon: String, title: String, freeText: String, vipText: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(red: 0.40, green: 0.31, blue: 0.96))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.86))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.10, green: 0.10, blue: 0.18))
                HStack {
                    Text(freeText)
                    Spacer(minLength: 8)
                    Text(vipText)
                        .foregroundStyle(Color(red: 0.40, green: 0.31, blue: 0.96))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(red: 0.96, green: 0.95, blue: 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private final class CloudDrawAdCell: UICollectionViewCell {
    static let reuseIdentifier = "CloudDrawAdCell"
    private let activity = UIActivityIndicatorView(style: .medium)
    private var loader: PangleDrawFeedAdLoader?
    private var loadedSlot: Int?
    private var failureAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true
        activity.color = .white
        activity.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(activity)
        NSLayoutConstraint.activate([
            activity.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        loader?.cancel()
        loader = nil
        loadedSlot = nil
        failureAction = nil
        contentView.backgroundColor = .black
        contentView.subviews.filter { $0 !== activity }.forEach { $0.removeFromSuperview() }
    }

    func load(slot: Int, rootViewController: UIViewController, onFailure: @escaping () -> Void) {
        guard loadedSlot != slot else { return }
        prepareForReuse()
        loadedSlot = slot
        failureAction = onFailure
        activity.startAnimating()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.loadedSlot == slot, self.activity.isAnimating else { return }
            self.loader?.cancel()
            self.finishWithFailure()
        }
        // Wait until UIKit has attached the reused cell and the presenting
        // controller to a window before touching GroMore's native view objects.
        DispatchQueue.main.async { [weak self, weak rootViewController] in
            guard let self, let rootViewController,
                  self.loadedSlot == slot,
                  self.window != nil,
                  rootViewController.viewIfLoaded?.window != nil else { return }
            let loader = PangleDrawFeedAdLoader()
            self.loader = loader
            loader.load(rootViewController: rootViewController) { [weak self] adView in
                guard let self, self.loadedSlot == slot else { return }
                self.activity.stopAnimating()
                guard let adView else {
                    self.finishWithFailure()
                    return
                }
                adView.frame = self.contentView.bounds
                adView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                self.contentView.addSubview(adView)
            }
        }
    }

    private func finishWithFailure() {
        activity.stopAnimating()
        let failureAction = failureAction
        self.failureAction = nil
        failureAction?()
    }
}
