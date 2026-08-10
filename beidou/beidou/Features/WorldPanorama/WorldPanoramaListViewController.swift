//
//  WorldPanoramaListViewController.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  世界景点全景列表 + 搜索。
//

import UIKit
import WebKit

final class WorldPanoramaListViewController: UIViewController {

    private enum Row {
        case place(Int)
        case ad(Int)
    }

    fileprivate static let placeRowHeight: CGFloat = 104
    private static let adInterval = 4

    private let backButton = UIButton(type: .system)
    private let searchBar = UISearchBar()
    private let categoryScrollView = UIScrollView()
    private let categoryStackView = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()
    private var selectedCategory = WorldPanoramaPlace.categories[0]
    private var places = WorldPanoramaPlace.places(in: WorldPanoramaPlace.categories[0])
    private var rows: [Row] = []
    private var categoryButtons: [UIButton] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.t("world.title")
        view.backgroundColor = .systemGroupedBackground
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("WorldPanoramaListViewController")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("WorldPanoramaListViewController")
    }

    private func setupUI() {
        var backButtonConfiguration = UIButton.Configuration.filled()
        backButtonConfiguration.image = UIImage(systemName: "chevron.left")
        backButtonConfiguration.baseForegroundColor = .white
        backButtonConfiguration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.16)
        backButtonConfiguration.cornerStyle = .capsule
        backButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        backButton.configuration = backButtonConfiguration
        backButton.accessibilityLabel = L10n.t("common.back")
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(tapBack), for: .touchUpInside)

        searchBar.placeholder = L10n.t("world.search_placeholder")
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.translatesAutoresizingMaskIntoConstraints = false

        categoryScrollView.showsHorizontalScrollIndicator = false
        categoryScrollView.translatesAutoresizingMaskIntoConstraints = false

        categoryStackView.axis = .horizontal
        categoryStackView.spacing = 8
        categoryStackView.alignment = .center
        categoryStackView.translatesAutoresizingMaskIntoConstraints = false

        WorldPanoramaPlace.categories.enumerated().forEach { index, category in
            let button = UIButton(type: .system)
            button.setTitle(Self.localizedCategoryTitle(category), for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            button.layer.cornerRadius = 15
            button.contentEdgeInsets = UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
            button.tag = index
            button.addTarget(self, action: #selector(tapCategory(_:)), for: .touchUpInside)
            categoryButtons.append(button)
            categoryStackView.addArrangedSubview(button)
        }
        updateCategoryButtons()

        tableView.register(WorldPanoramaPlaceCell.self, forCellReuseIdentifier: WorldPanoramaPlaceCell.reuseIdentifier)
        tableView.register(WorldPanoramaDrawAdCell.self, forCellReuseIdentifier: WorldPanoramaDrawAdCell.reuseIdentifier)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.keyboardDismissMode = .onDrag
        tableView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.text = L10n.t("world.empty")
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        tableView.backgroundView = emptyLabel

        view.addSubview(backButton)
        view.addSubview(searchBar)
        view.addSubview(categoryScrollView)
        categoryScrollView.addSubview(categoryStackView)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            backButton.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            backButton.widthAnchor.constraint(equalToConstant: 42),
            backButton.heightAnchor.constraint(equalToConstant: 42),

            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            categoryScrollView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            categoryScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            categoryScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            categoryScrollView.heightAnchor.constraint(equalToConstant: 44),

            categoryStackView.topAnchor.constraint(equalTo: categoryScrollView.contentLayoutGuide.topAnchor),
            categoryStackView.leadingAnchor.constraint(equalTo: categoryScrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            categoryStackView.trailingAnchor.constraint(equalTo: categoryScrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            categoryStackView.bottomAnchor.constraint(equalTo: categoryScrollView.contentLayoutGuide.bottomAnchor),
            categoryStackView.heightAnchor.constraint(equalTo: categoryScrollView.frameLayoutGuide.heightAnchor),

            tableView.topAnchor.constraint(equalTo: categoryScrollView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        rebuildRows()
    }

    private func applySearch(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let categoryPlaces = WorldPanoramaPlace.places(in: selectedCategory)
        places = query.isEmpty ? categoryPlaces : categoryPlaces.filter { $0.searchText.contains(query) }
        emptyLabel.isHidden = !places.isEmpty
        rebuildRows()
    }

    private func rebuildRows() {
        rows.removeAll(keepingCapacity: true)
        for index in places.indices {
            rows.append(.place(index))
            if (index + 1).isMultiple(of: Self.adInterval) {
                rows.append(.ad(index / Self.adInterval))
            }
        }
        tableView.reloadData()
    }

    private func removeAdRow(slot: Int) {
        guard let row = rows.firstIndex(where: {
            if case .ad(let value) = $0 { return value == slot }
            return false
        }) else { return }
        rows.remove(at: row)
        tableView.performBatchUpdates {
            tableView.deleteRows(at: [IndexPath(row: row, section: 0)], with: .fade)
        }
    }

    private static func localizedCategoryTitle(_ category: String) -> String {
        switch category {
        case "热门": return L10n.t("world.category.popular")
        case "华北": return L10n.t("world.category.north")
        case "华东": return L10n.t("world.category.east")
        case "华中": return L10n.t("world.category.central")
        case "华南": return L10n.t("world.category.south")
        case "西南": return L10n.t("world.category.southwest")
        case "西北": return L10n.t("world.category.northwest")
        case "东北": return L10n.t("world.category.northeast")
        default: return category
        }
    }

    @objc private func tapCategory(_ sender: UIButton) {
        selectedCategory = WorldPanoramaPlace.categories[sender.tag]
        updateCategoryButtons()
        applySearch(searchBar.text ?? "")
        tableView.setContentOffset(.zero, animated: false)
    }

    private func updateCategoryButtons() {
        for (index, button) in categoryButtons.enumerated() {
            let selected = WorldPanoramaPlace.categories[index] == selectedCategory
            button.backgroundColor = selected ? (UIColor(named: "ThemeBlue") ?? .systemBlue) : .secondarySystemGroupedBackground
            button.tintColor = selected ? .white : .label
        }
    }

    @objc private func tapBack() {
        navigationController?.popViewController(animated: true)
    }
}

extension WorldPanoramaListViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        applySearch(searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        applySearch(searchBar.text ?? "")
    }
}

extension WorldPanoramaListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch rows[indexPath.row] {
        case .place(let placeIndex):
            let cell = tableView.dequeueReusableCell(withIdentifier: WorldPanoramaPlaceCell.reuseIdentifier, for: indexPath) as! WorldPanoramaPlaceCell
            cell.configure(with: places[placeIndex])
            return cell
        case .ad(let slot):
            let cell = tableView.dequeueReusableCell(withIdentifier: WorldPanoramaDrawAdCell.reuseIdentifier, for: indexPath) as! WorldPanoramaDrawAdCell
            cell.load(slot: slot, rootViewController: self) { [weak self] in
                self?.removeAdRow(slot: slot)
            }
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard case .place(let placeIndex) = rows[indexPath.row] else { return }
        navigationController?.pushViewController(WorldPanoramaDetailViewController(place: places[placeIndex]), animated: true)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch rows[indexPath.row] {
        case .place: return Self.placeRowHeight
        case .ad: return Self.placeRowHeight * 2
        }
    }
}

private final class WorldPanoramaDrawAdCell: UITableViewCell {
    static let reuseIdentifier = "WorldPanoramaDrawAdCell"

    private let activity = UIActivityIndicatorView(style: .medium)
    private var loader: PangleDrawFeedAdLoader?
    private var loadedSlot: Int?
    private var failureAction: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .black
        contentView.backgroundColor = .black
        contentView.clipsToBounds = true
        activity.color = .white
        activity.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(activity)
        NSLayoutConstraint.activate([
            activity.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        loader?.cancel()
        loader = nil
        loadedSlot = nil
        failureAction = nil
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

        DispatchQueue.main.async { [weak self, weak rootViewController] in
            guard let self, let rootViewController,
                  self.loadedSlot == slot,
                  self.window != nil,
                  rootViewController.viewIfLoaded?.window != nil else { return }
            let loader = PangleDrawFeedAdLoader()
            self.loader = loader
            let size = CGSize(
                width: max(self.contentView.bounds.width, UIScreen.main.bounds.width - 32),
                height: WorldPanoramaListViewController.placeRowHeight * 2
            )
            loader.load(rootViewController: rootViewController, adSize: size) { [weak self] adView in
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
        let action = failureAction
        failureAction = nil
        action?()
    }
}

private final class WorldPanoramaPlaceCell: UITableViewCell {
    static let reuseIdentifier = "WorldPanoramaPlaceCell"

    private let placeImageView = RemoteImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let summaryLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        accessoryType = .disclosureIndicator
        backgroundColor = .secondarySystemGroupedBackground

        placeImageView.clipsToBounds = true
        placeImageView.layer.cornerRadius = 8
        placeImageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .label

        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel

        summaryLabel.font = .systemFont(ofSize: 12)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, summaryLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(placeImageView)
        contentView.addSubview(textStack)
        NSLayoutConstraint.activate([
            placeImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            placeImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            placeImageView.widthAnchor.constraint(equalToConstant: 86),
            placeImageView.heightAnchor.constraint(equalToConstant: 70),

            textStack.leadingAnchor.constraint(equalTo: placeImageView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    func configure(with place: WorldPanoramaPlace) {
        titleLabel.text = place.name
        subtitleLabel.text = place.localizedCountry
        summaryLabel.text = place.localizedSummary
        placeImageView.setImage(named: place.imageName, fallbackURL: place.imageURL)
    }
}

#if false // Replaced by CloudPanoramaListViewController.swift and bundled 246-item data.
private struct CloudPanoramaItem {
    let title: String
    let url: URL
    let imageName: String

    var localizedTitle: String {
        guard Locale.current.languageCode != "zh" else { return title }
        switch title {
        case "北京天坛": return "Temple of Heaven"
        case "清华大学": return "Tsinghua University"
        case "冰雪世界": return "Ice and Snow World"
        case "元宇宙艺术展": return "Metaverse Art Exhibition"
        case "秦始皇兵马俑": return "Terracotta Warriors"
        case "深圳像素摄影": return "Shenzhen Pixel Photography"
        case "拉萨布达拉宫": return "Potala Palace"
        case "贡嘎攀登": return "Gongga Climb"
        case "北京故宫": return "Forbidden City"
        case "泰国曼谷": return "Bangkok, Thailand"
        case "稻城亚丁": return "Daocheng Yading"
        case "故宫雪景": return "Forbidden City in Snow"
        case "橘子洲头": return "Orange Isle"
        case "黄山风景区": return "Huangshan Scenic Area"
        case "广州塔": return "Canton Tower"
        case "上海陆家嘴": return "Shanghai Lujiazui"
        case "邓紫棋演唱会场馆": return "G.E.M. Concert Venue"
        case "全景看北京": return "Panoramic Beijing"
        default: return title
        }
    }
}

private final class LegacyCloudPanoramaListViewController: UIViewController {

    private let items: [CloudPanoramaItem] = [
        .init(title: "北京天坛", url: URL(string: "https://www.720yun.com/t/83vkcli708q?scene_id=59434172")!, imageName: "CloudPanorama01"),
        .init(title: "清华大学", url: URL(string: "https://www.720yun.com/vr/85c24wagung")!, imageName: "CloudPanorama02"),
        .init(title: "贡嘎攀登", url: URL(string: "https://www.720yun.com/vr/792jkrtnev5")!, imageName: "CloudPanorama08"),
        .init(title: "稻城亚丁", url: URL(string: "https://www.720yun.com/t/9a4j5gtkuy0?scene_id=11843262")!, imageName: "CloudPanorama11"),
        .init(title: "上海陆家嘴", url: URL(string: "https://www.720yun.com/t/59vkbyplr7q?scene_id=90167954")!, imageName: "CloudPanorama16"),
        .init(title: "黄山风景区", url: URL(string: "https://www.720yun.com/t/favkte8w0fb?scene_id=69676267")!, imageName: "CloudPanorama14"),
        .init(title: "橘子洲头", url: URL(string: "https://www.720yun.com/t/f562c9zfuci?scene_id=1589907")!, imageName: "CloudPanorama13"),
        .init(title: "全景看北京", url: URL(string: "https://www.720yun.com/t/942jOryutu8?scene_id=2095322")!, imageName: "CloudPanorama18"),
        .init(title: "冰雪世界", url: URL(string: "https://www.720yun.com/vr/cccj5syntn3")!, imageName: "CloudPanorama03"),
        .init(title: "元宇宙艺术展", url: URL(string: "https://www.720yun.com/vr/28a2eqiuwcr")!, imageName: "CloudPanorama04"),
        .init(title: "秦始皇兵马俑", url: URL(string: "https://www.720yun.com/t/07cjrOhfzk4?scene_id=28286004")!, imageName: "CloudPanorama05"),
        .init(title: "深圳像素摄影", url: URL(string: "https://www.720yun.com/t/35vkcmdlpqb?scene_id=67060540")!, imageName: "CloudPanorama06"),
        .init(title: "拉萨布达拉宫", url: URL(string: "https://www.720yun.com/vr/c8027wsg9br")!, imageName: "CloudPanorama07"),
        .init(title: "北京故宫", url: URL(string: "https://www.720yun.com/t/942jOryutu8?scene_id=2095322")!, imageName: "CloudPanorama09"),
        .init(title: "泰国曼谷", url: URL(string: "https://www.720yun.com/t/74b22jidaen?scene_id=343404")!, imageName: "CloudPanorama10"),
        .init(title: "故宫雪景", url: URL(string: "https://www.720yun.com/t/df4jussOrw1?scene_id=60406967")!, imageName: "CloudPanorama12"),
        .init(title: "广州塔", url: URL(string: "https://www.720yun.com/t/35vkOm7lgqe?scene_id=56460523")!, imageName: "CloudPanorama15"),
        .init(title: "邓紫棋演唱会场馆", url: URL(string: "https://www.720yun.com/vr/d12j57ekuv9")!, imageName: "CloudPanorama17")
    ]
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 62, left: 16, bottom: 24, right: 16)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.register(CloudPanoramaCell.self, forCellWithReuseIdentifier: CloudPanoramaCell.reuseIdentifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.t("world.source_title")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(tapBack)
        )
        setupUI()
        setupBackButton()
        setupTitleLabel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("CloudPanoramaListViewController")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("CloudPanoramaListViewController")
    }

    private func setupUI() {
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupBackButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "chevron.left")
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.16)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        backButton.configuration = configuration
        backButton.accessibilityLabel = L10n.t("common.back")
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(tapBack), for: .touchUpInside)

        view.addSubview(backButton)
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            backButton.widthAnchor.constraint(equalToConstant: 42),
            backButton.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    private func setupTitleLabel() {
        titleLabel.text = L10n.t("world.cloud_panorama_title")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12)
        ])
    }

    @objc private func tapBack() {
        navigationController?.popViewController(animated: true)
    }
}

extension CloudPanoramaListViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: CloudPanoramaCell.reuseIdentifier,
            for: indexPath
        ) as! CloudPanoramaCell
        cell.configure(with: items[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let item = items[indexPath.item]
        navigationController?.pushViewController(
            CloudPanoramaWebViewController(title: item.localizedTitle, url: item.url),
            animated: true
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let horizontalInset: CGFloat = 16 * 2
        let interitemSpacing: CGFloat = 12
        let width = floor((collectionView.bounds.width - horizontalInset - interitemSpacing) / 2)
        return CGSize(width: width, height: width * 0.78 + 44)
    }
}

private final class CloudPanoramaCell: UICollectionViewCell {
    static let reuseIdentifier = "CloudPanoramaCell"

    private let thumbnailView = CloudPanoramaThumbnailView(frame: .zero)
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailView.image = nil
        titleLabel.text = nil
    }

    private func setupUI() {
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(thumbnailView)
        contentView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnailView.heightAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.78),

            titleLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    func configure(with item: CloudPanoramaItem) {
        titleLabel.text = item.localizedTitle
        thumbnailView.image = UIImage(named: item.imageName) ?? UIImage(systemName: "photo.on.rectangle.angled")
    }
}

private final class CloudPanoramaThumbnailView: UIImageView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        contentMode = .scaleAspectFill
        backgroundColor = UIColor(named: "ThemeBlue")?.withAlphaComponent(0.12) ?? .secondarySystemBackground
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif

final class CloudPanoramaWebViewController: UIViewController {
    /// 与 Android CloudWebActivity 保持一致，只处理 720 云页面自身的广告组件。
    private static let disableAdPopupJavaScript = #"""
    (function() {
      function hideAdsWrapper(img) {
        var target = img, hops = 0;
        while (target && hops < 10) {
          if (typeof target.className === 'string' && /ads/i.test(target.className)) {
            target.style.display = 'none';
            return;
          }
          target = target.parentElement;
          hops++;
        }
        img.style.display = 'none';
      }
      function killAd() {
        var bannerImgs = document.querySelectorAll('img[src*="720static.com/home/"]');
        for (var i = 0; i < bannerImgs.length; i++) {
          hideAdsWrapper(bannerImgs[i]);
        }
        var candidates = document.querySelectorAll('[style]');
        for (var j = 0; j < candidates.length; j++) {
          var el = candidates[j];
          if (el.style && el.style.zIndex === '10000002') {
            el.style.display = 'none';
          }
        }
      }
      if (!window.__cloudAdKillerStarted) {
        window.__cloudAdKillerStarted = true;
        setInterval(killAd, 100);
      }
      killAd();
    })();
    """#

    private let pageTitle: String
    private let url: URL
    private let webView: WKWebView
    private let backButton = UIButton(type: .system)
    private var previousNavigationBarHidden = false

    init(title: String, url: URL) {
        self.pageTitle = title
        self.url = url

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.disableAdPopupJavaScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        self.webView = WKWebView(frame: .zero, configuration: configuration)

        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupWebView()
        setupBackButton()
        webView.load(URLRequest(url: url))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        previousNavigationBarHidden = navigationController?.isNavigationBarHidden ?? false
        navigationController?.setNavigationBarHidden(true, animated: animated)
        setNeedsStatusBarAppearanceUpdate()
        UMengAnalytics.shared.pageBegin(pageTitle)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(previousNavigationBarHidden, animated: animated)
        UMengAnalytics.shared.pageEnd(pageTitle)
        ReviewPromptManager.recordCloudPanoramaSceneViewed(url: url)
    }

    private func setupWebView() {
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupBackButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "chevron.left")
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.16)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        backButton.configuration = configuration
        backButton.accessibilityLabel = L10n.t("common.back")
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(tapBack), for: .touchUpInside)

        view.addSubview(backButton)
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            backButton.widthAnchor.constraint(equalToConstant: 42),
            backButton.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    @objc private func tapBack() {
        navigationController?.popViewController(animated: true)
    }
}

extension CloudPanoramaWebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(Self.disableAdPopupJavaScript, completionHandler: nil)
    }
}
