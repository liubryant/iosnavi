//
//  PrivacyCompliance.swift
//  beidou
//
//  地图SDK隐私合规接口。对应 Android IndexActivity.privacyCompliance()
//  ⚠️ 仅在用户同意《用户协议》和《隐私政策》后调用 agreeAll()。
//

import Foundation

#if canImport(AMapFoundationKit)
import AMapFoundationKit
#endif

#if canImport(MAMapKit)
import MAMapKit
#endif

#if canImport(AMapNaviKit)
import AMapNaviKit
#endif

#if canImport(AMapLocationKit)
import AMapLocationKit
#endif

#if canImport(AMapSearchKit)
import AMapSearchKit
#endif

#if canImport(BMKLocationKit)
import BMKLocationKit
#endif

#if canImport(BaiduMapAPI_Map)
import BaiduMapAPI_Map
#endif

#if canImport(BaiduMapAPI_Search)
import BaiduMapAPI_Search
#endif

enum PrivacyCompliance {

    /// 用户同意隐私政策与用户协议后调用，开启地图/定位/搜索 SDK 的合规开关
    static func agreeAll() {
        guard SpUtil.bool(.agreementAccepted) else { return }
        agreeAMap()
        agreeBaidu()
    }

    private static func agreeAMap() {
        #if canImport(AMapFoundationKit)
        AMapServices.shared().apiKey = Constants.amapAPIKey
        AMapServices.shared().enableHTTPS = true
        #endif

        #if canImport(MAMapKit) || canImport(AMapNaviKit)
        MAMapView.updatePrivacyShow(.didShow, privacyInfo: .didContain)
        MAMapView.updatePrivacyAgree(.didAgree)
        #endif

        #if canImport(AMapLocationKit)
        AMapLocationManager.updatePrivacyShow(.didShow, privacyInfo: .didContain)
        AMapLocationManager.updatePrivacyAgree(.didAgree)
        #endif

        #if canImport(AMapSearchKit)
        AMapSearchAPI.updatePrivacyShow(.didShow, privacyInfo: .didContain)
        AMapSearchAPI.updatePrivacyAgree(.didAgree)
        #endif
    }

    private static func agreeBaidu() {
        #if canImport(BaiduMapAPI_Map)
        BMKMapManager.setAgreePrivacy(true)
        #endif

        #if canImport(BMKLocationKit)
        BMKLocationAuthManager.setAgreePrivacy(true)
        #endif

        #if canImport(BaiduMapAPI_Map)
        mapManager.start(Constants.baiduMapAPIKey, generalDelegate: mapManagerDelegate)
        #endif
    }

    #if canImport(BaiduMapAPI_Map)
    private static let mapManager = BMKMapManager()
    private static let mapManagerDelegate = BaiduMapManagerDelegate()
    #endif
}

#if canImport(BaiduMapAPI_Map)
/// BMKMapManager 启动回调，仅做日志记录
private final class BaiduMapManagerDelegate: NSObject, BMKGeneralDelegate {
    func onGetNetworkState(_ iError: Int32) {
        print("百度地图 网络状态: \(iError)")
    }

    func onGetPermissionState(_ iError: Int32) {
        print("百度地图 权限状态: \(iError)")
    }
}
#endif
