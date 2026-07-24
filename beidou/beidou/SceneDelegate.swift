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
        if let url = connectionOptions.urlContexts.first?.url {
            WidgetDeepLinkManager.shared.handle(url)
        }
        if let shortcutItem = connectionOptions.shortcutItem {
            AppShortcutManager.handle(shortcutItem)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        WidgetDeepLinkManager.shared.handle(url)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(AppShortcutManager.handle(shortcutItem))
    }
}
