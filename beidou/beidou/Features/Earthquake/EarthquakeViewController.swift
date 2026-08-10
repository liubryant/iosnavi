//
//  EarthquakeViewController.swift
//  beidou
//
//  Mobile earthquake report page: map + latest earthquake list.
//

import UIKit
import MapKit

final class EarthquakeViewController: UIViewController {
    private struct FeatureCollection: Decodable {
        let features: [Feature]
    }

    private struct Feature: Decodable {
        let id: String
        let properties: Properties
        let geometry: Geometry
    }

    private struct Properties: Decodable {
        let mag: Double?
        let place: String?
        let time: Double
        let updated: Double?
        let url: String?
        let tsunami: Int?

        private enum CodingKeys: String, CodingKey {
            case mag, place, time, updated, url, tsunami
            case flynnRegion = "flynn_region"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mag = try? container.decode(Double.self, forKey: .mag)
            place = (try? container.decode(String.self, forKey: .place))
                ?? (try? container.decode(String.self, forKey: .flynnRegion))
            updated = try? container.decode(Double.self, forKey: .updated)
            url = try? container.decode(String.self, forKey: .url)
            tsunami = try? container.decode(Int.self, forKey: .tsunami)

            if let milliseconds = try? container.decode(Double.self, forKey: .time) {
                time = milliseconds
            } else {
                let value = try container.decode(String.self, forKey: .time)
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                guard let date = formatter.date(from: value) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .time,
                        in: container,
                        debugDescription: "Unsupported earthquake time"
                    )
                }
                time = date.timeIntervalSince1970 * 1_000
            }
        }
    }

    private struct Geometry: Decodable {
        let coordinates: [Double]
    }

    private final class EarthquakeAnnotation: NSObject, MKAnnotation {
        let feature: Feature
        let coordinate: CLLocationCoordinate2D
        var title: String? {
            String(format: "%.1f级地震", feature.properties.mag ?? 0)
        }
        var subtitle: String? {
            [
                feature.properties.place ?? "未知位置",
                EarthquakeViewController.dateFormatter.string(
                    from: Date(timeIntervalSince1970: feature.properties.time / 1_000)
                )
            ].joined(separator: " · ")
        }

        init(feature: Feature) {
            self.feature = feature
            let coordinates = feature.geometry.coordinates
            coordinate = CLLocationCoordinate2D(
                latitude: coordinates.count > 1 ? coordinates[1] : 0,
                longitude: coordinates.first ?? 0
            )
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private let mapView = MKMapView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let refreshControl = UIRefreshControl()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private var earthquakes: [Feature] = []
    private var dataTask: URLSessionDataTask?
    private var dataDescription = "实时数据"
    private var previousNavigationBarHidden = false

    private var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("earthquake-latest.geojson")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.t("home.earthquake_report")
        view.backgroundColor = .systemGroupedBackground
        setupViews()
        setupImmersiveHeader()
        loadEarthquakes(showLoading: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        previousNavigationBarHidden = navigationController?.isNavigationBarHidden ?? false
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(previousNavigationBarHidden, animated: animated)
    }

    deinit {
        dataTask?.cancel()
    }

    private func setupViews() {
        mapView.delegate = self
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.pointOfInterestFilter = .excludingAll
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: "earthquake"
        )
        mapView.translatesAutoresizingMaskIntoConstraints = false

        let initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30.5, longitude: 112),
            span: MKCoordinateSpan(latitudeDelta: 35, longitudeDelta: 45)
        )
        mapView.setRegion(initialRegion, animated: false)

        statusLabel.text = "正在获取最新地震…"
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 2

        loadingIndicator.startAnimating()
        let statusStack = UIStackView(arrangedSubviews: [statusLabel, loadingIndicator])
        statusStack.axis = .horizontal
        statusStack.alignment = .center
        statusStack.spacing = 8
        statusStack.isLayoutMarginsRelativeArrangement = true
        statusStack.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        statusStack.backgroundColor = .secondarySystemGroupedBackground
        statusStack.translatesAutoresizingMaskIntoConstraints = false

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 92
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 76, bottom: 0, right: 16)
        tableView.backgroundColor = .systemBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.refreshControl = refreshControl
        tableView.translatesAutoresizingMaskIntoConstraints = false
        refreshControl.addTarget(self, action: #selector(refreshEarthquakes), for: .valueChanged)

        view.addSubview(mapView)
        view.addSubview(statusStack)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.40),

            statusStack.topAnchor.constraint(equalTo: mapView.bottomAnchor),
            statusStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: statusStack.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupImmersiveHeader() {
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

        titleLabel.text = L10n.t("home.earthquake_report")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .black
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
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -64)
        ])
    }

    @objc private func tapBack() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func refreshEarthquakes() {
        loadEarthquakes(showLoading: false)
    }

    private func loadEarthquakes(showLoading: Bool) {
        dataTask?.cancel()
        if showLoading {
            loadingIndicator.startAnimating()
            statusLabel.text = "正在获取最新地震…"
        }

        requestSource(at: 0)
    }

    private func requestSource(at index: Int) {
        let sources = UrlConstants.earthquakeFeeds
        guard index < sources.count, let url = URL(string: sources[index]) else {
            loadCachedOrFallbackData()
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadRevalidatingCacheData

        dataTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard error == nil,
                      let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let data else {
                    self.requestSource(at: index + 1)
                    return
                }

                do {
                    try self.apply(data: data)
                    self.dataDescription = index == 0 ? "USGS 实时数据" : "EMSC 备用实时数据"
                    try? data.write(to: self.cacheURL ?? URL(fileURLWithPath: "/dev/null"), options: .atomic)
                    self.finishLoadingAndRender()
                } catch {
                    self.requestSource(at: index + 1)
                }
            }
        }
        dataTask?.resume()
    }

    private func apply(data: Data) throws {
        let collection = try JSONDecoder().decode(FeatureCollection.self, from: data)
        earthquakes = collection.features
            .filter { feature in
                let coordinates = feature.geometry.coordinates
                return coordinates.count >= 2 &&
                    CLLocationCoordinate2DIsValid(
                        CLLocationCoordinate2D(latitude: coordinates[1], longitude: coordinates[0])
                    )
            }
            .sorted { $0.properties.time > $1.properties.time }
        guard !earthquakes.isEmpty else {
            throw NSError(domain: "EarthquakeData", code: 1)
        }
    }

    private func loadCachedOrFallbackData() {
        if let cacheURL,
           let data = try? Data(contentsOf: cacheURL),
           (try? apply(data: data)) != nil {
            dataDescription = "本地缓存"
            finishLoadingAndRender()
            return
        }

        earthquakes = Self.offlineFallback
        dataDescription = "离线兜底数据"
        finishLoadingAndRender()
    }

    private func finishLoadingAndRender() {
        loadingIndicator.stopAnimating()
        refreshControl.endRefreshing()
        renderEarthquakes()
    }

    private func renderEarthquakes() {
        mapView.removeAnnotations(mapView.annotations)
        mapView.addAnnotations(earthquakes.map(EarthquakeAnnotation.init))
        tableView.reloadData()

        if earthquakes.isEmpty {
            statusLabel.text = "最近一周暂无地震记录"
        } else {
            let updateTime = Self.dateFormatter.string(from: Date())
            statusLabel.text = "\(dataDescription) · \(earthquakes.count) 条 · 更新于 \(updateTime)"
        }
    }

    private func showLoadFailure(_ message: String) {
        loadingIndicator.stopAnimating()
        refreshControl.endRefreshing()
        statusLabel.text = message
        if earthquakes.isEmpty {
            tableView.reloadData()
        }
    }

    private func magnitudeColor(_ magnitude: Double) -> UIColor {
        switch magnitude {
        case 6...: return .systemRed
        case 5..<6: return .systemOrange
        case 4..<5: return .systemYellow
        default: return .systemBlue
        }
    }

    private func focusMap(on feature: Feature) {
        let annotation = mapView.annotations
            .compactMap { $0 as? EarthquakeAnnotation }
            .first { $0.feature.id == feature.id }
        guard let annotation else { return }
        mapView.setRegion(
            MKCoordinateRegion(
                center: annotation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)
            ),
            animated: true
        )
        mapView.selectAnnotation(annotation, animated: true)
    }

    private static let offlineFallback: [Feature] = {
        let json = """
        {"features":[
          {"id":"offline-1","properties":{"mag":5.3,"place":"印度尼西亚巴布亚附近海域","time":1784891494234},"geometry":{"coordinates":[138.8612,-2.5436,10]}},
          {"id":"offline-2","properties":{"mag":4.2,"place":"斐济群岛附近海域","time":1784887777157},"geometry":{"coordinates":[-178.1299,-18.0389,602.3]}},
          {"id":"offline-3","properties":{"mag":4.8,"place":"印度洋中脊","time":1784880078375},"geometry":{"coordinates":[68.9337,-23.0953,10]}},
          {"id":"offline-4","properties":{"mag":4.3,"place":"秘鲁南部","time":1784878901602},"geometry":{"coordinates":[-69.6685,-17.6234,145.9]}},
          {"id":"offline-5","properties":{"mag":4.8,"place":"波多黎各北部海域","time":1784860956550},"geometry":{"coordinates":[-67.2968,18.9423,9]}}
        ]}
        """
        return (try? JSONDecoder().decode(FeatureCollection.self, from: Data(json.utf8)).features) ?? []
    }()
}

extension EarthquakeViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        earthquakes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let feature = earthquakes[indexPath.row]
        let magnitude = feature.properties.mag ?? 0

        var configuration = cell.defaultContentConfiguration()
        configuration.text = String(format: "%.1f级地震", magnitude)
        let detailLine = [
            Self.dateFormatter.string(from: Date(timeIntervalSince1970: feature.properties.time / 1_000)),
            feature.geometry.coordinates.count > 2
                ? String(format: "深度 %.1f km", abs(feature.geometry.coordinates[2]))
                : nil
        ].compactMap { $0 }.joined(separator: "  ·  ")
        configuration.secondaryText = [
            feature.properties.place ?? "未知位置",
            detailLine
        ].joined(separator: "\n")
        configuration.textProperties.font = .systemFont(ofSize: 15, weight: .semibold)
        configuration.secondaryTextProperties.font = .systemFont(ofSize: 13)
        configuration.secondaryTextProperties.color = .secondaryLabel
        configuration.secondaryTextProperties.numberOfLines = 2

        let badge = UILabel(frame: CGRect(x: 0, y: 0, width: 52, height: 52))
        badge.text = String(format: "%.1f", magnitude)
        badge.font = .systemFont(ofSize: 17, weight: .bold)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = magnitudeColor(magnitude)
        badge.layer.cornerRadius = 26
        badge.clipsToBounds = true
        configuration.image = badge.asImage()
        configuration.imageProperties.cornerRadius = 26
        configuration.imageToTextPadding = 12

        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        focusMap(on: earthquakes[indexPath.row])
    }
}

extension EarthquakeViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let earthquake = annotation as? EarthquakeAnnotation else { return nil }
        let view = mapView.dequeueReusableAnnotationView(
            withIdentifier: "earthquake",
            for: earthquake
        ) as? MKMarkerAnnotationView
        let magnitude = earthquake.feature.properties.mag ?? 0
        view?.markerTintColor = magnitudeColor(magnitude)
        view?.glyphText = String(format: "%.1f", magnitude)
        view?.canShowCallout = true
        return view
    }
}

private extension UIView {
    func asImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { context in
            layer.render(in: context.cgContext)
        }
    }
}
