import StoreKit
import UIKit

/// App Store 评分相关行为的唯一入口，确保符合苹果审核规则:
/// - 自动提示只调用系统原生 `AppStore.requestReview(in:)` / `SKStoreReviewController.requestReview(in:)`，
///   不做自定义"满意度筛选"弹窗去过滤谁能看到系统评分框。
/// - 每个版本浏览至少3个不同景区后才开始请求，每24小时最多一次、每个版本最多3次。
/// - 侧边栏的手动评分入口是用户主动点击触发，直接跳转 App Store 评论页，不经过任何中间弹窗。
@MainActor
enum ReviewPromptManager {

    private static let defaults = UserDefaults.standard
    private static var isRequestScheduled = false

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private static var viewedSceneIDsKey: String {
        "review.viewedCloudPanoramaSceneIDs.\(appVersion)"
    }

    private static var attemptCountKey: String {
        "review.attemptCount.\(appVersion)"
    }

    private static var lastRequestDateKey: String {
        "review.lastRequestDate.\(appVersion)"
    }

    /// 记录一次720云景区被浏览过(CloudPanoramaWebViewController 展示时调用)，用于判断是否达到提示评分的阈值。
    static func recordCloudPanoramaSceneViewed(url: URL) {
        var viewed = Set(defaults.stringArray(forKey: viewedSceneIDsKey) ?? [])
        if viewed.insert(url.absoluteString).inserted {
            defaults.set(Array(viewed), forKey: viewedSceneIDsKey)
        }
    }

    /// 每个版本浏览至少3个不同的720云景区后，返回720首页或App首页时尝试请求系统评分。
    static func requestSystemReviewIfEligibleAfterCloudScenes(in viewController: UIViewController) {
        let viewedSceneCount = defaults.stringArray(forKey: viewedSceneIDsKey)?.count ?? 0
        guard viewedSceneCount >= 3 else { return }

        let attemptCount = defaults.integer(forKey: attemptCountKey)
        guard attemptCount < 3, !isRequestScheduled else { return }

        let lastRequestTime = defaults.double(forKey: lastRequestDateKey)
        if lastRequestTime > 0 {
            guard Date().timeIntervalSince1970 - lastRequestTime >= 24 * 60 * 60 else { return }
        }

        isRequestScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isRequestScheduled = false
            guard let scene = viewController.viewIfLoaded?.window?.windowScene,
                  scene.activationState == .foregroundActive else { return }

            defaults.set(attemptCount + 1, forKey: attemptCountKey)
            defaults.set(Date().timeIntervalSince1970, forKey: lastRequestDateKey)
            if #available(iOS 18.0, *) {
                AppStore.requestReview(in: scene)
            } else {
                SKStoreReviewController.requestReview(in: scene)
            }
        }
    }

    /// 侧边栏"评分"入口：用户主动点击，直接跳转 App Store 评论页，不受系统弹窗频率限制。
    static func openAppStoreReviewPage() {
        guard let url = Constants.appStoreReviewURL else { return }
        UIApplication.shared.open(url)
    }
}
