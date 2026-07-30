//
//  SavedPlaceStore.swift
//  beidou
//
//  家、公司与收藏地点的本地持久化。
//

import Foundation

enum SavedPlaceKind: String, CaseIterable, Identifiable {
    case home
    case work
    case favorite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return L10n.t("places.home")
        case .work: return L10n.t("places.work")
        case .favorite: return L10n.t("places.favorite")
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .work: return "briefcase.fill"
        case .favorite: return "star.fill"
        }
    }

    var colorName: String {
        switch self {
        case .home: return "systemOrange"
        case .work: return "systemBlue"
        case .favorite: return "systemPurple"
        }
    }
}

enum SavedPlaceStore {
    private static let key = "saved_frequent_places"

    static func place(for kind: SavedPlaceKind) -> SelectedPOI? {
        load()[kind.rawValue]
    }

    static func save(_ place: SelectedPOI, for kind: SavedPlaceKind) {
        var values = load()
        values[kind.rawValue] = place
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: key)
        AppShortcutManager.configureShortcutItems()
    }

    static func remove(_ kind: SavedPlaceKind) {
        var values = load()
        values.removeValue(forKey: kind.rawValue)
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: key)
        AppShortcutManager.configureShortcutItems()
    }

    private static func load() -> [String: SelectedPOI] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: SelectedPOI].self, from: data)) ?? [:]
    }
}
