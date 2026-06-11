//
//  SelectedPOI.swift
//  beidou
//
//  通用 POI 数据模型 (高德 GCJ02 坐标)。
//  用于路线规划起终点、POI搜索结果选择、导航参数传递等场景。
//

import Foundation

struct SelectedPOI: Codable, Equatable {
    let name: String
    let address: String
    /// GCJ02 纬度
    let latitude: Double
    /// GCJ02 经度
    let longitude: Double
}
