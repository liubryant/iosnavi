import UIKit

final class CloudPanoramaWelcomeViewController: UIViewController {
    var onOpenFeatured: (() -> Void)?
    var onViewMore: (() -> Void)?

    private let item: CloudScenicItem
    private let cardView = UIView()

    init(item: CloudScenicItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.56)

        cardView.backgroundColor = .systemBackground
        cardView.layer.cornerRadius = 18
        cardView.layer.cornerCurve = .continuous
        cardView.clipsToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "\(L10n.t("cloud.welcome_featured_accessibility")) \(item.title)"
        imageView.accessibilityTraits = .button
        imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openFeatured)))
        if let url = item.coverImageURL {
            imageView.image = UIImage(contentsOfFile: url.path)
        }
        if imageView.image == nil {
            imageView.image = UIImage(systemName: "mountain.2.fill")
            imageView.tintColor = .systemBlue
            imageView.backgroundColor = .secondarySystemBackground
        }
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let recommendationLabel = makeImageBadge(text: L10n.t("cloud.welcome_recommendation"))
        let tapHintLabel = makeImageBadge(text: L10n.t("cloud.welcome_tap_hint"))

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.48)
        closeButton.layer.cornerRadius = 16
        closeButton.accessibilityLabel = L10n.t("common.close")
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = item.title
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        let messageLabel = UILabel()
        messageLabel.text = L10n.f("cloud.welcome_message", item.title)
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        let sourceLabel = UILabel()
        sourceLabel.text = L10n.t("cloud.welcome_source_notice")
        sourceLabel.font = .systemFont(ofSize: 10)
        sourceLabel.textColor = .tertiaryLabel
        sourceLabel.textAlignment = .center
        sourceLabel.numberOfLines = 0

        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.title = L10n.t("cloud.welcome_more")
        buttonConfiguration.cornerStyle = .small
        buttonConfiguration.baseBackgroundColor = .systemBlue
        let moreButton = UIButton(configuration: buttonConfiguration)
        moreButton.addTarget(self, action: #selector(viewMore), for: .touchUpInside)
        moreButton.heightAnchor.constraint(equalToConstant: 42).isActive = true

        let contentStack = UIStackView(arrangedSubviews: [titleLabel, messageLabel, sourceLabel, moreButton])
        contentStack.axis = .vertical
        contentStack.spacing = 10
        contentStack.setCustomSpacing(14, after: sourceLabel)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(cardView)
        cardView.addSubview(imageView)
        cardView.addSubview(recommendationLabel)
        cardView.addSubview(tapHintLabel)
        cardView.addSubview(closeButton)
        cardView.addSubview(contentStack)

        let preferredWidth = cardView.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -72)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 310),
            preferredWidth,

            imageView.topAnchor.constraint(equalTo: cardView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 0.55),

            recommendationLabel.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 12),
            recommendationLabel.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 12),
            tapHintLabel.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            tapHintLabel.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -10),

            closeButton.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            contentStack.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 14),
            contentStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16)
        ])
    }

    private func makeImageBadge(text: String) -> UILabel {
        let label = UILabel()
        label.text = "  \(text)  "
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.textAlignment = .center
        label.heightAnchor.constraint(equalToConstant: 20).isActive = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func openFeatured() {
        let action = onOpenFeatured
        dismiss(animated: true) {
            action?()
        }
    }

    @objc private func viewMore() {
        let action = onViewMore
        dismiss(animated: true) {
            action?()
        }
    }
}
