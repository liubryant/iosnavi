//
//  ApiClient.swift
//  beidou
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
        var components = URLComponents(string: UrlConstants.amapWeather)
        components?.queryItems = [
            URLQueryItem(name: "key", value: Constants.amapWebServiceKey),
            URLQueryItem(name: "city", value: city),
            URLQueryItem(name: "extensions", value: extensions)
        ]
        guard let url = components?.url else {
            completion(nil)
            return
        }
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(json) }
        }
        task.resume()
    }
}
