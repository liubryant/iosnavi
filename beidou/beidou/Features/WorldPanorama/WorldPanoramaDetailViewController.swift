//
//  WorldPanoramaDetailViewController.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  国内景区详情：使用现有百度地图能力解析景区真实坐标，并展示附近网页全景。
//

import UIKit
import WebKit

#if canImport(BaiduMapAPI_Search)
import BaiduMapAPI_Search
#endif

final class WorldPanoramaDetailViewController: UIViewController {

    private static let sharedFallbackLatitude = 39.9402
    private static let sharedFallbackLongitude = 116.4434

    private let place: WorldPanoramaPlace
    private let titleLabel = UILabel()
    private let summaryLabel = UILabel()
    private let coordinateLabel = UILabel()
    private let emptyLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let webView = WKWebView(frame: .zero)

    #if canImport(BaiduMapAPI_Search)
    private var poiSearcher: BMKPoiSearch?
    #endif

    private var resolvedLatitude: Double?
    private var resolvedLongitude: Double?
    private var didStartPanorama = false

    init(place: WorldPanoramaPlace) {
        self.place = place
        super.init(nibName: nil, bundle: nil)
        title = place.name
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        #if canImport(BaiduMapAPI_Search)
        poiSearcher?.delegate = nil
        #endif
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        resolvePlaceAndLoadPanorama()
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
        titleLabel.text = "\(place.name) · \(place.localizedRegion)"
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        summaryLabel.text = place.localizedSummary
        summaryLabel.font = .systemFont(ofSize: 14)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.numberOfLines = 0

        coordinateLabel.text = L10n.t("world.locating_coordinate")
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
        webView.isOpaque = false
        webView.backgroundColor = .secondarySystemBackground
        webView.scrollView.backgroundColor = .secondarySystemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.text = L10n.t("world.loading")
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()

        [infoStack, webView, emptyLabel, activityIndicator].forEach(view.addSubview)

        NSLayoutConstraint.activate([
            infoStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            infoStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            infoStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            webView.topAnchor.constraint(equalTo: infoStack.bottomAnchor, constant: 16),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: webView.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(equalTo: webView.trailingAnchor, constant: -24),

            activityIndicator.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            activityIndicator.bottomAnchor.constraint(equalTo: emptyLabel.topAnchor, constant: -12)
        ])
    }

    private func resolvePlaceAndLoadPanorama() {
        if let cachedPlace = WorldPanoramaCoordinateCache.coordinate(for: place) {
            resolvedLatitude = cachedPlace.latitude
            resolvedLongitude = cachedPlace.longitude
            updateCoordinateLabel(latitude: cachedPlace.latitude, longitude: cachedPlace.longitude)
            loadPanorama(latitude: cachedPlace.latitude, longitude: cachedPlace.longitude)
            return
        }

        #if canImport(BaiduMapAPI_Search)
        let searcher = BMKPoiSearch()
        searcher.delegate = self
        poiSearcher = searcher

        let option = BMKPOICitySearchOption()
        option.keyword = place.name
        option.city = place.city
        option.isCityLimit = true
        option.scope = BMKPOISearchScopeType(rawValue: 2)!
        option.pageIndex = 0
        option.pageSize = 20
        option.extensionsAdcode = true

        guard searcher.poiSearch(inCity: option) else {
            finishSearching()
            loadSharedFallbackPanorama()
            return
        }
        #else
        loadSharedFallbackPanorama()
        #endif
    }

    #if canImport(BaiduMapAPI_Search)
    private func handleSearchResult(_ result: BMKPOISearchResult?, errorCode: BMKSearchErrorCode) {
        defer { finishSearching() }
        guard errorCode.rawValue == 0,
              let candidates = result?.poiInfoList,
              let poi = candidates.max(by: { poiScore($0) < poiScore($1) }) else {
            loadSharedFallbackPanorama()
            return
        }

        let latitude = poi.pt.latitude
        let longitude = poi.pt.longitude
        guard CLLocationCoordinate2DIsValid(poi.pt),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            loadSharedFallbackPanorama()
            return
        }

        resolvedLatitude = latitude
        resolvedLongitude = longitude
        updateCoordinateLabel(latitude: latitude, longitude: longitude)
        WorldPanoramaCoordinateCache.save(latitude: latitude, longitude: longitude, for: place)
        loadPanorama(latitude: latitude, longitude: longitude)
    }

    private func finishSearching() {
        poiSearcher?.delegate = nil
        poiSearcher = nil
    }

    private func poiScore(_ poi: BMKPoiInfo) -> Int {
        let title = normalized(poi.name)
        let target = normalized(place.name)
        var score = 0

        if title == target {
            score += 100
        } else if title.contains(target) || target.contains(title) {
            score += 60
        }

        let cityText = normalized("\(poi.city ?? "") \(poi.address ?? "")")
        let provinceText = normalized("\(poi.province ?? "") \(poi.address ?? "")")
        if cityText.contains(normalized(place.city)) { score += 20 }
        if provinceText.contains(normalized(place.province)) { score += 10 }
        if nonempty(poi.streetID) != nil { score += 5 }
        return score
    }
    #endif

    private func loadPanorama(latitude: Double, longitude: Double) {
        guard !didStartPanorama else { return }
        didStartPanorama = true
        activityIndicator.startAnimating()
        emptyLabel.text = L10n.t("world.loading")
        emptyLabel.isHidden = false
        webView.loadHTMLString(
            Self.panoramaHTML(latitude: latitude, longitude: longitude),
            baseURL: URL(string: "https://api.map.baidu.com")
        )
    }

    private func loadSharedFallbackPanorama() {
        coordinateLabel.isHidden = true
        resolvedLatitude = Self.sharedFallbackLatitude
        resolvedLongitude = Self.sharedFallbackLongitude
        loadPanorama(
            latitude: Self.sharedFallbackLatitude,
            longitude: Self.sharedFallbackLongitude
        )
    }

    private func showEmptyState() {
        activityIndicator.stopAnimating()
        emptyLabel.text = L10n.t("world.no_baidu_panorama")
        emptyLabel.isHidden = false
    }

    private func updateCoordinateLabel(latitude: Double, longitude: Double) {
        coordinateLabel.text = String(
            format: L10n.t("world.coordinate_format"),
            latitude,
            longitude
        )
    }

    private func normalized(_ value: String?) -> String {
        (value ?? "")
            .lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .joined()
    }

    private func nonempty(_ value: String?) -> String? {
        let result = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return result.isEmpty ? nil : result
    }

    private static func panoramaHTML(latitude: Double, longitude: Double) -> String {
        """
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
                #nearby-tip {
                    position: absolute; left: 50%; bottom: 14px; z-index: 10;
                    transform: translateX(-50%);
                    padding: 7px 12px; border-radius: 13px;
                    color: white; background: rgba(0, 0, 0, 0.58);
                    font-size: 12px; white-space: nowrap;
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    display: none;
                }
            </style>
            <script src="https://api.map.baidu.com/api?v=3.0&ak=\(Constants.baiduMapAPIKey)"></script>
        </head>
        <body>
            <div id="pano"></div>
            <div id="empty-tip">\(L10n.t("world.loading"))</div>
            <div id="nearby-tip">\(L10n.t("world.nearest_panorama"))</div>
            <script>
                var finished = false;
                var activePanorama = null;
                var searchRadii = [300, 1000, 3000, 10000, 30000, 50000];
                var originPoint = new BMap.Point(\(longitude), \(latitude));
                var fallbackPoints = [
                    [116.4074, 39.9042], [121.4737, 31.2304], [113.2644, 23.1291],
                    [114.0579, 22.5431], [104.0665, 30.5723], [106.5516, 29.5630],
                    [120.1551, 30.2741], [118.7969, 32.0603], [114.3054, 30.5931],
                    [108.9398, 34.3416], [112.9388, 28.2282], [117.2000, 39.1333],
                    [120.5853, 31.2989], [120.3826, 36.0671], [117.1201, 36.6512],
                    [113.6254, 34.7466], [123.4315, 41.8057], [126.5349, 45.8038],
                    [102.8329, 24.8801], [118.0894, 24.4798], [106.6302, 26.6470],
                    [108.3669, 22.8170], [110.1983, 20.0440], [91.1409, 29.6456],
                    [103.8343, 36.0611], [101.7782, 36.6171], [87.6168, 43.8256],
                    [106.2309, 38.4872], [109.7813, 39.6083], [125.3235, 43.8171]
                ];

                fallbackPoints.sort(function(a, b) {
                    var distanceA = Math.pow(a[0] - originPoint.lng, 2) + Math.pow(a[1] - originPoint.lat, 2);
                    var distanceB = Math.pow(b[0] - originPoint.lng, 2) + Math.pow(b[1] - originPoint.lat, 2);
                    return distanceA - distanceB;
                });

                function showPanorama(pano, id, isNearby) {
                    finished = true;
                    document.getElementById("empty-tip").style.display = "none";
                    if (isNearby) {
                        var nearbyTip = document.getElementById("nearby-tip");
                        nearbyTip.style.display = "block";
                        setTimeout(function() {
                            nearbyTip.style.display = "none";
                        }, 5000);
                    }
                    pano.setId(id);
                    pano.setPov({heading: 0, pitch: 0});
                }

                function forceKnownPanorama(pano) {
                    if (finished) { return; }
                    document.getElementById("empty-tip").style.display = "none";
                    var nearbyTip = document.getElementById("nearby-tip");
                    nearbyTip.style.display = "block";
                    setTimeout(function() {
                        nearbyTip.style.display = "none";
                    }, 5000);

                    // This point is retained as the final shared fallback because it has
                    // stable Baidu street-view coverage. The scenic coordinate remains
                    // visible above, while the panorama area never ends on an empty page.
                    pano.setPosition(new BMap.Point(116.4434, 39.9402));
                    pano.setPov({heading: 0, pitch: 0});
                    finished = true;
                }

                function searchFallback(service, pano, index) {
                    if (finished) { return; }
                    if (index >= fallbackPoints.length) {
                        forceKnownPanorama(pano);
                        return;
                    }

                    var candidate = fallbackPoints[index];
                    var point = new BMap.Point(candidate[0], candidate[1]);
                    service.getPanoramaByLocation(point, 10000, function(data) {
                        if (finished) { return; }
                        if (data && data.id) {
                            showPanorama(pano, data.id, true);
                        } else {
                            searchFallback(service, pano, index + 1);
                        }
                    });
                }

                function searchNearest(service, pano, point, index) {
                    if (finished) { return; }
                    if (index >= searchRadii.length) {
                        searchFallback(service, pano, 0);
                        return;
                    }

                    var radius = searchRadii[index];
                    service.getPanoramaByLocation(point, radius, function(data) {
                        if (finished) { return; }
                        if (data && data.id) {
                            showPanorama(pano, data.id, radius > 300);
                        } else {
                            searchNearest(service, pano, point, index + 1);
                        }
                    });
                }

                function initPanorama() {
                    try {
                        var pano = new BMap.Panorama("pano");
                        activePanorama = pano;
                        var service = new BMap.PanoramaService();
                        searchNearest(service, pano, originPoint, 0);
                    } catch (error) {
                        var fallbackPano = new BMap.Panorama("pano");
                        activePanorama = fallbackPano;
                        forceKnownPanorama(fallbackPano);
                    }
                }

                window.onload = initPanorama;
                setTimeout(function() {
                    if (!finished && activePanorama) {
                        forceKnownPanorama(activePanorama);
                    }
                }, 12000);
            </script>
        </body>
        </html>
        """
    }
}

#if canImport(BaiduMapAPI_Search)
extension WorldPanoramaDetailViewController: BMKPoiSearchDelegate {
    func onGetPoiResult(
        _ searcher: BMKPoiSearch!,
        result poiResult: BMKPOISearchResult!,
        errorCode: BMKSearchErrorCode
    ) {
        handleSearchResult(poiResult, errorCode: errorCode)
    }
}
#endif

extension WorldPanoramaDetailViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
        emptyLabel.isHidden = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showEmptyState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showEmptyState()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        didStartPanorama = false
        if let latitude = resolvedLatitude, let longitude = resolvedLongitude {
            loadPanorama(latitude: latitude, longitude: longitude)
        } else {
            showEmptyState()
        }
    }
}
