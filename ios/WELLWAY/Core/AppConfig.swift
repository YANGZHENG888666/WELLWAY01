import Foundation

/// 从 Info.plist 读取后端配置(和 backend/.env 使用同一套 URL / Key)。
enum AppConfig {
    static var supabaseURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
        guard let url = URL(string: raw), !raw.contains("YOUR_PROJECT") else {
            fatalError("请先在 ios/WELLWAY/Resources/Info.plist 中配置 SUPABASE_URL")
        }
        return url
    }

    static var supabaseAnonKey: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
        guard !raw.isEmpty, !raw.contains("YOUR_ANON_KEY") else {
            fatalError("请先在 ios/WELLWAY/Resources/Info.plist 中配置 SUPABASE_ANON_KEY")
        }
        return raw
    }

    /// 和风天气 Key(https://dev.qweather.com 控制台生成)。
    /// 未配置时返回空串，天气模块会自动回退 Open-Meteo,不会崩、不会弹错。
    static var qweatherKey: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "QWEATHER_KEY") as? String ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("$(") || trimmed.contains("YOUR_") { return "" }
        return trimmed
    }

    /// 和风接口域名：开发版用 https://devapi.qweather.com;
    /// 若控制台给了专属域名(xxx.re.qweatherapi.com),填到 QWEATHER_HOST 覆盖。
    static var qweatherHost: String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "QWEATHER_HOST") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || raw.hasPrefix("$(") { return "https://devapi.qweather.com" }
        return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    }
}
