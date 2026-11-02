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
            .naviDuoContinuityTransition()
    }
}

private extension View {
    /// iPhone Duo 开合时保留同一个 UIKit 根控制器，只对根画面添加轻量过渡。
    /// 右侧始终先显现，展开方向不能与设备的屏幕展开方向相反。
    @ViewBuilder
    func naviDuoContinuityTransition() -> some View {
        if #available(iOS 27.1, *) {
            modifier(NaviDuoContinuityModifier())
        } else {
            self
        }
    }
}

@available(iOS 27.1, *)
private struct NaviDuoContinuityModifier: ViewModifier {
    @State private var contentScale: CGFloat = 1
    @State private var leadingMaskOpacity = 1.0
    @State private var trailingMaskOpacity = 1.0
    @State private var closingHandoffTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            // 以右边缘为固定点缩放：展开时右侧先稳定呈现，再自然延伸到左侧。
            .scaleEffect(contentScale, anchor: .trailing)
            .mask {
                LinearGradient(
                    colors: [
                        .white.opacity(leadingMaskOpacity),
                        .white.opacity(trailingMaskOpacity)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .animation(.linear(duration: 0.08), value: contentScale)
            .animation(.linear(duration: 0.08), value: leadingMaskOpacity)
            .animation(.linear(duration: 0.08), value: trailingMaskOpacity)
            .onHingeChange { oldContext, newContext in
                updateTransition(from: oldContext.hinge, to: newContext.hinge)
            }
            .onDisappear { closingHandoffTask?.cancel() }
    }

    private func updateTransition(from oldHinge: DeviceHinge?, to hinge: DeviceHinge?) {
        closingHandoffTask?.cancel()

        guard let hinge else {
            resetTransition()
            return
        }

        if hinge.status == .closed {
            // 首次在外屏启动不播放动画；仅处理从半展开到完全合拢的收尾。
            guard oldHinge?.status == .partiallyOpen else {
                resetTransition()
                return
            }
            completeClosingHandoff()
            return
        }

        guard hinge.status == .partiallyOpen else {
            resetTransition()
            return
        }

        let progress = min(max(hinge.angle.degrees / 180, 0), 1)

        contentScale = 0.988 + (0.012 * progress)
        // 右侧透明度始终高于左侧：展开时效果从右向左铺开；
        // 合拢时随着 progress 降低，会自然按相反方向收回。
        leadingMaskOpacity = 0.92 + (0.08 * progress)
        trailingMaskOpacity = 0.985 + (0.015 * progress)
    }

    private func completeClosingHandoff() {
        withAnimation(.easeOut(duration: 0.12)) {
            contentScale = 0.982
            leadingMaskOpacity = 0.88
            trailingMaskOpacity = 0.97
        }

        closingHandoffTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.24, dampingFraction: 0.90)) {
                resetTransition()
            }
        }
    }

    private func resetTransition() {
        contentScale = 1
        leadingMaskOpacity = 1
        trailingMaskOpacity = 1
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
