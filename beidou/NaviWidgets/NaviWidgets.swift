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
    case map, cloud, typhoon, sunset, earthquake, moon

    var title: String {
        switch self {
        case .map: return "卫星导航地图"
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
        NaviFeatureWidget<CloudWidgetDescriptor>()
        NaviFeatureWidget<TyphoonWidgetDescriptor>()
        NaviFeatureWidget<SunsetWidgetDescriptor>()
        NaviFeatureWidget<EarthquakeWidgetDescriptor>()
        NaviFeatureWidget<MoonWidgetDescriptor>()
    }
}
