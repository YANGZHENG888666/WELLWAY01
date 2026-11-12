import SwiftUI

// MARK: - 城市限行（只展示文字摘要，不做通行判定）

/// 出发页「限行提示」卡片。
/// 数据来自 `rpc/moto_rule`（迁移 0020）：命中且有正文 → 展示摘要；只有城市条目 → 展示"待收录"；
/// 接口不存在/网络失败 → 展示"暂不可用"（不阻塞骑行主流程）。
struct MotoRuleCard: View {
    @Environment(AuthManager.self) private var auth
    /// 反地理编码得到的地名，如 "北京市·朝阳区"
    let cityHint: String?
    /// 定位不可用时的路线城市兜底，如 "杭州"
    var fallbackCity: String? = nil

    @State private var rule: MotoRule?
    @State private var didLoad = false
    @State private var expanded = false

    private var displayCity: String? {
        if let name = rule?.cityName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return city
    }

    private var city: String? {
        for raw in [cityHint, fallbackCity] {
            guard let raw else { continue }
            let hint = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hint.isEmpty else { continue }
            let head = hint.split(whereSeparator: { $0 == "·" || $0 == "/" || $0 == "／" })
                .first.map(String.init) ?? hint
            let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("限行提示")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                if let name = displayCity {
                    // 这里查的是"你所在城市"，不是路线所在城市，写清楚避免误读
                    Text("当前城市 · \(name)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.lightField)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: city) {
            guard let city else {
                // 无定位/取不到城市：直接收尾，避免一直停在「正在查询」
                rule = nil
                didLoad = true
                return
            }
            rule = await TripService.motoRule(auth.client, cityCode: city)
            didLoad = true
        }
    }

    @ViewBuilder
    private var content: some View {
        if let rule, rule.hasRule {
            let text = rule.ruleText ?? ""
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(4)
                    .lineLimit(expanded ? nil : 4)
                if text.count > 60 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        Text(expanded ? "收起" : "展开全部")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                }
            }
        } else if didLoad {
            Text(emptyText)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        } else {
            Text("正在查询当地限行政策…")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var emptyText: String {
        if city == nil {
            return "开启定位后可查询当地摩托车限行政策，请以交管部门公告为准。"
        }
        if rule == nil {
            return "限行信息暂时获取不到，请以交管部门公告为准。"
        }
        // found 只代表城市条目存在；正文为空时 hasRule 为 false，走到这里必须说"没有规则正文"。
        // 原来写「已收录…限行信息」，卡片里却一个字都没有，用户读成加载失败。
        // 卡片标题已经写了「当前城市 · 北京市」，正文再重复一次城市名
        // 会变成「当前城市 · 北京市 / 「北京市」的…」，同一句话读两遍。
        return "摩托车限行规则暂未收录，请以交管部门公告为准。"
    }
}

// MARK: - 计划前往该目的地的骑友人数（匿名汇总，只有数字）

/// 纯展示组件：数据由 `RideInfoPanel` 拉取后传入。
/// (不能在卡片内部用 `.task` 拉取——人数为 0 时卡片整体不渲染，SwiftUI 不会挂载视图、
///  `.task` 永远不会执行，人数就永远查不出来。)
struct RiderPlanCard: View {
    let count: Int?
    let destName: String?
    var isLoading = false
    var failed = false
    var onRetry: (() -> Void)? = nil

    private var place: String {
        destName.map { "「\($0)」" } ?? "该目的地"
    }

    var body: some View {
        Group {
            if isLoading {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Theme.separator)
                            .frame(width: 176, height: 12)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Theme.separator.opacity(0.72))
                            .frame(width: 136, height: 10)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityLabel("正在加载同路线骑手统计")
            } else {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    if failed {
                        Text("同路线骑手统计暂不可用")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text("请检查网络后重试")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    } else if let count, count > 0 {
                        Text("\(count) 位骑手计划前往\(place)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text("仅统计人数，不显示任何个人信息")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("暂无骑手计划前往\(place)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text("路线热度会随骑手计划更新")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                if failed, let onRetry {
                    Button(action: onRetry) {
                        Text("重试")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                    .accessibilityLabel("重试加载同路线骑手统计")
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - 常驻免责文案

struct DisclaimerFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }
}

// MARK: - 逐小时预报 + 气象灾害预警（和风 QWeather；无 Key 时自动隐藏）

struct WeatherDetailStrip: View {
    let weather: WeatherSnapshot?

    /// 预警正文默认收起为两行：完整预警动辄上百字，展开会挤占逐小时与适宜度模块
    @State private var warningExpanded = false

    private var hours: [HourlyForecast] {
        Array((weather?.hourly ?? []).prefix(8))
    }

    private var warnings: [WeatherWarning] {
        weather?.warnings ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let first = warnings.first {
                warningBanner(first, more: warnings.count - 1)
            }
            if !hours.isEmpty {
                hourStrip
            }
        }
    }

    private func warningBanner(_ warning: WeatherWarning, more: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(warningColor(warning))
            VStack(alignment: .leading, spacing: 3) {
                Text(more > 0 ? "\(warning.title) 等 \(warnings.count) 条预警" : warning.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                if !warningDetail(warning).isEmpty {
                    Text(warningDetail(warning))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(2)
                        .lineLimit(warningExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if warningDetail(warning).count > 60 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { warningExpanded.toggle() }
                        } label: {
                            Text(warningExpanded ? "收起" : "展开预警")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(warningColor(warning).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 预警正文常常以标题那句原样开头：去掉重复前缀，避免同一句话出现两遍。
    private func warningDetail(_ warning: WeatherWarning) -> String {
        var text = warning.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = warning.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, text.hasPrefix(title) {
            text = String(text.dropFirst(title.count))
        }
        // 和风正文常写成「市气象台…发布暴雪黄色预警信号：预计…」，
        // 前半句与标题重复，直接从冒号后开始。
        if let colon = text.firstIndex(of: "：") {
            let prefix = String(text[text.startIndex...colon])
            if prefix.count <= 80, prefix.contains("预警") {
                text = String(text[text.index(after: colon)...])
            }
        }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " ：:，,。.\n"))
    }

    private var hourStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("逐小时预报")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                // 间距略小于整屏可容纳宽度，让第 7 个小时露出来，
                // 用户能看出这行可以左右滑动
                // 顶部对齐：只有降水概率 > 0 的小时才多一行，居中会让时间/图标/温度
                // 在有概率和没概率的列之间错开一整行。
                HStack(alignment: .top, spacing: 14) {
                    ForEach(hours) { hour in
                        let style = WeatherVisuals.style(
                            for: hour.openMeteoCode,
                            isNight: WeatherVisuals.isNight(iso: hour.time)
                        )
                        VStack(spacing: 5) {
                            Text(hourLabel(hour.time))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                            Image(systemName: style.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(style.tint)
                            Text("\(Int(hour.temp.rounded()))°")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.ink)
                            if let pop = hour.pop, pop > 0 {
                                // 单个「2%」放在温度下面看不出是什么；补一枚小雨滴，
                                // 让人一眼认出是降水概率。
                                HStack(spacing: 1) {
                                    Image(systemName: "drop.fill")
                                        .font(.system(size: 8))
                                    Text("\(pop)%")
                                        .font(.system(size: 12))
                                }
                                .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(width: 44)
                        // 不合成一句的话，7 个小时会被拆成 30 多个「21时、Rain、2°、59%」碎片，
                        // 相邻小时的数字还会被连读成同一组
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(hourSpokenLabel(hour, style: style))
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, 20)
            }
            // 不要把内容画到容器外：否则最后一列会贴着屏幕边缘被裁一半，
            // 现在只在 20pt 内容边界内露出半列，提示可横滑的同时保留留白
            .scrollClipDisabled(false)

            // 露出的半列会被裁在图标中间，读起来像渲染错误；
            // 右缘一段白→透明渐变把裁切变成「还能往右滑」
            LinearGradient(
                colors: [Color.white.opacity(0), Color.white],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 40)
            .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "2026-09-17T13:00+08:00" → "13时"
    private func hourSpokenLabel(_ hour: HourlyForecast, style: WeatherVisuals.Style) -> String {
        var parts = [hourLabel(hour.time), style.text, "\(Int(hour.temp.rounded())) 度"]
        if let pop = hour.pop, pop > 0 { parts.append("降水概率 \(pop)%") }
        return parts.joined(separator: "，")
    }

    private func hourLabel(_ iso: String) -> String {
        guard let tIndex = iso.firstIndex(of: "T") else { return iso }
        let after = iso[iso.index(after: tIndex)...]
        let hour = after.prefix(2)
        return "\(Int(hour) ?? 0)时"
    }

    private func warningColor(_ warning: WeatherWarning) -> Color {
        switch warning.severityColor {
        case "Yellow": return Color(red: 0xE6 / 255, green: 0xA5 / 255, blue: 0x00 / 255)
        case "Orange": return Color(red: 0xF2 / 255, green: 0x7A / 255, blue: 0x00 / 255)
        case "Red", "Black": return Theme.danger
        default: return Color(red: 0x2F / 255, green: 0x6F / 255, blue: 0xD8 / 255)
        }
    }
}
