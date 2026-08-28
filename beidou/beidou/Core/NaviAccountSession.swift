//
//  NaviAccountSession.swift
//  beidou
//
//  账号与会员状态的本地会话。账号由服务端按手机号统一识别，
//  本 App 只保存自己的登录凭证，不要求用户登录后才能使用地图功能。
//

import Combine
import Foundation
import Security

@MainActor
final class NaviAccountSession: ObservableObject {
    static let shared = NaviAccountSession()

    private enum Key {
        static let isLoggedIn = "is_logged_in"
        static let userPhone = "user_phone"
        static let isVipActive = "vip_active"
        static let vipExpiresAt = "vip_expires_at"
        static let appleProductID = "apple_product_id"
    }

    private static let tokenAccount = "user_access_token"
    private static let appleGuestTokenAccount = "apple_guest_access_token"

    @Published private(set) var isLoggedIn: Bool
    @Published private(set) var phone: String?
    @Published private(set) var isVipActive: Bool
    @Published private(set) var vipExpiresAt: String?
    @Published private(set) var appleProductID: String?

    private let defaults: UserDefaults
    private let keychain: NaviKeychainStore

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.keychain = NaviKeychainStore()

        let storedPhone = defaults.string(forKey: Key.userPhone)
        let hasToken = !(keychain.string(for: Self.tokenAccount)?.isEmpty ?? true)
        let storedLoggedIn = defaults.bool(forKey: Key.isLoggedIn)
        phone = storedPhone
        isLoggedIn = storedLoggedIn && !(storedPhone?.isEmpty ?? true) && hasToken
        isVipActive = defaults.bool(forKey: Key.isVipActive)
        vipExpiresAt = defaults.string(forKey: Key.vipExpiresAt)
        appleProductID = defaults.string(forKey: Key.appleProductID)

        Constants.isCloseSplashAd = isVipActive
    }

    var accessToken: String? {
        guard isLoggedIn else { return nil }
        return keychain.string(for: Self.tokenAccount)
    }

    var appleGuestAccessToken: String? {
        keychain.string(for: Self.appleGuestTokenAccount)
    }

    var effectiveMembershipToken: String? {
        if let accessToken, !accessToken.isEmpty { return accessToken }
        return appleGuestAccessToken
    }

    var maskedPhone: String {
        guard let phone, phone.count >= 7 else { return phone ?? "" }
        return String(phone.prefix(3)) + " **** " + String(phone.suffix(4))
    }

    func saveLogin(phone: String, accessToken: String) {
        self.phone = phone
        isLoggedIn = !phone.isEmpty && !accessToken.isEmpty
        defaults.set(phone, forKey: Key.userPhone)
        defaults.set(isLoggedIn, forKey: Key.isLoggedIn)
        try? keychain.setString(accessToken, for: Self.tokenAccount)
        postStateChange()
    }

    func updateMembership(active: Bool, expiresAt: String?) {
        isVipActive = active
        vipExpiresAt = expiresAt
        defaults.set(active, forKey: Key.isVipActive)
        if let expiresAt, !expiresAt.isEmpty {
            defaults.set(expiresAt, forKey: Key.vipExpiresAt)
        } else {
            defaults.removeObject(forKey: Key.vipExpiresAt)
        }
        // 会员只免开屏广告，信息流、Banner、激励视频仍正常展示。
        Constants.isCloseSplashAd = active
        postStateChange()
    }

    func applyAppleVerification(_ verification: NaviApplePurchaseVerification) {
        if let guestToken = verification.guestAccessToken {
            try? keychain.setString(guestToken, for: Self.appleGuestTokenAccount)
        }
        setAppleProductID(verification.appleActive ? verification.appleProductID : nil)
        updateMembership(
            active: verification.membership.active || verification.appleActive,
            expiresAt: verification.membership.expiresAt ?? verification.appleExpiresAt
        )
    }

    func refreshMembership() async throws {
        guard let token = effectiveMembershipToken, !token.isEmpty else {
            updateMembership(active: false, expiresAt: nil)
            setAppleProductID(nil)
            return
        }
        let status = try await NaviMembershipService.shared.loadMembership(token: token)
        let apple = try? await NaviMembershipService.shared.loadAppleMembership(token: token)
        setAppleProductID(apple?.active == true ? apple?.productID : nil)
        updateMembership(
            active: status.active || apple?.active == true,
            expiresAt: status.expiresAt ?? apple?.expiresAt
        )
    }

    func bindGuestMembershipAfterLogin() async {
        guard let userToken = accessToken, !userToken.isEmpty,
              let guestToken = appleGuestAccessToken, !guestToken.isEmpty else { return }
        if let status = try? await NaviMembershipService.shared.bindAppleGuestMembership(
            userToken: userToken,
            guestToken: guestToken
        ) {
            updateMembership(active: status.active, expiresAt: status.expiresAt)
        }
    }

    func refreshMembershipSilently() {
        guard effectiveMembershipToken != nil else { return }
        Task { try? await refreshMembership() }
    }

    func logout() {
        phone = nil
        isLoggedIn = false
        defaults.removeObject(forKey: Key.userPhone)
        defaults.set(false, forKey: Key.isLoggedIn)
        try? keychain.setString(nil, for: Self.tokenAccount)
        if appleGuestAccessToken == nil {
            setAppleProductID(nil)
            updateMembership(active: false, expiresAt: nil)
        } else {
            postStateChange()
            refreshMembershipSilently()
        }
    }

    func clearAfterAccountDeletion() {
        logout()
    }

    private func postStateChange() {
        NotificationCenter.default.post(name: .naviAccountStateDidChange, object: self)
    }

    private func setAppleProductID(_ productID: String?) {
        appleProductID = productID
        if let productID, !productID.isEmpty {
            defaults.set(productID, forKey: Key.appleProductID)
        } else {
            defaults.removeObject(forKey: Key.appleProductID)
        }
    }
}

extension Notification.Name {
    static let naviAccountStateDidChange = Notification.Name("beidou.naviAccountStateDidChange")
}

private struct NaviKeychainStore {
    private let service = Bundle.main.bundleIdentifier ?? "cn.navibeidou.beidou"

    func string(for account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setString(_ value: String?, for account: String) throws {
        let query = baseQuery(account: account)
        guard let value, !value.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }

        let data = Data(value.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
        }

        var item = query
        item[kSecValueData as String] = data
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
