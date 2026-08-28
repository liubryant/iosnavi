//
//  NaviStoreKitService.swift
//  beidou
//
//  StoreKit 2 自动续订订阅：只负责 Apple 商品、交易和 JWS 凭证；
//  会员发放必须以服务端完成 JWS 验签后的结果为准。
//

import Foundation
import StoreKit

@MainActor
final class NaviStoreKitService {
    static let shared = NaviStoreKitService()

    // App Store Connect 自动续订商品。数字 ID 是 Apple 内部 ID，StoreKit 使用下列产品 ID。
    static let productIDs = [
        "cn.navi.vip.week",   // 6805419214
        "cn.navi.vip.month",  // 6805415814
        "cn.navi.vip.year"    // 6805408437
    ]

    enum StoreError: LocalizedError {
        case productNotFound
        case notEntitled
        case failedVerification
        case pending
        case unknown

        var errorDescription: String? {
            switch self {
            case .productNotFound:
                return "未找到对应的 App Store 订阅商品，请确认商品已可供销售"
            case .notEntitled:
                return "支付未完成"
            case .failedVerification:
                return "Apple 交易凭证校验失败，请重试"
            case .pending:
                return "支付正在等待确认，确认完成后会员将自动开通"
            case .unknown:
                return "支付失败，请稍后重试"
            }
        }
    }

    struct SignedTransaction {
        let transactionID: String
        let originalID: String
        let productID: String
        let jws: String
    }

    private var productsCache: [String: Product] = [:]
    private var updatesListener: Task<Void, Never>?

    private init() {}

    @discardableResult
    func loadProducts() async -> [Product] {
        do {
            let products = try await Product.products(for: Self.productIDs)
            products.forEach { productsCache[$0.id] = $0 }
            return Self.productIDs.compactMap { productsCache[$0] }
        } catch {
            print("[NaviIAP] loadProducts failed: \(error)")
            return []
        }
    }

    func purchase(productID: String) async throws -> SignedTransaction {
        await finishExpiredUnfinishedTransactions()

        let product: Product
        if let cached = productsCache[productID] {
            product = cached
        } else if let fetched = try? await Product.products(for: [productID]).first {
            productsCache[productID] = fetched
            product = fetched
        } else {
            throw StoreError.productNotFound
        }

        switch try await product.purchase() {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            guard isCurrentlyActive(transaction) else {
                await transaction.finish()
                throw StoreError.notEntitled
            }
            return SignedTransaction(
                transactionID: String(transaction.id),
                originalID: String(transaction.originalID),
                productID: transaction.productID,
                jws: verification.jwsRepresentation
            )
        case .userCancelled:
            throw CancellationError()
        case .pending:
            throw StoreError.pending
        @unknown default:
            throw StoreError.unknown
        }
    }

    func finish(transactionID: String) async {
        for await result in Transaction.all {
            if case .verified(let transaction) = result,
               String(transaction.id) == transactionID {
                await transaction.finish()
                return
            }
        }
    }

    func restore() async throws -> [SignedTransaction] {
        await finishExpiredUnfinishedTransactions()
        try await AppStore.sync()

        var transactions: [SignedTransaction] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard Self.productIDs.contains(transaction.productID) else { continue }
            guard isCurrentlyActive(transaction) else {
                await transaction.finish()
                continue
            }
            transactions.append(SignedTransaction(
                transactionID: String(transaction.id),
                originalID: String(transaction.originalID),
                productID: transaction.productID,
                jws: result.jwsRepresentation
            ))
        }
        return transactions
    }

    func startObservingUpdates(
        onSigned: @escaping @MainActor (SignedTransaction) async -> Void
    ) {
        updatesListener?.cancel()
        updatesListener = Task { [weak self] in
            guard let self else { return }
            for await result in Transaction.updates {
                if Task.isCancelled { return }
                guard case .verified(let transaction) = result else { continue }
                guard Self.productIDs.contains(transaction.productID) else { continue }
                guard isCurrentlyActive(transaction) else {
                    await transaction.finish()
                    continue
                }
                await onSigned(SignedTransaction(
                    transactionID: String(transaction.id),
                    originalID: String(transaction.originalID),
                    productID: transaction.productID,
                    jws: result.jwsRepresentation
                ))
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let value):
            return value
        }
    }

    private func isCurrentlyActive(_ transaction: Transaction) -> Bool {
        guard transaction.revocationDate == nil, !transaction.isUpgraded else { return false }
        return transaction.expirationDate.map { $0 > Date() } ?? true
    }

    private func finishExpiredUnfinishedTransactions() async {
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            if !isCurrentlyActive(transaction) {
                await transaction.finish()
            }
        }
    }
}

@MainActor
enum NaviIAPBootstrap {
    private static var hasStarted = false

    static func startObservingTransactions() {
        guard !hasStarted else { return }
        hasStarted = true

        NaviStoreKitService.shared.startObservingUpdates { signed in
            let session = NaviAccountSession.shared
            do {
                let verified = try await NaviMembershipService.shared.verifyApplePurchase(
                    token: session.accessToken,
                    backendProductID: "",
                    appleProductID: signed.productID,
                    transactionID: signed.transactionID,
                    jws: signed.jws
                )
                session.applyAppleVerification(verified)
                await NaviStoreKitService.shared.finish(transactionID: signed.transactionID)
            } catch {
                // 服务端校验失败时不结束交易，下次启动或恢复购买时继续补交。
                print("[NaviIAP] transaction update verification failed: \(error)")
            }
        }
    }
}
