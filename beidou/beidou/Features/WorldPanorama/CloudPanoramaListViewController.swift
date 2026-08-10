import UIKit

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
        applyFilter()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("CloudPanoramaListViewController")
        if selectedCategory == "收藏" { applyFilter() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ReviewPromptManager.requestSystemReviewIfEligibleAfterCloudScenes(in: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("CloudPanoramaListViewController")
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
            cell.configure(item: item, isFavorite: CloudPanoramaFavorites.contains(item.id)) { [weak self] in
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
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        favoriteButton.tintColor = .systemRed
        favoriteButton.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        favoriteButton.layer.cornerRadius = 16
        favoriteButton.addTarget(self, action: #selector(toggleFavorite), for: .touchUpInside)
        favoriteButton.translatesAutoresizingMaskIntoConstraints = false
        [imageView, titleLabel, favoriteButton].forEach(contentView.addSubview)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.72),
            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 7),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
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
        favoriteAction = nil
    }

    func configure(item: CloudScenicItem, isFavorite: Bool, favoriteAction: @escaping () -> Void) {
        titleLabel.text = item.title
        if let url = item.coverImageURL { imageView.image = UIImage(contentsOfFile: url.path) }
        if imageView.image == nil { imageView.image = UIImage(systemName: "photo.on.rectangle.angled") }
        favoriteButton.setImage(UIImage(systemName: isFavorite ? "heart.fill" : "heart"), for: .normal)
        self.favoriteAction = favoriteAction
    }

    @objc private func toggleFavorite() { favoriteAction?() }
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
