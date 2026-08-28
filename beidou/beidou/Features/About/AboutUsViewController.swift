//
//  AboutUsViewController.swift
//  beidou
//
//  将协议、隐私、反馈和评分入口从侧边栏集中到独立页面。
//

import UIKit

final class AboutUsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private enum Item: CaseIterable {
        case serviceAgreement
        case vipAgreement
        case autoRenewAgreement
        case privacyPolicy
        case feedback
        case rating
        case clearCache

        var title: String {
            switch self {
            case .serviceAgreement: return L10n.t("menu.service_agreement")
            case .vipAgreement: return L10n.t("menu.vip_agreement")
            case .autoRenewAgreement: return L10n.t("menu.auto_renew_agreement")
            case .privacyPolicy: return L10n.t("menu.privacy_policy")
            case .feedback: return L10n.t("menu.feedback")
            case .rating: return L10n.t("menu.rating")
            case .clearCache: return L10n.t("menu.clear_cache")
            }
        }

        var iconName: String {
            switch self {
            case .serviceAgreement: return "doc.text"
            case .vipAgreement: return "crown"
            case .autoRenewAgreement: return "arrow.triangle.2.circlepath"
            case .privacyPolicy: return "hand.raised"
            case .feedback: return "envelope"
            case .rating: return "star"
            case .clearCache: return "trash"
            }
        }
    }

    private let items = Item.allCases
    private let reuseIdentifier = "AboutUsItemCell"
    private let topBar = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let pageBackgroundColor = UIColor(red: 0.965, green: 0.972, blue: 0.985, alpha: 1)

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.t("menu.about_us")
        overrideUserInterfaceStyle = .light
        view.backgroundColor = pageBackgroundColor
        setupTopBar()
        setupTableView()
        setupAppHeader()
        setupFooter()
    }

    private func setupTopBar() {
        topBar.backgroundColor = pageBackgroundColor
        topBar.translatesAutoresizingMaskIntoConstraints = false

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

        titleLabel.text = L10n.t("menu.about_us")
        titleLabel.font = .systemFont(ofSize: 19, weight: .bold)
        titleLabel.textColor = UIColor(red: 0.10, green: 0.12, blue: 0.17, alpha: 1)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(topBar)
        topBar.addSubview(backButton)
        topBar.addSubview(titleLabel)
        topBar.addSubview(separator)
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 58),

            backButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            backButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 42),
            backButton.heightAnchor.constraint(equalToConstant: 42),

            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: topBar.trailingAnchor, constant: -60),

            separator.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 50
        tableView.backgroundColor = pageBackgroundColor
        tableView.separatorColor = UIColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 1)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 58, bottom: 0, right: 18)
        tableView.showsVerticalScrollIndicator = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupAppHeader() {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 180))

        let iconView = UIImageView(
            image: UIImage(named: "AppLogo")
                ?? UIImage(named: "AppIcon")
                ?? UIImage(systemName: "location.north.circle.fill")
        )
        iconView.contentMode = .scaleAspectFit
        iconView.layer.cornerRadius = 17
        iconView.layer.cornerCurve = .continuous
        iconView.clipsToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let appNameLabel = UILabel()
        appNameLabel.text = Constants.appName
        appNameLabel.font = .systemFont(ofSize: 17, weight: .regular)
        appNameLabel.textColor = UIColor(red: 0.10, green: 0.12, blue: 0.17, alpha: 1)
        appNameLabel.textAlignment = .center
        appNameLabel.translatesAutoresizingMaskIntoConstraints = false

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let versionLabel = UILabel()
        versionLabel.text = String(format: L10n.t("about.version_format"), version)
        versionLabel.font = .systemFont(ofSize: 14)
        versionLabel.textColor = UIColor(red: 0.43, green: 0.46, blue: 0.53, alpha: 1)
        versionLabel.textAlignment = .center
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(iconView)
        header.addSubview(appNameLabel)
        header.addSubview(versionLabel)
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: header.topAnchor, constant: 24),
            iconView.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 68),
            iconView.heightAnchor.constraint(equalToConstant: 68),

            appNameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),
            appNameLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            appNameLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),

            versionLabel.topAnchor.constraint(equalTo: appNameLabel.bottomAnchor, constant: 6),
            versionLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor)
        ])
        tableView.tableHeaderView = header
    }

    private func setupFooter() {
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 116))

        let taglineLabel = UILabel()
        taglineLabel.text = L10n.t("about.tagline")
        taglineLabel.font = .systemFont(ofSize: 13)
        taglineLabel.textColor = UIColor(red: 0.46, green: 0.49, blue: 0.56, alpha: 1)
        taglineLabel.textAlignment = .center
        taglineLabel.translatesAutoresizingMaskIntoConstraints = false

        let year = Calendar.current.component(.year, from: Date())
        let copyrightLabel = UILabel()
        copyrightLabel.text = String(format: L10n.t("about.copyright_format"), year)
        copyrightLabel.font = .systemFont(ofSize: 12)
        copyrightLabel.textColor = UIColor(red: 0.56, green: 0.58, blue: 0.64, alpha: 1)
        copyrightLabel.textAlignment = .center
        copyrightLabel.translatesAutoresizingMaskIntoConstraints = false

        footer.addSubview(taglineLabel)
        footer.addSubview(copyrightLabel)
        NSLayoutConstraint.activate([
            taglineLabel.topAnchor.constraint(equalTo: footer.topAnchor, constant: 27),
            taglineLabel.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 20),
            taglineLabel.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -20),

            copyrightLabel.topAnchor.constraint(equalTo: taglineLabel.bottomAnchor, constant: 8),
            copyrightLabel.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 20),
            copyrightLabel.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -20)
        ])
        tableView.tableFooterView = footer
    }

    @objc private func tapBack() {
        if let navigationController,
           navigationController.viewControllers.first !== self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier)
            ?? UITableViewCell(style: .default, reuseIdentifier: reuseIdentifier)
        let item = items[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = item.title
        content.textProperties.font = .systemFont(ofSize: 14, weight: .regular)
        content.textProperties.color = UIColor(red: 0.15, green: 0.17, blue: 0.22, alpha: 1)
        content.image = UIImage(systemName: item.iconName)
        content.imageProperties.tintColor = UIColor(red: 0.32, green: 0.35, blue: 0.94, alpha: 1)
        content.imageProperties.maximumSize = CGSize(width: 20, height: 20)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        cell.backgroundColor = .white
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch items[indexPath.row] {
        case .serviceAgreement:
            navigationController?.pushViewController(
                WebViewController(
                    title: L10n.t("legal.service_agreement"),
                    content: .localText(resourceName: "user_agreement"),
                    showsPageHeader: true
                ),
                animated: true
            )
        case .vipAgreement:
            navigationController?.pushViewController(
                WebViewController(
                    title: L10n.t("menu.vip_agreement"),
                    content: .localText(resourceName: "vip_agreement"),
                    showsPageHeader: true
                ),
                animated: true
            )
        case .autoRenewAgreement:
            navigationController?.pushViewController(
                WebViewController(
                    title: L10n.t("menu.auto_renew_agreement"),
                    content: .localText(resourceName: "auto_renew_agreement"),
                    showsPageHeader: true
                ),
                animated: true
            )
        case .privacyPolicy:
            navigationController?.pushViewController(
                WebViewController(
                    title: L10n.t("legal.privacy_policy"),
                    content: .remoteURL(Constants.privacyPolicyURL),
                    showsPageHeader: true
                ),
                animated: true
            )
        case .feedback:
            navigationController?.pushViewController(FeedbackViewController(), animated: true)
        case .rating:
            ReviewPromptManager.openAppStoreReviewPage()
        case .clearCache:
            presentClearCacheConfirmation()
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
}
