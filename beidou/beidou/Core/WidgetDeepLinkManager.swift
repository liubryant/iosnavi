import Foundation

enum WidgetDestination: String {
    case map
    case cloud
    case typhoon
    case sunset
    case earthquake
    case moon
}

final class WidgetDeepLinkManager {
    static let shared = WidgetDeepLinkManager()
    static let openDestinationNotification = Notification.Name("WidgetDeepLinkManager.openDestination")

    private(set) var pendingDestination: WidgetDestination?

    private init() {}

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "beidounavi",
              url.host?.lowercased() == "open",
              let destinationName = url.pathComponents.dropFirst().first,
              let destination = WidgetDestination(rawValue: destinationName.lowercased()) else {
            return false
        }
        pendingDestination = destination
        NotificationCenter.default.post(name: Self.openDestinationNotification, object: nil)
        return true
    }

    func consumePendingDestination() -> WidgetDestination? {
        defer { pendingDestination = nil }
        return pendingDestination
    }
}
