//
//  WorldPanoramaListViewController.swift
//  beidou
//
//  世界景点全景列表 + 搜索。
//

import UIKit
import WebKit

final class WorldPanoramaListViewController: UIViewController {

    private let searchBar = UISearchBar()
    private let categoryScrollView = UIScrollView()
    private let categoryStackView = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()
    private var selectedCategory = WorldPanoramaPlace.categories[0]
    private var places = WorldPanoramaPlace.places(in: WorldPanoramaPlace.categories[0])
    private var categoryButtons: [UIButton] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "国内热门景区全景"
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
        searchBar.placeholder = "搜索景区、城市或省份"
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
            button.setTitle(category, for: .normal)
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
        tableView.delegate = self
        tableView.dataSource = self
        tableView.keyboardDismissMode = .onDrag
        tableView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.text = "未找到相关景点"
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        tableView.backgroundView = emptyLabel

        view.addSubview(searchBar)
        view.addSubview(categoryScrollView)
        categoryScrollView.addSubview(categoryStackView)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
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
    }

    private func applySearch(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let categoryPlaces = WorldPanoramaPlace.places(in: selectedCategory)
        places = query.isEmpty ? categoryPlaces : categoryPlaces.filter { $0.searchText.contains(query) }
        emptyLabel.isHidden = !places.isEmpty
        tableView.reloadData()
    }

    @objc private func tapCategory(_ sender: UIButton) {
        selectedCategory = WorldPanoramaPlace.categories[sender.tag]
        updateCategoryButtons()
        applySearch(searchBar.text ?? "")
        tableView.setContentOffset(.zero, animated: false)
    }

    private func updateCategoryButtons() {
        for button in categoryButtons {
            let selected = button.currentTitle == selectedCategory
            button.backgroundColor = selected ? (UIColor(named: "ThemeBlue") ?? .systemBlue) : .secondarySystemGroupedBackground
            button.tintColor = selected ? .white : .label
        }
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
        places.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: WorldPanoramaPlaceCell.reuseIdentifier, for: indexPath) as! WorldPanoramaPlaceCell
        cell.configure(with: places[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(WorldPanoramaDetailViewController(place: places[indexPath.row]), animated: true)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        104
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
        subtitleLabel.text = "\(place.region) · \(place.country)"
        summaryLabel.text = place.summary
        placeImageView.setImage(named: place.imageName, fallbackURL: place.imageURL)
    }
}

private struct CloudPanoramaItem {
    let title: String
    let url: URL
    let imageName: String
}

final class CloudPanoramaListViewController: UIViewController {

    private let items: [CloudPanoramaItem] = [
        .init(title: "北京天坛", url: URL(string: "https://www.720yun.com/t/83vkcli708q?scene_id=59434172")!, imageName: "CloudPanorama01"),
        .init(title: "清华大学", url: URL(string: "https://www.720yun.com/vr/85c24wagung")!, imageName: "CloudPanorama02"),
        .init(title: "冰雪世界", url: URL(string: "https://www.720yun.com/vr/cccj5syntn3")!, imageName: "CloudPanorama03"),
        .init(title: "元宇宙艺术展", url: URL(string: "https://www.720yun.com/vr/28a2eqiuwcr")!, imageName: "CloudPanorama04"),
        .init(title: "秦始皇兵马俑", url: URL(string: "https://www.720yun.com/t/07cjrOhfzk4?scene_id=28286004")!, imageName: "CloudPanorama05"),
        .init(title: "深圳像素摄影", url: URL(string: "https://www.720yun.com/t/35vkcmdlpqb?scene_id=67060540")!, imageName: "CloudPanorama06"),
        .init(title: "拉萨布达拉宫", url: URL(string: "https://www.720yun.com/vr/c8027wsg9br")!, imageName: "CloudPanorama07"),
        .init(title: "贡嘎攀登", url: URL(string: "https://www.720yun.com/vr/792jkrtnev5")!, imageName: "CloudPanorama08"),
        .init(title: "北京故宫", url: URL(string: "https://www.720yun.com/t/942jOryutu8?scene_id=2095322")!, imageName: "CloudPanorama09"),
        .init(title: "泰国曼谷", url: URL(string: "https://www.720yun.com/t/74b22jidaen?scene_id=343404")!, imageName: "CloudPanorama10"),
        .init(title: "稻城亚丁", url: URL(string: "https://www.720yun.com/t/9a4j5gtkuy0?scene_id=11843262")!, imageName: "CloudPanorama11"),
        .init(title: "故宫雪景", url: URL(string: "https://www.720yun.com/t/df4jussOrw1?scene_id=60406967")!, imageName: "CloudPanorama12"),
        .init(title: "橘子洲头", url: URL(string: "https://www.720yun.com/t/f562c9zfuci?scene_id=1589907")!, imageName: "CloudPanorama13"),
        .init(title: "黄山风景区", url: URL(string: "https://www.720yun.com/t/favkte8w0fb?scene_id=69676267")!, imageName: "CloudPanorama14"),
        .init(title: "广州塔", url: URL(string: "https://www.720yun.com/t/35vkOm7lgqe?scene_id=56460523")!, imageName: "CloudPanorama15"),
        .init(title: "上海陆家嘴", url: URL(string: "https://www.720yun.com/t/59vkbyplr7q?scene_id=90167954")!, imageName: "CloudPanorama16"),
        .init(title: "邓紫棋演唱会场馆", url: URL(string: "https://www.720yun.com/vr/d12j57ekuv9")!, imageName: "CloudPanorama17"),
        .init(title: "全景看北京", url: URL(string: "https://www.720yun.com/t/942jOryutu8?scene_id=2095322")!, imageName: "CloudPanorama18")
    ]
    private let backButton = UIButton(type: .system)

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
        title = "720云"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(tapBack)
        )
        setupUI()
        setupBackButton()
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
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.52)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        backButton.configuration = configuration
        backButton.accessibilityLabel = "返回"
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
            CloudPanoramaWebViewController(title: item.title, url: item.url),
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
        titleLabel.text = item.title
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

private final class CloudPanoramaWebViewController: UIViewController {
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
    }

    private func setupWebView() {
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
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
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.52)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        backButton.configuration = configuration
        backButton.accessibilityLabel = "返回"
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
