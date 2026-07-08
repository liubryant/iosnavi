//
//  AppDelegate.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  App生命周期入口。仅做基础设置，不在此处初始化广告/统计/定位等需要隐私授权的SDK，
//  那些初始化由 RootViewController 在用户同意隐私协议后统一触发。
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UINavigationBar.appearance().tintColor = .systemBlue
        AppShortcutManager.configureShortcutItems()
        if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            AppShortcutManager.handle(shortcutItem)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(AppShortcutManager.handle(shortcutItem))
    }
}
