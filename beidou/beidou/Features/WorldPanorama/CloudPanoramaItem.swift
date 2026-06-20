import Foundation

struct CloudScenicItem: Decodable, Hashable {
    let title: String
    let url: URL
    let cover: String
    let category: String

    var id: String { cover }

    static let categories = ["全部", "收藏", "海外", "北京", "上海", "深圳", "云南", "山海", "湖泊", "文博", "5A"]

    static let all: [CloudScenicItem] = {
        guard let url = Bundle.main.url(forResource: "cloud_panorama_items", withExtension: "json")
                ?? Bundle.main.url(forResource: "cloud_panorama_items", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([CloudScenicItem].self, from: data) else {
            print("⚠️ cloud_panorama_items.json is missing or invalid")
            return []
        }
        return items
    }()

    func matches(_ query: String) -> Bool {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || title.localizedCaseInsensitiveContains(value)
    }

    var coverImageURL: URL? {
        // Xcode's synchronized resource group flattens this folder into the app bundle.
        Bundle.main.url(forResource: cover, withExtension: nil)
            ?? Bundle.main.url(forResource: cover, withExtension: nil, subdirectory: "720yun")
    }
}

enum CloudPanoramaFavorites {
    private static let key = "cloud_panorama_favorites"

    static var ids: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: key) }
    }

    static func contains(_ id: String) -> Bool { ids.contains(id) }

    @discardableResult
    static func toggle(_ id: String) -> Bool {
        var values = ids
        let isFavorite: Bool
        if values.contains(id) {
            values.remove(id)
            isFavorite = false
        } else {
            values.insert(id)
            isFavorite = true
        }
        ids = values
        return isFavorite
    }
}
