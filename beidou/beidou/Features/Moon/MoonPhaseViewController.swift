//
//  MoonPhaseViewController.swift
//  beidou
//
//  Immersive mobile moon calendar.
//

import UIKit
import WebKit

final class MoonPhaseViewController: UIViewController {
    private static let adCleanupScript = #"""
    (function() {
      const selectors = [
        'ins.adsbygoogle',
        '[id^="google_ads_"]',
        '[id*="google_ads_iframe"]',
        '[class*="google-ad"]',
        '[class*="adsbygoogle"]',
        '[data-ad-unit]',
        '[data-ad-slot]',
        'iframe[src*="doubleclick.net"]',
        'iframe[src*="googlesyndication.com"]',
        'iframe[src*="googleadservices.com"]'
      ];

      function removeAds(root) {
        selectors.forEach(function(selector) {
          (root || document).querySelectorAll(selector).forEach(function(node) {
            const container = node.closest('[data-ad-unit], [data-ad-slot]') || node;
            container.remove();
          });
        });

        document.querySelectorAll('iframe').forEach(function(frame) {
          const src = frame.getAttribute('src') || '';
          if (/doubleclick|googlesyndication|googleadservices|adservice/i.test(src)) {
            const wrapper = frame.parentElement;
            frame.remove();
            if (wrapper && wrapper.children.length === 0) wrapper.remove();
          }
        });
      }

      removeAds(document);
      new MutationObserver(function(mutations) {
        mutations.forEach(function(mutation) {
          mutation.addedNodes.forEach(function(node) {
            if (node.nodeType === 1) removeAds(node);
          });
        });
        removeAds(document);
      }).observe(document.documentElement, { childList: true, subtree: true });

      const style = document.createElement('style');
      style.textContent = selectors.join(',') + '{display:none!important;height:0!important;min-height:0!important;}';
      document.documentElement.appendChild(style);
    })();
    """#

    private static let blockedAdHosts = [
        "doubleclick.net",
        "googlesyndication.com",
        "googleadservices.com",
        "adservice.google.com"
    ]

    private let webView: WKWebView
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let refreshControl = UIRefreshControl()
    private let errorView = UIView()
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var progressObservation: NSKeyValueObservation?
    private var previousNavigationBarHidden = false

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.adCleanupScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        title = L10n.t("home.moon_phase")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupWebView()
        setupImmersiveHeader()
        setupErrorView()
        loadPage()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        previousNavigationBarHidden = navigationController?.isNavigationBarHidden ?? false
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(previousNavigationBarHidden, animated: animated)
    }

    deinit {
        progressObservation?.invalidate()
    }

    private func setupWebView() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        webView.translatesAutoresizingMaskIntoConstraints = false

        refreshControl.tintColor = .white
        refreshControl.addTarget(self, action: #selector(refreshPage), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        progressView.progressTintColor = .systemBlue
        progressView.trackTintColor = .clear
        progressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2)
        ])

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.progressView.setProgress(Float(webView.estimatedProgress), animated: true)
                self?.progressView.isHidden = webView.estimatedProgress >= 1
            }
        }
    }

    private func setupImmersiveHeader() {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "chevron.left")
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.52)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        backButton.configuration = configuration
        backButton.accessibilityLabel = L10n.t("common.back")
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(tapBack), for: .touchUpInside)

        titleLabel.text = L10n.t("home.moon_phase")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.layer.shadowColor = UIColor.black.cgColor
        titleLabel.layer.shadowOpacity = 0.75
        titleLabel.layer.shadowRadius = 3
        titleLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isHidden = true

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

    private func setupErrorView() {
        errorView.backgroundColor = .systemBackground
        errorView.isHidden = true
        errorView.translatesAutoresizingMaskIntoConstraints = false

        errorLabel.text = "月相页面加载失败，请检查网络后重试"
        errorLabel.textColor = .secondaryLabel
        errorLabel.font = .systemFont(ofSize: 15)
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0

        var configuration = UIButton.Configuration.filled()
        configuration.title = "重新加载"
        configuration.cornerStyle = .capsule
        retryButton.configuration = configuration
        retryButton.addTarget(self, action: #selector(retryPage), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [errorLabel, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.insertSubview(errorView, aboveSubview: webView)
        errorView.addSubview(stack)
        NSLayoutConstraint.activate([
            errorView.topAnchor.constraint(equalTo: view.topAnchor),
            errorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: errorView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: errorView.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: errorView.trailingAnchor, constant: -32)
        ])

        view.bringSubviewToFront(progressView)
        view.bringSubviewToFront(backButton)
        view.bringSubviewToFront(titleLabel)
    }

    private func loadPage() {
        guard let url = URL(string: UrlConstants.moonCalendar) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .returnCacheDataElseLoad
        errorView.isHidden = true
        progressView.isHidden = false
        webView.load(request)
    }

    @objc private func refreshPage() {
        webView.reload()
    }

    @objc private func retryPage() {
        loadPage()
    }

    @objc private func tapBack() {
        navigationController?.popViewController(animated: true)
    }
}

extension MoonPhaseViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let host = navigationAction.request.url?.host?.lowercased(),
           Self.blockedAdHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshControl.endRefreshing()
        errorView.isHidden = true
        progressView.isHidden = true
        webView.evaluateJavaScript(Self.adCleanupScript)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showLoadFailure()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showLoadFailure()
    }

    private func showLoadFailure() {
        refreshControl.endRefreshing()
        progressView.isHidden = true
        errorView.isHidden = false
    }
}

extension MoonPhaseViewController: WKUIDelegate {
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
