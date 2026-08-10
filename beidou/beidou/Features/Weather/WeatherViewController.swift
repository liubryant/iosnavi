//
//  WeatherViewController.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  天气查询页 (对应 Android WeatherSearchActivity)。
//  使用高德天气搜索接口获取当前位置实时天气和预报。
//

import UIKit
import CoreLocation

#if canImport(AMapSearchKit)
import AMapSearchKit
#endif

final class WeatherViewController: UIViewController {

    private let location: CurrentLocation?

    private let backgroundView = WeatherAnimatedBackgroundView()
    private let backButton = UIButton(type: .system)
    private let cityLabel = UILabel()
    private let topWeatherInfoStack = UIStackView()
    private let topWeatherIconView = UIImageView()
    private let altitudeLabel = UILabel()
    private let weatherLabel = UILabel()
    private let weatherIconView = UIImageView()
    private let temperatureLabel = UILabel()
    private let windLabel = UILabel()
    private let humidityLabel = UILabel()
    private let reportTimeLabel = UILabel()
    private let sunsetScoreLabel = UILabel()
    private let sunsetStrengthChartView = SunsetStrengthChartView()
    private let sunsetFactorStack = UIStackView()
    private let sunsetTimeLabel = UILabel()
    private let sunsetCloudLabel = UILabel()
    private let sunsetMetricsLabel = UILabel()
    private let forecastStack = UIStackView()
    private let feedAdContainer = UIView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var didLoadFeedAd = false
    #if canImport(AMapSearchKit)
    private let searchAPI = AMapSearchAPI()
    private var amapWeatherLocation: CurrentLocation?
    private var amapWeatherCandidates: [String] = []
    private var amapWeatherErrors: [String] = []
    private var activeAmapWeatherCity: String?
    #endif

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
        view.backgroundColor = UIColor(red: 0.92, green: 0.97, blue: 1.0, alpha: 1.0)

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundView)

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .clear
        scrollView.contentInset.bottom = 40
        scrollView.verticalScrollIndicatorInsets.bottom = 40

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        cityLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        cityLabel.textAlignment = .center
        cityLabel.text = location?.city ?? L10n.t("city.beijing")
        cityLabel.translatesAutoresizingMaskIntoConstraints = false
        topWeatherIconView.contentMode = .scaleAspectFit
        topWeatherIconView.tintColor = .systemOrange
        topWeatherIconView.image = UIImage(systemName: "cloud.sun.fill")
        topWeatherIconView.translatesAutoresizingMaskIntoConstraints = false
        altitudeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        altitudeLabel.textColor = .secondaryLabel
        altitudeLabel.textAlignment = .right
        altitudeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        altitudeLabel.translatesAutoresizingMaskIntoConstraints = false
        topWeatherInfoStack.axis = .horizontal
        topWeatherInfoStack.alignment = .center
        topWeatherInfoStack.spacing = 5
        topWeatherInfoStack.translatesAutoresizingMaskIntoConstraints = false
        topWeatherInfoStack.addArrangedSubview(topWeatherIconView)
        topWeatherInfoStack.addArrangedSubview(altitudeLabel)

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

        let sunsetTitle = UILabel()
        sunsetTitle.text = L10n.t("weather.sunset_title")
        sunsetTitle.font = .boldSystemFont(ofSize: 16)
        let sunsetCard = makeSunsetPredictionCard()

        forecastStack.axis = .vertical
        forecastStack.spacing = 0
        let forecastCard = makeCard(arrangedSubviews: [forecastStack])

        setupFeedAdContainer()

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()

        contentStack.addArrangedSubview(liveCard)
        contentStack.addArrangedSubview(sunsetTitle)
        contentStack.addArrangedSubview(sunsetCard)
        contentStack.addArrangedSubview(forecastTitle)
        contentStack.addArrangedSubview(forecastCard)
        contentStack.addArrangedSubview(feedAdContainer)

        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 62),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -56),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        setupBackButton()
        setupCityHeader()
        showSunsetPredictionLoading()

        loadWeather()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        applyTopTitleStyle()
    }

    private func setupCityHeader() {
        view.addSubview(cityLabel)
        view.addSubview(topWeatherInfoStack)
        NSLayoutConstraint.activate([
            cityLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            cityLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cityLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8),
            cityLabel.trailingAnchor.constraint(lessThanOrEqualTo: topWeatherInfoStack.leadingAnchor, constant: -8),

            topWeatherInfoStack.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            topWeatherInfoStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            topWeatherIconView.widthAnchor.constraint(equalToConstant: 26),
            topWeatherIconView.heightAnchor.constraint(equalToConstant: 26)
        ])
        applyTopTitleStyle()
    }

    private func applyTopTitleStyle() {
        cityLabel.textColor = traitCollection.userInterfaceStyle == .dark ? .black : .label
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
        card.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.62)
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 0.5
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.7).cgColor

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
        feedAdContainer.layer.cornerRadius = 12
        feedAdContainer.layer.cornerCurve = .continuous
        feedAdContainer.clipsToBounds = true
        feedAdContainer.isHidden = !Constants.isInlineTemplateAdEnabled
        feedAdContainer.heightAnchor.constraint(equalToConstant: Constants.isInlineTemplateAdEnabled ? 250 : 0).isActive = true
    }

    private func makeSunsetPredictionCard() -> UIView {
        sunsetScoreLabel.font = .systemFont(ofSize: 34, weight: .bold)
        sunsetScoreLabel.textAlignment = .center

        sunsetStrengthChartView.translatesAutoresizingMaskIntoConstraints = false
        sunsetStrengthChartView.heightAnchor.constraint(equalToConstant: 96).isActive = true

        sunsetFactorStack.axis = .vertical
        sunsetFactorStack.spacing = 8

        [sunsetTimeLabel, sunsetCloudLabel, sunsetMetricsLabel].forEach { label in
            label.font = .systemFont(ofSize: 14)
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            label.numberOfLines = 0
        }

        return makeCard(arrangedSubviews: [
            sunsetScoreLabel,
            sunsetStrengthChartView,
            sunsetTimeLabel,
            sunsetCloudLabel,
            sunsetMetricsLabel,
            sunsetFactorStack
        ])
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
        updateAltitudeLabel(for: current)
        loadSunsetPrediction(location: current)
        if !loadAmapSearchKitWeather(location: current) {
            loadAmapWeatherFallback(location: current)
        }
    }

    private func loadSunsetPrediction(location: CurrentLocation) {
        if let cached = cachedSunsetPredictions(), !cached.isEmpty {
            applySunsetPredictions(cached)
        } else {
            showSunsetPredictionLoading()
        }

        ApiClient.fetchSunsetPredictions(latitude: location.latitude, longitude: location.longitude) { [weak self] predictions in
            guard let self else { return }
            guard !predictions.isEmpty else {
                if self.cachedSunsetPredictions()?.isEmpty != false {
                    self.showSunsetPredictionFailed()
                }
                return
            }
            self.cacheSunsetPredictions(predictions)
            self.applySunsetPredictions(predictions)
        }
    }

    private func cachedSunsetPredictions() -> [ApiClient.SunsetPrediction]? {
        guard let data = SpUtil.data(.sunsetPredictionCache) else { return nil }
        return try? JSONDecoder().decode([ApiClient.SunsetPrediction].self, from: data)
    }

    private func cacheSunsetPredictions(_ predictions: [ApiClient.SunsetPrediction]) {
        guard let data = try? JSONEncoder().encode(predictions) else { return }
        SpUtil.setData(data, for: .sunsetPredictionCache)
    }

    private func loadAmapSearchKitWeather(location: CurrentLocation) -> Bool {
        #if canImport(AMapSearchKit)
        amapWeatherLocation = location
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

    private func loadAmapWeatherFallback(location: CurrentLocation) {
        loadAmapWeatherFallback(location: location, candidates: weatherCityCandidates(for: location), errors: [])
    }

    private func loadAmapWeatherFallback(location: CurrentLocation, candidates: [String], errors: [String]) {
        guard let weatherCity = candidates.first else {
            activityIndicator.stopAnimating()
            weatherLabel.text = L10n.t("weather.fallback_failed")
            temperatureLabel.text = "--°"
            windLabel.text = L10n.t("weather.check_capability")
            humidityLabel.text = nil
            reportTimeLabel.text = nil
            showForecastMessage(weatherErrorMessage(amapError: errors.joined(separator: "\n")))
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
                    candidates: Array(candidates.dropFirst()),
                    errors: nextErrors
                )
                return
            }

            self.activityIndicator.stopAnimating()
            self.cityLabel.text = (live["city"] as? String)?.isEmpty == false ? (live["city"] as? String) : location.city
            self.updateAltitudeLabel(for: location)
            let weather = live["weather"] as? String ?? L10n.t("weather.title")
            self.setWeatherText(weather)

            if let temperature = live["temperature"] as? String, !temperature.isEmpty {
                self.temperatureLabel.text = "\(temperature)°"
            } else {
                self.temperatureLabel.text = "--°"
            }
            self.cacheLiveWeather(weather: weather, temperature: live["temperature"] as? String ?? "")

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

    private func weatherErrorMessage(amapError: String?) -> String {
        let messages = [
            amapError.map { L10n.f("weather.amap_error", $0) }
        ].compactMap { $0 }
        return messages.isEmpty ? L10n.t("weather.no_forecast") : messages.joined(separator: "\n")
    }

    private func showSunsetPredictionLoading() {
        sunsetScoreLabel.text = "--%"
        sunsetScoreLabel.textColor = .secondaryLabel
        sunsetStrengthChartView.predictions = []
        sunsetTimeLabel.text = L10n.t("weather.sunset_loading")
        sunsetCloudLabel.text = nil
        sunsetMetricsLabel.text = nil
        sunsetFactorStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    private func showSunsetPredictionFailed() {
        sunsetScoreLabel.text = "--%"
        sunsetScoreLabel.textColor = .secondaryLabel
        sunsetStrengthChartView.predictions = []
        sunsetTimeLabel.text = L10n.t("weather.sunset_failed")
        sunsetCloudLabel.text = nil
        sunsetMetricsLabel.text = nil
        sunsetFactorStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    private func applySunsetPredictions(_ predictions: [ApiClient.SunsetPrediction]) {
        guard let prediction = predictions.first else { return }
        let color = sunsetColor(for: prediction.quality)
        sunsetScoreLabel.text = L10n.f("weather.sunset_score_format", "\(prediction.percentage)", sunsetQualityLabel(for: prediction.quality))
        sunsetScoreLabel.textColor = color
        sunsetStrengthChartView.predictions = predictions

        let timeParts = [
            prediction.sunsetTime.isEmpty ? nil : L10n.f("weather.sunset_time", prediction.sunsetTime),
            prediction.goldenHour.isEmpty ? nil : L10n.f("weather.sunset_golden_hour", prediction.goldenHour)
        ].compactMap { $0 }
        sunsetTimeLabel.text = timeParts.joined(separator: "  ")
        sunsetCloudLabel.text = "\(prediction.modelName) · \(prediction.cloudDescription)"

        let metrics = [
            L10n.f("weather.sunset_vividness", "\(prediction.vividnessPercentage)"),
            L10n.f("weather.sunset_aerosol_proxy", "\(prediction.aerosolProxyPercentage)"),
            prediction.cloudCover.map { L10n.f("weather.sunset_cloud_cover", "\($0)") },
            prediction.visibilityKm.map { L10n.f("weather.sunset_visibility", String(format: "%.1f", $0)) },
            prediction.humidity.map { L10n.f("weather.sunset_humidity", "\($0)") },
            L10n.f("weather.sunset_rain", "\(prediction.rainProbability)"),
            L10n.f("weather.sunset_confidence", "\(Int((prediction.confidence * 100).rounded()))")
        ].compactMap { $0 }
        sunsetMetricsLabel.text = metrics.joined(separator: "  ")

        sunsetFactorStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        prediction.factors.forEach { factor in
            sunsetFactorStack.addArrangedSubview(makeSunsetFactorRow(factor, prediction: prediction))
        }
    }

    private func makeSunsetFactorRow(_ factor: ApiClient.SunsetPrediction.Factor, prediction: ApiClient.SunsetPrediction) -> UIView {
        let row = UIStackView()
        row.axis = .vertical
        row.spacing = 3

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.text = factor.title

        let valueLabel = UILabel()
        valueLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        valueLabel.textAlignment = .right
        let displayValue = displayValue(for: factor, prediction: prediction)
        valueLabel.textColor = sunsetColor(for: displayValue)
        valueLabel.text = "\(Int((displayValue * 100).rounded()))%"

        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(valueLabel)

        let bar = GradientMeterView()
        bar.value = displayValue
        bar.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let detailLabel = UILabel()
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .tertiaryLabel
        detailLabel.numberOfLines = 0
        detailLabel.text = factor.detail

        row.addArrangedSubview(header)
        row.addArrangedSubview(bar)
        row.addArrangedSubview(detailLabel)
        return row
    }

    private func displayValue(for factor: ApiClient.SunsetPrediction.Factor, prediction: ApiClient.SunsetPrediction) -> Double {
        if factor.title == L10n.t("weather.sunset_factor_rain") {
            return min(1.0, max(0.0, 1.0 - Double(prediction.rainProbability) / 100.0))
        }
        return factor.value
    }

    private func sunsetQualityLabel(for quality: Double) -> String {
        if quality >= 0.75 {
            return L10n.t("weather.sunset_quality_excellent")
        }
        if quality >= 0.65 {
            return L10n.t("weather.sunset_quality_good")
        }
        if quality >= 0.50 {
            return L10n.t("weather.sunset_quality_ok")
        }
        if quality >= 0.35 {
            return L10n.t("weather.sunset_quality_fair")
        }
        if quality >= 0.20 {
            return L10n.t("weather.sunset_quality_weak")
        }
        return L10n.t("weather.sunset_quality_poor")
    }

    private func sunsetColor(for quality: Double) -> UIColor {
        if quality >= 0.75 {
            return .systemRed
        }
        if quality >= 0.50 {
            return .systemOrange
        }
        if quality >= 0.35 {
            return .systemYellow
        }
        return .systemGray
    }

    private func setWeatherText(_ text: String) {
        weatherLabel.text = text
        let icon = weatherIcon(for: text)
        weatherIconView.image = UIImage(systemName: icon.name)
        weatherIconView.tintColor = icon.color
        topWeatherIconView.image = UIImage(systemName: icon.name)
        topWeatherIconView.tintColor = icon.color
        backgroundView.apply(scene: weatherScene(for: text))
        weatherIconView.isHidden = text.isEmpty
        topWeatherIconView.isHidden = text.isEmpty
    }

    private func cacheLiveWeather(weather: String, temperature: String) {
        SpUtil.setString(weather, for: .lastLiveWeather)
        SpUtil.setString(temperature, for: .lastLiveTemperature)
    }

    private func updateAltitudeLabel(for location: CurrentLocation) {
        guard let altitude = location.altitude else {
            altitudeLabel.text = nil
            altitudeLabel.isHidden = true
            return
        }
        let value = L10n.f("home.altitude_value_format", altitude)
        altitudeLabel.text = L10n.f("weather.altitude_format", value)
        altitudeLabel.isHidden = false
    }

    private func weatherScene(for weather: String) -> WeatherAnimatedBackgroundView.Scene {
        let value = weather.lowercased()

        if value.contains("暴雨") || value.contains("大暴雨") || value.contains("特大暴雨") || value.contains("heavy rain") {
            return .heavyRain
        }
        if value.contains("大雨") || value.contains("中雨") || value.contains("阵雨") || value.contains("雨") || value.contains("rain") {
            return .rain
        }
        if value.contains("雷") || value.contains("thunder") || value.contains("storm") {
            return .storm
        }
        if value.contains("雪") || value.contains("snow") {
            return .snow
        }
        if value.contains("雾") || value.contains("霾") || value.contains("沙") || value.contains("尘") || value.contains("fog") || value.contains("haze") {
            return .haze
        }
        if value.contains("阴") || value.contains("cloudy") {
            return .cloudy
        }
        if value.contains("多云") || value.contains("少云") || value.contains("partly") {
            return .partlyCloudy
        }
        if value.contains("晴") || value.contains("clear") || value.contains("sun") {
            return .sunny
        }

        return .partlyCloudy
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
        updateAltitudeLabel(for: location)
        setWeatherText(weather.isEmpty ? L10n.t("weather.title") : weather)
        temperatureLabel.text = temperature.isEmpty ? "--°" : "\(temperature)°"
        cacheLiveWeather(weather: weather, temperature: temperature)

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
            altitude: nil,
            city: L10n.t("city.beijing"),
            adcode: "110000",
            address: ""
        )
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

    @objc private func tapBack() {
        navigationController?.popViewController(animated: true)
    }
}

private final class SunsetStrengthChartView: UIView {
    var predictions: [ApiClient.SunsetPrediction] = [] {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let rows = Array(predictions.prefix(2))
        guard !rows.isEmpty else {
            drawEmpty(in: rect)
            return
        }

        let labelWidth: CGFloat = 44
        let valueWidth: CGFloat = 44
        let barHeight: CGFloat = 16
        let rowGap: CGFloat = 22
        let top: CGFloat = 10
        let barX = labelWidth
        let barWidth = max(0, rect.width - labelWidth - valueWidth - 6)

        for (index, prediction) in rows.enumerated() {
            let y = top + CGFloat(index) * (barHeight + rowGap)
            drawText(prediction.dateLabel, in: CGRect(x: 0, y: y - 2, width: labelWidth - 6, height: 20), font: .systemFont(ofSize: 12, weight: .semibold), color: .secondaryLabel, alignment: .left)

            let trackRect = CGRect(x: barX, y: y, width: barWidth, height: barHeight)
            drawTrack(in: trackRect, context: context)
            let fillRect = CGRect(x: trackRect.minX, y: trackRect.minY, width: trackRect.width * CGFloat(prediction.quality), height: trackRect.height)
            drawGradient(in: fillRect, context: context)

            drawText("\(prediction.percentage)%", in: CGRect(x: trackRect.maxX + 6, y: y - 2, width: valueWidth, height: 20), font: .systemFont(ofSize: 12, weight: .bold), color: strengthColor(for: prediction.quality), alignment: .right)
        }

        let scaleY = top + CGFloat(rows.count) * (barHeight + rowGap) - 7
        [L10n.t("weather.sunset_scale_weak"), L10n.t("weather.sunset_scale_mid"), L10n.t("weather.sunset_scale_strong")].enumerated().forEach { index, text in
            let x = barX + CGFloat(index) * barWidth / 2 - 12
            drawText(text, in: CGRect(x: x, y: scaleY, width: 24, height: 14), font: .systemFont(ofSize: 10), color: .tertiaryLabel, alignment: .center)
        }
    }

    private func drawEmpty(in rect: CGRect) {
        drawText("--", in: rect, font: .systemFont(ofSize: 14, weight: .semibold), color: .secondaryLabel, alignment: .center)
    }

    private func drawTrack(in rect: CGRect, context: CGContext) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        UIColor.systemGray5.withAlphaComponent(0.9).setFill()
        path.fill()
    }

    private func drawGradient(in rect: CGRect, context: CGContext) {
        guard rect.width > 0 else { return }
        context.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).addClip()
        let colors = [
            UIColor.systemGray.cgColor,
            UIColor.systemYellow.cgColor,
            UIColor.systemOrange.cgColor,
            UIColor.systemRed.cgColor
        ] as CFArray
        let locations: [CGFloat] = [0, 0.35, 0.65, 1]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
            context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.midY), end: CGPoint(x: rect.maxX, y: rect.midY), options: [])
        }
        context.restoreGState()
    }

    private func drawText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    private func strengthColor(for value: Double) -> UIColor {
        if value >= 0.75 { return .systemRed }
        if value >= 0.50 { return .systemOrange }
        if value >= 0.35 { return .systemYellow }
        return .systemGray
    }
}

private final class GradientMeterView: UIView {
    var value: Double = 0 {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let track = rect.insetBy(dx: 0, dy: 1)
        UIColor.systemGray5.withAlphaComponent(0.9).setFill()
        UIBezierPath(roundedRect: track, cornerRadius: track.height / 2).fill()

        let fill = CGRect(x: track.minX, y: track.minY, width: track.width * CGFloat(min(1, max(0, value))), height: track.height)
        guard fill.width > 0 else { return }
        context.saveGState()
        UIBezierPath(roundedRect: fill, cornerRadius: fill.height / 2).addClip()
        let colors = [UIColor.systemGray.cgColor, UIColor.systemYellow.cgColor, UIColor.systemOrange.cgColor, UIColor.systemRed.cgColor] as CFArray
        let locations: [CGFloat] = [0, 0.35, 0.65, 1]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
            context.drawLinearGradient(gradient, start: CGPoint(x: fill.minX, y: fill.midY), end: CGPoint(x: fill.maxX, y: fill.midY), options: [])
        }
        context.restoreGState()
    }
}

final class WeatherAnimatedBackgroundView: UIView {
    enum Scene: Equatable {
        case sunny
        case partlyCloudy
        case cloudy
        case rain
        case heavyRain
        case storm
        case snow
        case haze
    }

    private let gradientLayer = CAGradientLayer()
    private let sunLayer = CAShapeLayer()
    private let sunHaloLayer = CAShapeLayer()
    private let sunlightLayer = CAEmitterLayer()
    private let cloudShadowLayer = CALayer()
    private let cloudLayer = CALayer()
    private let secondCloudLayer = CALayer()
    private let particleLayer = CAEmitterLayer()
    private var currentScene: Scene = .partlyCloudy

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        setupLayers()
        apply(scene: .partlyCloudy)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        sunlightLayer.frame = bounds
        sunlightLayer.emitterPosition = CGPoint(x: bounds.width * 0.78, y: bounds.height * 0.18)
        sunlightLayer.emitterSize = CGSize(width: bounds.width * 0.36, height: bounds.height * 0.22)
        cloudShadowLayer.frame = CGRect(x: -60, y: bounds.height * 0.48, width: bounds.width + 160, height: max(180, bounds.height * 0.30))
        particleLayer.frame = bounds
        particleLayer.emitterPosition = CGPoint(x: bounds.midX - bounds.width * 0.18, y: -28)
        particleLayer.emitterSize = CGSize(width: bounds.width * 1.8, height: 1)
        layoutSun()
        layoutClouds()
    }

    func apply(scene: Scene) {
        guard scene != currentScene || gradientLayer.colors == nil else { return }
        currentScene = scene
        updateGradient(for: scene)
        updateWeatherElements(for: scene)
    }

    private func setupLayers() {
        layer.addSublayer(gradientLayer)
        layer.addSublayer(sunHaloLayer)
        layer.addSublayer(sunLayer)
        layer.addSublayer(sunlightLayer)
        layer.addSublayer(cloudShadowLayer)
        layer.addSublayer(cloudLayer)
        layer.addSublayer(secondCloudLayer)
        layer.addSublayer(particleLayer)

        sunLayer.fillColor = UIColor(red: 1.0, green: 0.72, blue: 0.12, alpha: 0.86).cgColor
        sunHaloLayer.fillColor = UIColor(red: 1.0, green: 0.78, blue: 0.18, alpha: 0.34).cgColor
        setupCloudShadows()
        [cloudLayer, secondCloudLayer].forEach {
            $0.opacity = 0.78
            addCloudShapes(to: $0)
        }
        addCloudDrift(to: cloudShadowLayer, duration: 18, distance: 52)
        addCloudDrift(to: cloudLayer, duration: 12, distance: 44)
        addCloudDrift(to: secondCloudLayer, duration: 15, distance: -36)
        addSunPulse()
    }

    private func updateGradient(for scene: Scene) {
        let colors: [UIColor]
        switch scene {
        case .sunny:
            colors = [
                UIColor(red: 0.62, green: 0.85, blue: 1.0, alpha: 1.0),
                UIColor(red: 0.92, green: 0.98, blue: 1.0, alpha: 1.0),
                UIColor(red: 1.0, green: 0.91, blue: 0.66, alpha: 1.0)
            ]
        case .partlyCloudy:
            colors = [
                UIColor(red: 0.72, green: 0.88, blue: 1.0, alpha: 1.0),
                UIColor(red: 0.95, green: 0.98, blue: 1.0, alpha: 1.0),
                UIColor(red: 1.0, green: 0.94, blue: 0.78, alpha: 1.0)
            ]
        case .cloudy, .haze:
            colors = [
                UIColor(red: 0.86, green: 0.92, blue: 0.97, alpha: 1.0),
                UIColor(red: 0.96, green: 0.98, blue: 0.99, alpha: 1.0),
                UIColor(red: 0.98, green: 0.98, blue: 0.95, alpha: 1.0)
            ]
        case .rain, .heavyRain, .storm:
            colors = [
                UIColor(red: 0.82, green: 0.90, blue: 0.97, alpha: 1.0),
                UIColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 1.0),
                UIColor(red: 0.99, green: 0.99, blue: 0.97, alpha: 1.0)
            ]
        case .snow:
            colors = [
                UIColor(red: 0.88, green: 0.95, blue: 1.0, alpha: 1.0),
                UIColor(red: 0.98, green: 0.99, blue: 1.0, alpha: 1.0),
                UIColor.white
            ]
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.45)
        gradientLayer.colors = colors.map(\.cgColor)
        gradientLayer.locations = [0.0, 0.56, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.2, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.9, y: 1)
        CATransaction.commit()
    }

    private func updateWeatherElements(for scene: Scene) {
        sunLayer.isHidden = [.cloudy, .rain, .heavyRain, .storm, .haze].contains(scene)
        sunHaloLayer.isHidden = sunLayer.isHidden
        sunlightLayer.isHidden = scene != .sunny
        cloudShadowLayer.isHidden = ![.partlyCloudy, .cloudy].contains(scene)

        switch scene {
        case .sunny:
            cloudLayer.opacity = 0.34
            secondCloudLayer.opacity = 0.22
            cloudShadowLayer.opacity = 0
            configureParticles(kind: .sunlight, intensity: 0.34)
            return
        case .partlyCloudy:
            cloudLayer.opacity = 0.92
            secondCloudLayer.opacity = 0.66
            cloudShadowLayer.opacity = 0.44
            configureParticles(kind: .sunlight, intensity: 0.18)
            return
        case .cloudy:
            cloudLayer.opacity = 0.96
            secondCloudLayer.opacity = 0.86
            cloudShadowLayer.opacity = 0.52
        default:
            cloudLayer.opacity = 0.82
            secondCloudLayer.opacity = [.rain, .heavyRain, .storm, .haze].contains(scene) ? 0.68 : 0.38
            cloudShadowLayer.opacity = 0
        }

        switch scene {
        case .rain:
            configureParticles(kind: .rain, intensity: 0.42)
        case .heavyRain, .storm:
            configureParticles(kind: .rain, intensity: 0.72)
        case .snow:
            configureParticles(kind: .snow, intensity: 0.36)
        case .haze:
            configureParticles(kind: .mist, intensity: 0.18)
        default:
            particleLayer.emitterCells = nil
            sunlightLayer.emitterCells = nil
        }
    }

    private func layoutSun() {
        let sunDiameter = max(bounds.width * 0.28, 108)
        let sunFrame = CGRect(x: bounds.width - sunDiameter * 0.82, y: 82, width: sunDiameter, height: sunDiameter)
        let haloFrame = sunFrame.insetBy(dx: -34, dy: -34)
        sunLayer.path = UIBezierPath(ovalIn: sunFrame).cgPath
        sunHaloLayer.path = UIBezierPath(ovalIn: haloFrame).cgPath
    }

    private func layoutClouds() {
        cloudLayer.frame = CGRect(x: -24, y: 120, width: bounds.width + 80, height: 150)
        secondCloudLayer.frame = CGRect(x: 36, y: 260, width: bounds.width + 70, height: 130)
    }

    private func addCloudShapes(to layer: CALayer) {
        addCloudGroup(
            to: layer,
            origin: CGPoint(x: -12, y: 26),
            scale: 1.08,
            alpha: 0.84
        )
        addCloudGroup(
            to: layer,
            origin: CGPoint(x: 236, y: 10),
            scale: 1.24,
            alpha: 0.78
        )
        addCloudGroup(
            to: layer,
            origin: CGPoint(x: 510, y: 42),
            scale: 0.96,
            alpha: 0.72
        )
    }

    private func addCloudGroup(to layer: CALayer, origin: CGPoint, scale: CGFloat, alpha: CGFloat) {
        let shadow = CAShapeLayer()
        shadow.fillColor = UIColor(red: 0.58, green: 0.72, blue: 0.88, alpha: 0.18 * alpha).cgColor
        shadow.path = UIBezierPath(
            roundedRect: CGRect(
                x: origin.x + 12 * scale,
                y: origin.y + 66 * scale,
                width: 252 * scale,
                height: 42 * scale
            ),
            cornerRadius: 22 * scale
        ).cgPath
        layer.addSublayer(shadow)

        let pieces: [(CGRect, CGFloat)] = [
            (CGRect(x: 0, y: 62, width: 280, height: 58), 29),
            (CGRect(x: 24, y: 46, width: 90, height: 70), 35),
            (CGRect(x: 86, y: 18, width: 118, height: 96), 48),
            (CGRect(x: 172, y: 36, width: 100, height: 76), 38),
            (CGRect(x: 222, y: 58, width: 86, height: 54), 27)
        ]

        for (rect, radius) in pieces {
            let frame = CGRect(
                x: origin.x + rect.origin.x * scale,
                y: origin.y + rect.origin.y * scale,
                width: rect.width * scale,
                height: rect.height * scale
            )
            let shape = CAShapeLayer()
            shape.fillColor = UIColor.white.withAlphaComponent(alpha).cgColor
            shape.path = UIBezierPath(roundedRect: frame, cornerRadius: radius * scale).cgPath
            layer.addSublayer(shape)
        }

        let highlight = CAShapeLayer()
        highlight.fillColor = UIColor.white.withAlphaComponent(0.28 * alpha).cgColor
        highlight.path = UIBezierPath(
            ovalIn: CGRect(
                x: origin.x + 78 * scale,
                y: origin.y + 30 * scale,
                width: 104 * scale,
                height: 34 * scale
            )
        ).cgPath
        layer.addSublayer(highlight)
    }

    private func setupCloudShadows() {
        addLowerCloudGroup(to: cloudShadowLayer, origin: CGPoint(x: -28, y: 18), scale: 1.15, alpha: 0.34)
        addLowerCloudGroup(to: cloudShadowLayer, origin: CGPoint(x: 230, y: 54), scale: 1.34, alpha: 0.30)
        addLowerCloudGroup(to: cloudShadowLayer, origin: CGPoint(x: 560, y: 34), scale: 1.0, alpha: 0.26)
        cloudShadowLayer.isHidden = true
    }

    private func addLowerCloudGroup(to layer: CALayer, origin: CGPoint, scale: CGFloat, alpha: CGFloat) {
        let cloud = CAShapeLayer()
        cloud.fillColor = UIColor(red: 0.32, green: 0.50, blue: 0.72, alpha: alpha).cgColor
        cloud.path = lowerCloudPath(origin: origin, scale: scale).cgPath
        layer.addSublayer(cloud)

        let softHighlight = CAShapeLayer()
        softHighlight.fillColor = UIColor.white.withAlphaComponent(alpha * 0.26).cgColor
        softHighlight.path = UIBezierPath(
            ovalIn: CGRect(
                x: origin.x + 92 * scale,
                y: origin.y + 26 * scale,
                width: 128 * scale,
                height: 30 * scale
            )
        ).cgPath
        layer.addSublayer(softHighlight)
    }

    private func lowerCloudPath(origin: CGPoint, scale: CGFloat) -> UIBezierPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }

        let path = UIBezierPath()
        path.move(to: point(8, 76))
        path.addCurve(to: point(58, 52), controlPoint1: point(16, 58), controlPoint2: point(35, 48))
        path.addCurve(to: point(118, 28), controlPoint1: point(64, 28), controlPoint2: point(91, 16))
        path.addCurve(to: point(178, 40), controlPoint1: point(142, 6), controlPoint2: point(174, 12))
        path.addCurve(to: point(244, 48), controlPoint1: point(196, 26), controlPoint2: point(225, 27))
        path.addCurve(to: point(306, 68), controlPoint1: point(271, 42), controlPoint2: point(296, 50))
        path.addCurve(to: point(344, 90), controlPoint1: point(326, 66), controlPoint2: point(342, 75))
        path.addCurve(to: point(298, 108), controlPoint1: point(338, 103), controlPoint2: point(321, 110))
        path.addLine(to: point(54, 108))
        path.addCurve(to: point(8, 76), controlPoint1: point(28, 109), controlPoint2: point(8, 98))
        path.close()
        return path
    }

    private func addCloudDrift(to layer: CALayer, duration: CFTimeInterval, distance: CGFloat) {
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = -distance
        animation.toValue = distance
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "cloudDrift")
    }

    private func addSunPulse() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.22
        animation.toValue = 0.42
        animation.duration = 3.8
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sunHaloLayer.add(animation, forKey: "sunPulse")
    }

    private enum ParticleKind {
        case rain
        case snow
        case mist
        case sunlight
    }

    private func configureParticles(kind: ParticleKind, intensity: Float) {
        particleLayer.emitterShape = .line
        particleLayer.emitterMode = .surface

        switch kind {
        case .sunlight:
            let glint = makeParticleCell(
                kind: .sunlight,
                birthRate: 90 * intensity,
                lifetime: 7.2,
                velocity: 10,
                velocityRange: 16,
                yAcceleration: -1,
                xAcceleration: -3,
                emissionLongitude: .pi,
                emissionRange: .pi,
                scale: 0.72,
                scaleRange: 0.42,
                alphaSpeed: -0.055
            )
            sunlightLayer.emitterShape = .rectangle
            sunlightLayer.emitterMode = .surface
            sunlightLayer.emitterCells = [glint]
            particleLayer.emitterCells = nil
        case .rain:
            sunlightLayer.emitterCells = nil
            let farRain = makeParticleCell(
                kind: .rain,
                birthRate: 72 * intensity,
                lifetime: 4.8,
                velocity: 210,
                velocityRange: 54,
                yAcceleration: 245,
                xAcceleration: -12,
                emissionLongitude: .pi * 0.51,
                emissionRange: 0.16,
                scale: 0.58,
                scaleRange: 0.12,
                alphaSpeed: -0.055
            )
            let nearRain = makeParticleCell(
                kind: .rain,
                birthRate: 42 * intensity,
                lifetime: 3.7,
                velocity: 285,
                velocityRange: 62,
                yAcceleration: 310,
                xAcceleration: -18,
                emissionLongitude: .pi * 0.52,
                emissionRange: 0.12,
                scale: 0.98,
                scaleRange: 0.18,
                alphaSpeed: -0.07
            )
            particleLayer.emitterCells = [farRain, nearRain]
        case .snow:
            sunlightLayer.emitterCells = nil
            particleLayer.emitterCells = [
                makeParticleCell(
                    kind: .snow,
                    birthRate: 90 * intensity,
                    lifetime: 9,
                    velocity: 34,
                    velocityRange: 18,
                    yAcceleration: 16,
                    xAcceleration: 10,
                    emissionLongitude: .pi * 0.5,
                    emissionRange: 0.45,
                    scale: 0.7,
                    scaleRange: 0.5,
                    alphaSpeed: -0.06
                )
            ]
        case .mist:
            sunlightLayer.emitterCells = nil
            particleLayer.emitterCells = [
                makeParticleCell(
                    kind: .mist,
                    birthRate: 90 * intensity,
                    lifetime: 4.2,
                    velocity: 250,
                    velocityRange: 42,
                    yAcceleration: 280,
                    xAcceleration: 10,
                    emissionLongitude: .pi * 0.5,
                    emissionRange: 0.45,
                    scale: 0.7,
                    scaleRange: 0.16,
                    alphaSpeed: -0.18
                )
            ]
        }
    }

    private func makeParticleCell(
        kind: ParticleKind,
        birthRate: Float,
        lifetime: Float,
        velocity: CGFloat,
        velocityRange: CGFloat,
        yAcceleration: CGFloat,
        xAcceleration: CGFloat,
        emissionLongitude: CGFloat,
        emissionRange: CGFloat,
        scale: CGFloat,
        scaleRange: CGFloat,
        alphaSpeed: Float
    ) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.birthRate = birthRate
        cell.lifetime = lifetime
        cell.velocity = velocity
        cell.velocityRange = velocityRange
        cell.yAcceleration = yAcceleration
        cell.xAcceleration = xAcceleration
        cell.emissionLongitude = emissionLongitude
        cell.emissionRange = emissionRange
        cell.scale = scale
        cell.scaleRange = scaleRange
        cell.alphaSpeed = alphaSpeed
        cell.contents = particleImage(for: kind).cgImage
        return cell
    }

    private func particleImage(for kind: ParticleKind) -> UIImage {
        let size: CGSize
        switch kind {
        case .rain:
            size = CGSize(width: 3, height: 18)
        case .sunlight:
            size = CGSize(width: 12, height: 12)
        default:
            size = CGSize(width: 8, height: 8)
        }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            switch kind {
            case .rain:
                UIColor(red: 0.43, green: 0.67, blue: 0.93, alpha: 0.36).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: 1.5).fill()
            case .snow:
                UIColor.white.withAlphaComponent(0.74).setFill()
                UIBezierPath(ovalIn: rect).fill()
            case .mist:
                UIColor.white.withAlphaComponent(0.28).setFill()
                context.cgContext.fillEllipse(in: rect)
            case .sunlight:
                UIColor(red: 1.0, green: 0.78, blue: 0.18, alpha: 0.48).setFill()
                UIBezierPath(ovalIn: rect).fill()
            }
        }
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
