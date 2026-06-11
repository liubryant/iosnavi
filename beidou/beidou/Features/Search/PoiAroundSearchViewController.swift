//
//  PoiAroundSearchViewController.swift
//  beidou
//
//  周边搜索页 (对应 Android 周边POI列表)。
//  使用高德 SearchKit 周边搜索接口，列表展示距离当前位置的POI，
//  点击直接以驾车模式发起导航 (对应 Android 选中POI -> 跳转导航)。
//

import UIKit
import CoreLocation

#if canImport(AMapSearchKit)
import AMapSearchKit
#endif
#if canImport(AMapNaviKit)
import AMapNaviKit
#endif

final class PoiAroundSearchViewController: UIViewController {

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
    private var searchWorkItem: DispatchWorkItem?
    private var latestKeyword = ""

    #if canImport(AMapSearchKit)
    private let searchAPI = AMapSearchAPI()
    #endif

    init(location: CurrentLocation? = nil) {
        self.location = location
        super.init(nibName: nil, bundle: nil)
        self.title = "周边"
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

        searchBar.placeholder = "搜索周边 (餐饮/酒店/加油站...)"
        searchBar.delegate = self
        searchBar.translatesAutoresizingMaskIntoConstraints = false

        setupMapPreview()

        tableView.delegate = self
        tableView.dataSource = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "poi")
        tableView.keyboardDismissMode = .onDrag

        statusLabel.text = "正在搜索附近地点..."
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

        performSearch(keyword: "")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("PoiAroundSearchViewController")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("PoiAroundSearchViewController")
    }

    // MARK: - 数据

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

    /// 当前位置 (GCJ02)，无定位时退化为默认起点
    private func currentLocationPOI() -> SelectedPOI {
        if let location = location {
            return SelectedPOI(name: "我的位置", address: location.address, latitude: location.latitude, longitude: location.longitude)
        }
        if let cached = LocationManager.shared.lastKnownLocation {
            return SelectedPOI(name: "我的位置", address: cached.address, latitude: cached.latitude, longitude: cached.longitude)
        }
        return SelectedPOI(name: "我的位置", address: "", latitude: Constants.defaultStartLat, longitude: Constants.defaultStartLon)
    }

    private func performSearch(keyword: String) {
        latestKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        statusLabel.text = "正在搜索附近地点..."
        statusLabel.isHidden = false

        let center = currentLocationPOI()

        #if canImport(AMapSearchKit)
        let request = AMapPOIAroundSearchRequest()
        request.location = AMapGeoPoint.location(withLatitude: CGFloat(center.latitude), longitude: CGFloat(center.longitude))
        request.radius = 5000
        request.offset = 25
        request.page = 1
        request.sortrule = 0
        request.showFieldsType = .all
        if !latestKeyword.isEmpty {
            request.keywords = latestKeyword
        } else {
            request.types = "餐饮服务|购物服务|生活服务|汽车服务|风景名胜"
        }
        searchAPI?.aMapPOIAroundSearch(request)
        #else
        ApiClient.searchPOIAround(latitude: center.latitude, longitude: center.longitude, keyword: keyword) { [weak self] pois in
            self?.applyResults(pois)
        }
        #endif
    }

    private func applyResults(_ pois: [SelectedPOI]) {
        results = pois
        tableView.reloadData()
        statusLabel.text = pois.isEmpty ? "暂无周边搜索结果" : nil
        statusLabel.isHidden = !pois.isEmpty
    }

    private func distanceText(to poi: SelectedPOI) -> String {
        let center = currentLocationPOI()
        let from = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let to = CLLocation(latitude: poi.latitude, longitude: poi.longitude)
        let meters = from.distance(from: to)
        if meters >= 1000 {
            return String(format: "%.1fkm", meters / 1000)
        }
        return String(format: "%.0fm", meters)
    }
}

#if canImport(AMapSearchKit)
// MARK: - AMapSearchDelegate

extension PoiAroundSearchViewController: AMapSearchDelegate {
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
        let center = currentLocationPOI()
        ApiClient.searchPOIAround(latitude: center.latitude, longitude: center.longitude, keyword: latestKeyword) { [weak self] pois in
            self?.applyResults(pois)
        }
    }
}
#endif

#if canImport(AMapNaviKit)
// MARK: - MAMapViewDelegate

extension PoiAroundSearchViewController: MAMapViewDelegate {
    func mapView(_ mapView: MAMapView, viewFor annotation: MAAnnotation) -> MAAnnotationView? {
        guard annotation is MAPointAnnotation else { return nil }
        let identifier = "aroundCurrentLocation"
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

extension PoiAroundSearchViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchWorkItem?.cancel()
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

extension PoiAroundSearchViewController: UITableViewDataSource, UITableViewDelegate {
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
        cell.accessoryType = .disclosureIndicator
        cell.detailTextLabel?.text = distanceText(to: poi)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let poi = results[indexPath.row]
        navigationController?.pushViewController(
            NaviViewController(start: currentLocationPOI(), end: poi, mode: .drive),
            animated: true
        )
    }
}
