//
//  AppShortcutManager.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  首页图标长按快捷入口。当前用于一键导航到最近一次导航目的地。
//

import UIKit

enum AppShortcutManager {
    static let navigateLastDestinationType = "cn.navibeidou.beidou.shortcut.navigateLastDestination"
    static let cloudPanoramaType = "cn.navibeidou.beidou.shortcut.cloudPanorama"
    static let navigateHomeType = "cn.navibeidou.beidou.shortcut.navigateHome"
    static let navigateWorkType = "cn.navibeidou.beidou.shortcut.navigateWork"
    static let navigateLastDestinationNotification = Notification.Name("AppShortcutNavigateLastDestination")
    static let cloudPanoramaNotification = Notification.Name("AppShortcutCloudPanorama")
    static let navigateSavedPlaceNotification = Notification.Name("AppShortcutNavigateSavedPlace")

    private static var pendingNavigateLastDestination = false
    private static var pendingCloudPanorama = false
    private(set) static var pendingSavedPlaceKind: SavedPlaceKind?

    static var hasPendingNavigateLastDestination: Bool {
        pendingNavigateLastDestination
    }

    static var hasPendingCloudPanorama: Bool {
        pendingCloudPanorama
    }

    static func configureShortcutItems() {
        var items: [UIApplicationShortcutItem] = []

        if let destination = POIHistoryStore.load().first {
            items.append(
                UIApplicationShortcutItem(
                    type: navigateLastDestinationType,
                    localizedTitle: "一键导航",
                    localizedSubtitle: "到\(destination.name)",
                    icon: UIApplicationShortcutIcon(systemImageName: "location.fill"),
                    userInfo: nil
                )
            )
        }

        let home = SavedPlaceStore.place(for: .home)
        items.append(
            UIApplicationShortcutItem(
                type: navigateHomeType,
                localizedTitle: "回家",
                localizedSubtitle: home?.name ?? "设置家的位置",
                icon: UIApplicationShortcutIcon(systemImageName: "house.fill"),
                userInfo: nil
            )
        )

        let work = SavedPlaceStore.place(for: .work)
        items.append(
            UIApplicationShortcutItem(
                type: navigateWorkType,
                localizedTitle: "去公司",
                localizedSubtitle: work?.name ?? "设置公司的位置",
                icon: UIApplicationShortcutIcon(systemImageName: "briefcase.fill"),
                userInfo: nil
            )
        )

        items.append(
            UIApplicationShortcutItem(
                type: cloudPanoramaType,
                localizedTitle: "720景区",
                localizedSubtitle: "直达720云景区",
                icon: UIApplicationShortcutIcon(systemImageName: "photo.on.rectangle.angled"),
                userInfo: nil
            )
        )
        UIApplication.shared.shortcutItems = items
    }

    @discardableResult
    static func handle(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        switch shortcutItem.type {
        case navigateLastDestinationType:
            pendingNavigateLastDestination = true
            NotificationCenter.default.post(name: navigateLastDestinationNotification, object: nil)
            return true
        case cloudPanoramaType:
            pendingCloudPanorama = true
            NotificationCenter.default.post(name: cloudPanoramaNotification, object: nil)
            return true
        case navigateHomeType:
            pendingSavedPlaceKind = .home
            NotificationCenter.default.post(name: navigateSavedPlaceNotification, object: nil)
            return true
        case navigateWorkType:
            pendingSavedPlaceKind = .work
            NotificationCenter.default.post(name: navigateSavedPlaceNotification, object: nil)
            return true
        default:
            return false
        }
    }

    static func consumePendingNavigateLastDestination() {
        pendingNavigateLastDestination = false
    }

    static func consumePendingCloudPanorama() {
        pendingCloudPanorama = false
    }

    static func consumePendingSavedPlaceKind() -> SavedPlaceKind? {
        defer { pendingSavedPlaceKind = nil }
        return pendingSavedPlaceKind
    }
}
