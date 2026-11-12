import Foundation

// MARK: - 和风天气 QWeather(实时 + 24h 逐小时 + 气象灾害预警)
//
// 设计要点：
//  · 和风是 `lon,lat` 顺序、温度/湿度都是字符串，这里统一归一化成 Open-Meteo 那套 `WeatherSnapshot`,
//    徽标/配色/骑行适宜度(WeatherVisuals / RideAdvice)继续用同一张表，不维护两套映射。
//  · 未配置 `QWEATHER_KEY`、或和风报错(401/402/超时)→ 自动回退 Open-Meteo,行为与旧版一致。
//  · Key 存在 `Info.plist` 的 `QWEATHER_KEY`(内测方案);V2 换成后端代理时只需改这里的取 key 方式。
//  · API Host 必须用控制台-设置里的专属域名(`xxxxx.re.qweatherapi.com`):公共 `devapi/api.qweather.com`
//    对新凭据一律返回 403 Invalid Host(官方公告公共地址 2026 年起逐步停服),故 `QWEATHER_HOST` 必填。
//  · 预警走新版 `GET /weatheralert/v1/current/{lat}/{lon}`;旧的 `/v7/warning/now` 已下线，只返回 403 Deprecated。

/// 逐小时预报(和风 24h → App 内部结构)
struct HourlyForecast: Codable, Equatable, Identifiable {
    let id: String          // fxTime,同时作为列表 identity
    let time: String        // 2026-09-17T13:00+08:00
    let temp: Double
    let icon: String        // 和风图标码，如 101
    let text: String
    let pop: Int?           // 降水概率 %
    /// Open-Meteo 兜底时直接保留 weather_code,避免把图标码和 weather_code 混用
    var weatherCode: Int? = nil

    /// 归一化成 Open-Meteo 的 weather_code,复用 WeatherVisuals
    var openMeteoCode: Int { weatherCode ?? QWeather.openMeteoCode(icon: icon) }
}

/// 气象灾害预警
struct WeatherWarning: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let severity: String        // Minor / Moderate / Severe / Extreme
    let severityColor: String   // Blue / Yellow / Orange / Red / Black
    let text: String
    let pubTime: String

    /// 橙/红/黑 或 Severe/Extreme 才算"需要明显提醒"
    var isSevere: Bool {
        ["Severe", "Extreme"].contains(severity)
            || ["Orange", "Red", "Black"].contains(severityColor)
    }
}

enum QWeatherError: LocalizedError {
    case noKey
    case badKey
    case quota
    case api(String)

    var errorDescription: String? {
        switch self {
        case .noKey: return "未配置和风天气 Key"
        case .badKey: return "和风天气 Key 无效"
        case .quota: return "和风天气调用量已用尽"
        case .api(let code): return "和风天气返回 \(code)"
        }
    }
}

enum QWeather {
    /// 和风图标码 → Open-Meteo weather_code(近似映射，只用于选图标/文案/配色)
    static func openMeteoCode(icon: String) -> Int {
        guard let n = Int(icon) else { return 3 }
        switch n {
            // 150–153 是 100–103 的夜间图标码，必须按白天对应关系映射：
            // 否则半夜的「晴」(150) 会被画成「多云」的云+月亮图标。
            case 100, 150: return 0
            case 101, 102, 103, 151, 152, 153: return 2
        case 104: return 3
        case 300, 301, 350, 351: return 80
        case 302, 303: return 95
        case 304: return 96
        case 305, 309, 399: return 51
        case 306: return 61
        case 307, 308, 310, 311, 312, 314, 315, 316, 317, 318: return 65
        case 313, 404, 405: return 66
        case 400, 499: return 71
        case 401, 408, 409, 410: return 73
        case 402, 403: return 75
        case 406, 407, 456, 457: return 85
        case 500, 501, 502, 509, 510, 511, 512, 513, 514, 515: return 45
        case 503, 504, 507, 508: return 48
        case 900: return 0
        case 901: return 71
        default: return 3
        }
    }

    static var isConfigured: Bool { !AppConfig.qweatherKey.isEmpty }

    /// 三个接口并发拉取，归一化成 WeatherSnapshot(带 hourly / warnings)
    static func fetch(lat: Double, lng: Double) async throws -> WeatherSnapshot {
        let key = AppConfig.qweatherKey
        guard !key.isEmpty else { throw QWeatherError.noKey }

        let loc = String(format: "%.4f,%.4f", lng, lat)   // 和风：经度在前
        async let nowTask: NowResponse = get("/v7/weather/now", key: key, loc: loc)
        async let hourlyTask: HourlyResponse = get("/v7/weather/24h", key: key, loc: loc)
        async let warningTask: AlertResponse = getAlert(key: key, lat: lat, lng: lng)

        let now = try await nowTask
        guard now.code == "200" else { throw mapCode(now.code) }

        let hourly = (try? await hourlyTask)?.hourly ?? []
        let warnings = (try? await warningTask)?.alerts ?? []

        let current = WeatherSnapshot.Current(
            temperature2m: Double(now.now.temp) ?? 0,
            relativeHumidity2m: Double(now.now.humidity) ?? 0,
            apparentTemperature: Double(now.now.feelsLike) ?? Double(now.now.temp) ?? 0,
            weatherCode: openMeteoCode(icon: now.now.icon),
            windSpeed10m: Double(now.now.windSpeed) ?? 0,
            windDirection10m: Double(now.now.wind360) ?? 0
        )

        var snapshot = WeatherSnapshot(
            current: current,
            daily: .init(sunrise: [], sunset: [])
        )
        snapshot.source = "qweather"
        snapshot.hourly = hourly.map {
            HourlyForecast(
                id: $0.fxTime,
                time: $0.fxTime,
                temp: Double($0.temp) ?? 0,
                icon: $0.icon,
                text: $0.text,
                pop: Int($0.pop ?? "")
            )
        }
        snapshot.warnings = warnings.map(\.asWarning)
        snapshot.placeText = now.now.text
        return snapshot
    }

    private static func mapCode(_ code: String) -> QWeatherError {
        switch code {
        case "401", "403": return .badKey
        case "402": return .quota
        default: return .api(code)
        }
    }

    private static func get<T: Decodable>(_ path: String, key: String, loc: String) async throws -> T {
        guard var comps = URLComponents(string: AppConfig.qweatherHost + path) else {
            throw QWeatherError.api("bad_url")
        }
        comps.queryItems = [
            URLQueryItem(name: "location", value: loc),
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "lang", value: "zh"),
        ]
        guard let url = comps.url else { throw QWeatherError.api("bad_url") }
        let request = URLRequest(url: url, timeoutInterval: 6)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// 预警接口把经纬度放在路径里(最多两位小数),与其他接口的 `location=经度，纬度` 查询参数不同
    private static func getAlert(key: String, lat: Double, lng: Double) async throws -> AlertResponse {
        let path = String(format: "/weatheralert/v1/current/%.2f/%.2f", lat, lng)
        guard var comps = URLComponents(string: AppConfig.qweatherHost + path) else {
            throw QWeatherError.api("bad_url")
        }
        comps.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "lang", value: "zh"),
        ]
        guard let url = comps.url else { throw QWeatherError.api("bad_url") }
        let request = URLRequest(url: url, timeoutInterval: 6)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(AlertResponse.self, from: data)
    }

    // MARK: - 和风响应体

    private struct NowResponse: Decodable {
        let code: String
        let now: Now
        struct Now: Decodable {
            let temp: String
            let feelsLike: String
            let icon: String
            let text: String
            let wind360: String
            let windSpeed: String
            let humidity: String
        }
    }

    private struct HourlyResponse: Decodable {
        let code: String
        let hourly: [Hour]
        struct Hour: Decodable {
            let fxTime: String
            let temp: String
            let icon: String
            let text: String
            let pop: String?
        }
    }

    /// 新版预警接口响应(GET /weatheralert/v1/current/{lat}/{lon})
    private struct AlertResponse: Decodable {
        let alerts: [Alert]?

        struct Alert: Decodable {
            let id: String
            let headline: String?
            let description: String?
            let severity: String?
            let issuedTime: String?
            let color: Color?
            let eventType: EventType?

            struct Color: Decodable { let code: String? }
            struct EventType: Decodable { let name: String? }

            /// 归一成 App 内部结构。新版 severity/color 是全小写(minor / blue),
            /// 而 WeatherWarning.isSevere 与预警配色按首字母大写判断，这里统一 capitalize。
            var asWarning: WeatherWarning {
                WeatherWarning(
                    id: id,
                    title: headline ?? eventType?.name ?? "气象预警",
                    severity: (severity ?? "").capitalized,
                    severityColor: (color?.code ?? "").capitalized,
                    text: description ?? "",
                    pubTime: issuedTime ?? ""
                )
            }
        }
    }
}

extension WeatherService {
    /// 和风优先，失败自动回退 Open-Meteo;两者都失败返回 nil
    static func fetchSmart(lat: Double, lng: Double) async -> WeatherSnapshot? {
        if QWeather.isConfigured, let q = try? await QWeather.fetch(lat: lat, lng: lng) {
            return q
        }
        if var fallback = try? await WeatherService.fetch(lat: lat, lng: lng) {
            fallback.source = "open-meteo"
            return fallback
        }
        return nil
    }
}
