import SwiftUI
import CoreLocation

// MARK: - 归一化天气模型(和风 QWeather 优先，Open-Meteo 兜底)

/// 单点当前天气 + 逐小时 + 灾害预警
/// - `current` / `daily` 沿用 Open-Meteo 字段名：和风的数据也归一化到这套字段，UI 只认一套。
/// - `hourly` / `warnings` / `source` 为 v1.1 新增：和风有值，Open-Meteo 兜底时为空。
struct WeatherSnapshot: Codable, Equatable {
    struct Current: Codable, Equatable {
        let temperature2m: Double
        let relativeHumidity2m: Double
        let apparentTemperature: Double
        let weatherCode: Int
        let windSpeed10m: Double
        let windDirection10m: Double

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case relativeHumidity2m = "relative_humidity_2m"
            case apparentTemperature = "apparent_temperature"
            case weatherCode = "weather_code"
            case windSpeed10m = "wind_speed_10m"
            case windDirection10m = "wind_direction_10m"
        }
    }

    struct Daily: Codable, Equatable {
        let sunrise: [String]
        let sunset: [String]
    }

    let current: Current
    let daily: Daily

    /// "qweather" | "open-meteo"
    var source: String? = nil
    /// 和风 now.text(如"多云"),Open-Meteo 下为 nil(由 weather_code 推)
    var placeText: String? = nil
    var hourly: [HourlyForecast]? = nil
    var warnings: [WeatherWarning]? = nil
}

enum WeatherService {
    private struct OpenMeteoResponse: Decodable {
        struct Hourly: Decodable {
            let time: [String]
            let temperature2m: [Double]
            let weatherCode: [Int]
            let precipitationProbability: [Int?]?

            enum CodingKeys: String, CodingKey {
                case time
                case temperature2m = "temperature_2m"
                case weatherCode = "weather_code"
                case precipitationProbability = "precipitation_probability"
            }
        }

        let current: WeatherSnapshot.Current
        let daily: WeatherSnapshot.Daily
        let hourly: Hourly?
    }

    static func fetch(lat: Double, lng: Double) async throws -> WeatherSnapshot {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", lng)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m"
            ),
            URLQueryItem(name: "daily", value: "sunrise,sunset"),
            URLQueryItem(
                name: "hourly",
                value: "temperature_2m,weather_code,precipitation_probability"
            ),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2"),
        ]
        // 超时 10s + 失败重试一次(移动网络下首次请求偶发超时)
        let request = URLRequest(url: comps.url!, timeoutInterval: 10)
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try decode(data)
        } catch {
            try? await Task.sleep(for: .milliseconds(1200))
            let (data, _) = try await URLSession.shared.data(for: request)
            return try decode(data)
        }
    }

    private static func decode(_ data: Data) throws -> WeatherSnapshot {
        let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        var snapshot = WeatherSnapshot(current: response.current, daily: response.daily)
        snapshot.source = "open-meteo"

        if let hourly = response.hourly {
            let count = min(
                hourly.time.count,
                min(hourly.temperature2m.count, hourly.weatherCode.count)
            )
            let mapped = (0..<count).map { index in
                let code = hourly.weatherCode[index]
                let pop = hourly.precipitationProbability.flatMap {
                    index < $0.count ? $0[index] : nil
                }
                return HourlyForecast(
                    id: hourly.time[index],
                    time: hourly.time[index],
                    temp: hourly.temperature2m[index],
                    icon: "",
                    text: WeatherVisuals.style(for: code).text,
                    pop: pop,
                    weatherCode: code
                )
            }
            snapshot.hourly = upcomingHours(mapped)
        }
        return snapshot
    }

    /// Open-Meteo 的 hourly 从当天 0 点开始；过滤已过去的小时，与和风的 24h 语义保持一致。
    private static func upcomingHours(_ items: [HourlyForecast]) -> [HourlyForecast] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let now = Date()
        let cutoff = Calendar.current.date(
            bySettingHour: Calendar.current.component(.hour, from: now),
            minute: 0,
            second: 0,
            of: now
        ) ?? now
        return items.filter { item in
            guard let date = formatter.date(from: item.time) else { return true }
            return date >= cutoff
        }
    }
}

// MARK: - 空气质量(Open-Meteo Air Quality,免费、无需 key)

/// 当前空气指数(US AQI)
struct AirQualitySnapshot: Codable, Equatable {
    struct Current: Codable, Equatable {
        let usAqi: Int?

        enum CodingKeys: String, CodingKey {
            case usAqi = "us_aqi"
        }
    }

    let current: Current
}

enum AirQualityService {
    static func fetch(lat: Double, lng: Double) async throws -> AirQualitySnapshot {
        var comps = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", lng)),
            URLQueryItem(name: "current", value: "us_aqi"),
        ]
        let request = URLRequest(url: comps.url!, timeoutInterval: 10)
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(AirQualitySnapshot.self, from: data)
        } catch {
            try? await Task.sleep(for: .milliseconds(1200))
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(AirQualitySnapshot.self, from: data)
        }
    }
}

/// AQI 等级文案(US AQI 标准)
enum AirQualityVisuals {
    static func level(_ aqi: Int) -> String {
        switch aqi {
        case ..<51: return "优"
        case ..<101: return "良"
        case ..<151: return "轻度污染"
        case ..<201: return "中度污染"
        case ..<301: return "重度污染"
        default: return "严重污染"
        }
    }

    /// 与全站一致的克制配色：只表达「可骑 / 一般 / 不宜久留」三档
    static func color(_ aqi: Int) -> Color {
        switch aqi {
        case ..<51: return Theme.success
        case ..<151: return Color(red: 0xE0 / 255, green: 0x9B / 255, blue: 0x2D / 255)
        default: return Theme.danger
        }
    }
}

// MARK: - 天气 → 图标 / 文案 / 配色

enum WeatherVisuals {
    struct Style {
        let icon: String
        let tint: Color
        let sky: [Color]
        let text: String
    }

    /// 夜间不再给晴/多云套太阳图标；只改变图标与色调，天气文案保持一致。
    static func style(for code: Int, isNight: Bool = false) -> Style {
        switch code {
        case 0, 1:
            return Style(
                icon: isNight ? "moon.stars.fill" : "sun.max.fill",
                tint: isNight
                    ? Color(red: 0.55, green: 0.64, blue: 0.82)
                    : Color(red: 1.0, green: 0.78, blue: 0.25),
                sky: isNight
                    ? [Color(red: 0.13, green: 0.17, blue: 0.28), Color(red: 0.30, green: 0.38, blue: 0.56)]
                    : [Color(red: 1.0, green: 0.88, blue: 0.55), Color(red: 0.45, green: 0.75, blue: 1.0)],
                text: "晴"
            )
        case 2:
            return Style(
                icon: isNight ? "cloud.moon.fill" : "cloud.sun.fill",
                tint: isNight
                    ? Color(red: 0.55, green: 0.64, blue: 0.82)
                    : Color(red: 1.0, green: 0.78, blue: 0.25),
                sky: isNight
                    ? [Color(red: 0.17, green: 0.21, blue: 0.31), Color(red: 0.38, green: 0.45, blue: 0.60)]
                    : [Color(red: 0.9, green: 0.94, blue: 0.99), Color(red: 0.5, green: 0.68, blue: 0.92)],
                text: "多云"
            )
        case 3:
            return Style(
                icon: "cloud.fill",
                tint: Color(red: 0.55, green: 0.58, blue: 0.64),
                sky: [Color(red: 0.85, green: 0.87, blue: 0.9), Color(red: 0.58, green: 0.61, blue: 0.68)],
                text: "阴"
            )
        case 45, 48:
            return Style(
                icon: "cloud.fog.fill",
                tint: Color(red: 0.5, green: 0.53, blue: 0.58),
                sky: [Color(red: 0.79, green: 0.81, blue: 0.84), Color(red: 0.6, green: 0.63, blue: 0.66)],
                text: "雾"
            )
        case 51, 53, 55, 56, 57:
            return Style(
                icon: "cloud.drizzle.fill",
                tint: Color(red: 0.3, green: 0.55, blue: 0.95),
                sky: [Color(red: 0.72, green: 0.83, blue: 0.95), Color(red: 0.42, green: 0.6, blue: 0.84)],
                text: "小雨"
            )
        case 61, 63, 65, 66, 67, 80, 81, 82:
            return Style(
                icon: "cloud.rain.fill",
                tint: Color(red: 0.25, green: 0.5, blue: 0.92),
                sky: [Color(red: 0.58, green: 0.72, blue: 0.9), Color(red: 0.33, green: 0.5, blue: 0.78)],
                text: "雨"
            )
        case 71, 73, 75, 77:
            return Style(
                icon: "cloud.snow.fill",
                tint: Color(red: 0.35, green: 0.68, blue: 0.92),
                sky: [Color(red: 0.87, green: 0.92, blue: 0.97), Color(red: 0.6, green: 0.77, blue: 0.92)],
                text: "雪"
            )
        case 95, 96, 99:
            return Style(
                icon: "cloud.bolt.rain.fill",
                tint: Color(red: 0.48, green: 0.38, blue: 0.86),
                sky: [Color(red: 0.52, green: 0.52, blue: 0.68), Color(red: 0.28, green: 0.3, blue: 0.48)],
                text: "雷雨"
            )
        default:
            return Style(
                icon: "cloud.fill",
                tint: Color(red: 0.55, green: 0.58, blue: 0.64),
                sky: [Color(red: 0.85, green: 0.87, blue: 0.9), Color(red: 0.58, green: 0.61, blue: 0.68)],
                text: "未知"
            )
        }
    }

    /// 逐小时天气的 time 形如 2026-11-06T21:00+08:00；夜间按 18:00–06:00 处理。
    static func hour(from iso: String) -> Int? {
        guard let tIndex = iso.firstIndex(of: "T") else { return nil }
        let afterT = iso[iso.index(after: tIndex)...]
        return Int(afterT.prefix(2))
    }

    static func isNight(iso: String) -> Bool {
        guard let hour = hour(from: iso) else { return false }
        return hour < 6 || hour >= 18
    }

    static func isNightNow() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 6 || hour >= 18
    }

    /// 风向(8 方位)
    static func windDirection(_ deg: Double) -> String {
        let dirs = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
        let idx = Int((deg + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        return dirs[idx]
    }

    /// "2026-08-24T05:31" → "05:31"
    static func time(_ iso: String) -> String {
        guard iso.count >= 16 else { return iso }
        return String(iso.suffix(5))
    }
}

// MARK: - 出发页骑行信息面板

/// 骑行参考：双地天气对比 + 骑行适宜度仪表盘 + 拥堵预估(高可视化，不只显示数字)
struct RideInfoPanel: View {
    let route: Route?
    let checkpoints: [Checkpoint]
    /// 出发页首屏只露出摘要，避免拥堵卡被底部按钮栏切掉半张；
    /// 调试页 / 其他入口默认仍然展开。
    let collapsible: Bool
    /// 展开时通知外层把面板滚到顶部，避免小屏上展开后只露出半行内容
    let onExpand: (() -> Void)?
    /// 把摘要里的适宜度回传给外层：出发页要据此在「不建议骑行」时先确认再出发
    let onSuitabilityChange: ((Int?) -> Void)?

    @State private var isExpanded: Bool

    init(route: Route?,
         checkpoints: [Checkpoint],
         collapsible: Bool = false,
         initiallyExpanded: Bool = true,
         onExpand: (() -> Void)? = nil,
         onSuitabilityChange: ((Int?) -> Void)? = nil) {
        self.route = route
        self.checkpoints = checkpoints
        self.collapsible = collapsible
        self.onExpand = onExpand
        self.onSuitabilityChange = onSuitabilityChange
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    @Environment(AuthManager.self) private var auth
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var riderCount: Int?
    @State private var riderStatsLoaded = false
    @State private var riderStatsFailed = false
    @State private var currentWeather: WeatherSnapshot?
    @State private var destWeather: WeatherSnapshot?
    @State private var currentLoading = false
    @State private var destLoading = false
    @State private var currentFailed = false
    @State private var destFailed = false
    @State private var locationAuth = CLLocationManager().authorizationStatus
    @State private var locationFetcher = OneShotLocationFetcher()
    @State private var cache: [String: WeatherSnapshot] = [:]
    @State private var currentPlaceName: String?
    @State private var currentCoordinate: CLLocationCoordinate2D?
    @State private var currentAQI: Int?

    /// 路线终点坐标(按 seq 取最后一个带坐标的打卡点)
    private var destCoordinate: (lat: Double, lng: Double)? {
        checkpoints
            .sorted { $0.seq < $1.seq }
            .compactMap { cp -> (Double, Double)? in
                guard let lat = cp.lat, let lng = cp.lng else { return nil }
                return (lat, lng)
            }
            .last
    }

    private var destKey: String {
        guard let c = destCoordinate else { return "none" }
        return String(format: "%.2f,%.2f", c.lat, c.lng)
    }

    private var routeKey: String {
        route.map { "\($0.id)" } ?? "none"
    }

    /// 终点地名：优先路线 end_name，其次最后一个打卡点；有城市时带上城市，
    /// 避免跨城路线只显示「中央公园」这类容易误解的通用地名。
    private var destTitle: String {
        let city = route?.city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        func withCity(_ name: String) -> String {
            guard !city.isEmpty, !name.contains(city) else { return name }
            return "\(city) · \(name)"
        }
        if let end = route?.endName?.trimmingCharacters(in: .whitespacesAndNewlines), !end.isEmpty {
            return withCity(end)
        }
        if let last = checkpoints.sorted(by: { $0.seq < $1.seq }).last,
           !last.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return withCity(last.name)
        }
        return "目的地"
    }

    /// 目的地坐标变化(如 checkpoints 异步到达)时重新拉取
    private var destTaskID: String {
        "\(routeKey)|\(destKey)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if collapsible && !isExpanded {
                collapsedSummary
            } else {
            HStack(spacing: 0) {
                Text("骑行参考")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    // 路况是出发前最先要看的一眼；放在标题行右侧，不必滚到拥堵卡
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Congestion.levelColor(congestionLevel))
                            .frame(width: 5, height: 5)
                        Text(Congestion.short(congestionLevel))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("路况\(Congestion.summary(congestionLevel))")

                    if let aqi = currentAQI {
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(width: 1, height: 10)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(AirQualityVisuals.color(aqi))
                                .frame(width: 5, height: 5)
                            Text("空气 \(aqi) \(AirQualityVisuals.level(aqi))")
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("空气质量指数 \(aqi)，\(AirQualityVisuals.level(aqi))")
                    }
                }
                if collapsible {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) { isExpanded = false }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.chevron)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                    .accessibilityLabel("收起骑行参考")
                }
            }
            .padding(.horizontal, 2)

            weatherCompareCard

            // 顺序＝出发前的决策顺序：先看天，再看路上堵不堵，然后才是安全规则、
            // 同路热度和逐小时。拥堵原先排在逐小时之后，要翻过大半屏才看得到，
            // 而这恰恰是这个页面最该先回答的问题。
            adviceCard

            // 限行属于安全前置信息：放在逐小时预报之前，避免用户还没看到规则就出发；
            // 与路线热度留出更大间距，避免首屏底部只露出卡片的一条圆角边。
            MotoRuleCard(cityHint: currentPlaceName, fallbackCity: route?.city)
                .padding(.top, 12)

            // 路线热度：已经在路上/打算去同一目的地的人数
            RiderPlanCard(
                count: riderCount,
                destName: destTitle,
                isLoading: !riderStatsLoaded,
                failed: riderStatsFailed
            ) {
                Task { await loadRiderStats() }
            }

            WeatherDetailStrip(weather: currentWeather)

            DisclaimerFootnote(text: TripService.fallbackDisclaimer)
            }
        }
        .padding(.horizontal, 20)
        .task(id: destTaskID) {
            await loadDestWeather()
            await loadRiderStats()
        }
        .task {
            await loadCurrentWeather()
        }
        .onChange(of: summaryScore, initial: true) { _, score in
            onSuitabilityChange?(score)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            let current = CLLocationManager().authorizationStatus
            guard current != locationAuth else { return }
            locationAuth = current
            if current == .authorizedWhenInUse || current == .authorizedAlways {
                Task { await loadCurrentWeather() }
            }
        }
    }

    // MARK: 首屏摘要

    private var summaryWeather: WeatherSnapshot? { destWeather ?? currentWeather }

    private var summaryWeatherStyle: WeatherVisuals.Style? {
        summaryWeather.map {
            WeatherVisuals.style(
                for: $0.current.weatherCode,
                isNight: WeatherVisuals.isNightNow()
            )
        }
    }

    private var summaryScore: Int? {
        summaryWeather.map { Suitability.score($0) }
    }

    private var isShortScreen: Bool {
        let height = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .screen.bounds.height ?? 800
        return height < 700
    }

    private var collapsedSummary: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { isExpanded = true }
            onExpand?()
        } label: {
            VStack(alignment: .leading, spacing: isShortScreen ? 8 : 10) {
                HStack(spacing: 4) {
                    Text("骑行参考")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 8)
                    Text("查看详情")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.chevron)
                }

                if isShortScreen {
                    // SE 上三列会顶到按钮栏，改成一条横向结论；空气质量留在详情。
                    shortSummaryRow
                } else {
                    MetricRowLayout {
                        summaryWeatherColumn
                        summaryDivider
                        summarySuitabilityColumn
                        summaryDivider
                        summaryCongestionColumn
                    }

                    HStack(spacing: 6) {
                        if let aqi = currentAQI {
                            Circle()
                                .fill(AirQualityVisuals.color(aqi))
                                .frame(width: 5, height: 5)
                            Text("空气 \(aqi) \(AirQualityVisuals.level(aqi))")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        // 拿不到空气质量时不再补一句「限行与路线热度可在详情查看」：
                        // 右上角已经有「查看详情」，这类指路文案属于重复噪声。
                        Spacer(minLength: 0)
                        HStack(spacing: 4) {
                            Image(systemName: "nosign")
                                .font(.system(size: 11, weight: .semibold))
                            Text("限行提示")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(isShortScreen ? 12 : 14)
            .background(Theme.lightField)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(CardPressStyle(scale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryAccessibilityLabel)
        .accessibilityHint("查看完整详情")
        .accessibilityAddTraits(.isButton)
    }

    private var shortSummaryRow: some View {
        HStack(spacing: 4) {
            if let style = summaryWeatherStyle {
                Image(systemName: style.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(style.tint)
            } else {
                // 拿不到目的地天气时，行首只剩一个「--」：没有图标也没有标签，
                // 用户看不出这一格是天气还是加载失败。小屏也要保留「天气」二字。
                Text("天气")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(summaryWeather.map { "\(Int($0.current.temperature2m.rounded()))°" } ?? "--")
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                // 缺失值和适宜度保持同一档的灰，不要用墨黑粗体假装「有数据」。
                .foregroundStyle(summaryWeather == nil ? Theme.listGray : Theme.ink)
            // 小屏一行放不下「多云 / 适宜度 / 路况 / 限行」四组词：
            // 天气图标已经表达了阴晴，省下「多云」两个字给「路况」——
            // 否则单独一个「缓行」夹在适宜度和限行之间，没人知道它说的是路。
            Text("·")
                .font(.system(size: 12))
                .foregroundStyle(Theme.chevron)
            Text("适宜度")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Text(summaryScore.map { "\($0)" } ?? "--")
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(summaryScore.map(scoreColor) ?? Theme.listGray)
            // 一个 65 放在「适宜度」后面没有判定词等于让用户自己猜量纲：
            // 紧凑行放不下「谨慎骑行」四个字，用两字判定补齐。
            if let score = summaryScore {
                Text(Suitability.shortLabel(score))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text("·")
                .font(.system(size: 12))
                .foregroundStyle(Theme.chevron)
            Text("路况")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Circle()
                .fill(Congestion.levelColor(congestionLevel))
                .frame(width: 5, height: 5)
            Text(Congestion.short(congestionLevel))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("·")
                .font(.system(size: 12))
                .foregroundStyle(Theme.chevron)
            Image(systemName: "nosign")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("限行提示")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var summaryWeatherColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("目的地天气")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let style = summaryWeatherStyle {
                    Image(systemName: style.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(style.tint)
                }
                Text(summaryWeather.map { "\(Int($0.current.temperature2m.rounded()))°" } ?? "--")
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                if let style = summaryWeatherStyle {
                    Text(style.text)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summarySuitabilityColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("骑行适宜度")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(summaryScore.map { "\($0)" } ?? "--")
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .foregroundStyle(summaryScore.map(scoreColor) ?? Theme.listGray)
                if let score = summaryScore {
                    Text(Suitability.label(score))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryCongestionColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("路况")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 5) {
                Circle()
                    .fill(Congestion.levelColor(congestionLevel))
                    .frame(width: 5, height: 5)
                Text(Congestion.short(congestionLevel))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: 1, height: 40)
            .padding(.horizontal, 10)
            .metricRowFixed()
    }

    private var summaryAccessibilityLabel: String {
        let weatherText = summaryWeather.map {
            "\(Int($0.current.temperature2m.rounded())) 度 \(summaryWeatherStyle?.text ?? "")"
        } ?? "天气暂无数据"
        let scoreText = summaryScore.map {
            "\($0) 分，\(Suitability.label($0))"
        } ?? "适宜度暂无数据"
        return "骑行参考，\(weatherText)，\(scoreText)，路况\(Congestion.summary(congestionLevel))"
    }

    // MARK: 双地天气

    /// 起点与终点天气一致时不再并排重复两遍，避免看起来像「复制」出来的数据
    private var weathersMatch: Bool {
        guard let a = currentWeather?.current, let b = destWeather?.current else { return false }
        return Int(a.temperature2m.rounded()) == Int(b.temperature2m.rounded())
            && a.weatherCode == b.weatherCode
    }

    /// 到路线终点的直线距离（公里）。不能用「天气相同」推断位置相近：
    /// 同一时刻几百公里外的城市也可能同温同天气。
    private var distanceToDestKm: Double? {
        guard let from = currentCoordinate, let to = destCoordinate else { return nil }
        let meters = CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.lat, longitude: to.lng))
        return meters / 1000
    }

    /// 终点栏右侧的距离说明：一律给具体距离。
    /// 之前 3 km 内只写「与当前位置相近」，用户无法判断要不要先骑过去，
    /// 也不如一个数字好做决定；1 km 内按 50 m 取整，再远保留一位小数。
    private var proximityNote: String? {
        guard let km = distanceToDestKm else { return nil }
        if km < 1 {
            let meters = max(50, Int((km * 1000 / 50).rounded()) * 50)
            return "距当前位置 \(meters) m"
        }
        if km < 10 { return String(format: "距当前位置 %.1f km", km) }
        return String(format: "距当前位置 %.0f km", km)
    }

    private var weatherCompareCard: some View {
        Group {
            if weathersMatch {
                weatherHalf(
                    title: destTitle,
                    weather: destWeather,
                    loading: destLoading,
                    failed: destFailed || destCoordinate == nil,
                    isCurrent: false,
                    noCoordinate: destCoordinate == nil,
                    note: proximityNote
                )
            } else {
                HStack(spacing: 0) {
                    weatherHalf(
                        title: "当前",
                        weather: currentWeather,
                        loading: currentLoading,
                        failed: currentFailed,
                        isCurrent: true,
                        noCoordinate: false
                    )

                    Rectangle()
                        .fill(Theme.separator)
                        .frame(width: 1)
                        .padding(.vertical, 12)

                    weatherHalf(
                        title: destTitle,
                        weather: destWeather,
                        loading: destLoading,
                        failed: destFailed || destCoordinate == nil,
                        isCurrent: false,
                        noCoordinate: destCoordinate == nil
                    )
                    .padding(.leading, 16)
                }
            }
        }
        .frame(height: 104)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
    }

    private var hasLocationPermission: Bool {
        locationAuth == .authorizedWhenInUse || locationAuth == .authorizedAlways
    }

    /// 天气半栏：白底 + 数值 + 一行风/湿度，不再用天空渐变(与全站配色一致)
    private func weatherHalf(
        title: String,
        weather: WeatherSnapshot?,
        loading: Bool,
        failed: Bool,
        isCurrent: Bool,
        noCoordinate: Bool = false,
        note: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                Image(systemName: isCurrent ? "location.fill" : "mappin")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                Text(isCurrent ? (currentPlaceName ?? title) : title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let note {
                    Text(note)
                        .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(Theme.textSecondary)

            // 有数据时把温度压到卡片底部，和右栏的湿度行对齐；
            // 没有数据时只有一行说明，再顶到最下面会在标题和文字之间留出一个空洞。
            if weather != nil {
                Spacer(minLength: 0)
            } else {
                Color.clear.frame(height: 12)
            }

            if let weather {
                let style = WeatherVisuals.style(
                    for: weather.current.weatherCode,
                    isNight: WeatherVisuals.isNightNow()
                )

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // 天气图标放最前，和「温度 + 天气」形成一眼可读的一组
                    Image(systemName: style.icon)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                    Text("\(Int(weather.current.temperature2m.rounded()))°")
                        .font(.system(size: 26, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                    Text(style.text)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
                // 图标原本会被读成英文的「Rain」；温度、天气词、图标合成一句才读得懂
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Int(weather.current.temperature2m.rounded())) 度，\(style.text)")

                // 白底说明性整句按规范用 12pt，不再降到 11pt
                Text("\(WeatherVisuals.windDirection(weather.current.windDirection10m))风 \(Int(weather.current.windSpeed10m.rounded())) km/h · 湿度 \(Int(weather.current.relativeHumidity2m.rounded()))%")
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 6)
                // 「km/h」会被逐字母念出来。
                .accessibilityLabel("\(WeatherVisuals.windDirection(weather.current.windDirection10m))风 \(Int(weather.current.windSpeed10m.rounded())) 公里每小时，湿度 \(Int(weather.current.relativeHumidity2m.rounded()))%")
            } else if loading {
                HStack(alignment: .center, spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.listGray)
                    Text("正在获取")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
                .accessibilityLabel("正在获取天气")
            } else {
                HStack(spacing: 8) {
                    Text(statusText(isCurrent: isCurrent, failed: failed, noCoordinate: noCoordinate))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if isCurrent, !hasLocationPermission {
                        Button("开启") {
                            Task { await enableCurrentLocation() }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                        .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                    } else if failed, !noCoordinate {
                        Button {
                            Task {
                                if isCurrent {
                                    await loadCurrentWeather()
                                } else {
                                    await loadDestWeather()
                                }
                            }
                        } label: {
                            Text("重试")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                        // 左右两栏各有一颗「重试」，读屏不能只报两个字：说清重试的是谁
                        .accessibilityLabel(isCurrent ? "重试获取当前位置天气" : "重试获取目的地天气")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // 左栏没有右栏那种 16pt leading，失败态的重试按钮会贴到分隔线上；
                // 单独补 12pt，让按钮和分隔线之间留出呼吸位。
                .padding(.trailing, isCurrent ? 12 : 0)
            }
        }
        .padding(.vertical, 12)
        // 顶部对齐：没有天气数据时只剩一行说明，垂直居中会在标题下方顶出一块空白
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func statusText(isCurrent: Bool, failed: Bool, noCoordinate: Bool) -> String {
        // 半栏只有 ~150pt，右侧还要放 44pt 的「重试」：像「目的地天气获取失败」
        // 这种 9 字提示会挤成两行、最后一行只剩一个「败」。
        // 单元格标题已经写明是本地还是目的地天气，状态行只说结论。
        if isCurrent {
            guard failed else { return "定位未开启" }
            let authorized = locationAuth == .authorizedWhenInUse || locationAuth == .authorizedAlways
            return authorized ? "暂时获取不到" : "定位未开启"
        }
        if noCoordinate { return "该路线无终点坐标" }
        return failed ? "暂时获取不到" : "暂无数据"
    }

    // MARK: 适宜度 + 拥堵(合并单框，与天气卡同款左右布局)

    private var adviceCard: some View {
        HStack(spacing: 0) {
            suitabilityHalf
            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 1)
            congestionHalf
        }
        // 132 只够说明文字一行；改成两行后底部会贴边，加高 8pt 留出呼吸位。
        .frame(height: 140)
        .background(Theme.lightField)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var suitabilityHalf: some View {
        let score: Int? = {
            guard let weather = destWeather ?? currentWeather else { return nil }
            return Suitability.score(weather)
        }()
        return VStack(alignment: .leading, spacing: 0) {
            Text("骑行适宜度")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.bottom, 5)
            .accessibilityHidden(true)

            Spacer(minLength: 0)

            gauge(score: score)

            Spacer(minLength: 0)

            // 一行写「不建议骑行 · 综合天气、风与降水」在半栏里必然截断，
            // 拆成「结论 / 依据」两行，断句落在短语之间而不是句子中间。
            VStack(alignment: .leading, spacing: 2) {
                if let score {
                    Text(Suitability.label(score))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                } else {
                    // 环里是「--」时只剩一行方法论说明，等于没回答「今天能不能骑」
                    Text("暂无天气数据")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("综合天气、风与降水")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func gauge(score: Int?) -> some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.07), lineWidth: 6)
            if let score {
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(
                        scoreColor(score),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            // 环内只放分数：状态词比环更宽，放进去会压到描边上
            Text(score.map { "\($0)" } ?? "--")
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .frame(width: 60, height: 60)
        .frame(maxWidth: .infinity)
        // 环里只有一个裸数字，读屏会单独念出「35」，既不知道是什么分也不知道满分多少
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { "骑行适宜度 \($0) 分，满分 100" } ?? "骑行适宜度暂无数据")
    }

    /// 单色分段，而不是一条彩虹渐变：分数只表达"好/一般/差"三档
    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 75...: return Theme.success
        case 45..<75: return Color(red: 0xE0 / 255, green: 0x9B / 255, blue: 0x2D / 255)
        default: return Theme.danger
        }
    }

    private var congestionHalf: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("拥堵预估")
                Spacer(minLength: 4)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.bottom, 5)
            .accessibilityHidden(true)

            Spacer(minLength: 0)

            // 四段等高刻度 = 「四档里的第几档」。之前用递增柱形，读起来更像信号强度，
            // 反而不像路况等级。
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(index <= congestionLevel
                              ? Congestion.levelColor(congestionLevel)
                              : Color.black.opacity(0.08))
                        .frame(maxWidth: .infinity)
                        .frame(height: 10)
                }
            }
            .frame(height: 36, alignment: .center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("拥堵预估：\(Congestion.summary(congestionLevel))")

            Spacer(minLength: 0)

            // 颜色只交给圆点：左侧「不建议骑行」是墨色，右侧若是彩色粗体，
            // 同一张卡里两个结论的字重看起来不一样。
            // 第二行把「按路线类型与时段估算」收进卡里：原来它悬在卡外，
            // 左右两个结论也一个两行一个一行，底边对不齐。
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Congestion.levelColor(congestionLevel))
                        .frame(width: 5, height: 5)
                    Text(Congestion.summary(congestionLevel))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
                Text("按时段估算 · 非实时")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var congestionLevel: Int {
        Congestion.level(for: route)
    }

    // MARK: 数据加载

    private func loadCurrentWeather() async {
        if ProcessInfo.processInfo.arguments.contains("-departdatafail") {
            locationAuth = .authorizedWhenInUse
            currentWeather = nil
            currentLoading = false
            currentFailed = true
            currentAQI = nil
            return
        }
        locationAuth = CLLocationManager().authorizationStatus
        guard locationAuth == .authorizedWhenInUse || locationAuth == .authorizedAlways else { return }
        currentLoading = true
        currentFailed = false
        if let loc = await locationFetcher.fetchLocation() {
            currentCoordinate = loc.coordinate
            let lat = loc.coordinate.latitude
            let lng = loc.coordinate.longitude
            let key = String(format: "%.2f,%.2f", lat, lng)
            if let hit = cache[key] {
                currentWeather = hit
            } else if let w = await WeatherService.fetchSmart(lat: lat, lng: lng) {
                cache[key] = w
                currentWeather = w
            } else {
                // 进页面时当前天气和目的地天气会并发请求，偶发只有一侧超时；
                // 静默补一次（间隔很短，不拖长加载态）再落到失败态。
                try? await Task.sleep(nanoseconds: 600_000_000)
                if let retried = await WeatherService.fetchSmart(lat: lat, lng: lng) {
                    cache[key] = retried
                    currentWeather = retried
                } else {
                    currentFailed = true
                }
            }
            if currentPlaceName == nil {
                currentPlaceName = await PlaceNameService.name(for: loc)
            }
            if currentAQI == nil,
               let aqi = try? await AirQualityService.fetch(lat: lat, lng: lng),
               let value = aqi.current.usAqi {
                currentAQI = value
            }
        } else {
            currentFailed = true
        }
        currentLoading = false
    }

    private func loadDestWeather() async {
        if ProcessInfo.processInfo.arguments.contains("-departdatafail") {
            destWeather = nil
            destLoading = false
            destFailed = true
            return
        }
        guard let c = destCoordinate else {
            destWeather = nil
            destLoading = false
            return
        }
        let key = String(format: "%.2f,%.2f", c.lat, c.lng)
        if let hit = cache[key] {
            destWeather = hit
            return
        }
        destLoading = true
        destFailed = false
        if let w = await WeatherService.fetchSmart(lat: c.lat, lng: c.lng) {
            cache[key] = w
            destWeather = w
        } else {
            // 和本地天气一样补一次：进页面时两边并发请求，免费额度下常有一侧被限流，
            // 只失败一次就报错会让「目的地天气」看起来长期不可用。
            try? await Task.sleep(nanoseconds: 600_000_000)
            if let retried = await WeatherService.fetchSmart(lat: c.lat, lng: c.lng) {
                cache[key] = retried
                destWeather = retried
            } else {
                destFailed = true
            }
        }
        destLoading = false
    }

    /// 查询同目的地骑友人数。
    /// 这里只读不写：行程计划在用户真正点击「开始骑行」后由 RidingView 创建，
    /// 避免浏览/切换路线时产生幽灵计划并抬高人数统计。
    private func loadRiderStats() async {
        riderStatsLoaded = false
        riderStatsFailed = false
        if ProcessInfo.processInfo.arguments.contains("-departdatafail") {
            riderCount = nil
            riderStatsLoaded = true
            riderStatsFailed = true
            return
        }
        guard let c = destCoordinate else {
            riderCount = nil
            riderStatsLoaded = true
            return
        }
        if let response = await TripService.riderCountToDest(
            auth.client, destLat: c.lat, destLon: c.lng
        ) {
            riderCount = response.count
        } else {
            riderCount = nil
            riderStatsFailed = true
        }
        riderStatsLoaded = true
    }

    private func enableCurrentLocation() async {
        locationAuth = CLLocationManager().authorizationStatus
        if locationAuth == .denied || locationAuth == .restricted {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
            return
        }
        await loadCurrentWeather()
        locationAuth = CLLocationManager().authorizationStatus
    }
}

// MARK: - 适宜度打分

enum Suitability {
    /// 100 分制：温度舒适度 + 降水 + 风力
    static func score(_ w: WeatherSnapshot) -> Int {
        var score = 100
        let t = w.current.temperature2m
        if t < 5 || t > 32 {
            score -= 30
        } else if t < 10 || t > 28 {
            score -= 15
        } else if t < 15 || t > 26 {
            score -= 5
        }

        switch w.current.weatherCode {
        case 0, 1, 2:
            break
        case 3:
            score -= 5
        case 45, 48:
            // 雾天对摩托车是明显的能见度风险，不能因为温度和风力舒适就判为适宜。
            score -= 35
        case 51...57, 80...82:
            score -= 30
        case 61...67:
            score -= 35
        case 71...77:
            score -= 50
        case 95...99:
            score -= 60
        default:
            score -= 40
        }

        let wind = w.current.windSpeed10m
        if wind > 35 {
            score -= 25
        } else if wind > 25 {
            score -= 15
        } else if wind > 18 {
            score -= 8
        }

        // 气象预警是安全底线，不能被舒适温度和大风扣分抵消。
        // 橙/红/黑或 Severe/Extreme 直接判为不建议；任何预警至少降为谨慎。
        let warnings = w.warnings ?? []
        if warnings.contains(where: { $0.isSevere }) {
            score = min(score, 40)
        } else if !warnings.isEmpty {
            score = min(score, 65)
        }

        return max(0, min(100, score))
    }

    static func label(_ score: Int?) -> String {
        guard let score else { return "等待数据" }
        if score >= 80 { return "适宜骑行" }
        if score >= 55 { return "谨慎骑行" }
        return "不建议骑行"
    }

    /// 紧凑摘要（出发页 SE）里的两字判定：只保留「适宜 / 谨慎 / 不建议」，
    /// 「骑行」二字在同一个「适宜度」上下文里是重复的。
    static func shortLabel(_ score: Int) -> String {
        if score >= 80 { return "适宜" }
        if score >= 55 { return "谨慎" }
        return "不建议"
    }
}

// MARK: - 拥堵预估(按路线类型 × 时段启发式，标注"智能预估")

enum Congestion {
    static func levelColor(_ level: Int) -> Color {
        switch max(0, min(3, level)) {
        case 0: return Color(red: 0.2, green: 0.78, blue: 0.35)
        case 1: return Color(red: 1.0, green: 0.8, blue: 0.0)
        case 2: return Color(red: 1.0, green: 0.58, blue: 0.1)
        default: return Color(red: 1.0, green: 0.23, blue: 0.19)
        }
    }

    /// 摘要文字用色(比色块更深，保证浅色底可读)
    static func summaryColor(_ level: Int) -> Color {
        switch max(0, min(3, level)) {
        // 上一版 #219E47 / #D99400 在 #F5F6F7 卡片上只有 3.4:1 / 2.4:1，
        // 13pt 的「部分路段可能缓行」几乎糊在底色里。这一组都在 4.7:1 以上
        // （卡片底 5.0 / 5.1 / 4.7 / 5.9），白底只会更高。
        case 0: return Color(red: 0.078, green: 0.478, blue: 0.220)
        case 1: return Color(red: 0.549, green: 0.380, blue: 0.0)
        case 2: return Color(red: 0.722, green: 0.302, blue: 0.020)
        default: return Color(red: 0.722, green: 0.129, blue: 0.102)
        }
    }

    /// 按路线类型与时段估算一个综合档位；不伪造实时分段路况。
    static func level(for route: Route?, at date: Date = Date()) -> Int {
        let name = route?.name ?? ""
        let urban = name.contains("城市") || name.contains("通勤") || name.contains("滨江")
            || name.contains("中央") || name.contains("长安街") || name.contains("四惠")
        var level = urban ? 1 : 0
        let hour = Calendar.current.component(.hour, from: date)
        if (7...9).contains(hour) || (17...19).contains(hour) {
            level += 1
        }
        if name.contains("环路") || name.contains("高速") {
            level += 1
        }
        return min(3, level)
    }

    static func summary(_ level: Int) -> String {
        switch max(0, min(3, level)) {
        case 0: return "预估顺畅"
        case 1: return "部分路段可能缓行"
        case 2: return "部分路段可能拥堵"
        default: return "多处可能拥堵，建议错峰"
        }
    }

    /// 标题行里的一眼级标签：整句摘要放标题行会挤掉空气质量和刷新状态
    static func short(_ level: Int) -> String {
        switch max(0, min(3, level)) {
        case 0: return "顺畅"
        case 1: return "缓行"
        case 2: return "拥堵"
        default: return "严重拥堵"
        }
    }
}
