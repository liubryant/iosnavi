//
//  beidouApp.swift
//  beidou
//
//  Created by liuzheng on 2026/6/10.
//

import SwiftUI

@main
struct beidouApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea()
                .statusBar(hidden: false)
        }
    }
}
