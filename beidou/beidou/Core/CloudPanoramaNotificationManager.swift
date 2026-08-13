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

    private let center = UNUserNotificationCenter.current()
    private let scheduleHours = [10, 12, 16, 20]
    private let scheduleDays = 14
    private let notificationCalendar = Calendar.current

    private override init() {
        super.init()
    }

    func configure() {
        center.delegate = self
        // 清理旧版本可能因滑动清除通知而错误留下的跳转状态。
        UserDefaults.standard.removeObject(forKey: Self.pendingScenicIDKey)
        let category = UNNotificationCategory(
            identifier: Self.notificationCategoryID,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorizationAndScheduleIfNeeded() {
        guard SpUtil.bool(.agreementAccepted) else { return }
        center.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                self?.scheduleDailyRecommendations()
                self?.center.removePendingNotificationRequests(withIdentifiers: [Self.testNotificationID])
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

        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)) { error in
            #if DEBUG
            if let error {
                print("⚠️ 720景区通知添加失败 [\(item.title)]：\(error.localizedDescription)")
            }
            #endif
        }
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
        let fileManager = FileManager.default
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = root.appendingPathComponent("CloudPanoramaNotificationCovers", isDirectory: true)
        let stableName = item.cover
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        let destination = directory.appendingPathComponent(stableName).deletingPathExtension()
            .appendingPathExtension("jpg")

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: destination.path) {
                try writeSquareNotificationCover(from: sourceURL, to: destination)
            }
            return try UNNotificationAttachment(
                identifier: "scenic-cover-\(item.id)",
                url: destination,
                options: [UNNotificationAttachmentOptionsTypeHintKey: "public.jpeg"]
            )
        } catch {
            #if DEBUG
            print("⚠️ 720景区通知封面创建失败 [\(item.title)]：\(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// 折叠通知的附件位置由 iOS 决定。统一生成方形封面，可以让右侧缩略图
    /// 与左侧标题和正文形成规整的同高内容块，避免横图被系统随意截断。
    private func writeSquareNotificationCover(from sourceURL: URL, to destination: URL) throws {
        guard let image = UIImage(contentsOfFile: sourceURL.path), let cgImage = image.cgImage else {
            throw NSError(domain: "CloudPanoramaNotification", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "无法读取景区封面"])
        }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let side = min(width, height)
        let cropRect = CGRect(x: (width - side) / 2, y: (height - side) / 2,
                              width: side, height: side).integral
        guard let cropped = cgImage.cropping(to: cropRect) else {
            throw NSError(domain: "CloudPanoramaNotification", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "景区封面裁剪失败"])
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240))
        let thumbnail = renderer.image { _ in
            UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: 0, width: 240, height: 240))
        }
        guard let data = thumbnail.jpegData(compressionQuality: 0.82) else {
            throw NSError(domain: "CloudPanoramaNotification", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "景区封面压缩失败"])
        }
        try data.write(to: destination, options: .atomic)
    }

    private func handleNotificationResponse(_ response: UNNotificationResponse) {
        // 只有明确点击通知主体才允许跳转。滑动清除、关闭或其他动作均忽略。
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            return
        }
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
