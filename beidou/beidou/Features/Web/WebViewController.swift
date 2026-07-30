//
//  WebViewController.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  通用内容容器: 用于展示《用户协议》《隐私政策》等长文本(对应 Android ProtocolActivity 文本展示部分)
//  以及通过 WKWebView 加载网页/本地HTML(对应 Android ProtocolActivity WebView 部分 / JsActivity)。
//

import UIKit
import WebKit

final class WebViewController: UIViewController {
    private static let typhoonPageBackgroundColor = UIColor(
        red: 253.0 / 255.0,
        green: 250.0 / 255.0,
        blue: 245.0 / 255.0,
        alpha: 1
    )

    private static let mobileFitJavaScript = #"""
    (function() {
      function applyMobileFit() {
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
          meta = document.createElement('meta');
          meta.name = 'viewport';
          document.head.appendChild(meta);
        }
        var width = Math.max(980, document.documentElement.scrollWidth || 0, document.body ? document.body.scrollWidth : 0);
        meta.setAttribute('content', 'width=' + width + ', initial-scale=1.0, maximum-scale=3.0, user-scalable=yes');
        if (document.body) {
          document.body.style.webkitTextSizeAdjust = '100%';
        }
      }
      applyMobileFit();
      setTimeout(applyMobileFit, 500);
      setTimeout(applyMobileFit, 1500);
    })();
    """#


    enum Content {
        /// 展示 Resources/Legal 下的本地长文本资源 (不含扩展名)
        case localText(resourceName: String)
        /// 通过 WKWebView 加载远程网页
        case remoteURL(URL)
        /// 通过 WKWebView 加载 Bundle 内的本地 HTML 文件 (不含扩展名)
        case localHTML(resourceName: String)
    }

    private let content: Content
    private let fullScreen: Bool
    private let mobileOptimized: Bool
    private let showsFullScreenTitle: Bool
    private var textView: UITextView?
    private var webView: WKWebView?
    private let backButton = UIButton(type: .system)
    private let fullScreenTitleLabel = UILabel()
    private let statusBarBackgroundView = UIView()
    private var previousNavigationBarHidden = false

    init(
        title: String,
        content: Content,
        fullScreen: Bool = false,
        mobileOptimized: Bool = false,
        showsFullScreenTitle: Bool = true
    ) {
        self.content = content
        self.fullScreen = fullScreen
        self.mobileOptimized = mobileOptimized
        self.showsFullScreenTitle = showsFullScreenTitle
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = fullScreen ? Self.typhoonPageBackgroundColor : .systemBackground

        switch content {
        case .localText(let resourceName):
            setupTextView(resourceName: resourceName)
        case .remoteURL(let url):
            setupWebView(url: url)
        case .localHTML(let resourceName):
            setupLocalHTML(resourceName: resourceName)
        }
        setupFullScreenEdgeBackGestureIfNeeded()
    }

    override var prefersStatusBarHidden: Bool {
        false
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        fullScreen ? .darkContent : .default
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if fullScreen {
            previousNavigationBarHidden = navigationController?.isNavigationBarHidden ?? false
            navigationController?.setNavigationBarHidden(true, animated: animated)
            installFullScreenStatusBarBackground()
            setNeedsStatusBarAppearanceUpdate()
        }
        UMengAnalytics.shared.pageBegin(title ?? "WebViewController")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installFullScreenStatusBarBackground()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if fullScreen {
            navigationController?.setNavigationBarHidden(previousNavigationBarHidden, animated: animated)
            statusBarBackgroundView.removeFromSuperview()
        }
        UMengAnalytics.shared.pageEnd(title ?? "WebViewController")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        applyFullScreenTitleStyle()
    }

    // MARK: - 本地长文本

    private func setupTextView(resourceName: String) {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.font = .systemFont(ofSize: 15)
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.text = Self.loadLegalText(resourceName: resourceName)
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        self.textView = textView
    }

    /// 读取打包在 Resources/Legal 下的文本资源
    static func loadLegalText(resourceName: String) -> String {
        let localizedResourceName = L10n.legalResourceName(resourceName)
        guard let url = Bundle.main.url(forResource: localizedResourceName, withExtension: "txt", subdirectory: "Legal")
            ?? Bundle.main.url(forResource: localizedResourceName, withExtension: "txt")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "txt", subdirectory: "Legal")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return text
    }

    // MARK: - 远程网页

    private func setupWebView(url: URL) {
        let configuration = WKWebViewConfiguration()
        if mobileOptimized {
            configuration.userContentController.addUserScript(
                WKUserScript(source: Self.mobileFitJavaScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            )
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = fullScreen ? .never : .automatic
        if mobileOptimized {
            webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        }
        webView.translatesAutoresizingMaskIntoConstraints = false
        if fullScreen {
            setupFullScreenStatusBarBackground()
        }
        view.addSubview(webView)
        let topAnchor = view.safeAreaLayoutGuide.topAnchor
        let bottomAnchor = fullScreen ? view.bottomAnchor : view.bottomAnchor
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        webView.load(URLRequest(url: url))
        self.webView = webView
        if fullScreen {
            setupFullScreenBackButton()
            if showsFullScreenTitle {
                setupFullScreenTitle()
            }
        }
    }

    private func setupFullScreenStatusBarBackground() {
        statusBarBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        statusBarBackgroundView.backgroundColor = Self.typhoonPageBackgroundColor
        statusBarBackgroundView.isUserInteractionEnabled = false
    }

    private func installFullScreenStatusBarBackground() {
        guard fullScreen,
              let window = view.window,
              statusBarBackgroundView.superview !== window else {
            return
        }

        statusBarBackgroundView.removeFromSuperview()
        window.addSubview(statusBarBackgroundView)
        NSLayoutConstraint.activate([
            statusBarBackgroundView.topAnchor.constraint(equalTo: window.topAnchor),
            statusBarBackgroundView.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            statusBarBackgroundView.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            statusBarBackgroundView.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor)
        ])
    }

    private func setupFullScreenBackButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "chevron.left")
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.52)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        backButton.configuration = configuration
        backButton.accessibilityLabel = L10n.t("common.back")
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(tapBack), for: .touchUpInside)

        view.addSubview(backButton)
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            backButton.widthAnchor.constraint(equalToConstant: 42),
            backButton.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    private func setupFullScreenTitle() {
        fullScreenTitleLabel.text = title
        fullScreenTitleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        fullScreenTitleLabel.textAlignment = .center
        fullScreenTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(fullScreenTitleLabel)
        NSLayoutConstraint.activate([
            fullScreenTitleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            fullScreenTitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            fullScreenTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8),
            fullScreenTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -64)
        ])
        applyFullScreenTitleStyle()
    }

    private func applyFullScreenTitleStyle() {
        fullScreenTitleLabel.textColor = traitCollection.userInterfaceStyle == .dark ? .black : .label
    }

    private func setupFullScreenEdgeBackGestureIfNeeded() {
        guard fullScreen else { return }
        let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleFullScreenEdgeBack(_:)))
        gesture.edges = .left
        view.addGestureRecognizer(gesture)
    }

    @objc private func handleFullScreenEdgeBack(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .recognized else { return }
        tapBack()
    }

    @objc private func tapBack() {
        if presentingViewController != nil {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    // MARK: - 本地HTML

    private func setupLocalHTML(resourceName: String) {
        let webView = WKWebView(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        self.webView = webView
    }
}
