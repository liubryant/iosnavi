import WidgetKit
import SwiftUI

private struct NaviWidgetEntry: TimelineEntry {
    let date: Date
}

private struct NaviWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> NaviWidgetEntry {
        NaviWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (NaviWidgetEntry) -> Void) {
        completion(NaviWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NaviWidgetEntry>) -> Void) {
        let entry = NaviWidgetEntry(date: Date())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date) ?? entry.date
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

private enum NaviWidgetFeature {
    case map, home, work, cloud, typhoon, sunset, earthquake, moon

    var title: String {
        switch self {
        case .map: return "卫星导航地图"
        case .home: return "回家"
        case .work: return "去公司"
        case .cloud: return "720云"
        case .typhoon: return "台风监测"
        case .sunset: return "火烧云"
        case .earthquake: return "地震速报"
        case .moon: return "月相查询"
        }
    }

    var subtitle: String {
        switch self {
        case .map: return "定位 · 路线 · 实时导航"
        case .home: return "一键驾车导航回家"
        case .work: return "一键驾车导航去公司"
        case .cloud: return "沉浸式探索云端全景"
        case .typhoon: return "追踪路径与实时动态"
        case .sunset: return "查看今天的晚霞概率"
        case .earthquake: return "全球地震信息及时掌握"
        case .moon: return "月相日历与观测指南"
        }
    }

    var icon: String {
        switch self {
        case .map: return "location.north.fill"
        case .home: return "house.fill"
        case .work: return "briefcase.fill"
        case .cloud: return "view.3d"
        case .typhoon: return "tropicalstorm"
        case .sunset: return "sunset.fill"
        case .earthquake: return "waveform.path.ecg.rectangle.fill"
        case .moon: return "moon.stars.fill"
        }
    }

    var route: String {
        switch self {
        case .map: return "map"
        case .home: return "home"
        case .work: return "work"
        case .cloud: return "cloud"
        case .typhoon: return "typhoon"
        case .sunset: return "sunset"
        case .earthquake: return "earthquake"
        case .moon: return "moon"
        }
    }

    var colors: [Color] {
        switch self {
        case .map: return [Color(red: 0.06, green: 0.34, blue: 0.86), Color(red: 0.08, green: 0.72, blue: 0.88)]
        case .home: return [Color(red: 0.05, green: 0.55, blue: 0.30), Color(red: 0.20, green: 0.78, blue: 0.42)]
        case .work: return [Color(red: 0.06, green: 0.35, blue: 0.84), Color(red: 0.10, green: 0.64, blue: 0.94)]
        case .cloud: return [Color(red: 0.08, green: 0.48, blue: 0.93), Color(red: 0.16, green: 0.78, blue: 0.73)]
        case .typhoon: return [Color(red: 0.24, green: 0.26, blue: 0.90), Color(red: 0.55, green: 0.30, blue: 0.91)]
        case .sunset: return [Color(red: 0.98, green: 0.28, blue: 0.30), Color(red: 1.00, green: 0.68, blue: 0.18)]
        case .earthquake: return [Color(red: 0.10, green: 0.43, blue: 0.88), Color(red: 0.20, green: 0.70, blue: 0.88)]
        case .moon: return [Color(red: 0.12, green: 0.16, blue: 0.42), Color(red: 0.43, green: 0.30, blue: 0.72)]
        }
    }
}

private struct FeatureWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NaviWidgetEntry
    let feature: NaviWidgetFeature

    var body: some View {
        ZStack {
            LinearGradient(colors: feature.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            decorativeBackground
            if feature == .map {
                mapContent
            } else {
                standardContent
            }
        }
        .widgetURL(URL(string: "beidounavi://open/\(feature.route)"))
        .modifier(WidgetContainerBackground(colors: feature.colors))
    }

    @ViewBuilder
    private var decorativeBackground: some View {
        GeometryReader { proxy in
            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: proxy.size.width * 0.80)
                .offset(x: proxy.size.width * 0.52, y: -proxy.size.height * 0.24)
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 18)
                .frame(width: proxy.size.height * 0.80)
                .offset(x: -proxy.size.height * 0.30, y: proxy.size.height * 0.58)
        }
    }

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
            HStack {
                iconBadge
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 2)
            Text(feature.title)
                .font(family == .systemSmall ? .headline : .title3.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(feature.subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.80))
                .lineLimit(family == .systemSmall ? 2 : 1)
            if family == .systemMedium {
                HStack(spacing: 5) {
                    Circle().fill(.green.opacity(0.9)).frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.86))
                }
            }
        }
        .padding(16)
    }

    private var mapContent: some View {
        GeometryReader { proxy in
            ZStack {
                Path { path in
                    for index in 1...4 {
                        let x = proxy.size.width * CGFloat(index) / 5
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                    }
                    for index in 1...3 {
                        let y = proxy.size.height * CGFloat(index) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                }
                .stroke(.white.opacity(0.10), lineWidth: 1)

                Path { path in
                    path.move(to: CGPoint(x: proxy.size.width * 0.10, y: proxy.size.height * 0.76))
                    path.addCurve(
                        to: CGPoint(x: proxy.size.width * 0.78, y: proxy.size.height * 0.28),
                        control1: CGPoint(x: proxy.size.width * 0.30, y: proxy.size.height * 0.92),
                        control2: CGPoint(x: proxy.size.width * 0.50, y: proxy.size.height * 0.18)
                    )
                }
                .stroke(.white.opacity(0.92), style: StrokeStyle(lineWidth: 4, lineCap: .round))

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        iconBadge
                        Spacer()
                    }
                    Spacer()
                    Text(feature.title)
                        .font(family == .systemSmall ? .headline : .title3.bold())
                        .foregroundStyle(.white)
                    Text(feature.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }
                .padding(16)

                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: family == .systemSmall ? 26 : 32))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.red)
                    .position(x: proxy.size.width * 0.78, y: proxy.size.height * 0.28)
            }
        }
    }

    private var iconBadge: some View {
        Image(systemName: feature.icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
    }

    private var statusText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "更新于 \(formatter.string(from: entry.date))"
    }
}

private protocol NaviWidgetDescriptor {
    static var kind: String { get }
    static var feature: NaviWidgetFeature { get }
}

private enum MapWidgetDescriptor: NaviWidgetDescriptor {
    static let kind = "SatelliteMapWidget"
    static let feature = NaviWidgetFeature.map
}

private enum HomeWidgetDescriptor: NaviWidgetDescriptor {
    static let kind = "NavigateHomeWidget"
    static let feature = NaviWidgetFeature.home
}

private enum WorkWidgetDescriptor: NaviWidgetDescriptor {
    static let kind = "NavigateWorkWidget"
    static let feature = NaviWidgetFeature.work
}

private enum CloudWidgetDescriptor: NaviWidgetDescriptor {
    static let kind = "CloudPanoramaWidget"
    static let feature = NaviWidgetFeature.cloud
}

private enum TyphoonWidgetDescriptor: NaviWidgetDescriptor {
    static let kind = "TyphoonWidget"
    static let feature = NaviWidgetFeature.typhoon
}

private enum SunsetWidgetDescriptor: NaviWidgetDescriptor {
    static let kind = "SunsetGlowWidget"
    static let feature = NaviWidgetFeature.sunset
}

private enum EarthquakeWidgetDescriptor: NaviWidgetDescriptor {
    static let kind = "EarthquakeWidget"
    static let feature = NaviWidgetFeature.earthquake
}

private enum MoonWidgetDescriptor: NaviWidgetDescriptor {
    static let kind = "MoonPhaseWidget"
    static let feature = NaviWidgetFeature.moon
}

private struct NaviFeatureWidget<Descriptor: NaviWidgetDescriptor>: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Descriptor.kind, provider: NaviWidgetProvider()) { entry in
            FeatureWidgetView(entry: entry, feature: Descriptor.feature)
        }
        .configurationDisplayName(Descriptor.feature.title)
        .description(Descriptor.feature.subtitle)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct WeatherWidgetSnapshot: Codable {
    let savedAt: Date
    let city: String
    let address: String
    let temperature: Int
    let weatherCode: Int
    let isDay: Bool
}

private struct WeatherWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WeatherWidgetSnapshot?
}

private struct WeatherWidgetProvider: TimelineProvider {
    private static let appGroupID = "group.cn.navibeidou.beidou"
    private static let snapshotKey = "weather_widget_snapshot_v1"

    func placeholder(in context: Context) -> WeatherWidgetEntry {
        WeatherWidgetEntry(date: Date(), snapshot: sampleSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherWidgetEntry) -> Void) {
        completion(WeatherWidgetEntry(date: Date(), snapshot: context.isPreview ? sampleSnapshot : loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherWidgetEntry>) -> Void) {
        let entry = WeatherWidgetEntry(date: Date(), snapshot: loadSnapshot())
        let nextUpdate = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadSnapshot() -> WeatherWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let data = defaults.data(forKey: Self.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WeatherWidgetSnapshot.self, from: data)
    }

    private var sampleSnapshot: WeatherWidgetSnapshot {
        WeatherWidgetSnapshot(
            savedAt: Date(), city: "北京市", address: "北京市东城区",
            temperature: 26, weatherCode: 1, isDay: true
        )
    }
}

private struct WeatherWidgetVisual {
    let title: String
    let symbol: String
    let colors: [Color]

    init(code: Int, isDay: Bool) {
        let daytime = [Color(red: 0.08, green: 0.36, blue: 0.72), Color(red: 0.26, green: 0.67, blue: 0.90)]
        let nighttime = [Color(red: 0.04, green: 0.08, blue: 0.22), Color(red: 0.18, green: 0.28, blue: 0.50)]
        let rainy = [Color(red: 0.14, green: 0.25, blue: 0.36), Color(red: 0.36, green: 0.51, blue: 0.62)]

        switch code {
        case 0:
            title = "晴朗"; symbol = isDay ? "sun.max.fill" : "moon.stars.fill"; colors = isDay ? daytime : nighttime
        case 1, 2:
            title = "少云"; symbol = isDay ? "cloud.sun.fill" : "cloud.moon.fill"; colors = isDay ? daytime : nighttime
        case 3:
            title = "阴天"; symbol = "cloud.fill"; colors = isDay ? daytime : nighttime
        case 45, 48:
            title = "有雾"; symbol = "cloud.fog.fill"; colors = rainy
        case 51...57:
            title = "毛毛雨"; symbol = "cloud.drizzle.fill"; colors = rainy
        case 61...67:
            title = "降雨"; symbol = "cloud.rain.fill"; colors = rainy
        case 71...77, 85, 86:
            title = "降雪"; symbol = "cloud.snow.fill"; colors = rainy
        case 80...82:
            title = "阵雨"; symbol = "cloud.heavyrain.fill"; colors = rainy
        case 95...99:
            title = "雷雨"; symbol = "cloud.bolt.rain.fill"; colors = rainy
        default:
            title = "天气变化"; symbol = "cloud.fill"; colors = isDay ? daytime : nighttime
        }
    }
}

private struct RealtimeWeatherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherWidgetEntry

    var body: some View {
        let visual = WeatherWidgetVisual(
            code: entry.snapshot?.weatherCode ?? 1,
            isDay: entry.snapshot?.isDay ?? true
        )
        ZStack {
            LinearGradient(colors: visual.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: family == .systemSmall ? 120 : 180)
                .offset(x: family == .systemSmall ? 68 : 145, y: -55)
            if family == .systemSmall {
                smallContent(visual: visual)
            } else {
                mediumContent(visual: visual)
            }
        }
        .widgetURL(URL(string: "beidounavi://open/weather"))
        .modifier(WidgetContainerBackground(colors: visual.colors))
    }

    private func smallContent(visual: WeatherWidgetVisual) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "location.fill").font(.caption2)
                Text(cityText).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 2)
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: visual.symbol)
                    .font(.system(size: 30, weight: .medium))
                    .symbolRenderingMode(.multicolor)
                Text(temperatureText)
                    .font(.system(size: 35, weight: .light, design: .rounded))
            }
            Text(entry.snapshot == nil ? "打开天气页获取当地天气" : visual.title)
                .font(.caption.weight(.semibold))
            Text(addressText)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(15)
    }

    private func mediumContent(visual: WeatherWidgetVisual) -> some View {
        HStack(spacing: 18) {
            VStack(spacing: 7) {
                Image(systemName: visual.symbol)
                    .font(.system(size: 44, weight: .medium))
                    .symbolRenderingMode(.multicolor)
                Text(visual.title).font(.caption.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(temperatureText)
                    .font(.system(size: 44, weight: .light, design: .rounded))
                Text(cityText).font(.headline).lineLimit(1)
                Label(addressText, systemImage: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(18)
    }

    private var temperatureText: String {
        entry.snapshot.map { "\($0.temperature)°" } ?? "--°"
    }

    private var cityText: String {
        guard let city = entry.snapshot?.city, !city.isEmpty else { return "实时天气" }
        return city
    }

    private var addressText: String {
        guard let address = entry.snapshot?.address, !address.isEmpty else { return "等待应用同步位置" }
        return address
    }
}

private struct RealtimeWeatherWidget: Widget {
    let kind = "RealtimeWeatherWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeatherWidgetProvider()) { entry in
            RealtimeWeatherWidgetView(entry: entry)
        }
        .configurationDisplayName("实时天气")
        .description("显示天气页面当前地点的气温、地址和天气状况。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct WidgetContainerBackground: ViewModifier {
    let colors: [Color]

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(for: .widget) {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        } else {
            content
        }
    }
}

@main
struct NaviWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NaviFeatureWidget<MapWidgetDescriptor>()
        NaviFeatureWidget<HomeWidgetDescriptor>()
        NaviFeatureWidget<WorkWidgetDescriptor>()
        RealtimeWeatherWidget()
        NaviFeatureWidget<CloudWidgetDescriptor>()
        NaviFeatureWidget<TyphoonWidgetDescriptor>()
        NaviFeatureWidget<SunsetWidgetDescriptor>()
        NaviFeatureWidget<EarthquakeWidgetDescriptor>()
        NaviFeatureWidget<MoonWidgetDescriptor>()
    }
}
