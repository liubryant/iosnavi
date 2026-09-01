//
//  MapPlaceDetailViewController.swift
//  beidou
//
//  首页百度地图 POI 详情卡片。地图点选后先展示基础信息，再异步补齐
//  地址、电话、营业时间、评分和图片；无高级图片权限时使用本地占位图。
//

import UIKit
import CoreLocation

struct MapPlaceDetail: Codable, Equatable {
    var uid: String?
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var category: String
    var phone: String
    var openingHours: String
    var rating: Double?
    var price: Double?
    var alias: String
    var contentTag: String
    var semanticDescription: String
    var photoURLs: [String]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var cacheKey: String {
        if let uid, !uid.isEmpty {
            return "uid:\(uid)"
        }
        return String(format: "coordinate:%.5f,%.5f", latitude, longitude)
    }

    var introduction: String {
        let normalizePunctuation: (String) -> String = { text in
            text
                .replacingOccurrences(of: ";", with: "，")
                .replacingOccurrences(of: "；", with: "，")
        }
        var components: [String] = []
        if !semanticDescription.isEmpty {
            components.append(normalizePunctuation(semanticDescription))
        }
        if !contentTag.isEmpty, !components.contains(contentTag) {
            components.append(normalizePunctuation(contentTag))
        }
        if !address.isEmpty,
           !components.contains(where: { $0.contains(address) }) {
            components.append("地点位于\(address)。")
        }
        if !category.isEmpty {
            components.append("地点类型：\(normalizePunctuation(category))。")
        }
        return components.isEmpty ? "已定位到该地点，可查看位置并规划导航路线。" : components.joined(separator: "\n")
    }
}

enum MapPlaceDetailCache {
    private struct Entry: Codable {
        let detail: MapPlaceDetail
        let savedAt: Date
    }

    private static let defaultsKey = "map.poi.detail.cache.v1"
    private static let lifetime: TimeInterval = 24 * 60 * 60
    private static let maximumCount = 60

    static func detail(for key: String, now: Date = Date()) -> MapPlaceDetail? {
        var entries = loadEntries()
        entries = entries.filter { now.timeIntervalSince($0.value.savedAt) < lifetime }
        saveEntries(entries)
        return entries[key]?.detail
    }

    static func save(_ detail: MapPlaceDetail, forKey key: String? = nil, now: Date = Date()) {
        var entries = loadEntries()
        entries[key ?? detail.cacheKey] = Entry(detail: detail, savedAt: now)
        if let key, key != detail.cacheKey {
            entries[detail.cacheKey] = Entry(detail: detail, savedAt: now)
        }
        if entries.count > maximumCount {
            let retainedKeys = entries
                .sorted { $0.value.savedAt > $1.value.savedAt }
                .prefix(maximumCount)
                .map(\.key)
            entries = entries.filter { retainedKeys.contains($0.key) }
        }
        saveEntries(entries)
    }

    private static func loadEntries() -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private static func saveEntries(_ entries: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

private final class MapPlaceRemoteImageView: UIImageView {
    private static let cache = NSCache<NSString, UIImage>()
    private var task: URLSessionDataTask?
    private var representedURL: String?

    deinit {
        task?.cancel()
    }

    func load(urlString: String) {
        task?.cancel()
        representedURL = urlString
        image = nil
        backgroundColor = .secondarySystemBackground

        let normalized = urlString.hasPrefix("http://")
            ? "https://" + urlString.dropFirst("http://".count)
            : urlString
        guard let url = URL(string: String(normalized)) else {
            showFallback()
            return
        }
        let cacheKey = url.absoluteString as NSString
        if let cached = Self.cache.object(forKey: cacheKey) {
            image = cached
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .returnCacheDataElseLoad
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self,
                  self.representedURL == urlString,
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data,
                  let image = UIImage(data: data) else {
                DispatchQueue.main.async { [weak self] in
                    guard self?.representedURL == urlString else { return }
                    self?.showFallback()
                }
                return
            }
            Self.cache.setObject(image, forKey: cacheKey)
            DispatchQueue.main.async { [weak self] in
                guard self?.representedURL == urlString else { return }
                self?.image = image
            }
        }
        task?.resume()
    }

    private func showFallback() {
        image = UIImage(systemName: "photo")
        tintColor = .tertiaryLabel
        contentMode = .center
    }
}

final class MapPlaceDetailViewController: UIViewController {
    var onNavigate: ((MapPlaceDetail) -> Void)?

    private var detail: MapPlaceDetail
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let contentStack = UIStackView()
    private let galleryScrollView = UIScrollView()
    private let galleryStack = UIStackView()
    private let pageControl = UIPageControl()
    private let titleLabel = UILabel()
    private let badgesStack = UIStackView()
    private let rowsStack = UIStackView()
    private let introductionLabel = UILabel()
    private let loadingStack = UIStackView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let loadingLabel = UILabel()
    private let navigateButton = MapPlaceGradientButton(type: .system)
    private var galleryPageWidth: CGFloat = 1

    init(detail: MapPlaceDetail, isLoading: Bool) {
        self.detail = detail
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        configureSheet()
        setLoading(isLoading, message: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupViews()
        applyDetail()
    }

    private func configureSheet() {
        guard let sheet = sheetPresentationController else { return }
        sheet.detents = [.medium(), .large()]
        sheet.selectedDetentIdentifier = .medium
        sheet.prefersGrabberVisible = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        sheet.preferredCornerRadius = 24
    }

    private func setupViews() {
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)

        galleryScrollView.isPagingEnabled = true
        galleryScrollView.showsHorizontalScrollIndicator = false
        galleryScrollView.delegate = self
        galleryScrollView.layer.cornerRadius = 18
        galleryScrollView.clipsToBounds = true
        galleryScrollView.translatesAutoresizingMaskIntoConstraints = false
        galleryStack.axis = .horizontal
        galleryStack.spacing = 0
        galleryStack.translatesAutoresizingMaskIntoConstraints = false
        galleryScrollView.addSubview(galleryStack)

        let galleryContainer = UIView()
        galleryContainer.translatesAutoresizingMaskIntoConstraints = false
        galleryContainer.addSubview(galleryScrollView)
        pageControl.currentPageIndicatorTintColor = .systemBlue
        pageControl.pageIndicatorTintColor = UIColor.systemGray4
        pageControl.hidesForSinglePage = true
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        galleryContainer.addSubview(pageControl)
        contentStack.addArrangedSubview(galleryContainer)

        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        contentStack.addArrangedSubview(titleLabel)

        badgesStack.axis = .vertical
        badgesStack.alignment = .fill
        badgesStack.spacing = 8
        contentStack.addArrangedSubview(badgesStack)

        rowsStack.axis = .vertical
        rowsStack.spacing = 0
        rowsStack.layer.cornerRadius = 16
        rowsStack.clipsToBounds = true
        rowsStack.backgroundColor = .secondarySystemBackground
        contentStack.addArrangedSubview(rowsStack)

        let introductionTitle = UILabel()
        introductionTitle.text = "地点介绍"
        introductionTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        introductionTitle.textColor = .label
        contentStack.addArrangedSubview(introductionTitle)

        introductionLabel.font = .systemFont(ofSize: 15)
        introductionLabel.textColor = .secondaryLabel
        introductionLabel.numberOfLines = 0
        introductionLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        contentStack.addArrangedSubview(introductionLabel)

        loadingStack.axis = .horizontal
        loadingStack.spacing = 10
        loadingStack.alignment = .center
        loadingStack.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        loadingStack.isLayoutMarginsRelativeArrangement = true
        loadingStack.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.08)
        loadingStack.layer.cornerRadius = 12
        loadingLabel.font = .systemFont(ofSize: 14)
        loadingLabel.textColor = .secondaryLabel
        loadingLabel.numberOfLines = 0
        loadingStack.addArrangedSubview(loadingIndicator)
        loadingStack.addArrangedSubview(loadingLabel)
        contentStack.addArrangedSubview(loadingStack)

        let sourceLabel = UILabel()
        sourceLabel.text = "地点信息由百度地图提供"
        sourceLabel.textAlignment = .center
        sourceLabel.font = .systemFont(ofSize: 11)
        sourceLabel.textColor = .tertiaryLabel
        contentStack.addArrangedSubview(sourceLabel)

        var navigateConfiguration = UIButton.Configuration.plain()
        var navigateTitle = AttributedString("到这里")
        navigateTitle.foregroundColor = .white
        navigateTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        navigateConfiguration.attributedTitle = navigateTitle
        navigateConfiguration.image = UIImage(systemName: "location.fill")
        navigateConfiguration.imagePadding = 8
        navigateConfiguration.baseForegroundColor = .white
        navigateConfiguration.imageColorTransformer = UIConfigurationColorTransformer { _ in .white }
        navigateConfiguration.background.backgroundColor = .clear
        navigateConfiguration.background.image = MapPlaceGradientButton.gradientBackgroundImage
        navigateConfiguration.background.imageContentMode = .scaleToFill
        navigateConfiguration.background.cornerRadius = 15
        navigateConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16)
        navigateButton.configuration = navigateConfiguration
        navigateButton.addTarget(self, action: #selector(tapNavigate), for: .touchUpInside)
        navigateButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigateButton)

        NSLayoutConstraint.activate([
            navigateButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            navigateButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            navigateButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            navigateButton.heightAnchor.constraint(equalToConstant: 52),

            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: navigateButton.topAnchor, constant: -8),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),

            galleryContainer.heightAnchor.constraint(equalToConstant: 220),
            galleryScrollView.topAnchor.constraint(equalTo: galleryContainer.topAnchor),
            galleryScrollView.leadingAnchor.constraint(equalTo: galleryContainer.leadingAnchor),
            galleryScrollView.trailingAnchor.constraint(equalTo: galleryContainer.trailingAnchor),
            galleryScrollView.bottomAnchor.constraint(equalTo: galleryContainer.bottomAnchor),
            galleryStack.topAnchor.constraint(equalTo: galleryScrollView.contentLayoutGuide.topAnchor),
            galleryStack.leadingAnchor.constraint(equalTo: galleryScrollView.contentLayoutGuide.leadingAnchor),
            galleryStack.trailingAnchor.constraint(equalTo: galleryScrollView.contentLayoutGuide.trailingAnchor),
            galleryStack.bottomAnchor.constraint(equalTo: galleryScrollView.contentLayoutGuide.bottomAnchor),
            galleryStack.heightAnchor.constraint(equalTo: galleryScrollView.frameLayoutGuide.heightAnchor),
            pageControl.centerXAnchor.constraint(equalTo: galleryContainer.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: galleryContainer.bottomAnchor, constant: -6)
        ])
    }

    func update(with detail: MapPlaceDetail, message: String? = nil) {
        self.detail = detail
        guard isViewLoaded else { return }
        applyDetail()
        setLoading(false, message: message)
    }

    func finishLoading(message: String) {
        guard isViewLoaded else { return }
        setLoading(false, message: message)
    }

    private func applyDetail() {
        titleLabel.text = detail.name
        introductionLabel.text = detail.introduction
        rebuildGallery()
        rebuildBadges()
        rebuildRows()
    }

    private func rebuildGallery() {
        galleryStack.arrangedSubviews.forEach {
            galleryStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let urls = Array(detail.photoURLs.prefix(8))
        pageControl.numberOfPages = max(urls.count, 1)
        pageControl.currentPage = 0
        galleryPageWidth = max(UIScreen.main.bounds.width - 40, 1)

        if urls.isEmpty {
            let placeholder = makeGalleryPlaceholder()
            galleryStack.addArrangedSubview(placeholder)
            placeholder.widthAnchor.constraint(equalTo: galleryScrollView.frameLayoutGuide.widthAnchor).isActive = true
            return
        }

        for url in urls {
            let imageView = MapPlaceRemoteImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.load(urlString: url)
            galleryStack.addArrangedSubview(imageView)
            imageView.widthAnchor.constraint(equalTo: galleryScrollView.frameLayoutGuide.widthAnchor).isActive = true
        }
    }

    private func makeGalleryPlaceholder() -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.10)
        let icon = UIImageView(image: UIImage(systemName: "mappin.and.ellipse"))
        icon.tintColor = .systemBlue
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .medium)
        icon.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = "暂无地点图片"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(icon)
        container.addSubview(label)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        ])
        return container
    }

    private func rebuildBadges() {
        badgesStack.arrangedSubviews.forEach {
            badgesStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        var badges: [(text: String, color: UIColor)] = []
        if let rating = detail.rating, rating > 0 {
            badges.append((String(format: "★ %.1f", rating), .systemOrange))
        }
        for category in categoryTags(from: detail.category) {
            badges.append((category, categoryColor(for: category)))
        }
        if let price = detail.price, price > 0 {
            badges.append((String(format: "人均 ¥%.0f", price), .systemPink))
        }

        let containerWidth = view.bounds.width > 100 ? view.bounds.width : UIScreen.main.bounds.width
        let maximumWidth = containerWidth - 40
        var row = makeBadgeRow()
        var rowWidth: CGFloat = 0
        for badge in badges {
            let label = makeBadge(text: badge.text, color: badge.color)
            let estimatedWidth = badge.text.size(withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold)]).width + 20
            if rowWidth > 0, rowWidth + 8 + estimatedWidth > maximumWidth {
                row.addArrangedSubview(UIView())
                badgesStack.addArrangedSubview(row)
                row = makeBadgeRow()
                rowWidth = 0
            }
            row.addArrangedSubview(label)
            rowWidth += (rowWidth == 0 ? 0 : 8) + estimatedWidth
        }
        if !row.arrangedSubviews.isEmpty {
            row.addArrangedSubview(UIView())
            badgesStack.addArrangedSubview(row)
        }
        badgesStack.isHidden = badges.isEmpty
    }

    private func makeBadgeRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        return row
    }

    private func categoryTags(from category: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",，;；/、|>·")
        var seen = Set<String>()
        return category
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func categoryColor(for category: String) -> UIColor {
        let rules: [(keywords: [String], color: UIColor)] = [
            (["公司", "企业", "商务", "写字楼"], .systemIndigo),
            (["园区", "产业园", "科技园", "工业园"], .systemTeal),
            (["景区", "旅游", "公园", "名胜", "展馆"], .systemGreen),
            (["餐饮", "美食", "餐厅", "咖啡", "茶"], .systemOrange),
            (["交通", "车站", "地铁", "机场", "停车"], .systemBlue),
            (["学校", "教育", "大学", "培训"], .systemPurple),
            (["医院", "医疗", "药店"], .systemRed),
            (["购物", "商场", "超市", "便利店"], .systemPink),
            (["酒店", "住宿", "民宿"], .systemBrown),
            (["住宅", "小区", "社区"], .systemCyan)
        ]
        if let match = rules.first(where: { rule in
            rule.keywords.contains(where: category.contains)
        }) {
            return match.color
        }
        let palette: [UIColor] = [.systemBlue, .systemIndigo, .systemTeal, .systemGreen, .systemOrange, .systemPurple]
        let index = category.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % palette.count }
        return palette[index]
    }

    private func makeBadge(text: String, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = "  \(text)  "
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = color
        label.backgroundColor = color.withAlphaComponent(0.10)
        label.layer.cornerRadius = 9
        label.clipsToBounds = true
        label.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return label
    }

    private func rebuildRows() {
        rowsStack.arrangedSubviews.forEach {
            rowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if !detail.address.isEmpty {
            addInfoRow(icon: "mappin.circle.fill", title: "地址", value: detail.address)
        }
        if !detail.openingHours.isEmpty {
            addInfoRow(icon: "clock.fill", title: "营业时间", value: detail.openingHours)
        }
        if !detail.phone.isEmpty {
            addInfoRow(icon: "phone.fill", title: "电话", value: detail.phone, action: #selector(tapPhone))
        }
        if !detail.alias.isEmpty, detail.alias != detail.name {
            addInfoRow(icon: "text.badge.checkmark", title: "别名", value: detail.alias)
        }
        if rowsStack.arrangedSubviews.isEmpty {
            let coordinateText = String(format: "%.6f, %.6f", detail.latitude, detail.longitude)
            addInfoRow(icon: "location.fill", title: "坐标", value: coordinateText)
        }
    }

    private func addInfoRow(icon: String, title: String, value: String, action: Selector? = nil) {
        if !rowsStack.arrangedSubviews.isEmpty {
            let separator = UIView()
            separator.backgroundColor = .separator
            separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
            rowsStack.addArrangedSubview(separator)
        }

        let row = UIControl()
        row.backgroundColor = .clear
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        if let action {
            row.addTarget(self, action: action, for: .touchUpInside)
        }

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(iconView)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(titleLabel)

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 15)
        valueLabel.textColor = action == nil ? .label : .systemBlue
        valueLabel.numberOfLines = 0
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: row.layoutMarginsGuide.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: row.layoutMarginsGuide.topAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: row.layoutMarginsGuide.trailingAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            valueLabel.trailingAnchor.constraint(equalTo: row.layoutMarginsGuide.trailingAnchor),
            valueLabel.bottomAnchor.constraint(equalTo: row.layoutMarginsGuide.bottomAnchor)
        ])
        rowsStack.addArrangedSubview(row)
    }

    private func setLoading(_ loading: Bool, message: String?) {
        let text = message ?? (loading ? "正在加载地点详细信息…" : "")
        loadingStack.isHidden = text.isEmpty
        loadingLabel.text = text
        if loading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }
    }

    @objc private func tapNavigate() {
        let selected = detail
        dismiss(animated: true) { [weak self] in
            self?.onNavigate?(selected)
        }
    }

    @objc private func tapPhone() {
        let number = detail.phone
            .components(separatedBy: CharacterSet(charactersIn: "0123456789+").inverted)
            .joined()
        guard !number.isEmpty,
              let url = URL(string: "tel:\(number)"),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}

extension MapPlaceDetailViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === galleryScrollView else { return }
        let width = max(galleryScrollView.bounds.width, galleryPageWidth, 1)
        pageControl.currentPage = Int(round(scrollView.contentOffset.x / width))
    }
}

private final class MapPlaceGradientButton: UIButton {
    private static let backgroundColors = [
        UIColor(red: 0.08, green: 0.58, blue: 1.0, alpha: 1).cgColor,
        UIColor(red: 0.12, green: 0.38, blue: 0.94, alpha: 1).cgColor,
        UIColor(red: 0.29, green: 0.31, blue: 0.90, alpha: 1).cgColor
    ]

    static let gradientBackgroundImage: UIImage = {
        let size = CGSize(width: 320, height: 58)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: backgroundColors as CFArray,
                locations: [0, 0.55, 1]
            ) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: size.height / 2),
                end: CGPoint(x: size.width, y: size.height / 2),
                options: []
            )
        }
        return image.resizableImage(
            withCapInsets: UIEdgeInsets(top: 20, left: 70, bottom: 20, right: 70),
            resizingMode: .stretch
        )
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupStyle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupStyle()
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.16) {
                self.alpha = self.isHighlighted ? 0.84 : 1
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.985, y: 0.985)
                    : .identity
            }
        }
    }

    private func setupStyle() {
        layer.cornerRadius = 15
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor(red: 0.05, green: 0.35, blue: 0.90, alpha: 1).cgColor
        layer.shadowOpacity = 0.24
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 6)
        tintColor = .white
    }
}
