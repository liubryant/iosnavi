//
//  POIHistoryStore.swift
//  beidou
//
//  终点搜索历史。只在用户选中终点并点击开始导航后写入。
//

import Foundation

enum POIHistoryStore {
    private static let key = "destination_poi_history"
    private static let maxCount = 20

    static func load() -> [SelectedPOI] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SelectedPOI].self, from: data)) ?? []
    }

    static func save(_ poi: SelectedPOI) {
        var items = load()
        items.removeAll { item in
            item.name == poi.name &&
            abs(item.latitude - poi.latitude) < 0.000001 &&
            abs(item.longitude - poi.longitude) < 0.000001
        }
        items.insert(poi, at: 0)
        if items.count > maxCount {
            items = Array(items.prefix(maxCount))
        }
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
