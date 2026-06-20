import Foundation
import WebKit

enum AppCacheManager {
    static var formattedApproximateSize: String {
        let cache = URLCache.shared
        let bytes = Int64(cache.currentDiskUsage + cache.currentMemoryUsage)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// 清理网络与 WebView 缓存，不清除 Cookie、LocalStorage、收藏或业务设置。
    static func clear(completion: @escaping () -> Void) {
        URLCache.shared.removeAllCachedResponses()

        let webCacheTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache
        ]
        WKWebsiteDataStore.default().removeData(
            ofTypes: webCacheTypes,
            modifiedSince: .distantPast
        ) {
            DispatchQueue.main.async(execute: completion)
        }
    }
}
