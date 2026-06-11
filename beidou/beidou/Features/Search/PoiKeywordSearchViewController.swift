//
//  PoiKeywordSearchViewController.swift
//  beidou
//
//  关键字POI搜索 (对应 Android 路线规划"输入终点"联想)。
//  使用高德 Web服务 关键字搜索接口，选中后通过 onSelect 回调返回。
//

import UIKit
import CoreLocation

#if canImport(AMapSearchKit)
import AMapSearchKit
#endif
#if canImport(AMapNaviKit)
import AMapNaviKit
#endif

final class PoiKeywordSearchViewController: UIViewController {

    var onSelect: ((SelectedPOI) -> Void)?

    private let city: String
    private let location: CurrentLocation?
    private let searchBar = UISearchBar()
    #if canImport(AMapNaviKit)
    private let mapView = MAMapView()
    #else
    private let mapView = UIView()
    #endif
    private let tableView = UITableView()
    private let statusLabel = UILabel()
    private var results: [SelectedPOI] = []
    private var isShowingHistory = false
    private var searchWorkItem: DispatchWorkItem?
    private var latestKeyword = ""

    #if canImport(AMapSearchKit)
    private let searchAPI = AMapSearchAPI()
    #endif

    init(city: String, location: CurrentLocation? = nil) {
        self.city = city
        self.location = location
        super.init(nibName: nil, bundle: nil)
        self.title = "搜索目的地"
        #if canImport(AMapSearchKit)
        searchAPI?.delegate = self
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        searchBar.placeholder = "输入终点名称/地址"
        searchBar.delegate = self
        searchBar.translatesAutoresizingMaskIntoConstraints = false

        setupMapPreview()

        tableView.delegate = self
        tableView.dataSource = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "poi")
        tableView.keyboardDismissMode = .onDrag

        statusLabel.text = "暂无历史记录"
        statusLabel.textColor = .secondaryLabel
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(searchBar)
        view.addSubview(mapView)
        view.addSubview(tableView)
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            mapView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.heightAnchor.constraint(equalToConstant: 190),

            tableView.topAnchor.constraint(equalTo: mapView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            statusLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: tableView.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: tableView.trailingAnchor, constant: -24)
        ])
        showHistory()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchBar.becomeFirstResponder()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("PoiKeywordSearchViewController")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("PoiKeywordSearchViewController")
    }

    private func setupMapPreview() {
        mapView.translatesAutoresizingMaskIntoConstraints = false

        #if canImport(AMapNaviKit)
        mapView.delegate = self
        mapView.mapType = .standard
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.zoomLevel = 16

        let center = currentLocationPOI()
        let gcj02 = CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
        mapView.setCenter(gcj02, animated: false)

        let annotation = MAPointAnnotation()
        annotation.coordinate = gcj02
        annotation.title = center.name
        annotation.subtitle = center.address
        mapView.addAnnotation(annotation)
        #else
        mapView.backgroundColor = .systemGray5
        let label = UILabel()
        label.text = "当前位置"
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: mapView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: mapView.centerYAnchor)
        ])
        #endif
    }

    private func currentLocationPOI() -> SelectedPOI {
        if let location {
            return SelectedPOI(name: "我的位置", address: location.address, latitude: location.latitude, longitude: location.longitude)
        }
        if let cached = LocationManager.shared.lastKnownLocation {
            return SelectedPOI(name: "我的位置", address: cached.address, latitude: cached.latitude, longitude: cached.longitude)
        }
        return SelectedPOI(name: "我的位置", address: "", latitude: Constants.defaultStartLat, longitude: Constants.defaultStartLon)
    }

    private func performSearch(keyword: String) {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        latestKeyword = trimmedKeyword
        guard !trimmedKeyword.isEmpty else {
            showHistory()
            return
        }
        isShowingHistory = false
        statusLabel.text = "正在搜索目的地..."
        statusLabel.isHidden = false

        #if canImport(AMapSearchKit)
        let request = AMapPOIKeywordsSearchRequest()
        request.keywords = trimmedKeyword
        request.city = city
        request.cityLimit = false
        request.offset = 20
        request.page = 1
        request.sortrule = 1
        request.location = AMapGeoPoint.location(
            withLatitude: CGFloat(currentLocationPOI().latitude),
            longitude: CGFloat(currentLocationPOI().longitude)
        )
        request.showFieldsType = .all
        searchAPI?.aMapPOIKeywordsSearch(request)
        #else
        ApiClient.searchPOI(keyword: keyword, city: city) { [weak self] pois in
            self?.applyResults(pois)
        }
        #endif
    }

    private func applyResults(_ pois: [SelectedPOI]) {
        isShowingHistory = false
        results = pois
        tableView.reloadData()
        statusLabel.text = pois.isEmpty ? (latestKeyword.isEmpty ? "输入终点名称或地址" : "暂无搜索结果") : nil
        statusLabel.isHidden = !pois.isEmpty
    }

    private func showHistory() {
        latestKeyword = ""
        isShowingHistory = true
        results = POIHistoryStore.load()
        tableView.reloadData()
        statusLabel.text = results.isEmpty ? "暂无历史记录" : nil
        statusLabel.isHidden = !results.isEmpty
    }
}

#if canImport(AMapSearchKit)
// MARK: - AMapSearchDelegate

extension PoiKeywordSearchViewController: AMapSearchDelegate {
    func onPOISearchDone(_ request: AMapPOISearchBaseRequest, response: AMapPOISearchResponse) {
        let pois = response.pois.compactMap { poi -> SelectedPOI? in
            guard let name = poi.name, !name.isEmpty, let location = poi.location else { return nil }
            let address = poi.address?.isEmpty == false ? (poi.address ?? "") : (poi.type ?? "")
            return SelectedPOI(
                name: name,
                address: address,
                latitude: Double(location.latitude),
                longitude: Double(location.longitude)
            )
        }
        applyResults(pois)
    }

    func aMapSearchRequest(_ request: Any, didFailWithError error: Error) {
        ApiClient.searchPOI(keyword: latestKeyword, city: city) { [weak self] pois in
            self?.applyResults(pois)
        }
    }
}
#endif

#if canImport(AMapNaviKit)
// MARK: - MAMapViewDelegate

extension PoiKeywordSearchViewController: MAMapViewDelegate {
    func mapView(_ mapView: MAMapView, viewFor annotation: MAAnnotation) -> MAAnnotationView? {
        guard annotation is MAPointAnnotation else { return nil }
        let identifier = "keywordCurrentLocation"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MAPinAnnotationView
        if annotationView == nil {
            annotationView = MAPinAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        } else {
            annotationView?.annotation = annotation
        }
        annotationView?.canShowCallout = true
        return annotationView
    }
}
#endif

// MARK: - UISearchBarDelegate

extension PoiKeywordSearchViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchWorkItem?.cancel()
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showHistory()
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.performSearch(keyword: searchText)
        }
        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        performSearch(keyword: searchBar.text ?? "")
    }
}

// MARK: - UITableViewDataSource / Delegate

extension PoiKeywordSearchViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        isShowingHistory && !results.isEmpty ? "历史记录" : nil
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "poi", for: indexPath)
        let poi = results[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = poi.name
        config.secondaryText = poi.address
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let poi = results[indexPath.row]
        onSelect?(poi)
        navigationController?.popViewController(animated: true)
    }
}
