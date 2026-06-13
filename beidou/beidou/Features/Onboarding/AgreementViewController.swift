//
//  AgreementViewController.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  首次启动隐私合规弹窗。对应 Android cn.navibeidou.beidou.widget.CommonStartDialog
//  用户需勾选"已阅读并同意《用户协议》和《隐私政策》"后点击"同意并继续"，
//  方可进入App；点击"不同意"则退出App。
//

import UIKit

final class AgreementViewController: UIViewController {

    /// 用户点击"同意并继续"且已勾选协议
    var onAgree: (() -> Void)?

    private let cardView = UIView()
    private let checkBoxButton = UIButton(type: .system)
    private let textView = UITextView()
    private var isChecked = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        setupCard()
    }

    private func setupCard() {
        cardView.backgroundColor = .systemBackground
        cardView.layer.cornerRadius = 16
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.75)
        ])

        let titleLabel = UILabel()
        titleLabel.text = Constants.appName
        titleLabel.font = .boldSystemFont(ofSize: 18)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isScrollEnabled = true
        textView.font = .systemFont(ofSize: 13)
        textView.dataDetectorTypes = []
        textView.delegate = self
        textView.attributedText = Self.buildAttributedSummary()
        textView.linkTextAttributes = [.foregroundColor: UIColor.systemBlue]

        checkBoxButton.setImage(UIImage(systemName: "square"), for: .normal)
        checkBoxButton.setImage(UIImage(systemName: "checkmark.square.fill"), for: .selected)
        checkBoxButton.tintColor = .systemBlue
        checkBoxButton.addTarget(self, action: #selector(toggleCheck), for: .touchUpInside)
        checkBoxButton.translatesAutoresizingMaskIntoConstraints = false

        let checkLabel = UILabel()
        checkLabel.text = L10n.t("agreement.checkbox")
        checkLabel.font = .systemFont(ofSize: 12)
        checkLabel.textColor = .secondaryLabel
        checkLabel.translatesAutoresizingMaskIntoConstraints = false
        checkLabel.isUserInteractionEnabled = true
        checkLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleCheck)))

        let checkRow = UIStackView(arrangedSubviews: [checkBoxButton, checkLabel])
        checkRow.axis = .horizontal
        checkRow.spacing = 6
        checkRow.alignment = .center
        checkRow.translatesAutoresizingMaskIntoConstraints = false

        let agreeButton = UIButton(type: .system)
        agreeButton.setTitle(L10n.t("agreement.agree_continue"), for: .normal)
        agreeButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        agreeButton.setTitleColor(.white, for: .normal)
        agreeButton.backgroundColor = .systemBlue
        agreeButton.layer.cornerRadius = 8
        agreeButton.addTarget(self, action: #selector(tapAgree), for: .touchUpInside)
        agreeButton.translatesAutoresizingMaskIntoConstraints = false

        let disagreeButton = UIButton(type: .system)
        disagreeButton.setTitle(L10n.t("agreement.disagree"), for: .normal)
        disagreeButton.titleLabel?.font = .systemFont(ofSize: 14)
        disagreeButton.setTitleColor(.secondaryLabel, for: .normal)
        disagreeButton.addTarget(self, action: #selector(tapDisagree), for: .touchUpInside)
        disagreeButton.translatesAutoresizingMaskIntoConstraints = false

        [titleLabel, textView, checkRow, agreeButton, disagreeButton].forEach { cardView.addSubview($0) }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),

            textView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),

            checkRow.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 8),
            checkRow.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            checkRow.trailingAnchor.constraint(lessThanOrEqualTo: cardView.trailingAnchor, constant: -16),
            checkBoxButton.widthAnchor.constraint(equalToConstant: 22),
            checkBoxButton.heightAnchor.constraint(equalToConstant: 22),

            agreeButton.topAnchor.constraint(equalTo: checkRow.bottomAnchor, constant: 16),
            agreeButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            agreeButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            agreeButton.heightAnchor.constraint(equalToConstant: 46),

            disagreeButton.topAnchor.constraint(equalTo: agreeButton.bottomAnchor, constant: 8),
            disagreeButton.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            disagreeButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16)
        ])
    }

    /// 构建带《用户协议》《隐私政策》可点击链接的协议摘要文本
    private static func buildAttributedSummary() -> NSAttributedString {
        let text = WebViewController.loadLegalText(resourceName: "agreement_summary")
        let attributed = NSMutableAttributedString(string: text)
        attributed.addAttributes([
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: UIColor.label
        ], range: NSRange(location: 0, length: attributed.length))

        if let range = text.range(of: L10n.t("legal.user_agreement")) {
            attributed.addAttribute(.link, value: "agreement://user", range: NSRange(range, in: text))
        }
        if let range = text.range(of: L10n.t("legal.privacy_policy")) {
            attributed.addAttribute(.link, value: "agreement://privacy", range: NSRange(range, in: text))
        }
        return attributed
    }

    @objc private func toggleCheck() {
        isChecked.toggle()
        checkBoxButton.isSelected = isChecked
    }

    @objc private func tapAgree() {
        guard isChecked else {
            let alert = UIAlertController(title: nil, message: L10n.t("agreement.must_check"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L10n.t("common.ok"), style: .default))
            present(alert, animated: true)
            return
        }
        onAgree?()
    }

    @objc private func tapDisagree() {
        let alert = UIAlertController(
            title: L10n.t("agreement.tip_title"),
            message: L10n.f("agreement.must_agree", Constants.appName),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.t("agreement.view"), style: .default))
        alert.addAction(UIAlertAction(title: L10n.t("agreement.exit_app"), style: .destructive) { _ in
            exit(0)
        })
        present(alert, animated: true)
    }

    private func presentLegalDoc(title: String, content: WebViewController.Content) {
        let vc = WebViewController(title: title, content: content)
        let nav = UINavigationController(rootViewController: vc)
        vc.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(dismissLegalDoc)
        )
        present(nav, animated: true)
    }

    @objc private func dismissLegalDoc() {
        presentedViewController?.dismiss(animated: true)
    }
}

// MARK: - UITextViewDelegate

extension AgreementViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        switch URL.absoluteString {
        case "agreement://user":
            presentLegalDoc(title: L10n.t("legal.user_agreement"), content: .localText(resourceName: "user_agreement"))
        case "agreement://privacy":
            presentLegalDoc(title: L10n.t("legal.privacy_policy"), content: .remoteURL(Constants.privacyPolicyURL))
        default:
            break
        }
        return false
    }
}
