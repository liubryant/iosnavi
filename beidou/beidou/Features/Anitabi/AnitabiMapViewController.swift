//
//  AnitabiMapViewController.swift
//  beidou
//
//  内嵌访问 Anitabi 社区维护的动画圣地巡礼地图。
//  不复制或二次分发社区数据，页面内容与更新均由 Anitabi 官方站点提供。
//

import UIKit
import WebKit

final class AnitabiMapViewController: UIViewController {

    private let statusBarBackgroundView = UIView()
    private let topBar = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let errorView = UIView()
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let attributionView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let attributionLabel = UILabel()
    private var progressObservation: NSKeyValueObservation?

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false
        return webView
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.t("anitabi.map_title")
        overrideUserInterfaceStyle = .light
        view.backgroundColor = .white
        setupFloatingHeader()
        setupWebView()
        setupLoadingState()
        setupAttribution()
        observeProgress()
        loadMap()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("AnitabiMapViewController")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("AnitabiMapViewController")
    }

    private func setupFloatingHeader() {
        statusBarBackgroundView.backgroundColor = .white
        statusBarBackgroundView.isUserInteractionEnabled = false
        statusBarBackgroundView.translatesAutoresizingMaskIntoConstraints = false

        topBar.backgroundColor = .white
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

        titleLabel.text = L10n.t("anitabi.map_title")
        titleLabel.font = .systemFont(ofSize: 19, weight: .bold)
        titleLabel.textColor = .black
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        progressView.progressTintColor = .systemBlue
        progressView.trackTintColor = .clear
        progressView.alpha = 0
        progressView.translatesAutoresizingMaskIntoConstraints = false

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(statusBarBackgroundView)
        view.addSubview(topBar)
        topBar.addSubview(backButton)
        topBar.addSubview(titleLabel)
        topBar.addSubview(separator)
        topBar.addSubview(progressView)
        NSLayoutConstraint.activate([
            statusBarBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            statusBarBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBarBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBarBackgroundView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),

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
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            progressView.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2)
        ])
    }

    private func setupWebView() {
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .darkContent
    }

    private func setupLoadingState() {
        activityIndicator.color = .secondaryLabel
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        let errorIcon = UIImageView(image: UIImage(systemName: "wifi.exclamationmark"))
        errorIcon.tintColor = .secondaryLabel
        errorIcon.contentMode = .scaleAspectFit
        errorIcon.translatesAutoresizingMaskIntoConstraints = false

        errorLabel.text = L10n.t("anitabi.load_failed")
        errorLabel.font = .systemFont(ofSize: 15)
        errorLabel.textColor = .secondaryLabel
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.translatesAutoresizingMaskIntoConstraints = false

        var retryConfiguration = UIButton.Configuration.filled()
        retryConfiguration.title = L10n.t("anitabi.retry")
        retryConfiguration.baseBackgroundColor = .systemBlue
        retryConfiguration.baseForegroundColor = .white
        retryConfiguration.cornerStyle = .capsule
        retryButton.configuration = retryConfiguration
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.addTarget(self, action: #selector(retry), for: .touchUpInside)

        errorView.backgroundColor = .systemBackground
        errorView.isHidden = true
        errorView.translatesAutoresizingMaskIntoConstraints = false
        errorView.addSubview(errorIcon)
        errorView.addSubview(errorLabel)
        errorView.addSubview(retryButton)
        view.addSubview(activityIndicator)
        view.addSubview(errorView)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: webView.centerYAnchor),

            errorView.topAnchor.constraint(equalTo: progressView.bottomAnchor),
            errorView.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            errorView.bottomAnchor.constraint(equalTo: webView.bottomAnchor),

            errorIcon.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),
            errorIcon.centerYAnchor.constraint(equalTo: errorView.centerYAnchor, constant: -52),
            errorIcon.widthAnchor.constraint(equalToConstant: 42),
            errorIcon.heightAnchor.constraint(equalToConstant: 42),

            errorLabel.topAnchor.constraint(equalTo: errorIcon.bottomAnchor, constant: 16),
            errorLabel.leadingAnchor.constraint(equalTo: errorView.leadingAnchor, constant: 28),
            errorLabel.trailingAnchor.constraint(equalTo: errorView.trailingAnchor, constant: -28),

            retryButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 18),
            retryButton.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),
            retryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 112),
            retryButton.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    private func setupAttribution() {
        attributionView.isUserInteractionEnabled = false
        attributionView.layer.cornerRadius = 14
        attributionView.layer.cornerCurve = .continuous
        attributionView.clipsToBounds = true
        attributionView.translatesAutoresizingMaskIntoConstraints = false

        attributionLabel.text = L10n.t("anitabi.attribution")
        attributionLabel.font = .systemFont(ofSize: 12, weight: .medium)
        attributionLabel.textColor = .white
        attributionLabel.textAlignment = .center
        attributionLabel.translatesAutoresizingMaskIntoConstraints = false

        attributionView.contentView.addSubview(attributionLabel)
        view.addSubview(attributionView)
        NSLayoutConstraint.activate([
            attributionView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            attributionView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -3),

            attributionLabel.topAnchor.constraint(equalTo: attributionView.contentView.topAnchor, constant: 6),
            attributionLabel.leadingAnchor.constraint(equalTo: attributionView.contentView.leadingAnchor, constant: 12),
            attributionLabel.trailingAnchor.constraint(equalTo: attributionView.contentView.trailingAnchor, constant: -12),
            attributionLabel.bottomAnchor.constraint(equalTo: attributionView.contentView.bottomAnchor, constant: -6)
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.3, animations: {
                self.attributionView.alpha = 0
            }, completion: { _ in
                self.attributionView.isHidden = true
            })
        }
    }

    private func observeProgress() {
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.progressView.progress = Float(webView.estimatedProgress)
                self.progressView.alpha = webView.estimatedProgress >= 1 ? 0 : 1
            }
        }
    }

    private func loadMap() {
        guard let url = URL(string: UrlConstants.anitabiMap) else {
            showLoadFailure()
            return
        }
        errorView.isHidden = true
        activityIndicator.startAnimating()
        // WKWebsiteDataStore.default() 会把网页资源持久化到磁盘；优先读取缓存，
        // 缓存不存在时再请求网络，兼顾重复打开速度和短时弱网可用性。
        webView.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30))
    }

    private func showLoadFailure() {
        activityIndicator.stopAnimating()
        progressView.alpha = 0
        errorView.isHidden = false
    }

    @objc private func tapBack() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func retry() {
        loadMap()
    }
}

extension AnitabiMapViewController: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
        errorView.isHidden = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        showLoadFailure()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        showLoadFailure()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if let scheme = url.scheme?.lowercased(), scheme != "http", scheme != "https" {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
