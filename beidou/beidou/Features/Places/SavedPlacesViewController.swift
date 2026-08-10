//
//  SavedPlacesViewController.swift
//  beidou
//
//  常用地点管理。
//

import UIKit

final class SavedPlacesViewController: UIViewController {
    private let currentLocation: CurrentLocation?
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let stackView = UIStackView()
    private var placeButtons: [SavedPlaceKind: UIButton] = [:]

    init(currentLocation: CurrentLocation? = nil) {
        self.currentLocation = currentLocation
        super.init(nibName: nil, bundle: nil)
        title = L10n.t("places.title")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        setupHeader()
        setupContent()
        reloadPlaces()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadPlaces()
        UMengAnalytics.shared.pageBegin("SavedPlacesViewController")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("SavedPlacesViewController")
    }

    private func setupHeader() {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "chevron.left")
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.16)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        backButton.configuration = configuration
        backButton.accessibilityLabel = L10n.t("common.back")
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(tapBack), for: .touchUpInside)

        titleLabel.text = L10n.t("places.title")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(backButton)
        view.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            backButton.widthAnchor.constraint(equalToConstant: 42),
            backButton.heightAnchor.constraint(equalToConstant: 42),
            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -64)
        ])
    }

    private func setupContent() {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let hintLabel = UILabel()
        hintLabel.text = L10n.t("places.hint")
        hintLabel.font = .systemFont(ofSize: 14)
        hintLabel.textColor = .secondaryLabel
        hintLabel.numberOfLines = 0

        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.backgroundColor = .clear

        for (index, kind) in SavedPlaceKind.allCases.enumerated() {
            let button = makePlaceButton(kind)
            button.tag = index
            placeButtons[kind] = button
            stackView.addArrangedSubview(button)
        }

        let contentStack = UIStackView(arrangedSubviews: [hintLabel, stackView])
        contentStack.axis = .vertical
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 18),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 10),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -18),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -36)
        ])
    }

    private func makePlaceButton(_ kind: SavedPlaceKind) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: kind.icon)
        configuration.imagePadding = 14
        configuration.titleAlignment = .leading
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.subtitleLineBreakMode = .byTruncatingTail
        configuration.baseForegroundColor = color(for: kind)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        button.configuration = configuration
        button.backgroundColor = .secondarySystemGroupedBackground
        button.layer.cornerRadius = 16
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.07
        button.layer.shadowOffset = CGSize(width: 0, height: 3)
        button.layer.shadowRadius = 8
        button.contentHorizontalAlignment = .leading
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 84).isActive = true
        button.addTarget(self, action: #selector(tapPlace(_:)), for: .touchUpInside)
        return button
    }

    private func reloadPlaces() {
        for kind in SavedPlaceKind.allCases {
            guard let button = placeButtons[kind] else { continue }
            var configuration = button.configuration
            let place = SavedPlaceStore.place(for: kind)
            configuration?.title = kind.title
            configuration?.subtitle = place.map {
                $0.address.isEmpty ? $0.name : "\($0.name) · \($0.address)"
            } ?? L10n.t("places.not_set")
            configuration?.baseForegroundColor = color(for: kind)
            button.configuration = configuration
        }
    }

    private func color(for kind: SavedPlaceKind) -> UIColor {
        switch kind {
        case .home: return .systemOrange
        case .work: return .systemBlue
        case .favorite: return .systemPurple
        }
    }

    @objc private func tapBack() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func tapPlace(_ sender: UIButton) {
        let kinds = SavedPlaceKind.allCases
        guard sender.tag >= 0, sender.tag < kinds.count else { return }
        let kind = kinds[sender.tag]
        let city = currentLocation?.city ?? LocationManager.shared.lastKnownLocation?.city ?? Constants.city
        let search = PoiKeywordSearchViewController(
            city: city,
            location: currentLocation ?? LocationManager.shared.lastKnownLocation
        )
        let save: (SelectedPOI) -> Void = { [weak self, weak search] place in
            SavedPlaceStore.save(place, for: kind)
            self?.reloadPlaces()
            search?.navigationController?.popViewController(animated: true)
        }
        search.onSelect = save
        search.onSelectHistory = save
        navigationController?.pushViewController(search, animated: true)
    }
}
