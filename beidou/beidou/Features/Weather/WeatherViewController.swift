//
//  WeatherViewController.swift
//  beidou
//
//  天气查询页 (对应 Android WeatherSearchActivity)。
//  使用 WeatherKit 获取当前位置实时天气和预报。
//

import UIKit
import CoreLocation

#if canImport(WeatherKit)
import WeatherKit
#endif
#if canImport(AMapSearchKit)
import AMapSearchKit
#endif

final class WeatherViewController: UIViewController {

    private let location: CurrentLocation?

    private let backButton = UIButton(type: .system)
    private let cityLabel = UILabel()
    private let topWeatherIconView = UIImageView()
    private let weatherLabel = UILabel()
    private let weatherIconView = UIImageView()
    private let temperatureLabel = UILabel()
    private let windLabel = UILabel()
    private let humidityLabel = UILabel()
    private let reportTimeLabel = UILabel()
    private let forecastStack = UIStackView()
    private let feedAdContainer = UIView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var didLoadFeedAd = false
    #if canImport(AMapSearchKit)
    private let searchAPI = AMapSearchAPI()
    private var amapWeatherLocation: CurrentLocation?
    private var amapWeatherKitError: Error?
    private var amapWeatherCandidates: [String] = []
    private var amapWeatherErrors: [String] = []
    private var activeAmapWeatherCity: String?
    #endif
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMMdE")
        return formatter
    }()

    init(location: CurrentLocation? = nil) {
        self.location = location
        super.init(nibName: nil, bundle: nil)
        self.title = L10n.t("weather.title")
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
        view.backgroundColor = .systemGroupedBackground

        setupBackButton()

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        cityLabel.font = .boldSystemFont(ofSize: 24)
        cityLabel.textAlignment = .center
        cityLabel.text = location?.city ?? L10n.t("city.beijing")
        topWeatherIconView.contentMode = .scaleAspectFit
        topWeatherIconView.tintColor = .systemOrange
        topWeatherIconView.image = UIImage(systemName: "cloud.sun.fill")
        topWeatherIconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topWeatherIconView.widthAnchor.constraint(equalToConstant: 26),
            topWeatherIconView.heightAnchor.constraint(equalToConstant: 26)
        ])

        let cityRow = UIStackView(arrangedSubviews: [cityLabel, topWeatherIconView])
        cityRow.axis = .horizontal
        cityRow.alignment = .center
        cityRow.distribution = .equalCentering
        cityRow.spacing = 8

        let weatherRow = UIStackView(arrangedSubviews: [weatherLabel, weatherIconView])
        weatherRow.axis = .horizontal
        weatherRow.alignment = .center
        weatherRow.distribution = .equalCentering
        weatherRow.spacing = 8

        let liveCard = makeCard(arrangedSubviews: [weatherRow, temperatureLabel, windLabel, humidityLabel, reportTimeLabel])
        weatherLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        weatherLabel.textAlignment = .center
        weatherIconView.contentMode = .scaleAspectFit
        weatherIconView.tintColor = .systemOrange
        weatherIconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            weatherIconView.widthAnchor.constraint(equalToConstant: 30),
            weatherIconView.heightAnchor.constraint(equalToConstant: 30)
        ])
        temperatureLabel.font = .systemFont(ofSize: 40, weight: .bold)
        temperatureLabel.textAlignment = .center
        windLabel.font = .systemFont(ofSize: 15)
        windLabel.textColor = .secondaryLabel
        windLabel.textAlignment = .center
        humidityLabel.font = .systemFont(ofSize: 15)
        humidityLabel.textColor = .secondaryLabel
        humidityLabel.textAlignment = .center
        reportTimeLabel.font = .systemFont(ofSize: 12)
        reportTimeLabel.textColor = .tertiaryLabel
        reportTimeLabel.textAlignment = .center

        let forecastTitle = UILabel()
        forecastTitle.text = L10n.t("weather.forecast_title")
        forecastTitle.font = .boldSystemFont(ofSize: 16)

        forecastStack.axis = .vertical
        forecastStack.spacing = 0
        let forecastCard = makeCard(arrangedSubviews: [forecastStack])

        setupFeedAdContainer()

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()

        contentStack.addArrangedSubview(cityRow)
        contentStack.addArrangedSubview(liveCard)
        contentStack.addArrangedSubview(forecastTitle)
        contentStack.addArrangedSubview(forecastCard)
        contentStack.addArrangedSubview(feedAdContainer)

        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 62),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        loadWeather()
    }

    private func setupBackButton() {
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("WeatherViewController")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        loadFeedAdIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UMengAnalytics.shared.pageEnd("WeatherViewController")
    }

    private func makeCard(arrangedSubviews: [UIView]) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 12

        let stack = UIStackView(arrangedSubviews: arrangedSubviews)
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16)
        ])
        return card
    }

    private func setupFeedAdContainer() {
        feedAdContainer.translatesAutoresizingMaskIntoConstraints = false
        feedAdContainer.backgroundColor = .secondarySystemGroupedBackground
        feedAdContainer.isHidden = !Constants.isInlineTemplateAdEnabled
        feedAdContainer.heightAnchor.constraint(equalToConstant: Constants.isInlineTemplateAdEnabled ? 250 : 0).isActive = true
    }

    private func loadFeedAdIfNeeded() {
        guard Constants.isInlineTemplateAdEnabled, !didLoadFeedAd else { return }
        didLoadFeedAd = true
        guard feedAdContainer.window != nil else {
            didLoadFeedAd = false
            return
        }
        PangleFeedAdManager.shared.loadFeedAd(in: feedAdContainer, rootViewController: self)
    }

    // MARK: - 数据加载

    private func loadWeather() {
        let current = currentLocation()
        if loadAmapSearchKitWeather(location: current) {
            return
        }
        guard #available(iOS 16.0, *) else {
            loadAmapWeatherFallback(location: current)
            return
        }

        Task { [weak self] in
            await self?.loadWeatherKit(location: current)
        }
    }

    private func loadAmapSearchKitWeather(location: CurrentLocation, weatherKitError: Error? = nil) -> Bool {
        #if canImport(AMapSearchKit)
        amapWeatherLocation = location
        amapWeatherKitError = weatherKitError
        amapWeatherCandidates = weatherCityCandidates(for: location)
        amapWeatherErrors = []
        requestNextAmapSearchKitWeatherCandidate()
        return true
        #else
        return false
        #endif
    }

    #if canImport(AMapSearchKit)
    private func requestNextAmapSearchKitWeatherCandidate() {
        guard let city = amapWeatherCandidates.first else {
            if let location = amapWeatherLocation {
                loadAmapWeatherFallback(
                    location: location,
                    weatherKitError: amapWeatherKitError,
                    candidates: weatherCityCandidates(for: location),
                    errors: amapWeatherErrors
                )
            }
            return
        }
        activeAmapWeatherCity = city

        let liveRequest = AMapWeatherSearchRequest()
        liveRequest.city = city
        liveRequest.type = .live
        searchAPI?.aMapWeatherSearch(liveRequest)

        let forecastRequest = AMapWeatherSearchRequest()
        forecastRequest.city = city
        forecastRequest.type = .forecast
        searchAPI?.aMapWeatherSearch(forecastRequest)
    }

    private func retryNextAmapSearchKitWeatherCandidate(reason: String) {
        guard !amapWeatherCandidates.isEmpty else { return }
        let city = amapWeatherCandidates.removeFirst()
        amapWeatherErrors.append("\(city): \(reason)")
        requestNextAmapSearchKitWeatherCandidate()
    }
    #endif

    @available(iOS 16.0, *)
    private func loadWeatherKit(location: CurrentLocation) async {
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)

        do {
            let weather = try await WeatherService.shared.weather(for: clLocation)
            applyWeatherKit(weather, location: location)
        } catch {
            if !loadAmapSearchKitWeather(location: location, weatherKitError: error) {
                loadAmapWeatherFallback(location: location, weatherKitError: error)
            }
        }
    }

    private func loadAmapWeatherFallback(location: CurrentLocation, weatherKitError: Error? = nil) {
        loadAmapWeatherFallback(location: location, weatherKitError: weatherKitError, candidates: weatherCityCandidates(for: location), errors: [])
    }

    private func loadAmapWeatherFallback(location: CurrentLocation, weatherKitError: Error?, candidates: [String], errors: [String]) {
        guard let weatherCity = candidates.first else {
            activityIndicator.stopAnimating()
            weatherLabel.text = L10n.t("weather.fallback_failed")
            temperatureLabel.text = "--°"
            windLabel.text = L10n.t("weather.check_capability")
            humidityLabel.text = nil
            reportTimeLabel.text = nil
            showForecastMessage(weatherErrorMessage(weatherKitError: weatherKitError, amapError: errors.joined(separator: "\n")))
            return
        }

        ApiClient.fetchWeatherDetail(city: weatherCity) { [weak self] result in
            guard let self else { return }

            guard let live = (result.json?["lives"] as? [[String: Any]])?.first else {
                var nextErrors = errors
                if let errorMessage = result.errorMessage {
                    nextErrors.append("\(weatherCity): \(errorMessage)")
                } else {
                    nextErrors.append("\(weatherCity): \(L10n.t("weather.fallback_failed"))")
                }
                self.loadAmapWeatherFallback(
                    location: location,
                    weatherKitError: weatherKitError,
                    candidates: Array(candidates.dropFirst()),
                    errors: nextErrors
                )
                return
            }

            self.activityIndicator.stopAnimating()
            self.cityLabel.text = (live["city"] as? String)?.isEmpty == false ? (live["city"] as? String) : location.city
            let weather = live["weather"] as? String ?? L10n.t("weather.title")
            self.setWeatherText(weather)

            if let temperature = live["temperature"] as? String, !temperature.isEmpty {
                self.temperatureLabel.text = "\(temperature)°"
            } else {
                self.temperatureLabel.text = "--°"
            }

            let windDirection = live["winddirection"] as? String ?? ""
            let windPower = live["windpower"] as? String ?? ""
            self.windLabel.text = [windDirection, windPower].filter { !$0.isEmpty }.joined(separator: " ")
            if self.windLabel.text?.isEmpty != false {
                self.windLabel.text = nil
            }

            if let humidity = live["humidity"] as? String, !humidity.isEmpty {
                self.humidityLabel.text = L10n.f("weather.humidity", humidity)
            } else {
                self.humidityLabel.text = nil
            }

            if let reportTime = live["reporttime"] as? String, !reportTime.isEmpty {
                self.reportTimeLabel.text = L10n.f("weather.updated", reportTime)
            } else {
                self.reportTimeLabel.text = nil
            }

            self.showForecastMessage(L10n.t("weather.no_forecast"))
        }
    }

    private func weatherCityCandidates(for location: CurrentLocation) -> [String] {
        [
            cityLevelAdcode(from: location.adcode),
            location.adcode,
            location.city,
            Constants.city,
            "110000"
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .reduce(into: [String]()) { result, value in
            if !result.contains(value) {
                result.append(value)
            }
        }
    }

    private func cityLevelAdcode(from adcode: String?) -> String? {
        guard let adcode = adcode?.trimmingCharacters(in: .whitespacesAndNewlines),
              adcode.count == 6,
              adcode.allSatisfy(\.isNumber) else {
            return nil
        }

        let provincePrefix = String(adcode.prefix(2))
        if ["11", "12", "31", "50"].contains(provincePrefix) {
            return "\(provincePrefix)0000"
        }

        let cityPrefix = String(adcode.prefix(4))
        return "\(cityPrefix)00"
    }

    private func weatherErrorMessage(weatherKitError: Error?, amapError: String?) -> String {
        let messages = [
            weatherKitError.map { L10n.f("weather.weatherkit_error", $0.localizedDescription) },
            amapError.map { L10n.f("weather.amap_error", $0) }
        ].compactMap { $0 }
        return messages.isEmpty ? L10n.t("weather.no_forecast") : messages.joined(separator: "\n")
    }

    private func setWeatherText(_ text: String) {
        weatherLabel.text = text
        let icon = weatherIcon(for: text)
        weatherIconView.image = UIImage(systemName: icon.name)
        weatherIconView.tintColor = icon.color
        topWeatherIconView.image = UIImage(systemName: icon.name)
        topWeatherIconView.tintColor = icon.color
        weatherIconView.isHidden = text.isEmpty
        topWeatherIconView.isHidden = text.isEmpty
    }

    private func weatherIcon(for weather: String) -> (name: String, color: UIColor) {
        let value = weather.lowercased()

        if value.contains("暴雨") || value.contains("大暴雨") || value.contains("特大暴雨") || value.contains("heavy rain") {
            return ("cloud.heavyrain.fill", .systemBlue)
        }
        if value.contains("大雨") || value.contains("中雨") || value.contains("阵雨") || value.contains("雨") || value.contains("rain") {
            return ("cloud.rain.fill", .systemBlue)
        }
        if value.contains("雷") || value.contains("thunder") || value.contains("storm") {
            return ("cloud.bolt.rain.fill", .systemYellow)
        }
        if value.contains("雪") || value.contains("snow") {
            return ("cloud.snow.fill", .systemTeal)
        }
        if value.contains("雾") || value.contains("霾") || value.contains("沙") || value.contains("尘") || value.contains("fog") || value.contains("haze") {
            return ("cloud.fog.fill", .systemGray)
        }
        if value.contains("阴") || value.contains("cloudy") {
            return ("cloud.fill", .systemGray)
        }
        if value.contains("多云") || value.contains("少云") || value.contains("partly") {
            return ("cloud.sun.fill", .systemOrange)
        }
        if value.contains("晴") || value.contains("clear") || value.contains("sun") {
            return ("sun.max.fill", .systemYellow)
        }

        return ("cloud.sun.fill", .systemOrange)
    }

    #if canImport(AMapSearchKit)
    private func applyAmapLiveWeather(_ live: AMapLocalWeatherLive, location: CurrentLocation) {
        let city = live.city ?? ""
        let weather = live.weather ?? ""
        let temperature = live.temperature ?? ""
        let windDirection = live.windDirection ?? ""
        let windPower = live.windPower ?? ""
        let humidity = live.humidity ?? ""
        let reportTime = live.reportTime ?? ""

        activityIndicator.stopAnimating()
        cityLabel.text = city.isEmpty ? location.city : city
        setWeatherText(weather.isEmpty ? L10n.t("weather.title") : weather)
        temperatureLabel.text = temperature.isEmpty ? "--°" : "\(temperature)°"

        windLabel.text = [windDirection, windPower].filter { !$0.isEmpty }.joined(separator: " ")
        if windLabel.text?.isEmpty != false {
            windLabel.text = nil
        }

        humidityLabel.text = humidity.isEmpty ? nil : L10n.f("weather.humidity", humidity)
        reportTimeLabel.text = reportTime.isEmpty ? nil : L10n.f("weather.updated", reportTime)
    }

    private func applyAmapForecast(_ forecast: AMapLocalWeatherForecast) {
        forecastStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let casts = Array((forecast.casts ?? []).prefix(4))
        guard !casts.isEmpty else {
            showForecastMessage(L10n.t("weather.no_forecast"))
            return
        }

        for (index, day) in casts.enumerated() {
            let dayWeather = day.dayWeather ?? ""
            let nightWeather = day.nightWeather ?? ""
            let weather = dayWeather.isEmpty ? nightWeather : dayWeather
            let dayTemp = day.dayTemp ?? "--"
            let nightTemp = day.nightTemp ?? "--"
            let row = makeForecastRow(date: day.date ?? "", weather: weather, temperature: "\(nightTemp)° / \(dayTemp)°")
            forecastStack.addArrangedSubview(row)

            if index < casts.count - 1 {
                forecastStack.addArrangedSubview(makeForecastDivider())
            }
        }
    }
    #endif

    private func currentLocation() -> CurrentLocation {
        if let location {
            return location
        }
        if let cached = LocationManager.shared.lastKnownLocation {
            return cached
        }
        return CurrentLocation(
            latitude: Constants.defaultStartLat,
            longitude: Constants.defaultStartLon,
            city: L10n.t("city.beijing"),
            adcode: "110000",
            address: ""
        )
    }

    @available(iOS 16.0, *)
    private func applyWeatherKit(_ weather: Weather, location: CurrentLocation) {
        activityIndicator.stopAnimating()
        cityLabel.text = location.city

        let current = weather.currentWeather
        setWeatherText(current.condition.description)
        temperatureLabel.text = "\(Int(current.temperature.converted(to: .celsius).value.rounded()))°"
        windLabel.text = L10n.f("weather.wind", "\(Int(current.wind.speed.converted(to: .kilometersPerHour).value.rounded()))")
        humidityLabel.text = L10n.f("weather.humidity", "\(Int((current.humidity * 100).rounded()))")
        reportTimeLabel.text = L10n.f("weather.updated", formatReportDate(current.date))

        forecastStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let dailyForecasts = Array(weather.dailyForecast.forecast.prefix(7))
        guard !dailyForecasts.isEmpty else {
            showForecastMessage(L10n.t("weather.no_forecast"))
            return
        }

        for (index, day) in dailyForecasts.enumerated() {
            let row = makeForecastRow(
                date: dateFormatter.string(from: day.date),
                weather: day.condition.description,
                temperature: "\(Int(day.lowTemperature.converted(to: .celsius).value.rounded()))° / \(Int(day.highTemperature.converted(to: .celsius).value.rounded()))°"
            )
            forecastStack.addArrangedSubview(row)

            if index < dailyForecasts.count - 1 {
                forecastStack.addArrangedSubview(makeForecastDivider())
            }
        }
    }

    private func makeForecastRow(date: String, weather: String, temperature: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let dateLabel = UILabel()
        dateLabel.font = .systemFont(ofSize: 14)
        dateLabel.text = date
        dateLabel.widthAnchor.constraint(equalToConstant: 110).isActive = true

        let weatherLabel = UILabel()
        weatherLabel.font = .systemFont(ofSize: 14)
        weatherLabel.textColor = .secondaryLabel
        weatherLabel.text = weather

        let tempLabel = UILabel()
        tempLabel.font = .systemFont(ofSize: 14)
        tempLabel.textAlignment = .right
        tempLabel.text = temperature

        row.addArrangedSubview(dateLabel)
        row.addArrangedSubview(weatherLabel)
        row.addArrangedSubview(tempLabel)
        row.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return row
    }

    private func makeForecastDivider() -> UIView {
        let divider = UIView()
        divider.backgroundColor = .separator
        divider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return divider
    }

    private func showForecastMessage(_ text: String) {
        forecastStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        forecastStack.addArrangedSubview(label)
    }

    private func formatReportDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @objc private func tapBack() {
        navigationController?.popViewController(animated: true)
    }
}

#if canImport(AMapSearchKit)
extension WeatherViewController: AMapSearchDelegate {
    func onWeatherSearchDone(_ request: AMapWeatherSearchRequest, response: AMapWeatherSearchResponse) {
        guard request.city == activeAmapWeatherCity,
              let location = amapWeatherLocation else {
            return
        }

        switch request.type {
        case .live:
            guard let live = response.lives.first else {
                retryNextAmapSearchKitWeatherCandidate(reason: L10n.t("weather.fallback_failed"))
                return
            }
            applyAmapLiveWeather(live, location: location)
        case .forecast:
            if let forecast = response.forecasts.first {
                applyAmapForecast(forecast)
            }
        @unknown default:
            break
        }
    }

    func aMapSearchRequest(_ request: Any, didFailWithError error: Error) {
        guard let weatherRequest = request as? AMapWeatherSearchRequest,
              weatherRequest.city == activeAmapWeatherCity else {
            return
        }

        if weatherRequest.type == .live {
            retryNextAmapSearchKitWeatherCandidate(reason: error.localizedDescription)
        } else if forecastStack.arrangedSubviews.isEmpty {
            showForecastMessage(L10n.t("weather.no_forecast"))
        }
    }
}
#endif
