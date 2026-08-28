//
//  NaviLoginView.swift
//  beidou
//
//  参考 iosagentclaw 的手机号验证码/密码登录与账号管理页面。
//

import SwiftUI
import Combine

@MainActor
final class NaviLoginViewModel: ObservableObject {
    @Published var phone = ""
    @Published var code = ""
    @Published var password = ""
    @Published var usesCode = true
    @Published var countdown = 0
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var countdownTask: Task<Void, Never>?

    var canSendCode: Bool {
        phone.count == 11 && countdown == 0 && !isLoading
    }

    var canLogin: Bool {
        guard phone.count == 11, !isLoading else { return false }
        return usesCode ? code.count == 6 : password.count >= 6
    }

    deinit {
        countdownTask?.cancel()
    }

    func sendCode() {
        guard canSendCode else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await NaviAuthService.shared.sendCode(phone: phone)
                isLoading = false
                startCountdown()
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func login(onSuccess: @escaping () -> Void) {
        guard canLogin else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let result: NaviLoginResult
                if usesCode {
                    result = try await NaviAuthService.shared.loginByCode(phone: phone, code: code)
                } else {
                    result = try await NaviAuthService.shared.loginByPassword(phone: phone, password: password)
                }
                NaviAccountSession.shared.saveLogin(
                    phone: result.phone,
                    accessToken: result.accessToken
                )
                await NaviAccountSession.shared.bindGuestMembershipAfterLogin()
                try? await NaviAccountSession.shared.refreshMembership()
                isLoading = false
                onSuccess()
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdown = 60
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if countdown > 0 {
                    countdown -= 1
                } else {
                    return
                }
            }
        }
    }
}

struct NaviLoginView: View {
    var onLoggedIn: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = NaviLoginViewModel()
    @ObservedObject private var session = NaviAccountSession.shared
    @State private var accountAction: AccountAction?
    @State private var legalDocument: NaviLegalDocument?

    var body: some View {
        Group {
            if session.isLoggedIn {
                accountContent
            } else {
                ZStack {
                    Color(red: 0.975, green: 0.97, blue: 0.995)
                        .ignoresSafeArea()
                    VStack(spacing: 0) {
                        topBar
                        loginContent
                    }
                }
            }
        }
        .sheet(item: $accountAction) { action in
            switch action {
            case .setPassword:
                NaviSetPasswordView(phone: session.phone ?? "")
            case .deleteAccount:
                NaviDeleteAccountView(phone: session.phone ?? "") {
                    dismiss()
                }
            }
        }
        .sheet(item: $legalDocument) { document in
            NaviLegalDocumentView(document: document)
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text("登录账号")
                .font(.system(size: 17, weight: .bold))
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 4)
        .background(Color.white.opacity(0.9))
    }

    private var loginContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    ZStack {
                        LinearGradient(
                            colors: [Color(red: 0.40, green: 0.31, blue: 0.96), Color(red: 0.62, green: 0.48, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(Circle())
                        Image(systemName: "person.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 68, height: 68)

                    Text(viewModel.usesCode ? "手机验证码快速登录" : "手机号密码登录")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                    Text("登录为可选操作，不登录也可以正常使用地图与导航功能")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 26)

                VStack(spacing: 16) {
                    labeledField(title: "手机号") {
                        HStack(spacing: 10) {
                            Text("+86")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.naviPurple)
                            Divider().frame(height: 20)
                            TextField("请输入手机号", text: Binding(
                                get: { viewModel.phone },
                                set: { viewModel.phone = String($0.filter(\.isNumber).prefix(11)) }
                            ))
                            .keyboardType(.numberPad)
                            .textContentType(.telephoneNumber)
                        }
                    }

                    if viewModel.usesCode {
                        labeledField(title: "验证码") {
                            HStack {
                                TextField("请输入6位验证码", text: Binding(
                                    get: { viewModel.code },
                                    set: { viewModel.code = String($0.filter(\.isNumber).prefix(6)) }
                                ))
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                Divider().frame(height: 20)
                                Button(action: { viewModel.sendCode() }) {
                                    Text(viewModel.countdown > 0 ? "\(viewModel.countdown)s" : "获取验证码")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(viewModel.canSendCode ? .naviPurple : .secondary)
                                        .frame(width: 78)
                                }
                                .disabled(!viewModel.canSendCode)
                            }
                        }
                    } else {
                        labeledField(title: "密码") {
                            SecureField("请输入密码（至少6位）", text: $viewModel.password)
                                .textContentType(.password)
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: {
                        viewModel.login {
                            onLoggedIn?()
                            dismiss()
                        }
                    }) {
                        Group {
                            if viewModel.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("登录")
                                    .font(.system(size: 16, weight: .bold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            LinearGradient(
                                colors: viewModel.canLogin
                                    ? [.naviPurple, Color(red: 0.61, green: 0.47, blue: 1.0)]
                                    : [Color.gray.opacity(0.4), Color.gray.opacity(0.4)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!viewModel.canLogin)

                    Button(action: {
                        viewModel.usesCode.toggle()
                        viewModel.errorMessage = nil
                    }) {
                        Text(viewModel.usesCode ? "使用密码登录" : "使用验证码登录")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.naviPurple)
                    }
                }
                .padding(.horizontal, 24)

                legalLinks
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
        }
    }

    /// 已登录账号沿用 AgentClaw 的居中弹窗样式，保留修改密码与退出登录。
    private var accountContent: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 560
            let dialogHeight = isCompact
                ? min(max(proxy.size.height * 0.62, 440), proxy.size.height - 20)
                : min(max(proxy.size.height * 0.62, 420), 500)

            ZStack {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("账号管理")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(Color(red: 0.067, green: 0.094, blue: 0.153))
                            Text("管理当前登录账号")
                                .font(.system(size: 13))
                                .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.50))
                        }
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.black)
                                .frame(width: 34, height: 34)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 14) {
                        ZStack {
                            LinearGradient(
                                colors: [.naviPurple, Color(red: 0.57, green: 0.47, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .frame(width: 52, height: 52)
                            .clipShape(Circle())
                            Image(systemName: "person.fill")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text("已登录")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 0.086, green: 0.63, blue: 0.42))
                            Text(session.maskedPhone)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(red: 0.067, green: 0.094, blue: 0.153))
                        }
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color(red: 0.086, green: 0.63, blue: 0.42))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 82)
                    .background(Color(red: 0.969, green: 0.961, blue: 1.0))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(red: 0.91, green: 0.89, blue: 1.0), lineWidth: 1)
                    )
                    .padding(.top, 26)

                    Spacer(minLength: 28)

                    Button(action: { accountAction = .deleteAccount }) {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .font(.system(size: 16, weight: .semibold))
                            Text("注销账号")
                                .font(.system(size: 15, weight: .bold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(Color(red: 0.76, green: 0.25, blue: 0.047))
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Color(red: 1.0, green: 0.97, blue: 0.95))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(red: 0.76, green: 0.25, blue: 0.047).opacity(0.45), lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button(action: { accountAction = .setPassword }) {
                        Text("设置或修改密码")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.09, green: 0.10, blue: 0.14), Color(red: 0.21, green: 0.25, blue: 0.35)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)

                    Button(action: { session.logout() }) {
                        Text("退出登录")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(red: 0.76, green: 0.25, blue: 0.047))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Color(red: 0.94, green: 0.92, blue: 0.89))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(red: 0.76, green: 0.25, blue: 0.047), lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 28)
                .frame(maxWidth: isCompact ? proxy.size.width - 20 : min(proxy.size.width - 48, 520))
                .frame(height: dialogHeight)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 8)
                .padding(isCompact ? 8 : 24)
                .onTapGesture { }
            }
        }
    }

    private func labeledField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            content()
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Color(red: 0.965, green: 0.95, blue: 1.0))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.naviPurple.opacity(0.16), lineWidth: 1)
                )
        }
    }

    private func accountButton(
        title: String,
        icon: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title).font(.system(size: 15, weight: .bold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(destructive ? .red : .primary)
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var legalLinks: some View {
        VStack(spacing: 8) {
            Text("登录即代表您已阅读并同意")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            HStack(spacing: 14) {
                Button("《用户协议》") {
                    legalDocument = .userAgreement
                }
                Button("《隐私政策》") {
                    legalDocument = .privacyPolicy
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.naviPurple)
        }
    }
}

private enum AccountAction: String, Identifiable {
    case setPassword
    case deleteAccount
    var id: String { rawValue }
}

struct NaviSetPasswordView: View {
    let phone: String
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var password = ""
    @State private var countdown = 0
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("验证码将发送至 \(maskedPhone)")) {
                    HStack {
                        TextField("6位验证码", text: Binding(
                            get: { code },
                            set: { code = String($0.filter(\.isNumber).prefix(6)) }
                        ))
                        .keyboardType(.numberPad)
                        Button(countdown > 0 ? "\(countdown)s" : "获取验证码") { sendCode() }
                            .disabled(phone.count != 11 || countdown > 0 || isLoading)
                    }
                    SecureField("新密码（至少6位）", text: $password)
                }
                if let message {
                    Text(message).foregroundColor(message == "密码修改成功" ? .green : .red)
                }
                Button("确认修改") { submit() }
                    .disabled(code.count != 6 || password.count < 6 || isLoading)
            }
            .navigationTitle("设置密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }

    private var maskedPhone: String {
        guard phone.count >= 7 else { return phone }
        return String(phone.prefix(3)) + "****" + String(phone.suffix(4))
    }

    private func sendCode() {
        isLoading = true
        message = nil
        Task {
            do {
                try await NaviAuthService.shared.sendCode(phone: phone)
                isLoading = false
                countdown = 60
                Task {
                    while countdown > 0 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        countdown -= 1
                    }
                }
            } catch {
                isLoading = false
                message = error.localizedDescription
            }
        }
    }

    private func submit() {
        isLoading = true
        message = nil
        Task {
            do {
                try await NaviAuthService.shared.setPassword(phone: phone, code: code, password: password)
                isLoading = false
                message = "密码修改成功"
            } catch {
                isLoading = false
                message = error.localizedDescription
            }
        }
    }
}

struct NaviDeleteAccountView: View {
    let phone: String
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var countdown = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showFinalConfirmation = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("注销后，账号资料将从服务端删除。会员订阅仍需在系统设置的 Apple 账户订阅中单独取消。")
                        .foregroundColor(.red)
                }
                Section(header: Text("验证当前手机号")) {
                    HStack {
                        TextField("6位验证码", text: Binding(
                            get: { code },
                            set: { code = String($0.filter(\.isNumber).prefix(6)) }
                        ))
                        .keyboardType(.numberPad)
                        Button(countdown > 0 ? "\(countdown)s" : "获取验证码") { sendCode() }
                            .disabled(phone.count != 11 || countdown > 0 || isLoading)
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
                Button("永久注销账号", role: .destructive) {
                    showFinalConfirmation = true
                }
                .disabled(code.count != 6 || isLoading)
            }
            .navigationTitle("注销账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .confirmationDialog(
                "确定永久注销当前账号吗？",
                isPresented: $showFinalConfirmation,
                titleVisibility: .visible
            ) {
                Button("确认注销", role: .destructive) { deleteAccount() }
                Button("取消", role: .cancel) { }
            }
        }
    }

    private func sendCode() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await NaviAuthService.shared.sendCode(phone: phone)
                isLoading = false
                countdown = 60
                Task {
                    while countdown > 0 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        countdown -= 1
                    }
                }
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteAccount() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await NaviAuthService.shared.deleteAccount(phone: phone, code: code)
                NaviAccountSession.shared.clearAfterAccountDeletion()
                isLoading = false
                dismiss()
                onDeleted()
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct NaviLegalDocument: Identifiable {
    let id: String
    let title: String
    let resourceName: String

    static let userAgreement = NaviLegalDocument(
        id: "user_agreement",
        title: "用户协议",
        resourceName: "user_agreement"
    )
    static let privacyPolicy = NaviLegalDocument(
        id: "privacy_policy",
        title: "隐私政策",
        resourceName: "privacy_policy"
    )
    static let vipAgreement = NaviLegalDocument(
        id: "vip_agreement",
        title: "会员服务协议",
        resourceName: "vip_agreement"
    )
    static let autoRenewAgreement = NaviLegalDocument(
        id: "auto_renew_agreement",
        title: "自动续费服务协议",
        resourceName: "auto_renew_agreement"
    )
}

struct NaviLegalDocumentView: View {
    let document: NaviLegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                Text(loadText())
                    .font(.system(size: 15))
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private func loadText() -> String {
        let localizedName = L10n.legalResourceName(document.resourceName)
        let candidates = [localizedName, document.resourceName]
        for name in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Legal")
                ?? Bundle.main.url(forResource: name, withExtension: "txt"),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        return "文档加载失败，请稍后重试。"
    }
}

private extension Color {
    static let naviPurple = Color(red: 0.40, green: 0.31, blue: 0.96)
    static let naviGold = Color(red: 0.79, green: 0.53, blue: 0.19)
}
