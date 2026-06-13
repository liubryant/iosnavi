//
//  ContentView.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  Created by liuzheng on 2026/6/10.
//
//  SwiftUI 入口，包裹基于 UIKit 的 RootViewController(隐私合规 → 启动页 → 主页面)。
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        RootViewControllerRepresentable()
            .ignoresSafeArea()
    }
}

private struct RootViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> RootViewController {
        RootViewController()
    }

    func updateUIViewController(_ uiViewController: RootViewController, context: Context) {
        // 无需更新
    }
}

#Preview {
    ContentView()
}
