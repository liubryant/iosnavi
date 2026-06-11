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

final class WeatherViewController: UIViewController {

    private let location: CurrentLocation?

    private let cityLabel = UILabel()
    private let weatherLabel = UILabel()
    private let temperatureLabel = UILabel()
    private let windLabel = UILabel()
    private let humidityLabel = UILabel()
    private let reportTimeLabel = UILabel()
    private let forecastStack = UIStackView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM月dd日 E"
        return formatter
    }()

    init(location: CurrentLocation? = nil) {
        self.location = location
        super.init(nibName: nil, bundle: nil)
        self.title = "天气查询"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        cityLabel.font = .boldSystemFont(ofSize: 24)
        cityLabel.textAlignment = .center
        cityLabel.text = location?.city ?? Constants.city

        let liveCard = makeCard(arrangedSubviews: [weatherLabel, temperatureLabel, windLabel, humidityLabel, reportTimeLabel])
        weatherLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        weatherLabel.textAlignment = .center
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
        forecastTitle.text = "未来天气预报"
        forecastTitle.font = .boldSystemFont(ofSize: 16)

        forecastStack.axis = .vertical
        forecastStack.spacing = 0
        let forecastCard = makeCard(arrangedSubviews: [forecastStack])

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()

        contentStack.addArrangedSubview(cityLabel)
        contentStack.addArrangedSubview(liveCard)
        contentStack.addArrangedSubview(forecastTitle)
        contentStack.addArrangedSubview(forecastCard)

        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        loadWeather()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("WeatherViewController")
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

    // MARK: - 数据加载

    private func loadWeather() {
        guard #available(iOS 16.0, *) else {
            activityIndicator.stopAnimating()
            weatherLabel.text = "当前系统不支持 WeatherKit"
            temperatureLabel.text = "--°"
            windLabel.text = "WeatherKit 需要 iOS 16 或更高版本"
            humidityLabel.text = nil
            reportTimeLabel.text = nil
            showForecastMessage("暂无预报数据")
            return
        }

        Task { [weak self] in
            await self?.loadWeatherKit()
        }
    }

    @available(iOS 16.0, *)
    private func loadWeatherKit() async {
        let current = currentLocation()
        let clLocation = CLLocation(latitude: current.latitude, longitude: current.longitude)

        do {
            let weather = try await WeatherService.shared.weather(for: clLocation)
            applyWeatherKit(weather, location: current)
        } catch {
            activityIndicator.stopAnimating()
            weatherLabel.text = "天气数据获取失败"
            temperatureLabel.text = "--°"
            windLabel.text = "请确认已开启 WeatherKit 能力并允许网络访问"
            humidityLabel.text = nil
            reportTimeLabel.text = nil
            showForecastMessage(error.localizedDescription)
        }
    }

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
            city: Constants.city,
            address: ""
        )
    }

    @available(iOS 16.0, *)
    private func applyWeatherKit(_ weather: Weather, location: CurrentLocation) {
        activityIndicator.stopAnimating()
        cityLabel.text = location.city

        let current = weather.currentWeather
        weatherLabel.text = current.condition.description
        temperatureLabel.text = "\(Int(current.temperature.converted(to: .celsius).value.rounded()))°"
        windLabel.text = "风速 \(Int(current.wind.speed.converted(to: .kilometersPerHour).value.rounded())) km/h"
        humidityLabel.text = "湿度 \(Int((current.humidity * 100).rounded()))%"
        reportTimeLabel.text = "\(formatReportDate(current.date)) 更新"

        forecastStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let dailyForecasts = Array(weather.dailyForecast.forecast.prefix(7))
        guard !dailyForecasts.isEmpty else {
            showForecastMessage("暂无预报数据")
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
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
