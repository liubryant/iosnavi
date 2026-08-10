//
//  MetroViewController.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  地铁图页 (对应 Android JsActivity 加载本地 metro.html)。
//  iOS 版使用 WKWebView 加载百度地图 JS API 的地铁图组件 (BMapSub.Subway)。
//

import UIKit
import WebKit

final class MetroViewController: UIViewController {

    private var webView: WKWebView?
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.title = L10n.t("metro.title")
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

        let webView = WKWebView(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
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
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        setupBackButton()
        setupTitleLabel()

        let preferredCityName = LocationManager.shared.lastKnownLocation?.city ?? Constants.city
        webView.loadHTMLString(Self.subwayHTML(preferredCityName: preferredCityName), baseURL: URL(string: "https://api.map.baidu.com"))
    }

    private func setupBackButton() {
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

        view.addSubview(backButton)
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            backButton.widthAnchor.constraint(equalToConstant: 42),
            backButton.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    private func setupTitleLabel() {
        titleLabel.text = L10n.t("metro.world_title")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .black
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -84)
        ])
    }

    @objc private func tapBack() {
        navigationController?.popViewController(animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("MetroViewController")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("MetroViewController")
    }

    /// 百度地图 JS API 地铁图组件页面。ak 复用百度地图 SDK Key。
    /// 右上角提供全国城市切换下拉框；默认尝试定位到的城市，若该城市没有地铁数据则回退到深圳。
    private static func subwayHTML(preferredCityName: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
            <style>
                html, body { width: 100%; height: 100%; margin: 0; padding: 0; overflow: hidden; background: #fff; }
                #subway-container { width: 100%; height: 100%; }
                #city-picker {
                    position: absolute;
                    top: calc(env(safe-area-inset-top, 0px) + 13px);
                    right: 12px;
                    z-index: 999;
                    height: 32px;
                    width: 64px;
                    border: none;
                    border-radius: 16px;
                    background: rgba(0,0,0,0.52);
                    color: #fff;
                    font-size: 12px;
                    padding: 0 8px;
                    text-align: center;
                    text-align-last: center;
                    -webkit-appearance: none;
                    appearance: none;
                }
                #city-picker option {
                    text-align: center;
                    color: #000;
                }
            </style>
            <script src="https://api.map.baidu.com/api?type=subway&v=1.0&ak=\(Constants.baiduMapAPIKey)"></script>
        </head>
        <body>
            <div id="subway-container"></div>
            <select id="city-picker"></select>
            <script>
                (function() {
                    var stripSuffix = function(name) {
                        return (name || "").replace(/(市|自治区|特别行政区|省)$/g, "");
                    };
                    var preferredName = stripSuffix("\(preferredCityName)");
                    var fallbackName = "深圳";
                    var cities = (window.BMapSub && BMapSub.SubwayCitiesList) || [];
                    var picker = document.getElementById("city-picker");
                    var matchedCode = null;
                    var fallbackCode = null;

                    cities.forEach(function(c) {
                        var code = c.cityCode || c.citycode;
                        var name = c.name || "";
                        var option = document.createElement("option");
                        option.value = code;
                        option.text = name;
                        picker.appendChild(option);

                        var shortName = stripSuffix(name);
                        if (!matchedCode && (shortName === preferredName || name === preferredName)) {
                            matchedCode = code;
                        }
                        if (!fallbackCode && (shortName === fallbackName || name === fallbackName)) {
                            fallbackCode = code;
                        }
                    });

                    var initialCode = matchedCode || fallbackCode;
                    var subway = new BMapSub.Subway("subway-container", initialCode);
                    subway.setZoom(0.5);
                    if (initialCode) {
                        picker.value = initialCode;
                    }

                    picker.addEventListener("change", function() {
                        subway.setCity(picker.value);
                        subway.setZoom(0.5);
                    });
                })();
            </script>
        </body>
        </html>
        """
    }
}

extension MetroViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
    }
}
