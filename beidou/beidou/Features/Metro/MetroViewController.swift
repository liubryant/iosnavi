//
//  MetroViewController.swift
//  beidou
//
//  地铁图页 (对应 Android JsActivity 加载本地 metro.html)。
//  iOS 版使用 WKWebView 加载高德地图"地铁图"网页版。
//

import UIKit
import WebKit

final class MetroViewController: UIViewController {

    private var webView: WKWebView?
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.title = "地铁图"
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
        view.backgroundColor = .systemBackground

        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.scrollView.delegate = self
        webView.scrollView.minimumZoomScale = 1
        webView.scrollView.maximumZoomScale = 1
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.alwaysBounceVertical = false
        view.addSubview(webView)
        self.webView = webView

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)
        activityIndicator.startAnimating()

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        if let url = URL(string: UrlConstants.metroMap) {
            webView.load(URLRequest(url: url))
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("MetroViewController")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("MetroViewController")
    }
}

extension MetroViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
        constrainPageOverflow(in: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
    }

    private func constrainPageOverflow(in webView: WKWebView) {
        let script = """
        (function() {
            var style = document.getElementById('iosnavi-metro-fit');
            if (!style) {
                style = document.createElement('style');
                style.id = 'iosnavi-metro-fit';
                document.head.appendChild(style);
            }
            style.textContent = [
                'html,body{width:100%!important;max-width:100%!important;min-width:0!important;margin:0!important;overflow-x:hidden!important;background:#fff!important;}',
                '#app,.app,.main,.container{max-width:100vw!important;}'
            ].join('');
        })();
        """
        webView.evaluateJavaScript(script)
    }
}

extension MetroViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        nil
    }
}
