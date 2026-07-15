//
//  CloudPanoramaNotificationManager.swift
//  beidou
//
//  本地 720 景区推荐通知：每天固定时段随机推荐景区，点击直达景区页面。
//

import UIKit
import UserNotifications

final class CloudPanoramaNotificationManager: NSObject {
    static let shared = CloudPanoramaNotificationManager()

    static let openScenicNotification = Notification.Name("CloudPanoramaNotificationOpenScenic")

    private static let pendingScenicIDKey = "cloud_panorama_notification_pending_scenic_id"
    private static let notificationCategoryID = "cloud.panorama.recommendation"
    private static let notificationIDPrefix = "cloud.panorama.daily."
    private static let testNotificationID = "cloud.panorama.test.30s"
    private static let isLaunchTestNotificationEnabled = false

    private let center = UNUserNotificationCenter.current()
    private let scheduleHours = [10, 12, 16, 20]
    private let scheduleDays = 14
    private let notificationCalendar = Calendar.current

    private override init() {
        super.init()
    }

    func configure() {
        center.delegate = self
        let category = UNNotificationCategory(
            identifier: Self.notificationCategoryID,
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorizationAndScheduleIfNeeded() {
        guard SpUtil.bool(.agreementAccepted) else { return }
        center.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                self?.scheduleDailyRecommendations()
                self?.scheduleLaunchTestRecommendation()
            }
        }
    }

    func consumePendingScenicID() -> String? {
        let id = UserDefaults.standard.string(forKey: Self.pendingScenicIDKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingScenicIDKey)
        return id?.isEmpty == false ? id : nil
    }

    private func scheduleDailyRecommendations() {
        let identifiers = (0..<scheduleDays).flatMap { day in
            scheduleHours.map { hour in "\(Self.notificationIDPrefix)\(day).\(hour)" }
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        let items = CloudScenicItem.all
        guard !items.isEmpty else { return }

        let now = Date()
        for day in 0..<scheduleDays {
            for hour in scheduleHours {
                guard let triggerDate = notificationCalendar.date(
                    byAdding: .day,
                    value: day,
                    to: notificationCalendar.startOfDay(for: now)
                ).flatMap({
                    notificationCalendar.date(bySettingHour: hour, minute: 0, second: 0, of: $0)
                }), triggerDate > now else {
                    continue
                }

                let item = items.randomElement() ?? items[0]
                let identifier = "\(Self.notificationIDPrefix)\(day).\(hour)"
                addNotification(identifier: identifier, item: item, trigger: UNCalendarNotificationTrigger(
                    dateMatching: notificationCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate),
                    repeats: false
                ))
            }
        }
    }

    private func scheduleLaunchTestRecommendation() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.testNotificationID])
        guard Self.isLaunchTestNotificationEnabled else { return }
        guard let item = CloudScenicItem.all.randomElement() else { return }
        addNotification(
            identifier: Self.testNotificationID,
            item: item,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 30, repeats: false)
        )
    }

    private func addNotification(identifier: String, item: CloudScenicItem, trigger: UNNotificationTrigger) {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = notificationBody(for: item)
        content.sound = .default
        content.categoryIdentifier = Self.notificationCategoryID
        content.userInfo = ["scenic_id": item.id]

        if let attachment = notificationAttachment(for: item) {
            content.attachments = [attachment]
        }

        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    private func notificationBody(for item: CloudScenicItem) -> String {
        let category = item.category.trimmingCharacters(in: .whitespacesAndNewlines)
        if category.isEmpty || category == "全部" {
            return "今日 720 全景推荐，点击查看沉浸式景区。"
        }
        return "\(category) 720 全景推荐，点击查看沉浸式景区。"
    }

    private func notificationAttachment(for item: CloudScenicItem) -> UNNotificationAttachment? {
        guard let sourceURL = item.coverImageURL else { return nil }
        let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let destination = directory
            .appendingPathComponent("cloud-panorama-notification-\(item.id.hashValue)")
            .appendingPathExtension(ext)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return try UNNotificationAttachment(identifier: "cover", url: destination)
        } catch {
            return nil
        }
    }

    private func handleNotificationResponse(_ response: UNNotificationResponse) {
        guard let scenicID = response.notification.request.content.userInfo["scenic_id"] as? String,
              !scenicID.isEmpty else {
            return
        }
        UserDefaults.standard.set(scenicID, forKey: Self.pendingScenicIDKey)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.openScenicNotification, object: nil)
        }
    }
}

extension CloudPanoramaNotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleNotificationResponse(response)
        completionHandler()
    }
}
