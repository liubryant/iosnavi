//
//  ApiClient.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  URLSession 轻封装。对应 Android 项目中 OkHttp 的简单GET请求工具。
//

import Foundation

/// 广告权限/版本信息查询结果 (对应后端 /api/info 接口)
struct PermissionInfo {
    /// 是否允许展示广告
    let isPermissionReceiveAd: Bool
    /// 服务端下发的版本号
    let versionCode: Int
    /// 广告关闭策略标识
    let adCloseType: String
}

enum ApiClient {

    struct WeatherAPIResult {
        let json: [String: Any]?
        let errorMessage: String?
    }

    struct SunsetPrediction: Codable {
        struct Factor: Codable {
            let title: String
            let value: Double
            let detail: String
        }

        let quality: Double
        let confidence: Double
        let modelName: String
        let dateLabel: String
        let vividnessIndex: Double
        let aerosolProxyIndex: Double
        let sunsetTime: String
        let goldenHour: String
        let cloudDescription: String
        let cloudCover: Int?
        let visibilityKm: Double?
        let humidity: Int?
        let rainProbability: Int
        let factors: [Factor]

        var percentage: Int {
            Int((quality * 100).rounded())
        }

        var vividnessPercentage: Int {
            Int((vividnessIndex * 100).rounded())
        }

        var aerosolProxyPercentage: Int {
            Int((aerosolProxyIndex * 100).rounded())
        }
    }

    /// 查询广告展示权限/版本信息
    static func fetchPermissionInfo(completion: @escaping (PermissionInfo?) -> Void) {
        guard let url = URL(string: UrlConstants.permissionInfo) else {
            completion(nil)
            return
        }
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let payload = (json["data"] as? [String: Any]) ?? json
            let info = PermissionInfo(
                isPermissionReceiveAd: payload["isPermissionReceiveAd"] as? Bool ?? true,
                versionCode: payload["versionCode"] as? Int ?? 0,
                adCloseType: payload["adCloseType"] as? String ?? ""
            )
            DispatchQueue.main.async { completion(info) }
        }
        task.resume()
    }

    /// 关键字POI搜索 (对应路线规划页"输入终点"联想)
    static func searchPOI(keyword: String, city: String, completion: @escaping ([SelectedPOI]) -> Void) {
        var components = URLComponents(string: UrlConstants.amapPlaceText)
        components?.queryItems = [
            URLQueryItem(name: "key", value: Constants.amapWebServiceKey),
            URLQueryItem(name: "keywords", value: keyword),
            URLQueryItem(name: "city", value: city),
            URLQueryItem(name: "citylimit", value: "false"),
            URLQueryItem(name: "offset", value: "20"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "extensions", value: "base")
        ]
        guard let url = components?.url else {
            completion([])
            return
        }
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pois = json["pois"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let results: [SelectedPOI] = pois.compactMap { poi in
                guard let name = poi["name"] as? String,
                      let location = poi["location"] as? String else { return nil }
                let parts = location.split(separator: ",")
                guard parts.count == 2,
                      let lon = Double(parts[0]),
                      let lat = Double(parts[1]) else { return nil }
                let address = poi["address"] as? String ?? ""
                return SelectedPOI(name: name, address: address, latitude: lat, longitude: lon)
            }
            DispatchQueue.main.async { completion(results) }
        }
        task.resume()
    }

    /// 周边POI搜索 (对应"周边"页面)
    static func searchPOIAround(latitude: Double, longitude: Double, keyword: String = "", radius: Int = 3000, completion: @escaping ([SelectedPOI]) -> Void) {
        var components = URLComponents(string: UrlConstants.amapPlaceAround)
        var queryItems = [
            URLQueryItem(name: "key", value: Constants.amapWebServiceKey),
            URLQueryItem(name: "location", value: "\(longitude),\(latitude)"),
            URLQueryItem(name: "radius", value: String(radius)),
            URLQueryItem(name: "offset", value: "20"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "extensions", value: "base")
        ]
        if !keyword.isEmpty {
            queryItems.append(URLQueryItem(name: "keywords", value: keyword))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            completion([])
            return
        }
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pois = json["pois"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let results: [SelectedPOI] = pois.compactMap { poi in
                guard let name = poi["name"] as? String,
                      let location = poi["location"] as? String else { return nil }
                let parts = location.split(separator: ",")
                guard parts.count == 2,
                      let lon = Double(parts[0]),
                      let lat = Double(parts[1]) else { return nil }
                let address = poi["address"] as? String ?? ""
                return SelectedPOI(name: name, address: address, latitude: lat, longitude: lon)
            }
            DispatchQueue.main.async { completion(results) }
        }
        task.resume()
    }

    /// 查询高德天气信息。city 可传城市名或 adcode；extensions="base"返回实时天气(lives)，"all"返回预报(forecasts)
    static func fetchWeather(city: String, extensions: String = "base", completion: @escaping ([String: Any]?) -> Void) {
        fetchWeatherDetail(city: city, extensions: extensions) { result in
            completion(result.json)
        }
    }

    /// 查询高德天气信息并保留接口错误原因，便于排查 Key/权限/参数问题。
    static func fetchWeatherDetail(city: String, extensions: String = "base", completion: @escaping (WeatherAPIResult) -> Void) {
        var components = URLComponents(string: UrlConstants.amapWeather)
        components?.queryItems = [
            URLQueryItem(name: "key", value: Constants.amapWebServiceKey),
            URLQueryItem(name: "city", value: city),
            URLQueryItem(name: "extensions", value: extensions)
        ]
        guard let url = components?.url else {
            completion(WeatherAPIResult(json: nil, errorMessage: "Invalid weather request URL"))
            return
        }
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            if let error {
                DispatchQueue.main.async {
                    completion(WeatherAPIResult(json: nil, errorMessage: error.localizedDescription))
                }
                return
            }
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async {
                    completion(WeatherAPIResult(json: nil, errorMessage: "Invalid weather response"))
                }
                return
            }
            let status = json["status"] as? String
            let info = json["info"] as? String
            let infocode = json["infocode"] as? String
            let message = [info, infocode].compactMap { $0 }.joined(separator: " / ")
            let errorMessage = status == "1" || message.isEmpty ? nil : message
            DispatchQueue.main.async { completion(WeatherAPIResult(json: json, errorMessage: errorMessage)) }
        }
        task.resume()
    }

    /// 火烧云预测。基于 r-ayin/sunset-prediction 的 Open-Meteo 五因子模型移植，原项目 MIT License。
    static func fetchSunsetPrediction(latitude: Double, longitude: Double, completion: @escaping (SunsetPrediction?) -> Void) {
        fetchSunsetPredictions(latitude: latitude, longitude: longitude) { predictions in
            completion(predictions.first)
        }
    }

    /// 获取今天和明天的火烧云预测。
    static func fetchSunsetPredictions(latitude: Double, longitude: Double, completion: @escaping ([SunsetPrediction]) -> Void) {
        var components = URLComponents(string: UrlConstants.openMeteoForecast)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "daily", value: "sunrise,sunset,precipitation_probability_mean"),
            URLQueryItem(name: "hourly", value: [
                "cloud_cover_low",
                "cloud_cover_mid",
                "cloud_cover_high",
                "cloud_cover",
                "visibility",
                "relative_humidity_2m",
                "precipitation_probability"
            ].joined(separator: ",")),
            URLQueryItem(name: "timezone", value: "Asia/Shanghai"),
            URLQueryItem(name: "forecast_days", value: "3")
        ]
        guard let url = components?.url else {
            completion([])
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let predictions = (0...1).compactMap { computeSunsetPrediction(from: json, dayIndex: $0) }
            DispatchQueue.main.async { completion(predictions) }
        }
        task.resume()
    }

    private static func computeSunsetPrediction(from json: [String: Any], dayIndex: Int) -> SunsetPrediction? {
        guard let daily = json["daily"] as? [String: Any],
              let hourly = json["hourly"] as? [String: Any],
              let dates = daily["time"] as? [String],
              dates.indices.contains(dayIndex),
              let hourlyTimes = hourly["time"] as? [String],
              !hourlyTimes.isEmpty else {
            return nil
        }

        let date = dates[dayIndex]
        let sunsetValues = daily["sunset"] as? [String]
        let sunsetTime = (sunsetValues?.indices.contains(dayIndex) == true ? sunsetValues?[dayIndex] : nil).flatMap(extractClock) ?? ""
        let sunsetHour = sunsetTime.split(separator: ":").first.flatMap { Int($0) } ?? 18
        guard let centerIndex = sunsetHourIndex(in: hourlyTimes, date: date, sunsetHour: sunsetHour) else {
            return nil
        }

        let startIndex = max(0, centerIndex - 1)
        let endIndex = min(hourlyTimes.count, centerIndex + 3)

        func average(_ key: String) -> Double? {
            guard let values = hourly[key] as? [Any] else { return nil }
            let slice = values[startIndex..<min(endIndex, values.count)].compactMap { value -> Double? in
                if let number = value as? NSNumber {
                    return number.doubleValue
                }
                return value as? Double
            }
            guard !slice.isEmpty else { return nil }
            return slice.reduce(0, +) / Double(slice.count)
        }

        let lowCloud = average("cloud_cover_low")
        let midCloud = average("cloud_cover_mid")
        let highCloud = average("cloud_cover_high")
        let totalCloud = average("cloud_cover")
        let humidity = average("relative_humidity_2m")
        let visibilityKm = average("visibility").map { $0 / 1000 }
        let rainProbability = dailyDouble(daily["precipitation_probability_mean"], at: dayIndex) ?? 0

        func value(_ input: Double?, fallback: Double = 0) -> Double {
            input ?? fallback
        }

        var score = 0.0
        var cloudType = "mixed"

        let highIsDominant = value(highCloud) >= 30 && value(lowCloud) < 40
        let lowIsDominant = value(lowCloud) >= 20 && value(lowCloud) <= 55 && value(highCloud) < 40
        let multiLayer = value(highCloud) > 15 && value(lowCloud) > 10
        let overcast = value(totalCloud) > 80
        let clearSky = value(totalCloud) < 10
        var cloudTypeScore = 0.0
        var textureBonus = 0.0

        if highIsDominant && !overcast {
            cloudTypeScore = 0.40
            score += cloudTypeScore
            cloudType = "high_cloud_dominant"
        } else if lowIsDominant && !overcast {
            cloudTypeScore = 0.28
            score += cloudTypeScore
            cloudType = "low_cloud_dominant"
        } else if value(totalCloud) >= 10 && value(totalCloud) <= 75 {
            cloudTypeScore = 0.22
            score += cloudTypeScore
            cloudType = "mixed"
        } else if clearSky {
            cloudTypeScore = 0.05
            score += cloudTypeScore
            cloudType = "clear"
        } else if overcast {
            cloudTypeScore = -0.10
            score += cloudTypeScore
            cloudType = "overcast"
        }

        if multiLayer {
            textureBonus = 0.08
            score += textureBonus
        } else if cloudType == "high_cloud_dominant", value(highCloud) > 40 {
            textureBonus = 0.04
            score += textureBonus
        }

        var visibilityScore = 0.0
        if let visibilityKm {
            if visibilityKm >= 20 {
                visibilityScore = 0.18
            } else if visibilityKm >= 12 {
                visibilityScore = 0.12
            } else if visibilityKm >= 6 {
                visibilityScore = 0.05
            } else {
                visibilityScore = -0.08
            }
            score += visibilityScore
        }

        var humidityScore = 0.0
        if let humidity {
            if (40...60).contains(humidity) {
                humidityScore = 0.15
            } else if (30..<40).contains(humidity) || (60...75).contains(humidity) {
                humidityScore = 0.08
            } else if humidity > 85 {
                humidityScore = -0.10
            } else {
                humidityScore = 0.04
            }
            score += humidityScore
        }

        var rainScore = 0.0
        if rainProbability > 50 {
            rainScore = -0.15
        } else if rainProbability > 25 {
            rainScore = -0.08
        }
        score += rainScore

        let total = value(totalCloud, fallback: 50)
        var totalCloudScore = 0.0
        if total > 75 {
            totalCloudScore = -0.08 * ((total - 75) / 25)
        } else if (15...60).contains(total) {
            totalCloudScore = 0.05
        }
        score += totalCloudScore

        let dataPoints = [lowCloud, midCloud, highCloud, totalCloud, humidity, visibilityKm].filter { $0 != nil }.count
        let confidence = min(1.0, Double(dataPoints) / 6.0 + 0.1)
        score = min(1.0, max(0.0, (score * 100).rounded() / 100))

        let cloudIndex = normalizedPositiveScore(cloudTypeScore + textureBonus, maxScore: 0.48)
        let visibilityIndex = visibilityQualityIndex(visibilityKm)
        let humidityIndex = humidityQualityIndex(humidity)
        let rainIndex = rainQualityIndex(rainProbability)
        let noRainProbabilityIndex = min(1.0, max(0.0, 1.0 - rainProbability / 100.0))
        let totalCloudIndex = totalCloudQualityIndex(totalCloud)
        let vividnessIndex = min(1.0, max(0.0, cloudIndex * 0.45 + visibilityIndex * 0.25 + humidityIndex * 0.15 + rainIndex * 0.10 + totalCloudIndex * 0.05))
        let aerosolProxyIndex = min(1.0, max(0.0, visibilityIndex * 0.75 + humidityIndex * 0.25))

        return SunsetPrediction(
            quality: score,
            confidence: (confidence * 100).rounded() / 100,
            modelName: L10n.t("weather.sunset_model_openmeteo"),
            dateLabel: dayIndex == 0 ? L10n.t("weather.sunset_today") : L10n.t("weather.sunset_tomorrow"),
            vividnessIndex: (vividnessIndex * 100).rounded() / 100,
            aerosolProxyIndex: (aerosolProxyIndex * 100).rounded() / 100,
            sunsetTime: sunsetTime,
            goldenHour: goldenHour(endingAt: sunsetTime),
            cloudDescription: cloudDescription(for: cloudType),
            cloudCover: totalCloud.map { Int($0.rounded()) },
            visibilityKm: visibilityKm.map { ($0 * 10).rounded() / 10 },
            humidity: humidity.map { Int($0.rounded()) },
            rainProbability: Int(rainProbability.rounded()),
            factors: [
                SunsetPrediction.Factor(
                    title: L10n.t("weather.sunset_factor_cloud"),
                    value: cloudIndex,
                    detail: cloudDescription(for: cloudType)
                ),
                SunsetPrediction.Factor(
                    title: L10n.t("weather.sunset_factor_vividness"),
                    value: vividnessIndex,
                    detail: L10n.f("weather.sunset_factor_vividness_detail", "\(Int((vividnessIndex * 100).rounded()))")
                ),
                SunsetPrediction.Factor(
                    title: L10n.t("weather.sunset_factor_aerosol"),
                    value: aerosolProxyIndex,
                    detail: L10n.t("weather.sunset_factor_aerosol_detail")
                ),
                SunsetPrediction.Factor(
                    title: L10n.t("weather.sunset_factor_humidity"),
                    value: humidity.map { min(1.0, max(0.0, $0 / 100)) } ?? humidityIndex,
                    detail: humidity.map { L10n.f("weather.sunset_factor_humidity_detail", "\(Int($0.rounded()))") } ?? L10n.t("weather.sunset_metric_missing")
                ),
                SunsetPrediction.Factor(
                    title: L10n.t("weather.sunset_factor_rain"),
                    value: noRainProbabilityIndex,
                    detail: L10n.f("weather.sunset_factor_rain_detail", "\(Int(rainProbability.rounded()))")
                )
            ]
        )
    }

    private static func normalizedPositiveScore(_ score: Double, maxScore: Double) -> Double {
        min(1.0, max(0.0, score / maxScore))
    }

    private static func visibilityQualityIndex(_ visibilityKm: Double?) -> Double {
        guard let visibilityKm else { return 0.5 }
        if visibilityKm >= 20 { return 1.0 }
        if visibilityKm >= 12 { return 0.75 }
        if visibilityKm >= 6 { return 0.45 }
        return 0.15
    }

    private static func humidityQualityIndex(_ humidity: Double?) -> Double {
        guard let humidity else { return 0.5 }
        if (40...60).contains(humidity) { return 1.0 }
        if (30..<40).contains(humidity) || (60...75).contains(humidity) { return 0.7 }
        if humidity > 85 { return 0.15 }
        return 0.45
    }

    private static func rainQualityIndex(_ rainProbability: Double) -> Double {
        if rainProbability <= 10 { return 1.0 }
        if rainProbability <= 25 { return 0.75 }
        if rainProbability <= 50 { return 0.45 }
        return 0.15
    }

    private static func totalCloudQualityIndex(_ totalCloud: Double?) -> Double {
        guard let totalCloud else { return 0.5 }
        if (15...60).contains(totalCloud) { return 1.0 }
        if (10..<15).contains(totalCloud) || (60...75).contains(totalCloud) { return 0.7 }
        if totalCloud < 10 { return 0.25 }
        return max(0.1, 1.0 - ((totalCloud - 75) / 25))
    }

    private static func sunsetHourIndex(in times: [String], date: String, sunsetHour: Int) -> Int? {
        let candidates: [(distance: Int, index: Int)] = times.enumerated().compactMap { index, time in
            guard time.hasPrefix("\(date)T"),
                  let hourText = time.split(separator: "T").last?.split(separator: ":").first,
                  let hour = Int(hourText),
                  (16...19).contains(hour) else {
                return nil
            }
            return (abs(hour - sunsetHour), index)
        }
        return candidates.sorted { $0.distance < $1.distance }.first?.index
    }

    private static func dailyDouble(_ value: Any?, at index: Int) -> Double? {
        guard let values = value as? [Any], values.indices.contains(index) else { return nil }
        let item = values[index]
        if let number = item as? NSNumber {
            return number.doubleValue
        }
        return item as? Double
    }

    private static func extractClock(from isoTime: String) -> String? {
        guard let timePart = isoTime.split(separator: "T").last else { return nil }
        return String(timePart.prefix(5))
    }

    private static func goldenHour(endingAt sunsetTime: String) -> String {
        let parts = sunsetTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return "" }
        let endMinutes = parts[0] * 60 + parts[1]
        let startMinutes = max(0, endMinutes - 30)
        return String(format: "%02d:%02d - %02d:%02d", startMinutes / 60, startMinutes % 60, endMinutes / 60, endMinutes % 60)
    }

    private static func cloudDescription(for cloudType: String) -> String {
        switch cloudType {
        case "high_cloud_dominant":
            return L10n.t("weather.sunset_cloud_high")
        case "low_cloud_dominant":
            return L10n.t("weather.sunset_cloud_low")
        case "clear":
            return L10n.t("weather.sunset_cloud_clear")
        case "overcast":
            return L10n.t("weather.sunset_cloud_overcast")
        default:
            return L10n.t("weather.sunset_cloud_mixed")
        }
    }
}
