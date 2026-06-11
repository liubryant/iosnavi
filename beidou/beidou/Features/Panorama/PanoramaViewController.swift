//
//  PanoramaViewController.swift
//  beidou
//
//  全景/街景页 (对应 Android QuanJingActivity 百度全景)。
//  使用 WKWebView 加载百度地图 JS API 的 Panorama 组件，定位到传入的经纬度(百度BD09坐标系)。
//

import UIKit
import WebKit
import CoreLocation

final class PanoramaViewController: UIViewController {

    /// 百度坐标系(BD09) 纬度/经度。为空时退化为默认起点坐标(GCJ02转BD09)
    private let latitude: Double
    private let longitude: Double

    private var webView: WKWebView?
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    init(latitude: Double? = nil, longitude: Double? = nil) {
        if let latitude = latitude, let longitude = longitude {
            self.latitude = latitude
            self.longitude = longitude
        } else {
            let bd09 = CoordinateConverter.gcj02ToBD09(
                CLLocationCoordinate2D(latitude: Constants.defaultStartLat, longitude: Constants.defaultStartLon)
            )
            self.latitude = bd09.latitude
            self.longitude = bd09.longitude
        }
        super.init(nibName: nil, bundle: nil)
        self.title = "全景"
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

        webView.loadHTMLString(Self.panoramaHTML(latitude: latitude, longitude: longitude), baseURL: URL(string: "https://api.map.baidu.com"))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("PanoramaViewController")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("PanoramaViewController")
    }

    /// 百度地图 JS API 全景组件页面。ak 复用百度地图 SDK Key，如全景加载失败需在百度地图开放平台
    /// 单独申请一个"浏览器端(JS API)"类型的 Key 替换此处。
    private static func panoramaHTML(latitude: Double, longitude: Double) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                html, body, #pano { width: 100%; height: 100%; margin: 0; padding: 0; }
                #empty-tip {
                    position: absolute; top: 50%; left: 0; right: 0;
                    transform: translateY(-50%);
                    text-align: center; color: #999; font-size: 14px;
                    font-family: -apple-system, sans-serif;
                    display: none;
                }
            </style>
            <script src="https://api.map.baidu.com/api?v=3.0&ak=\(Constants.baiduMapAPIKey)"></script>
        </head>
        <body>
            <div id="pano"></div>
            <div id="empty-tip">该位置暂无全景数据</div>
            <script>
                var point = new BMap.Point(\(longitude), \(latitude));
                var pano = new BMap.Panorama("pano");
                pano.setPosition(point);
                pano.setPov({heading: 0, pitch: 0});
                pano.addEventListener("emptyposition", function () {
                    document.getElementById("empty-tip").style.display = "block";
                });
            </script>
        </body>
        </html>
        """
    }
}

extension PanoramaViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
    }
}
