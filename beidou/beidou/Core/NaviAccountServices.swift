//
//  NaviAccountServices.swift
//  beidou
//
//  与 iosagentclaw 共用的手机号账号和会员接口。
//

import Foundation
import UIKit

struct NaviLoginResult {
    let phone: String
    let isNewUser: Bool
    let accessToken: String
}

struct NaviMembershipStatus {
    let active: Bool
    let expiresAt: String?
}

struct NaviAppleMembershipStatus {
    let active: Bool
    let expiresAt: String?
    let productID: String?
}

struct NaviApplePurchaseVerification {
    let membership: NaviMembershipStatus
    let guestAccessToken: String?
    let appleActive: Bool
    let appleExpiresAt: String?
    let appleProductID: String?
    let transactionAlreadyProcessed: Bool
}

private enum NaviServiceEndpoint {
    static let baseURL = "https://www.cjym123.cn"
    static let membershipBaseURL = "\(baseURL)/im/bot/navi/vip"
}

final class NaviAuthService {
    static let shared = NaviAuthService()

    func sendCode(phone: String) async throws {
        _ = try await postJSON(path: "/im/bot/login-code", body: ["phone": phone])
    }

    func loginByCode(phone: String, code: String) async throws -> NaviLoginResult {
        try await login(
            path: "/im/bot/login-by-code",
            phone: phone,
            credential: ["code": code]
        )
    }

    func loginByPassword(phone: String, password: String) async throws -> NaviLoginResult {
        try await login(
            path: "/im/bot/login-by-password",
            phone: phone,
            credential: ["password": password]
        )
    }

    func setPassword(phone: String, code: String, password: String) async throws {
        _ = try await postJSON(
            path: "/im/bot/set-password",
            body: ["phone": phone, "code": code, "password": password]
        )
    }

    func deleteAccount(phone: String, code: String) async throws {
        _ = try await postJSON(
            path: "/im/bot/remove_account",
            body: ["phone": phone, "code": code]
        )
    }

    private func login(
        path: String,
        phone: String,
        credential: [String: String]
    ) async throws -> NaviLoginResult {
        let deviceInfo = await MainActor.run {
            (UIDevice.current.model, UIDevice.current.systemVersion)
        }
        var body: [String: Any] = [
            "phone": phone,
            "deviceModel": deviceInfo.0,
            "osVersion": deviceInfo.1,
            "appName": "Navi"
        ]
        credential.forEach { body[$0.key] = $0.value }

        let json = try await postJSON(path: path, body: body)
        let data = json["data"] as? [String: Any] ?? [:]
        let returnedPhone = nonEmptyString(data["phone"]) ?? phone
        let accessToken = nonEmptyString(data["accessToken"])
            ?? nonEmptyString(data["token"])
            ?? ""
        guard !accessToken.isEmpty else {
            throw NSError(
                domain: "NaviAuthService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "登录成功但未取得账号凭证，请稍后重试"]
            )
        }
        return NaviLoginResult(
            phone: returnedPhone,
            isNewUser: data["newUser"] as? Bool ?? false,
            accessToken: accessToken
        )
    }

    private func postJSON(path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: NaviServiceEndpoint.baseURL + path) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await NaviServiceResponse.load(request)
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }
}

final class NaviMembershipService {
    static let shared = NaviMembershipService()

    func loadMembership(token: String) async throws -> NaviMembershipStatus {
        let json = try await makeRequest(path: "/membership", token: token)
        return membershipStatus(from: json)
    }

    func loadAppleMembership(token: String) async throws -> NaviAppleMembershipStatus {
        let json = try await makeRequest(path: "/apple/membership", token: token)
        let data = json["data"] as? [String: Any] ?? [:]
        return NaviAppleMembershipStatus(
            active: data["appleActive"] as? Bool ?? false,
            expiresAt: nonEmptyString(data["appleExpiresAt"]),
            productID: nonEmptyString(data["appleProductId"])
        )
    }

    func bindAppleGuestMembership(
        userToken: String,
        guestToken: String
    ) async throws -> NaviMembershipStatus {
        let json = try await makeRequest(
            path: "/apple/bind",
            method: "POST",
            token: userToken,
            body: ["guestAccessToken": guestToken]
        )
        return membershipStatus(from: json)
    }

    func verifyApplePurchase(
        token: String?,
        backendProductID: String,
        appleProductID: String,
        transactionID: String,
        jws: String
    ) async throws -> NaviApplePurchaseVerification {
        let json = try await makeRequest(
            path: "/apple/verify",
            method: "POST",
            token: token,
            body: [
                "productId": backendProductID,
                "appleProductId": appleProductID,
                "transactionId": transactionID,
                "jws": jws,
                "platform": "ios",
                "bundleId": Bundle.main.bundleIdentifier ?? ""
            ]
        )
        let data = json["data"] as? [String: Any] ?? [:]
        return NaviApplePurchaseVerification(
            membership: membershipStatus(from: json),
            guestAccessToken: nonEmptyString(data["guestAccessToken"]),
            appleActive: data["appleActive"] as? Bool ?? false,
            appleExpiresAt: nonEmptyString(data["appleExpiresAt"]),
            appleProductID: nonEmptyString(data["appleProductId"]),
            transactionAlreadyProcessed: data["transactionAlreadyProcessed"] as? Bool ?? false
        )
    }

    private func makeRequest(
        path: String,
        method: String = "GET",
        token: String? = nil,
        body: [String: Any]? = nil
    ) async throws -> [String: Any] {
        guard let url = URL(string: NaviServiceEndpoint.membershipBaseURL + path) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await NaviServiceResponse.load(request)
    }

    private func membershipStatus(from json: [String: Any]) -> NaviMembershipStatus {
        let data = json["data"] as? [String: Any] ?? [:]
        let active = data["active"] as? Bool
            ?? data["isVip"] as? Bool
            ?? data["isMember"] as? Bool
            ?? false
        return NaviMembershipStatus(
            active: active,
            expiresAt: nonEmptyString(data["expiresAt"])
        )
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }
}

private enum NaviServiceResponse {
    static func load(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let code = json["code"]
        let successCode = (code as? Int == 0) || (code as? String == "0")
        guard (200..<300).contains(http.statusCode), successCode else {
            let message = json["msg"] as? String
                ?? json["message"] as? String
                ?? "请求失败，请稍后重试"
            let businessCode = code as? Int ?? http.statusCode
            throw NSError(
                domain: "NaviService",
                code: businessCode,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        return json
    }
}
