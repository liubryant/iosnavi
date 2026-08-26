import UIKit
import WidgetKit

/// 新版天气页。旧的 `WeatherViewController` 保留，所有用户入口切换到本页面。
/// 数据来自 Open-Meteo，无需 API Key。
final class OpenMeteoWeatherViewController: UIViewController {

    private static let cacheKey = "open_meteo_weather_page_cache_v1"
    private let initialLocation: CurrentLocation?
    private var activeLocation: CurrentLocation?
    private var response: OpenMeteoForecast?
    private var task: URLSessionDataTask?

    private let gradientLayer = CAGradientLayer()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let cityLabel = UILabel()
    private let addressLabel = UILabel()
    private let heroIcon = UIImageView()
    private let temperatureLabel = UILabel()
    private let conditionLabel = UILabel()
    private let rangeLabel = UILabel()
    private let hourlyStack = UIStackView()
    private let dailyStack = UIStackView()
    private let metricsStack = UIStackView()
    private let activity = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()
    private let retryButton = UIButton(type: .system)

    init(location: CurrentLocation? = nil) {
        initialLocation = location
        activeLocation = location ?? LocationManager.shared.lastKnownLocation
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)
        buildUI()
        restoreCachedWeather()
        loadWeather(refreshLocation: initialLocation == nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 主导航控制器全局使用自定义顶部栏，系统导航栏必须始终隐藏。
        // 这里不能在返回时显示系统导航栏，否则首页及后续所有页面都会整体下移。
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
    }

    deinit { task?.cancel() }

    private func buildUI() {
        view.backgroundColor = UIColor(red: 0.18, green: 0.40, blue: 0.67, alpha: 1)
        gradientLayer.colors = [
            UIColor(red: 0.10, green: 0.32, blue: 0.62, alpha: 1).cgColor,
            UIColor(red: 0.30, green: 0.60, blue: 0.82, alpha: 1).cgColor,
            UIColor(red: 0.67, green: 0.82, blue: 0.91, alpha: 1).cgColor
        ]
        gradientLayer.locations = [0, 0.52, 1]
        view.layer.insertSublayer(gradientLayer, at: 0)

        addDecorativeGlow(color: UIColor.white.withAlphaComponent(0.10), diameter: 280, x: -90, y: 105)
        addDecorativeGlow(color: UIColor.systemYellow.withAlphaComponent(0.12), diameter: 220, x: view.bounds.width - 85, y: 310)

        let topBar = UIView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        let back = roundButton(symbol: "chevron.left")
        back.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        topBar.addSubview(back)

        cityLabel.font = .systemFont(ofSize: 20, weight: .bold)
        cityLabel.textColor = .white
        cityLabel.textAlignment = .center
        cityLabel.text = activeLocation?.city.nonEmpty ?? "当地天气"
        addressLabel.font = .systemFont(ofSize: 11, weight: .medium)
        addressLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        addressLabel.textAlignment = .center
        addressLabel.numberOfLines = 1
        addressLabel.text = activeLocation?.address.nonEmpty ?? "Open-Meteo 实时预报"
        let titleStack = UIStackView(arrangedSubviews: [cityLabel, addressLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 2
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(titleStack)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.refreshControl = UIRefreshControl()
        scrollView.refreshControl?.tintColor = .white
        scrollView.refreshControl?.addTarget(self, action: #selector(refreshTapped), for: .valueChanged)
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(makeHero())
        contentStack.addArrangedSubview(makeSection(title: "逐小时预报", subtitle: "未来 24 小时", body: makeHorizontalForecast()))
        contentStack.addArrangedSubview(makeSection(title: "未来 10 天", subtitle: "每日天气趋势", body: dailyStack))
        contentStack.addArrangedSubview(makeSection(title: "天气详情", subtitle: "当前观测数据", body: metricsStack))
        let attribution = UILabel()
        attribution.text = "天气数据 · Open-Meteo"
        attribution.font = .systemFont(ofSize: 11, weight: .medium)
        attribution.textColor = UIColor.white.withAlphaComponent(0.5)
        attribution.textAlignment = .center
        contentStack.addArrangedSubview(attribution)

        activity.color = .white
        activity.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activity)
        messageLabel.font = .systemFont(ofSize: 15, weight: .medium)
        messageLabel.textColor = .white
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageLabel)
        retryButton.setTitle("重新加载", for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        retryButton.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        retryButton.layer.cornerRadius = 18
        retryButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.isHidden = true
        view.addSubview(retryButton)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 54),
            back.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 18), back.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            back.widthAnchor.constraint(equalToConstant: 42), back.heightAnchor.constraint(equalToConstant: 42),
            titleStack.centerXAnchor.constraint(equalTo: topBar.centerXAnchor), titleStack.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            titleStack.leadingAnchor.constraint(greaterThanOrEqualTo: back.trailingAnchor, constant: 10),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: topBar.trailingAnchor, constant: -18),

            scrollView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -18),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -36),
            activity.centerXAnchor.constraint(equalTo: view.centerXAnchor), activity.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor), messageLabel.topAnchor.constraint(equalTo: activity.bottomAnchor, constant: 14),
            messageLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -70),
            retryButton.centerXAnchor.constraint(equalTo: view.centerXAnchor), retryButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 14),
            retryButton.widthAnchor.constraint(equalToConstant: 108), retryButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func makeHero() -> UIView {
        let card = glassCard()
        heroIcon.image = UIImage(systemName: "cloud.sun.fill")
        heroIcon.tintColor = UIColor(red: 1, green: 0.89, blue: 0.48, alpha: 1)
        heroIcon.contentMode = .scaleAspectFit
        heroIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 68, weight: .medium)
        temperatureLabel.text = "--°"
        temperatureLabel.font = .systemFont(ofSize: 82, weight: .thin)
        temperatureLabel.textColor = .white
        temperatureLabel.adjustsFontSizeToFitWidth = true
        conditionLabel.text = "正在获取天气"
        conditionLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        conditionLabel.textColor = .white
        rangeLabel.text = "体感 --° · 最高 --° / 最低 --°"
        rangeLabel.font = .systemFont(ofSize: 14, weight: .medium)
        rangeLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        let text = UIStackView(arrangedSubviews: [temperatureLabel, conditionLabel, rangeLabel])
        text.axis = .vertical; text.spacing = 4
        let row = UIStackView(arrangedSubviews: [text, heroIcon])
        row.axis = .horizontal; row.alignment = .center; row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 22), row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22), row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            heroIcon.widthAnchor.constraint(equalToConstant: 92), heroIcon.heightAnchor.constraint(equalToConstant: 92),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 190)
        ])
        return card
    }

    private func makeHorizontalForecast() -> UIView {
        hourlyStack.axis = .horizontal; hourlyStack.spacing = 10
        let horizontal = UIScrollView()
        horizontal.showsHorizontalScrollIndicator = false
        horizontal.translatesAutoresizingMaskIntoConstraints = false
        hourlyStack.translatesAutoresizingMaskIntoConstraints = false
        horizontal.addSubview(hourlyStack)
        NSLayoutConstraint.activate([
            horizontal.heightAnchor.constraint(equalToConstant: 118),
            hourlyStack.leadingAnchor.constraint(equalTo: horizontal.contentLayoutGuide.leadingAnchor),
            hourlyStack.trailingAnchor.constraint(equalTo: horizontal.contentLayoutGuide.trailingAnchor),
            hourlyStack.topAnchor.constraint(equalTo: horizontal.contentLayoutGuide.topAnchor),
            hourlyStack.bottomAnchor.constraint(equalTo: horizontal.contentLayoutGuide.bottomAnchor),
            hourlyStack.heightAnchor.constraint(equalTo: horizontal.frameLayoutGuide.heightAnchor)
        ])
        return horizontal
    }

    private func makeSection(title: String, subtitle: String, body: UIView) -> UIView {
        let titleLabel = UILabel(); titleLabel.text = title; titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        let subtitleLabel = UILabel(); subtitleLabel.text = subtitle; subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        let heading = UIStackView(arrangedSubviews: [titleLabel, UIView(), subtitleLabel]); heading.alignment = .center
        let stack = UIStackView(arrangedSubviews: [heading, body]); stack.axis = .vertical; stack.spacing = 10
        return stack
    }

    private func glassCard() -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        view.layer.cornerRadius = 24
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 0.7
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
        return view
    }

    private func roundButton(symbol: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        button.layer.cornerRadius = 21
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func addDecorativeGlow(color: UIColor, diameter: CGFloat, x: CGFloat, y: CGFloat) {
        let glow = UIView(frame: CGRect(x: x, y: y, width: diameter, height: diameter))
        glow.backgroundColor = color; glow.layer.cornerRadius = diameter / 2
        glow.isUserInteractionEnabled = false
        view.addSubview(glow)
    }

    @objc private func goBack() { navigationController?.popViewController(animated: true) }
    @objc private func refreshTapped() { loadWeather(refreshLocation: true) }

    private func loadWeather(refreshLocation: Bool) {
        setLoading(true)
        if refreshLocation {
            LocationManager.shared.requestLocation { [weak self] location in
                guard let self else { return }
                self.activeLocation = location ?? self.activeLocation ?? Self.beijingFallback
                self.fetch(location: self.activeLocation ?? Self.beijingFallback)
            }
        } else {
            fetch(location: activeLocation ?? Self.beijingFallback)
        }
    }

    private func fetch(location: CurrentLocation) {
        activeLocation = location
        cityLabel.text = location.city.nonEmpty ?? "当地天气"
        addressLabel.text = location.address.nonEmpty ?? "Open-Meteo 实时预报"
        var components = URLComponents(string: UrlConstants.openMeteoForecast)!
        components.queryItems = [
            .init(name: "latitude", value: String(location.latitude)), .init(name: "longitude", value: String(location.longitude)),
            .init(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m"),
            .init(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,uv_index_max"),
            .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "10")
        ]
        guard let url = components.url else { return showError("天气请求地址无效") }
        task?.cancel()
        task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error, (error as NSError).code != NSURLErrorCancelled { return self.showError("天气加载失败\n\(error.localizedDescription)") }
                guard let data else { return self.showError("暂时没有天气数据") }
                do {
                    let forecast = try JSONDecoder().decode(OpenMeteoForecast.self, from: data)
                    let hadVisibleData = self.response != nil
                    self.response = forecast
                    self.saveCache(forecast, location: location)
                    if hadVisibleData {
                        UIView.transition(with: self.contentStack, duration: 0.28, options: [.transitionCrossDissolve, .allowAnimatedContent]) {
                            self.render(forecast)
                        }
                    } else {
                        self.render(forecast)
                    }
                    self.setLoading(false)
                } catch { self.showError("天气数据解析失败，请稍后重试") }
            }
        }
        task?.resume()
    }

    private func render(_ forecast: OpenMeteoForecast) {
        let current = forecast.current
        let condition = WeatherCondition(code: current.weatherCode, isDay: current.isDay == 1)
        heroIcon.image = UIImage(systemName: condition.symbol)
        heroIcon.tintColor = condition.tint
        temperatureLabel.text = "\(Int(current.temperature.rounded()))°"
        conditionLabel.text = condition.title
        let high = forecast.daily.temperatureMax.first.map { Int($0.rounded()) }
        let low = forecast.daily.temperatureMin.first.map { Int($0.rounded()) }
        rangeLabel.text = "体感 \(Int(current.apparentTemperature.rounded()))° · 最高 \(high ?? 0)° / 最低 \(low ?? 0)°"
        SpUtil.setString(condition.title, for: .lastLiveWeather)
        SpUtil.setString(String(Int(current.temperature.rounded())), for: .lastLiveTemperature)
        updateGradient(condition: condition, isDay: current.isDay == 1)
        renderHourly(forecast)
        renderDaily(forecast)
        renderMetrics(forecast)
    }

    private func renderHourly(_ forecast: OpenMeteoForecast) {
        hourlyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let now = parseDate(forecast.current.time, timezone: forecast.timezone) ?? Date()
        let dates = forecast.hourly.time.map { parseDate($0, timezone: forecast.timezone) }
        let start = dates.firstIndex(where: { ($0 ?? .distantPast) >= now.addingTimeInterval(-1800) }) ?? 0
        for i in start..<min(start + 24, forecast.hourly.time.count) {
            let date = dates[i]
            let title = i == start ? "现在" : date.map { hourFormatter(timezone: forecast.timezone).string(from: $0) } ?? "--"
            let code = forecast.hourly.weatherCode[safe: i] ?? 0
            let item = ForecastHourView(time: title, symbol: WeatherCondition(code: code, isDay: isDayHour(date)).symbol,
                                        temp: forecast.hourly.temperature[safe: i] ?? 0,
                                        rain: forecast.hourly.precipitationProbability[safe: i] ?? 0)
            hourlyStack.addArrangedSubview(item)
        }
    }

    private func renderDaily(_ forecast: OpenMeteoForecast) {
        dailyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        dailyStack.axis = .vertical; dailyStack.spacing = 0
        let card = glassCard()
        let rows = UIStackView(); rows.axis = .vertical; rows.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(rows)
        NSLayoutConstraint.activate([rows.topAnchor.constraint(equalTo: card.topAnchor, constant: 8), rows.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8), rows.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14), rows.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14)])
        for i in 0..<forecast.daily.time.count {
            rows.addArrangedSubview(ForecastDayView(day: dayTitle(forecast.daily.time[i], index: i, timezone: forecast.timezone),
                symbol: WeatherCondition(code: forecast.daily.weatherCode[safe: i] ?? 0, isDay: true).symbol,
                low: forecast.daily.temperatureMin[safe: i] ?? 0, high: forecast.daily.temperatureMax[safe: i] ?? 0,
                rain: forecast.daily.precipitationProbability[safe: i] ?? 0))
        }
        dailyStack.addArrangedSubview(card)
    }

    private func renderMetrics(_ forecast: OpenMeteoForecast) {
        metricsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        metricsStack.axis = .vertical; metricsStack.spacing = 10
        let c = forecast.current
        let sunrise = forecast.daily.sunrise.first.flatMap { parseDate($0, timezone: forecast.timezone) }.map { hourFormatter(timezone: forecast.timezone).string(from: $0) } ?? "--"
        let sunset = forecast.daily.sunset.first.flatMap { parseDate($0, timezone: forecast.timezone) }.map { hourFormatter(timezone: forecast.timezone).string(from: $0) } ?? "--"
        let values = [("drop.fill", "湿度", "\(c.humidity)%"), ("wind", "风速", "\(Int(c.windSpeed.rounded())) km/h"),
                      ("gauge.with.dots.needle.50percent", "气压", "\(Int(c.pressure.rounded())) hPa"), ("sun.max.fill", "紫外线", String(format: "%.1f", forecast.daily.uvIndexMax.first ?? 0)),
                      ("cloud.rain.fill", "降水", String(format: "%.1f mm", c.precipitation)), ("sunrise.fill", "日出 / 日落", "\(sunrise) / \(sunset)")]
        for rowStart in stride(from: 0, to: values.count, by: 2) {
            let row = UIStackView(); row.axis = .horizontal; row.spacing = 10; row.distribution = .fillEqually
            for item in values[rowStart..<min(rowStart + 2, values.count)] { row.addArrangedSubview(MetricView(symbol: item.0, title: item.1, value: item.2)) }
            metricsStack.addArrangedSubview(row)
        }
    }

    private func updateGradient(condition: WeatherCondition, isDay: Bool) {
        let colors: [UIColor]
        if !isDay { colors = [.init(red: 0.04, green: 0.08, blue: 0.20, alpha: 1), .init(red: 0.12, green: 0.20, blue: 0.38, alpha: 1), .init(red: 0.25, green: 0.32, blue: 0.47, alpha: 1)] }
        else if condition.isRainy { colors = [.init(red: 0.15, green: 0.24, blue: 0.34, alpha: 1), .init(red: 0.28, green: 0.43, blue: 0.55, alpha: 1), .init(red: 0.53, green: 0.65, blue: 0.70, alpha: 1)] }
        else { colors = [.init(red: 0.08, green: 0.34, blue: 0.69, alpha: 1), .init(red: 0.27, green: 0.62, blue: 0.85, alpha: 1), .init(red: 0.68, green: 0.84, blue: 0.93, alpha: 1)] }
        UIView.animate(withDuration: 0.5) { self.gradientLayer.colors = colors.map(\.cgColor) }
    }

    private func setLoading(_ loading: Bool) {
        messageLabel.text = nil
        retryButton.isHidden = true
        if loading && response == nil { activity.startAnimating() } else { activity.stopAnimating() }
        contentStack.alpha = loading && response == nil ? 0.28 : 1
        if !loading { scrollView.refreshControl?.endRefreshing() }
    }

    private func showError(_ message: String) {
        activity.stopAnimating(); scrollView.refreshControl?.endRefreshing()
        // 已有缓存时继续展示旧数据，网络失败不使用错误页覆盖内容。
        messageLabel.text = response == nil ? message : nil
        retryButton.isHidden = response != nil
        contentStack.alpha = response == nil ? 0.28 : 1
    }

    private func restoreCachedWeather() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let cache = try? JSONDecoder().decode(OpenMeteoWeatherCache.self, from: data) else { return }
        response = cache.forecast
        if activeLocation == nil {
            activeLocation = CurrentLocation(
                latitude: cache.latitude,
                longitude: cache.longitude,
                altitude: nil,
                city: cache.city,
                adcode: nil,
                address: cache.address
            )
        }
        cityLabel.text = activeLocation?.city.nonEmpty ?? cache.city.nonEmpty ?? "当地天气"
        addressLabel.text = activeLocation?.address.nonEmpty ?? cache.address.nonEmpty ?? "Open-Meteo 实时预报"
        render(cache.forecast)
        saveWeatherWidgetSnapshot(cache.forecast, location: activeLocation ?? Self.beijingFallback)
    }

    private func saveCache(_ forecast: OpenMeteoForecast, location: CurrentLocation) {
        let cache = OpenMeteoWeatherCache(
            savedAt: Date(), latitude: location.latitude, longitude: location.longitude,
            city: location.city, address: location.address, forecast: forecast
        )
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
        saveWeatherWidgetSnapshot(forecast, location: location)
    }

    private func saveWeatherWidgetSnapshot(_ forecast: OpenMeteoForecast, location: CurrentLocation) {
        let current = forecast.current
        let snapshot = WeatherWidgetSnapshot(
            savedAt: Date(), city: location.city,
            address: location.address.isEmpty ? location.city : location.address,
            temperature: Int(current.temperature.rounded()),
            weatherCode: current.weatherCode, isDay: current.isDay == 1
        )
        guard let defaults = UserDefaults(suiteName: WeatherWidgetSnapshot.appGroupID),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: WeatherWidgetSnapshot.key)
        WidgetCenter.shared.reloadTimelines(ofKind: "RealtimeWeatherWidget")
    }

    private func parseDate(_ string: String, timezone: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezone); formatter.dateFormat = string.count == 10 ? "yyyy-MM-dd" : "yyyy-MM-dd'T'HH:mm"
        return formatter.date(from: string)
    }
    private func hourFormatter(timezone: String) -> DateFormatter { let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.timeZone = TimeZone(identifier: timezone); f.dateFormat = "HH:mm"; return f }
    private func dayTitle(_ string: String, index: Int, timezone: String) -> String { if index == 0 { return "今天" }; if index == 1 { return "明天" }; guard let date = parseDate(string, timezone: timezone) else { return string }; let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "E"; return f.string(from: date) }
    private func isDayHour(_ date: Date?) -> Bool { guard let date else { return true }; let h = Calendar.current.component(.hour, from: date); return h >= 6 && h < 19 }

    private static let beijingFallback = CurrentLocation(latitude: 39.9042, longitude: 116.4074, altitude: nil, city: "北京市", adcode: nil, address: "定位不可用，展示北京市天气")
}

private struct OpenMeteoWeatherCache: Codable {
    let savedAt: Date
    let latitude: Double
    let longitude: Double
    let city: String
    let address: String
    let forecast: OpenMeteoForecast
}

private struct WeatherWidgetSnapshot: Codable {
    static let appGroupID = "group.cn.navibeidou.beidou"
    static let key = "weather_widget_snapshot_v1"

    let savedAt: Date
    let city: String
    let address: String
    let temperature: Int
    let weatherCode: Int
    let isDay: Bool
}

private struct OpenMeteoForecast: Codable {
    let timezone: String; let current: Current; let hourly: Hourly; let daily: Daily
    struct Current: Codable {
        let time: String, temperature: Double, apparentTemperature: Double, precipitation: Double, windSpeed: Double, pressure: Double
        let humidity: Int, isDay: Int, weatherCode: Int
        enum CodingKeys: String, CodingKey { case time, precipitation; case temperature = "temperature_2m"; case apparentTemperature = "apparent_temperature"; case humidity = "relative_humidity_2m"; case isDay = "is_day"; case weatherCode = "weather_code"; case windSpeed = "wind_speed_10m"; case pressure = "pressure_msl" }
    }
    struct Hourly: Codable {
        let time: [String], temperature: [Double], precipitationProbability: [Int], weatherCode: [Int]
        enum CodingKeys: String, CodingKey { case time; case temperature = "temperature_2m"; case precipitationProbability = "precipitation_probability"; case weatherCode = "weather_code" }
    }
    struct Daily: Codable {
        let time: [String], weatherCode: [Int], temperatureMax: [Double], temperatureMin: [Double], sunrise: [String], sunset: [String], precipitationProbability: [Int], uvIndexMax: [Double]
        enum CodingKeys: String, CodingKey { case time, sunrise, sunset; case weatherCode = "weather_code"; case temperatureMax = "temperature_2m_max"; case temperatureMin = "temperature_2m_min"; case precipitationProbability = "precipitation_probability_max"; case uvIndexMax = "uv_index_max" }
    }
}

private struct WeatherCondition {
    let title: String, symbol: String, tint: UIColor, isRainy: Bool
    init(code: Int, isDay: Bool) {
        switch code {
        case 0: title = "晴朗"; symbol = isDay ? "sun.max.fill" : "moon.stars.fill"; tint = .systemYellow; isRainy = false
        case 1, 2: title = "少云"; symbol = isDay ? "cloud.sun.fill" : "cloud.moon.fill"; tint = .systemYellow; isRainy = false
        case 3: title = "阴天"; symbol = "cloud.fill"; tint = .white; isRainy = false
        case 45, 48: title = "有雾"; symbol = "cloud.fog.fill"; tint = .white; isRainy = false
        case 51...57: title = "毛毛雨"; symbol = "cloud.drizzle.fill"; tint = .white; isRainy = true
        case 61...67: title = "降雨"; symbol = "cloud.rain.fill"; tint = .white; isRainy = true
        case 71...77: title = "降雪"; symbol = "cloud.snow.fill"; tint = .white; isRainy = true
        case 80...82: title = "阵雨"; symbol = "cloud.heavyrain.fill"; tint = .white; isRainy = true
        case 85, 86: title = "阵雪"; symbol = "cloud.snow.fill"; tint = .white; isRainy = true
        case 95...96: title = "雷雨"; symbol = "cloud.bolt.rain.fill"; tint = UIColor(red: 0.34, green: 0.42, blue: 0.78, alpha: 1); isRainy = true
        case 97...99: title = "强雷雨"; symbol = "cloud.bolt.rain.fill"; tint = UIColor(red: 0.28, green: 0.32, blue: 0.68, alpha: 1); isRainy = true
        default: title = "天气变化"; symbol = "cloud.fill"; tint = .white; isRainy = false
        }
    }
}

private final class ForecastHourView: UIView {
    init(time: String, symbol: String, temp: Double, rain: Int) {
        super.init(frame: .zero); backgroundColor = UIColor.white.withAlphaComponent(0.13); layer.cornerRadius = 18; layer.cornerCurve = .continuous
        let t = label(time, 12, .medium, .white); let icon = UIImageView(image: UIImage(systemName: symbol)); icon.tintColor = .white; icon.contentMode = .scaleAspectFit
        let degree = label("\(Int(temp.rounded()))°", 18, .semibold, .white); let chance = label(rain > 0 ? "\(rain)%" : "—", 10, .medium, UIColor.white.withAlphaComponent(0.65))
        let stack = UIStackView(arrangedSubviews: [t, icon, degree, chance]); stack.axis = .vertical; stack.alignment = .center; stack.spacing = 6; stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack); NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 70), stack.topAnchor.constraint(equalTo: topAnchor, constant: 10), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8), stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor), icon.heightAnchor.constraint(equalToConstant: 26), icon.widthAnchor.constraint(equalToConstant: 32)])
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class ForecastDayView: UIView {
    init(day: String, symbol: String, low: Double, high: Double, rain: Int) {
        super.init(frame: .zero)
        let dayLabel = label(day, 14, .semibold, .white); let icon = UIImageView(image: UIImage(systemName: symbol)); icon.tintColor = .white; icon.contentMode = .scaleAspectFit
        let rainLabel = label(rain > 0 ? "\(rain)%" : "", 11, .medium, UIColor.white.withAlphaComponent(0.65)); let temp = label("\(Int(low.rounded()))°     \(Int(high.rounded()))°", 14, .semibold, .white); temp.textAlignment = .right
        [dayLabel, icon, rainLabel, temp].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: 48), dayLabel.leadingAnchor.constraint(equalTo: leadingAnchor), dayLabel.centerYAnchor.constraint(equalTo: centerYAnchor), dayLabel.widthAnchor.constraint(equalToConstant: 62), icon.leadingAnchor.constraint(equalTo: dayLabel.trailingAnchor), icon.centerYAnchor.constraint(equalTo: centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 30), icon.heightAnchor.constraint(equalToConstant: 25), rainLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7), rainLabel.centerYAnchor.constraint(equalTo: centerYAnchor), temp.trailingAnchor.constraint(equalTo: trailingAnchor), temp.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class MetricView: UIView {
    init(symbol: String, title: String, value: String) {
        super.init(frame: .zero); backgroundColor = UIColor.white.withAlphaComponent(0.14); layer.cornerRadius = 20; layer.cornerCurve = .continuous; layer.borderWidth = 0.6; layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        let icon = UIImageView(image: UIImage(systemName: symbol)); icon.tintColor = UIColor.white.withAlphaComponent(0.8); icon.contentMode = .scaleAspectFit
        let titleLabel = label(title, 12, .medium, UIColor.white.withAlphaComponent(0.65)); let valueLabel = label(value, 18, .semibold, .white); valueLabel.adjustsFontSizeToFitWidth = true
        [icon, titleLabel, valueLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: 102), icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14), icon.topAnchor.constraint(equalTo: topAnchor, constant: 14), icon.widthAnchor.constraint(equalToConstant: 22), icon.heightAnchor.constraint(equalToConstant: 22), titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7), titleLabel.centerYAnchor.constraint(equalTo: icon.centerYAnchor), valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14), valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10), valueLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)])
    }
    required init?(coder: NSCoder) { fatalError() }
}

private func label(_ text: String, _ size: CGFloat, _ weight: UIFont.Weight, _ color: UIColor) -> UILabel { let l = UILabel(); l.text = text; l.font = .systemFont(ofSize: size, weight: weight); l.textColor = color; return l }
private extension String { var nonEmpty: String? { isEmpty ? nil : self } }
private extension Array { subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil } }
