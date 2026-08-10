//
//  TodayTideViewController.swift
//  beidou
//
//  今日潮汐 H5 页面。
//

import UIKit
import WebKit

final class TodayTideViewController: UIViewController {
    private enum CacheKey {
        static let city = "today_tide_cached_city"
        static let url = "today_tide_cached_url"
    }

    private let webView: WKWebView
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let loadingView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let loadingLabel = UILabel()
    private let errorView = UIView()
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var pendingCityName: String?
    private var displayedCityName: String?
    private var isResolvingLocation = false

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        title = L10n.t("tide.today_title")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupWebView()
        setupHeader()
        setupErrorView()
        setupLoadingView()
        loadCachedPageThenRefreshLocation()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("TodayTideViewController")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("TodayTideViewController")
    }

    private func setupWebView() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = true
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

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

        titleLabel.text = L10n.t("tide.today_title")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .white
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
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -84)
        ])
    }

    private func setupErrorView() {
        errorView.backgroundColor = .systemBackground
        errorView.isHidden = true
        errorView.translatesAutoresizingMaskIntoConstraints = false

        errorLabel.text = L10n.t("tide.load_failed")
        errorLabel.textColor = .secondaryLabel
        errorLabel.font = .systemFont(ofSize: 15)
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.translatesAutoresizingMaskIntoConstraints = false

        var configuration = UIButton.Configuration.filled()
        configuration.title = L10n.t("tide.retry")
        configuration.cornerStyle = .capsule
        retryButton.configuration = configuration
        retryButton.addTarget(self, action: #selector(retryPage), for: .touchUpInside)
        retryButton.translatesAutoresizingMaskIntoConstraints = false

        errorView.addSubview(errorLabel)
        errorView.addSubview(retryButton)
        view.insertSubview(errorView, aboveSubview: webView)
        NSLayoutConstraint.activate([
            errorView.topAnchor.constraint(equalTo: view.topAnchor),
            errorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            errorLabel.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: errorView.centerYAnchor, constant: -24),
            errorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: errorView.leadingAnchor, constant: 30),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: errorView.trailingAnchor, constant: -30),
            retryButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 18),
            retryButton.centerXAnchor.constraint(equalTo: errorView.centerXAnchor)
        ])

        view.bringSubviewToFront(backButton)
        view.bringSubviewToFront(titleLabel)
    }

    private func setupLoadingView() {
        loadingView.layer.cornerRadius = 14
        loadingView.layer.cornerCurve = .continuous
        loadingView.clipsToBounds = true
        loadingView.translatesAutoresizingMaskIntoConstraints = false

        activityIndicator.style = .medium
        activityIndicator.color = .white
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        loadingLabel.text = L10n.t("tide.loading")
        loadingLabel.textColor = .white
        loadingLabel.font = .systemFont(ofSize: 14, weight: .medium)
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false

        loadingView.contentView.addSubview(activityIndicator)
        loadingView.contentView.addSubview(loadingLabel)
        view.addSubview(loadingView)
        NSLayoutConstraint.activate([
            loadingView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            activityIndicator.leadingAnchor.constraint(equalTo: loadingView.contentView.leadingAnchor, constant: 18),
            activityIndicator.centerYAnchor.constraint(equalTo: loadingView.contentView.centerYAnchor),
            loadingLabel.leadingAnchor.constraint(equalTo: activityIndicator.trailingAnchor, constant: 10),
            loadingLabel.trailingAnchor.constraint(equalTo: loadingView.contentView.trailingAnchor, constant: -18),
            loadingLabel.topAnchor.constraint(equalTo: loadingView.contentView.topAnchor, constant: 16),
            loadingLabel.bottomAnchor.constraint(equalTo: loadingView.contentView.bottomAnchor, constant: -16)
        ])
        loadingView.isHidden = true
        view.bringSubviewToFront(backButton)
        view.bringSubviewToFront(titleLabel)
    }

    private func loadCachedPageThenRefreshLocation() {
        let defaults = UserDefaults.standard
        let cachedCity = defaults.string(forKey: CacheKey.city)
        let cachedURL = defaults.string(forKey: CacheKey.url).flatMap(URL.init(string:))

        if let cachedCity, let cachedURL {
            displayedCityName = cachedCity
            loadPage(at: cachedURL)
        } else {
            showLoading()
        }
        refreshCurrentLocation(hasCachedPage: cachedURL != nil)
    }

    private func refreshCurrentLocation(hasCachedPage: Bool = false) {
        guard !isResolvingLocation else { return }
        isResolvingLocation = true

        LocationManager.shared.requestLocation { [weak self] location in
            guard let self else { return }
            self.isResolvingLocation = false
            let resolvedLocation = location ?? LocationManager.shared.lastKnownLocation
            guard let city = resolvedLocation.map({ self.tideCityName(from: $0.city) }) else {
                if !hasCachedPage {
                    self.loadPage()
                }
                return
            }
            guard city != self.displayedCityName else {
                if !self.webView.isLoading {
                    self.hideLoading()
                }
                return
            }
            self.pendingCityName = city
            self.loadPage()
        }
    }

    private func tideCityName(from city: String) -> String {
        let suffixes = ["特别行政区", "自治州", "地区", "盟", "市"]
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        return suffixes.first(where: { trimmed.hasSuffix($0) })
            .map { String(trimmed.dropLast($0.count)) } ?? trimmed
    }

    private func loadPage() {
        guard let url = URL(string: UrlConstants.todayTide) else {
            showLoadError()
            return
        }
        loadPage(at: url)
    }

    private func loadPage(at url: URL) {
        errorView.isHidden = true
        showLoading()
        webView.load(URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 20
        ))
    }

    private func showLoading() {
        loadingView.isHidden = false
        activityIndicator.startAnimating()
        view.bringSubviewToFront(loadingView)
        view.bringSubviewToFront(backButton)
        view.bringSubviewToFront(titleLabel)
    }

    private func hideLoading() {
        activityIndicator.stopAnimating()
        loadingView.isHidden = true
    }

    private func showLoadError() {
        hideLoading()
        errorView.isHidden = false
    }

    @objc private func tapBack() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func retryPage() {
        refreshCurrentLocation()
        if let url = webView.url {
            loadPage(at: url)
        } else {
            loadPage()
        }
    }
}

extension TodayTideViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        errorView.isHidden = true
        guard let city = pendingCityName,
              webView.url?.path == "/" || webView.url?.path.isEmpty == true else {
            if let url = webView.url, url.path.hasPrefix("/tide/"), url.path != "/tide/" {
                let defaults = UserDefaults.standard
                defaults.set(url.absoluteString, forKey: CacheKey.url)
                if let displayedCityName {
                    defaults.set(displayedCityName, forKey: CacheKey.city)
                }
            }
            hideLoading()
            return
        }
        pendingCityName = nil
        displayedCityName = city

        // The tide site exposes all supported cities as server-rendered links.
        // Selecting the matching link avoids asking the user to repeat a city search.
        let cityJSON = (try? JSONSerialization.data(withJSONObject: city, options: [.fragmentsAllowed]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        let script = """
        (() => {
          const city = \(cityJSON);
          const link = Array.from(document.querySelectorAll('a[href^="/tide/"]'))
            .find(item => item.textContent.trim() === city);
          if (link) {
            window.location.href = link.href;
            return true;
          }
          const input = document.querySelector('input[aria-label="城市搜索"]');
          const form = input && input.closest('form');
          if (!input || !form) return false;
          const setter = Object.getOwnPropertyDescriptor(
            window.HTMLInputElement.prototype, 'value'
          ).set;
          setter.call(input, city);
          input.dispatchEvent(new Event('input', { bubbles: true }));
          form.requestSubmit();
          return true;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            if result as? Bool != true {
                self?.hideLoading()
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showLoadError()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showLoadError()
    }
}

extension TodayTideViewController: WKUIDelegate {
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
