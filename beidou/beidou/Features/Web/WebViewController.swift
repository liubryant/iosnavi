//
//  WebViewController.swift
//  beidou
//
//  通用内容容器: 用于展示《用户协议》《隐私政策》等长文本(对应 Android ProtocolActivity 文本展示部分)
//  以及通过 WKWebView 加载网页/本地HTML(对应 Android ProtocolActivity WebView 部分 / JsActivity)。
//

import UIKit
import WebKit

final class WebViewController: UIViewController {

    enum Content {
        /// 展示 Resources/Legal 下的本地长文本资源 (不含扩展名)
        case localText(resourceName: String)
        /// 通过 WKWebView 加载远程网页
        case remoteURL(URL)
        /// 通过 WKWebView 加载 Bundle 内的本地 HTML 文件 (不含扩展名)
        case localHTML(resourceName: String)
    }

    private let content: Content
    private var textView: UITextView?
    private var webView: WKWebView?

    init(title: String, content: Content) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        switch content {
        case .localText(let resourceName):
            setupTextView(resourceName: resourceName)
        case .remoteURL(let url):
            setupWebView(url: url)
        case .localHTML(let resourceName):
            setupLocalHTML(resourceName: resourceName)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin(title ?? "WebViewController")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd(title ?? "WebViewController")
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
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "txt", subdirectory: "Legal")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return text
    }

    // MARK: - 远程网页

    private func setupWebView(url: URL) {
        let webView = WKWebView(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        webView.load(URLRequest(url: url))
        self.webView = webView
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
