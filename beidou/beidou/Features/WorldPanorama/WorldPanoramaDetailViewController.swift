//
//  WorldPanoramaDetailViewController.swift
//  beidou
//
//  国内 5A 景区详情，页面内展示百度全景。
//

import UIKit
import WebKit

final class WorldPanoramaDetailViewController: UIViewController {

    private let place: WorldPanoramaPlace
    private let titleLabel = UILabel()
    private let summaryLabel = UILabel()
    private let coordinateLabel = UILabel()
    private let webView = WKWebView(frame: .zero)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    init(place: WorldPanoramaPlace) {
        self.place = place
        super.init(nibName: nil, bundle: nil)
        title = place.name
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        loadPanorama()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("WorldPanoramaDetailViewController")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("WorldPanoramaDetailViewController")
    }

    private func setupUI() {
        titleLabel.text = "\(place.name) · \(place.country)"
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        summaryLabel.text = place.summary
        summaryLabel.font = .systemFont(ofSize: 14)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.numberOfLines = 0

        coordinateLabel.text = String(format: "经纬度 %.6f, %.6f", place.latitude, place.longitude)
        coordinateLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        coordinateLabel.textColor = .tertiaryLabel

        let infoStack = UIStackView(arrangedSubviews: [titleLabel, summaryLabel, coordinateLabel])
        infoStack.axis = .vertical
        infoStack.spacing = 8
        infoStack.translatesAutoresizingMaskIntoConstraints = false

        webView.navigationDelegate = self
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.backgroundColor = .secondarySystemBackground
        webView.clipsToBounds = true
        webView.translatesAutoresizingMaskIntoConstraints = false

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()

        [infoStack, webView, activityIndicator].forEach { view.addSubview($0) }

        NSLayoutConstraint.activate([
            infoStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            infoStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            infoStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            webView.topAnchor.constraint(equalTo: infoStack.bottomAnchor, constant: 16),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: webView.centerYAnchor)
        ])
    }

    private func loadPanorama() {
        activityIndicator.startAnimating()
        webView.loadHTMLString(
            Self.panoramaHTML(place: place),
            baseURL: URL(string: "https://api.map.baidu.com")
        )
    }

    private static func panoramaHTML(place: WorldPanoramaPlace) -> String {
        let keyword = jsString("\(place.name) \(place.country)")
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                html, body, #pano { width: 100%; height: 100%; margin: 0; padding: 0; overflow: hidden; background: #f2f3f5; }
                #empty-tip {
                    position: absolute; top: 50%; left: 16px; right: 16px;
                    transform: translateY(-50%);
                    text-align: center; color: #777; font-size: 14px;
                    line-height: 1.5; font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    display: block;
                }
            </style>
            <script src="https://api.map.baidu.com/api?v=3.0&ak=\(Constants.baiduMapAPIKey)"></script>
        </head>
        <body>
            <div id="pano"></div>
            <div id="empty-tip">正在加载百度全景...</div>
            <script>
                var keyword = \(keyword);
                var hasLoaded = false;

                function showEmpty() {
                    document.getElementById("empty-tip").innerText = "该景区附近暂无可用百度全景数据";
                    document.getElementById("empty-tip").style.display = "block";
                }

                function hideEmpty() {
                    document.getElementById("empty-tip").style.display = "none";
                }

                function loadByPoint(point) {
                    try {
                        var pano = new BMap.Panorama("pano");
                        var service = new BMap.PanoramaService();

                        service.getPanoramaByLocation(point, 5000, function(data) {
                            if (data && data.id) {
                                hideEmpty();
                                pano.setId(data.id);
                                pano.setPov({heading: 0, pitch: 0});
                            } else {
                                hideEmpty();
                                pano.setPosition(point);
                                pano.setPov({heading: 0, pitch: 0});
                                pano.addEventListener("emptyposition", showEmpty);
                                setTimeout(showEmpty, 2500);
                            }
                        });
                    } catch (e) {
                        var pano = new BMap.Panorama("pano");
                        pano.setPosition(point);
                        pano.setPov({heading: 0, pitch: 0});
                    }
                }

                function initPanorama() {
                    var fallbackPoint = new BMap.Point(\(place.longitude), \(place.latitude));
                    var local = new BMap.LocalSearch("", {
                        onSearchComplete: function(results) {
                            if (hasLoaded) { return; }
                            hasLoaded = true;
                            if (local.getStatus() == BMAP_STATUS_SUCCESS && results && results.getCurrentNumPois() > 0) {
                                loadByPoint(results.getPoi(0).point);
                            } else {
                                loadByPoint(fallbackPoint);
                            }
                        }
                    });

                    local.search(keyword);
                    setTimeout(function() {
                        if (!hasLoaded) {
                            hasLoaded = true;
                            loadByPoint(fallbackPoint);
                        }
                    }, 1800);
                }

                window.onload = initPanorama;
            </script>
        </body>
        </html>
        """
    }

    private static func jsString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value], options: [])
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(json.dropFirst().dropLast())
    }
}

extension WorldPanoramaDetailViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        activityIndicator.stopAnimating()
        loadPanorama()
    }
}
