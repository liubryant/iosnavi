# iosnavi (cn.navibeidou.beidou)

参考 Android 项目 `/Users/liuzheng/StudioProjects/navi`(同包名)用 Swift/UIKit 重写的 iOS App。
工程位于 `beidou/`，复用原 Xcode 模板生成的 `beidou.xcodeproj`(Bundle ID 已是
`cn.navibeidou.beidou`)。

> 本项目在没有完整 Xcode 的环境下编写，**从未实际编译过**。`pod install` 已在本环境成功执行
> (见下方"已完成的环境验证")。下次继续时第一步应该是在装有 Xcode 的 Mac 上打开 `.xcworkspace`
> 编译，把剩余报错逐个修掉(预计主要集中在 Task #6 的 AMapNaviKit 导航代理方法签名)。

## 进度总览 (10个任务)

- [x] #1 基础设施: Podfile / Info.plist / Constants / Util层
- [x] #2 隐私合规与App入口框架 (AgreementViewController / RootViewController / PrivacyCompliance)
- [x] #3 启动页 SplashViewController + 开屏广告
- [x] #4 主页地图(百度地图)+ 左侧抽屉侧边栏 (MapViewController / SideMenuViewController)
- [x] #5 路线规划页 RoutePlanViewController (起终点/驾车-步行-骑行-货车/POI搜索联想)
- [x] #6 高德导航 NaviViewController + TTSController (**重点待验证，见下文**)
- [x] #7 周边/天气/全景/地铁/协议页面 (PoiAroundSearch / Weather / Panorama / Metro / Web)
- [x] #8 信息流/插屏广告定时加载 (PangleFeedAdManager，已接入主页 viewDidAppear)
- [x] #9 资源迁移与主题: App图标已完成；新增 ThemePrimary/ThemeBlue/ThemeBlueDark 三个 Color Set
      (对应 Android colors.xml 的 colorAmethyst/colorPeterRiver/colorBelizeHole)。其余图标资源
      迁移为可选/延后项(见下方说明)
- [x] #10 收尾: pbxproj接入确认 + `pod install` 验证 + LD_RUNPATH_SEARCH_PATHS修复

## 已完成的环境验证 (本次会话新增)

- **`pod install` 已成功执行**，9个pod全部装好:
  `AMap3DMap (11.2.000)` / `AMapFoundation (1.9.0)` / `AMapLocation (2.12.0)` /
  `AMapNavi (11.2.000)` / `AMapSearch (9.8.0)` / `Ads-CN-Beta (7.6.0.3)` /
  `BaiduMapKit (7.1.0)` / `UMCommon (7.5.11)` / `UMDevice (3.6.0)`。
  - **重要**: Podfile 中高德导航的 CocoaPods trunk 名称是 `AMapNavi`(不是 `AMapNaviKit`)，
    已修正。但实际生成的 framework/module 名称仍是 `AMapNaviKit.framework` /
    `AMapFoundationKit.framework`(已核对 `Pods/AMapNavi/AMapNaviKit.framework/Modules/module.modulemap`
    和 `Pods/AMapFoundation/AMapFoundationKit.framework/Modules/module.modulemap`)，
    所以 `NaviViewController.swift` / `PrivacyCompliance.swift` / `LocationManager.swift` 中
    `import AMapNaviKit` / `import AMapFoundationKit` / `import AMapLocationKit` /
    `import AMapSearchKit` **均无需修改，写法正确**。同理 `BaiduMapAPI_Map/Base/Search/Utils`、
    `BUAdSDK`、`UMCommon`、`UMDevice` 的 import 也已逐一核对，与 `Pods/` 下实际 framework 名一致。
  - **已修复**: `pod install` 报的两条 `LD_RUNPATH_SEARCH_PATHS` 警告——已在
    `beidou.xcodeproj/project.pbxproj` 的 `beidou` target Debug/Release 配置中将
    `LD_RUNPATH_SEARCH_PATHS` 与 `LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]` 改为数组形式并加入
    `$(inherited)`，使其继承 CocoaPods 生成的 `Pods-beidou.{debug,release}.xcconfig` 设置。
  - **已修复**: 编译报错 `Multiple commands produce '.../beidou.app/Info.plist'`——原因是
    `INFOPLIST_FILE = beidou/Info.plist` 已指定 `beidou/Info.plist` 用于生成 Info.plist，
    但 Xcode16 的 PBXFileSystemSynchronizedRootGroup 同时把它当作普通资源文件复制到 bundle，
    两者输出路径冲突。已在 `project.pbxproj` 的 `beidou` 同步分组中添加
    `PBXFileSystemSynchronizedBuildFileExceptionSet`(`membershipExceptions = (Info.plist,)`)，
    将 `Info.plist` 排除出 Copy Bundle Resources。

## 下次继续时优先做的事

1. **打开 `beidou.xcworkspace` 用 Xcode 编译**，按报错修复。重点关注:
   - `NaviViewController.swift` 中 `AMapNaviDriveManager` / `AMapNaviWalkManager` /
     `AMapNaviRideManager` 及其 delegate 方法签名(`onCalculateRouteSuccess` /
     `playNaviSoundString:soundStringType:` / `onArrivedDestination` 等)、
     `AMapNaviPoint.location(withLatitude:longitude:)`、`AMapNaviTruckInfo` 的属性名，
     这些是基于常见SDK版本回忆编写的，**未对照实际头文件核对**，文件内已加注释标注。
   - `PangleFeedAdManager.swift` 中 `BUNativeExpressFullscreenVideoAd` 的初始化方法/代理方法名。
2. **(可选) 资源迁移收尾**: 从 `/Users/liuzheng/StudioProjects/navi/app/src/main/res` 迁移
   navi 项目其他图标资源(目前UI图标用的是 SF Symbols 占位，可按需替换为 navi 项目原图标)。
3. **占位符密钥清单**(需用户在对应平台申请后替换 `Constants.swift`):
   - `Constants.interactionID` — 穿山甲插屏广告位ID (PLACEHOLDER_PANGLE_IOS_INTERACTION_ID)
   - `Constants.bannerID` — 穿山甲Banner广告位ID (PLACEHOLDER_PANGLE_IOS_BANNER_ID)
   - `Constants.streamID` — 穿山甲信息流广告位ID (PLACEHOLDER_PANGLE_IOS_STREAM_ID)
   - `Constants.umengAppKey` — 友盟iOS AppKey (PLACEHOLDER_UMENG_IOS_APP_KEY)
   - `Constants.amapWebServiceKey` — 当前复用了 AMap SDK Key，如天气/POI接口报错(INVALID_USER_SCODE等)
     需在高德开放平台单独申请"Web服务"类型Key替换

## 已就绪的真实凭证 (无需替换)

- 百度地图 iOS SDK Key: `Constants.baiduMapAPIKey`
- 高德地图 iOS SDK Key: `Constants.amapAPIKey`
- 穿山甲 App ID: `Constants.pangleAppID`
- 穿山甲开屏广告位ID: `Constants.openID`

## 功能模块速览

- `Features/Root` — 启动流程编排 (协议弹窗 → 初始化SDK → 启动页 → 主页)
- `Features/Onboarding` — 首次启动隐私协议弹窗
- `Features/Splash` — 开屏广告页
- `Features/Home` — 主地图页 + 自定义抽屉侧边栏
- `Features/RoutePlan` — 路线规划(起终点/出行方式)
- `Features/Navigation` — 高德实际导航 + TTS播报
- `Features/Search` — 关键字POI搜索 / 周边搜索
- `Features/Weather` — 天气查询(高德Web天气API)
- `Features/Panorama` — 全景/街景(WKWebView + 百度地图JS API)
- `Features/Metro` — 地铁图(WKWebView)
- `Features/Web` — 服务协议/隐私政策/用户反馈通用容器
- `Core/Analytics` — 友盟统计 + 穿山甲(开屏/Banner/插屏/信息流)广告管理

## 编译运行步骤(用户机器)

`pod install` 已在本环境执行成功，`Pods/` 目录已生成。用户机器上只需:

```bash
cd /Users/liuzheng/Desktop/iosnavi/beidou
open beidou.xcworkspace
```

(若克隆/同步到新机器导致 `Pods/` 缺失或 CocoaPods 版本不同，重新执行一次 `pod install` 即可。)

打开后在 Xcode 中编译，根据报错对照本文件"重点待验证"部分逐项修正。
