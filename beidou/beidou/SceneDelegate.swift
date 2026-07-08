//
//  SceneDelegate.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  SwiftUI 生命周期下的 Scene 级快捷菜单回调，确保桌面长按入口不只唤起首页。
//

import UIKit

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let shortcutItem = connectionOptions.shortcutItem {
            AppShortcutManager.handle(shortcutItem)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(AppShortcutManager.handle(shortcutItem))
    }
}
