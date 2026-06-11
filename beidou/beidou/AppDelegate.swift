//
//  AppDelegate.swift
//  beidou
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
        return true
    }
}
