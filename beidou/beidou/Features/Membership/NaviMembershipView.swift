//
//  NaviMembershipView.swift
//  beidou
//
//  金色会员页：展示 App Store 本地化订阅价格，支持购买、恢复购买、
//  服务端 JWS 校验，以及游客权益在自愿登录后的账号同步。
//

import Combine
import StoreKit
import SwiftUI

/// 统一创建会员页。存在导航栈时使用与“地铁线路图”一致的系统 push 转场。
@MainActor
enum NaviMembershipPresentation {
    static func show(from presenter: UIViewController) {
        guard let navigationController = presenter.navigationController else {
            presenter.present(makeViewController(), animated: true)
            return
        }

        weak var membershipController: UIViewController?
        let rootView = NaviMembershipView(onClose: { [weak navigationController] in
            guard let navigationController,
                  let membershipController,
                  navigationController.topViewController === membershipController else { return }
            navigationController.popViewController(animated: true)
        })
        let controller = UIHostingController(rootView: rootView)
        membershipController = controller
        navigationController.pushViewController(controller, animated: true)
    }

    static func makeViewController() -> UIViewController {
        UIHostingController(rootView: NaviMembershipView())
    }
}

@MainActor
final class NaviMembershipViewModel: ObservableObject {
    @Published var isRefreshing = false
    @Published var isProcessing = false
    @Published var statusMessage = "正在加载 App Store 会员套餐…"
    @Published private(set) var displayPrices: [String: String] = [:]
    @Published private(set) var availableProductIDs = Set<String>()

    func loadData() {
        guard !isRefreshing else { return }
        isRefreshing = true
        statusMessage = "正在加载 App Store 会员套餐…"

        Task {
            async let productsRequest = NaviStoreKitService.shared.loadProducts()

            let session = NaviAccountSession.shared
            if session.effectiveMembershipToken != nil {
                try? await session.refreshMembership()
            }

            let products = await productsRequest
            displayPrices = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0.displayPrice) })
            availableProductIDs = Set(products.map(\.id))
            isRefreshing = false

            if products.isEmpty {
                statusMessage = "暂未获取到 App Store 商品，请稍后重试"
            } else if session.isVipActive {
                statusMessage = session.vipExpiresAt.map { "会员权益有效期至 \($0)" } ?? "会员权益已生效"
            } else {
                statusMessage = "请选择套餐并通过 App Store 订阅"
            }
        }
    }

    func price(for plan: MembershipPlan) -> String {
        displayPrices[plan.productID] ?? "获取中…"
    }

    func isAvailable(_ plan: MembershipPlan) -> Bool {
        availableProductIDs.contains(plan.productID)
    }

    func isCurrent(_ plan: MembershipPlan) -> Bool {
        NaviAccountSession.shared.isVipActive
            && NaviAccountSession.shared.appleProductID == plan.productID
    }

    func purchase(plan: MembershipPlan, agreementsAccepted: Bool) {
        guard agreementsAccepted else {
            statusMessage = "请先阅读并同意会员、自动续费、隐私政策和使用条款"
            return
        }
        guard isAvailable(plan) else {
            statusMessage = "该 App Store 商品暂不可购买，请稍后重试"
            return
        }
        guard !isCurrent(plan), !isProcessing else { return }

        isProcessing = true
        statusMessage = "正在打开 App Store 支付…"
        Task {
            do {
                let signed = try await NaviStoreKitService.shared.purchase(productID: plan.productID)
                statusMessage = "支付结果确认中…"
                let session = NaviAccountSession.shared
                let verified = try await NaviMembershipService.shared.verifyApplePurchase(
                    token: session.accessToken,
                    backendProductID: "",
                    appleProductID: signed.productID,
                    transactionID: signed.transactionID,
                    jws: signed.jws
                )
                session.applyAppleVerification(verified)
                await NaviStoreKitService.shared.finish(transactionID: signed.transactionID)

                isProcessing = false
                if verified.transactionAlreadyProcessed {
                    statusMessage = "当前订阅已生效，本次未生成新的续订周期"
                } else if verified.appleActive {
                    statusMessage = verified.appleExpiresAt.map { "支付成功，订阅有效期至 \($0)" }
                        ?? "支付成功，会员已开通"
                } else {
                    statusMessage = "支付已完成，会员状态同步中…"
                    try? await session.refreshMembership()
                }
            } catch is CancellationError {
                isProcessing = false
                statusMessage = "已取消支付"
            } catch {
                isProcessing = false
                statusMessage = error.localizedDescription
            }
        }
    }

    func restorePurchases() {
        guard !isProcessing else { return }
        isProcessing = true
        statusMessage = "正在从 App Store 恢复购买…"

        Task {
            do {
                let transactions = try await NaviStoreKitService.shared.restore()
                var restoredCount = 0
                var lastError: Error?
                for signed in transactions {
                    do {
                        let session = NaviAccountSession.shared
                        let verified = try await NaviMembershipService.shared.verifyApplePurchase(
                            token: session.accessToken,
                            backendProductID: "",
                            appleProductID: signed.productID,
                            transactionID: signed.transactionID,
                            jws: signed.jws
                        )
                        session.applyAppleVerification(verified)
                        await NaviStoreKitService.shared.finish(transactionID: signed.transactionID)
                        restoredCount += 1
                    } catch {
                        lastError = error
                    }
                }

                isProcessing = false
                if restoredCount > 0 {
                    let session = NaviAccountSession.shared
                    statusMessage = session.vipExpiresAt.map { "会员权益已恢复，有效期至 \($0)" }
                        ?? "会员权益已恢复"
                } else if let lastError {
                    statusMessage = lastError.localizedDescription
                } else {
                    statusMessage = "当前 Apple 账户没有可恢复的有效订阅"
                }
            } catch {
                isProcessing = false
                statusMessage = error.localizedDescription
            }
        }
    }
}

struct NaviMembershipView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var session = NaviAccountSession.shared
    @StateObject private var viewModel = NaviMembershipViewModel()
    @State private var selectedPlan = 1
    @State private var hasAcceptedAgreements = false
    @State private var showLogin = false
    @State private var legalDocument: NaviLegalDocument?
    var onClose: (() -> Void)? = nil

    private let plans = MembershipPlan.all
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.027, blue: 0.012).ignoresSafeArea()
            decoration

            VStack(spacing: 0) {
                topBar
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        accountHeader
                        benefitsCard
                        planSection
                        statusArea
                        payMethodDivider
                        payChannelArea
                        tipsCard
                    }
                    .padding(.bottom, 18)
                }
                bottomArea
            }
        }
        .sheet(isPresented: $showLogin) {
            NaviLoginView(onLoggedIn: { viewModel.loadData() })
        }
        .sheet(item: $legalDocument) { document in
            NaviLegalDocumentView(document: document)
        }
        .onAppear { viewModel.loadData() }
    }

    private var decoration: some View {
        VStack {
            HStack {
                Spacer()
                Circle()
                    .fill(Color(red: 0.79, green: 0.45, blue: 0.17).opacity(0.18))
                    .frame(width: 250, height: 250)
                    .blur(radius: 28)
                    .offset(x: 80, y: -80)
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack {
            Button(action: {
                if let onClose {
                    onClose()
                } else {
                    dismiss()
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.membershipLightGold)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text("VIP 会员")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.membershipLightGold)
            Spacer()
            Button(action: { viewModel.loadData() }) {
                if viewModel.isRefreshing {
                    ProgressView().tint(.membershipLightGold)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.membershipLightGold)
                }
            }
            .frame(width: 44, height: 44)
            .disabled(viewModel.isRefreshing || viewModel.isProcessing)
        }
        .padding(.horizontal, 4)
        .background(Color.black.opacity(0.24))
    }

    private var accountHeader: some View {
        HStack(spacing: 13) {
            ZStack {
                LinearGradient(
                    colors: [.membershipLightGold, Color(red: 0.51, green: 0.28, blue: 0.13)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(Circle())
                Image(systemName: session.isVipActive ? "crown.fill" : "person.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(red: 0.31, green: 0.16, blue: 0.07))
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 5) {
                Text(session.isLoggedIn ? session.maskedPhone : "Apple 账户可直接订阅")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Text(membershipSubtitle)
                    .font(.system(size: 13))
                    .foregroundColor(session.isVipActive ? .membershipLightGold : .membershipMutedGold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()

            if !session.isLoggedIn {
                Button("登录同步") { showLogin = true }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 0.46, green: 0.25, blue: 0.10))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Color.membershipLightGold)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var membershipSubtitle: String {
        if session.isVipActive {
            return session.vipExpiresAt.map { "有效期至 \($0)" } ?? "会员权益已生效"
        }
        return "无需登录也可购买，登录后可同步到手机号账号"
    }

    private var benefitsCard: some View {
        VStack(spacing: 17) {
            HStack {
                Text("会员权益")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.membershipLightGold)
                Spacer()
            }

            HStack(spacing: 0) {
                benefit(icon: "rectangle.slash.fill", title: "免开屏广告", subtitle: "启动更清爽")
                benefit(icon: "map.fill", title: "全部720°景区", subtitle: "所有景区畅看")
                benefit(icon: "waveform.circle.fill", title: "VIP导航语音包", subtitle: "专属语音播报")
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.055, blue: 0.03), Color(red: 0.24, green: 0.14, blue: 0.075)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.membershipGold.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private func benefit(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 25, weight: .medium))
                .foregroundColor(.membershipLightGold)
                .frame(height: 30)
            Text(title).font(.system(size: 12, weight: .bold)).foregroundColor(.white)
            Text(subtitle).font(.system(size: 10)).foregroundColor(.membershipMutedGold)
        }
        .frame(maxWidth: .infinity)
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择会员套餐")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.membershipLightGold)
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 11) {
                    ForEach(plans.indices, id: \.self) { index in
                        planCard(plans[index], index: index)
                    }
                }
                .padding(.horizontal, isPad ? 22 : 12)
            }
            .frame(height: isPad ? 190 : 164)
        }
        .padding(.top, isPad ? 28 : 24)
    }

    private func planCard(_ plan: MembershipPlan, index: Int) -> some View {
        let selected = selectedPlan == index
        let badge = badgeStyle(for: index)
        let priceAndPeriod = displayPriceAndPeriod(for: plan)
        return Button(action: { selectedPlan = index }) {
            ZStack(alignment: .top) {
                VStack(spacing: 6) {
                    Spacer().frame(height: 14)
                    if priceAndPeriod == "获取中…" {
                        // 与 AgentClaw 一致：价格返回前使用磨砂色骨架占位，避免文字闪动。
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(red: 0.227, green: 0.180, blue: 0.133))
                            .frame(width: isPad ? 68 : 58, height: isPad ? 26 : 22)
                            .padding(.vertical, 3)
                    } else {
                        Text(priceAndPeriod)
                            .font(.system(size: isPad ? 24 : 20, weight: .bold))
                            .foregroundColor(selected ? .membershipSelectedPrice : .membershipUnselectedPrice)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    Text(plan.name)
                        .font(.system(size: isPad ? 14 : 12, weight: .semibold))
                        .foregroundColor(selected ? .membershipSelectedTitle : .membershipUnselectedTitle)
                    Text(plan.detail)
                        .font(.system(size: isPad ? 12 : 10))
                        .foregroundColor(selected ? .membershipSelectedDetail : .membershipUnselectedDetail)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 4)
                    Spacer()
                }
                .frame(width: isPad ? 158 : 138, height: isPad ? 172 : 148)
                .background(
                    LinearGradient(
                        colors: selected
                            ? [Color(red: 0.286, green: 0.208, blue: 0.133), Color(red: 0.169, green: 0.129, blue: 0.094)]
                            : [Color(red: 0.102, green: 0.082, blue: 0.071), Color(red: 0.102, green: 0.082, blue: 0.071)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            selected ? Color.membershipUnselectedPrice : Color(red: 0.318, green: 0.267, blue: 0.216),
                            lineWidth: selected ? 2 : 1
                        )
                )
                .padding(.top, 16)

                Text(badge.text)
                    .font(.system(size: isPad ? 11 : 9.5, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        LinearGradient(colors: [badge.start, badge.end], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .offset(y: 4)
            }
            .frame(height: isPad ? 190 : 164)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func badgeStyle(for index: Int) -> (text: String, start: Color, end: Color) {
        switch index {
        case 0:
            return ("限时特惠", Color(red: 0.612, green: 0.153, blue: 0.690), Color(red: 0.416, green: 0.106, blue: 0.604))
        case 1:
            return ("超值特惠", Color(red: 1.0, green: 0.702, blue: 0.0), Color(red: 0.961, green: 0.486, blue: 0.0))
        default:
            return ("80%用户选择", Color(red: 1.0, green: 0.420, blue: 0.208), Color(red: 0.898, green: 0.224, blue: 0.208))
        }
    }

    private func displayPriceAndPeriod(for plan: MembershipPlan) -> String {
        let price = viewModel.price(for: plan).replacingOccurrences(of: "¥", with: "￥")
        guard price != "获取中…" else { return price }
        return "\(price)/\(plan.periodUnit)"
    }

    private var statusArea: some View {
        HStack(spacing: 8) {
            if viewModel.isProcessing { ProgressView().tint(.membershipGold) }
            Text(viewModel.statusMessage)
                .font(.system(size: 12))
                .foregroundColor(.membershipReadableMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var payMethodDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color(red: 0.32, green: 0.28, blue: 0.24))
                .frame(width: 20, height: 1)
            Text("支付方式")
                .font(.system(size: 12))
                .foregroundColor(.membershipReadableMuted)
            Rectangle()
                .fill(Color(red: 0.32, green: 0.28, blue: 0.24))
                .frame(width: 20, height: 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }

    private var payChannelArea: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "applelogo")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color(red: 0.525, green: 0.31, blue: 0.176))
                Text("通过 App Store 支付")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(red: 0.525, green: 0.31, blue: 0.176))
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.membershipGold)
            }
            .padding(.horizontal, 16)
            .frame(height: isPad ? 64 : 56)
            .background(Color(red: 0.996, green: 0.922, blue: 0.725))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.membershipGold, lineWidth: 1)
            )

            Button(action: { viewModel.restorePurchases() }) {
                Text("恢复购买")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.membershipMutedGold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isProcessing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("温馨提示", systemImage: "info.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(red: 0.78, green: 0.61, blue: 0.36))
            Text(warmTipsContent)
                .font(.system(size: 11.5))
                .foregroundColor(.membershipTipsText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var warmTipsContent: String {
        """
        1. 本会员为虚拟数字服务，通过苹果 App Store 内购（IAP）完成支付，费用将从您的 Apple ID 账户扣除。
        2. 会员权益在支付成功、服务端确认订单后立即生效，具体到期时间以页面顶部显示为准。
        3. 本套餐为自动续订订阅；除非在当前订阅期结束至少 24 小时前取消，否则将自动续订。您可在 iOS“设置—Apple 账户—订阅”中管理或取消。
        4. 会员可免除 App 冷启动和热启动开屏广告，页面内其他广告仍正常展示。
        5. 若支付后权益未及时到账，可稍后重新进入本页面，或点击「恢复购买」同步订单状态。
        6. 由于数字商品的特殊性，会员一经开通、权益开始使用后原则上不支持退款；如遇重复扣费或支付异常，请通过应用内「用户反馈」联系我们核实处理。
        7. 无需注册或登录即可购买、恢复订阅；登录仅用于在支持的设备间同步账号内容与会员权益。
        8. 开通即代表您已阅读并同意《会员服务协议》《自动续费服务协议》《隐私政策》和《使用条款（EULA）》。
        """
    }

    private var bottomArea: some View {
        let plan = plans[selectedPlan]
        let isCurrent = viewModel.isCurrent(plan)
        let isPayEnabled = !viewModel.isProcessing && !isCurrent && viewModel.isAvailable(plan)
        return VStack(spacing: 5) {
            Button(action: {
                viewModel.purchase(plan: plan, agreementsAccepted: hasAcceptedAgreements)
            }) {
                Group {
                    if viewModel.isProcessing {
                        HStack(spacing: 10) {
                            ProgressView().tint(Color(red: 0.46, green: 0.25, blue: 0.10))
                            Text(processingPaymentText)
                                .font(.system(size: isPad ? 14 : 13, weight: .bold))
                        }
                    } else {
                        HStack(spacing: 8) {
                            Text(displayPriceAndPeriod(for: plan))
                                .font(.system(size: isPad ? 21 : 19, weight: .bold))
                            Text(isCurrent ? "当前套餐" : (session.isVipActive ? "更换套餐" : "立即开通"))
                                .font(.system(size: isPad ? 13 : 12, weight: .bold))
                        }
                    }
                }
                .foregroundColor(isPayEnabled || viewModel.isProcessing
                    ? Color(red: 0.46, green: 0.25, blue: 0.10)
                    : Color(red: 0.76, green: 0.70, blue: 0.64))
                .frame(maxWidth: .infinity, minHeight: isPad ? 56 : 48)
                .background(
                    LinearGradient(
                        colors: isPayEnabled || viewModel.isProcessing
                            ? [Color(red: 0.996, green: 0.922, blue: 0.725), Color(red: 1.0, green: 0.847, blue: 0.537)]
                            : [Color(red: 0.294, green: 0.255, blue: 0.216), Color(red: 0.22, green: 0.192, blue: 0.169)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(Capsule())
            }
            .disabled(!isPayEnabled)
            .padding(.horizontal, 28)
            .padding(.top, 7)

            HStack(spacing: 3) {
                Button(action: { hasAcceptedAgreements.toggle() }) {
                    Image(systemName: hasAcceptedAgreements ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundColor(hasAcceptedAgreements ? .membershipGold : .membershipReadableMuted)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text("请阅读并同意")
                    .font(.system(size: 12))
                    .foregroundColor(.membershipReadableMuted)
                Button("《会员服务协议》") { legalDocument = .vipAgreement }
                Button("《自动续费协议》") { legalDocument = .autoRenewAgreement }
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.membershipGold)

            HStack(spacing: 10) {
                Button("《隐私政策》") { legalDocument = .privacyPolicy }
                Button("《使用条款（EULA）》") {
                    if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                        openURL(url)
                    }
                }
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.membershipGold)
        }
        .padding(.bottom, 8)
        .background(Color(red: 0.055, green: 0.027, blue: 0.012))
    }

    private var processingPaymentText: String {
        let message = viewModel.statusMessage
        if message.contains("确认") { return "支付结果确认中…" }
        if message.contains("恢复") { return "正在恢复购买…" }
        return "正在打开 App Store 支付…"
    }
}

struct MembershipPlan {
    let name: String
    let detail: String
    let badge: String
    let period: String
    let productID: String
    let appleNumericID: String

    var periodUnit: String {
        period.hasPrefix("每") ? String(period.dropFirst()) : period
    }

    static let all = [
        MembershipPlan(
            name: "周会员", detail: "短期体验 · 灵活续费", badge: "限时特惠", period: "每周",
            productID: "cn.navi.vip.week", appleNumericID: "6805419214"
        ),
        MembershipPlan(
            name: "月会员", detail: "热门之选 · 畅享全月", badge: "超值特惠", period: "每月",
            productID: "cn.navi.vip.month", appleNumericID: "6805415814"
        ),
        MembershipPlan(
            name: "年会员", detail: "超值长期 · 尊享一年", badge: "推荐", period: "每年",
            productID: "cn.navi.vip.year", appleNumericID: "6805408437"
        )
    ]
}

private extension Color {
    static let membershipLightGold = Color(red: 1.0, green: 0.91, blue: 0.68)
    static let membershipGold = Color(red: 0.79, green: 0.48, blue: 0.20)
    static let membershipMutedGold = Color(red: 0.72, green: 0.61, blue: 0.43)
    static let membershipReadableMuted = Color(red: 0.69, green: 0.65, blue: 0.61)
    static let membershipTipsText = Color(red: 0.74, green: 0.70, blue: 0.66)
    static let membershipSelectedPrice = Color(red: 1.0, green: 0.88, blue: 0.63)
    static let membershipUnselectedPrice = Color(red: 0.92, green: 0.78, blue: 0.51)
    static let membershipSelectedTitle = Color(red: 1.0, green: 0.96, blue: 0.87)
    static let membershipUnselectedTitle = Color(red: 0.82, green: 0.75, blue: 0.65)
    static let membershipSelectedDetail = Color(red: 0.86, green: 0.75, blue: 0.59)
    static let membershipUnselectedDetail = Color(red: 0.62, green: 0.55, blue: 0.46)
}
