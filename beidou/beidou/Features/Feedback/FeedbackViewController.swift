//
//  FeedbackViewController.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  原生用户反馈页。
//

import UIKit

final class FeedbackViewController: UIViewController {

    private struct FeedbackRecord: Codable {
        let category: String
        let content: String
        let contact: String
        let createdAt: String
    }

    private static let feedbackRecordsKey = "feedback_records"

    private let categoryControl = UISegmentedControl(items: [
        L10n.t("feedback.category_bug"),
        L10n.t("feedback.category_location"),
        L10n.t("feedback.category_suggestion")
    ])
    private let contentTextView = UITextView()
    private let placeholderLabel = UILabel()
    private let contactField = UITextField()
    private let submitButton = UIButton(type: .system)
    private let topBar = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.title = L10n.t("feedback.title")
    }

    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = .systemGroupedBackground
        setupTopBar()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("FeedbackViewController")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("FeedbackViewController")
    }

    private func setupTopBar() {
        topBar.backgroundColor = .systemGroupedBackground
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

        titleLabel.text = L10n.t("feedback.title")
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

    private func setupUI() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.addSubview(stack)
        view.addSubview(scrollView)

        categoryControl.selectedSegmentIndex = 0
        categoryControl.translatesAutoresizingMaskIntoConstraints = false

        contentTextView.delegate = self
        contentTextView.font = .systemFont(ofSize: 15)
        contentTextView.backgroundColor = .secondarySystemGroupedBackground
        contentTextView.layer.cornerRadius = 8
        contentTextView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        contentTextView.translatesAutoresizingMaskIntoConstraints = false

        placeholderLabel.text = L10n.t("feedback.placeholder")
        placeholderLabel.font = .systemFont(ofSize: 15)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        contentTextView.addSubview(placeholderLabel)

        contactField.placeholder = L10n.t("feedback.contact_placeholder")
        contactField.font = .systemFont(ofSize: 15)
        contactField.backgroundColor = .secondarySystemGroupedBackground
        contactField.layer.cornerRadius = 8
        contactField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        contactField.leftViewMode = .always
        contactField.clearButtonMode = .whileEditing
        contactField.translatesAutoresizingMaskIntoConstraints = false

        var config = UIButton.Configuration.filled()
        config.title = L10n.t("feedback.submit")
        config.image = UIImage(systemName: "paperplane.fill")
        config.imagePadding = 8
        config.baseBackgroundColor = .systemBlue
        config.baseForegroundColor = .white
        submitButton.configuration = config
        submitButton.layer.cornerRadius = 8
        submitButton.translatesAutoresizingMaskIntoConstraints = false
        submitButton.addTarget(self, action: #selector(tapSubmit), for: .touchUpInside)

        stack.addArrangedSubview(makeSection(title: L10n.t("feedback.type"), view: categoryControl))
        stack.addArrangedSubview(makeSection(title: L10n.t("feedback.content"), view: contentTextView))
        stack.addArrangedSubview(makeSection(title: L10n.t("feedback.contact"), view: contactField))
        stack.addArrangedSubview(makeTipsView())
        stack.addArrangedSubview(submitButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),

            categoryControl.heightAnchor.constraint(equalToConstant: 36),
            contentTextView.heightAnchor.constraint(equalToConstant: 180),
            contactField.heightAnchor.constraint(equalToConstant: 48),
            submitButton.heightAnchor.constraint(equalToConstant: 48),

            placeholderLabel.topAnchor.constraint(equalTo: contentTextView.topAnchor, constant: 12),
            placeholderLabel.leadingAnchor.constraint(equalTo: contentTextView.leadingAnchor, constant: 15),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentTextView.trailingAnchor, constant: -12)
        ])
    }

    @objc private func tapBack() {
        if let navigationController,
           navigationController.viewControllers.first !== self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    private func makeSection(title: String, view contentView: UIView) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [titleLabel, contentView])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func makeTipsView() -> UIView {
        let label = UILabel()
        label.text = L10n.t("feedback.tips")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }

    @objc private func tapSubmit() {
        let content = contentTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.count >= 5 else {
            showAlert(message: L10n.t("feedback.too_short"))
            return
        }

        saveFeedback(content: content)
        contentTextView.resignFirstResponder()
        contactField.resignFirstResponder()
        showAlert(message: L10n.t("feedback.submitted")) { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }

    private func saveFeedback(content: String) {
        let category = categoryControl.titleForSegment(at: categoryControl.selectedSegmentIndex) ?? L10n.t("feedback.category_bug")
        let contact = contactField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let record = FeedbackRecord(
            category: category,
            content: content,
            contact: contact,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        var records: [FeedbackRecord] = []
        if let data = UserDefaults.standard.data(forKey: Self.feedbackRecordsKey),
           let decoded = try? JSONDecoder().decode([FeedbackRecord].self, from: data) {
            records = decoded
        }
        records.insert(record, at: 0)
        if records.count > 50 {
            records = Array(records.prefix(50))
        }
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.feedbackRecordsKey)
    }

    private func showAlert(message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.t("common.ok"), style: .default) { _ in
            completion?()
        })
        present(alert, animated: true)
    }
}

extension FeedbackViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }
}
