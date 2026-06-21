import StoreKit
import UIKit

/// App Store 评分相关行为的唯一入口，确保符合苹果审核规则:
/// - 自动提示只调用系统原生 `AppStore.requestReview(in:)` / `SKStoreReviewController.requestReview(in:)`，
///   不做自定义"满意度筛选"弹窗去过滤谁能看到系统评分框。
/// - 每个触发场景只在达到阈值后调用一次，不重复请求(系统本身也会限制 365 天内最多 3 次)。
/// - 侧边栏的手动评分入口是用户主动点击触发，直接跳转 App Store 评论页，不经过任何中间弹窗。
enum ReviewPromptManager {

    /// 记录一次720云景区被浏览过(CloudPanoramaWebViewController 展示时调用)，用于判断是否达到提示评分的阈值。
    static func recordCloudPanoramaSceneViewed(url: URL) {
        var viewed = Set(SpUtil.stringArray(.viewedCloudPanoramaSceneIDs))
        viewed.insert(url.absoluteString)
        SpUtil.setStringArray(Array(viewed), for: .viewedCloudPanoramaSceneIDs)
    }

    /// 浏览满2个720云景区后，返回720首页或App首页时尝试弹出系统原生评分框；仅触发一次。
    static func requestSystemReviewIfEligibleAfterCloudScenes(in viewController: UIViewController) {
        guard !SpUtil.bool(.reviewPromptedAfterCloudScenes) else { return }
        guard SpUtil.stringArray(.viewedCloudPanoramaSceneIDs).count >= 2 else { return }
        guard let scene = viewController.view.window?.windowScene else { return }
        SpUtil.setBool(true, for: .reviewPromptedAfterCloudScenes)
        if #available(iOS 16.0, *) {
            AppStore.requestReview(in: scene)
        } else {
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    /// 侧边栏"评分"入口：用户主动点击，直接跳转 App Store 评论页，不受系统弹窗频率限制。
    static func openAppStoreReviewPage() {
        guard let url = Constants.appStoreReviewURL else { return }
        UIApplication.shared.open(url)
    }
}
