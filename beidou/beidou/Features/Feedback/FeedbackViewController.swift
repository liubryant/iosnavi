//
//  FeedbackViewController.swift
//  beidou
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

    private let categoryControl = UISegmentedControl(items: ["功能异常", "定位问题", "体验建议"])
    private let contentTextView = UITextView()
    private let placeholderLabel = UILabel()
    private let contactField = UITextField()
    private let submitButton = UIButton(type: .system)

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.title = "用户反馈"
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
        view.backgroundColor = .systemGroupedBackground
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

        placeholderLabel.text = "请描述你遇到的问题或建议"
        placeholderLabel.font = .systemFont(ofSize: 15)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        contentTextView.addSubview(placeholderLabel)

        contactField.placeholder = "手机号/邮箱/微信号（选填）"
        contactField.font = .systemFont(ofSize: 15)
        contactField.backgroundColor = .secondarySystemGroupedBackground
        contactField.layer.cornerRadius = 8
        contactField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        contactField.leftViewMode = .always
        contactField.clearButtonMode = .whileEditing
        contactField.translatesAutoresizingMaskIntoConstraints = false

        var config = UIButton.Configuration.filled()
        config.title = "提交反馈"
        config.image = UIImage(systemName: "paperplane.fill")
        config.imagePadding = 8
        config.baseBackgroundColor = .systemBlue
        config.baseForegroundColor = .white
        submitButton.configuration = config
        submitButton.layer.cornerRadius = 8
        submitButton.translatesAutoresizingMaskIntoConstraints = false
        submitButton.addTarget(self, action: #selector(tapSubmit), for: .touchUpInside)

        stack.addArrangedSubview(makeSection(title: "反馈类型", view: categoryControl))
        stack.addArrangedSubview(makeSection(title: "反馈内容", view: contentTextView))
        stack.addArrangedSubview(makeSection(title: "联系方式", view: contactField))
        stack.addArrangedSubview(makeTipsView())
        stack.addArrangedSubview(submitButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
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
        label.text = "我们会优先处理包含具体地点、操作步骤、设备信息的反馈。"
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }

    @objc private func tapSubmit() {
        let content = contentTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.count >= 5 else {
            showAlert(message: "请至少输入 5 个字的反馈内容")
            return
        }

        saveFeedback(content: content)
        contentTextView.resignFirstResponder()
        contactField.resignFirstResponder()
        showAlert(message: "反馈已提交，感谢你的建议") { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }

    private func saveFeedback(content: String) {
        let category = categoryControl.titleForSegment(at: categoryControl.selectedSegmentIndex) ?? "功能异常"
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
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
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
