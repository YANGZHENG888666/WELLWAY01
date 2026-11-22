import SwiftUI

/// 骑行统计：本周 / 本月，仅使用已完成的真实骑行记录。
/// 没有轨迹的记录仍计入次数与时长，但不虚报里程、爬升和均速。
struct RideStatsView: View {
    let store: RecordsStore
    @State private var range: StatsRange

    init(store: RecordsStore) {
        self.store = store
        let startsOnWeek = ProcessInfo.processInfo.arguments.contains("-statsweek")
        _range = State(initialValue: startsOnWeek ? .week : .month)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.firstWeekday = 2
        return calendar
    }

    var body: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: "骑行统计")
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    DesignSegmentedControl(
                        options: StatsRange.allCases.map(\.title),
                        selection: rangeSelection
                    )

                    let period = makePeriod(range)
                    let summary = makeSummary(store.records, in: period.interval)
                    let previous = makeSummary(store.records, in: period.previous)

                    if summary.count == 0 {
                        DesignEmptyState(
                            icon: "chart.bar",
                            title: "\(range.title)还没有骑行",
                            message: "完成一次骑行后，这里会出现里程、时长和爬升统计"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 84)
                    } else {
                        hero(summary: summary, previous: previous)

                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: 1)

                        metrics(summary: summary)

                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: 1)

                        chart(summary: summary)

                        if summary.missingTrackCount > 0 {
                            Text("另有 \(summary.missingTrackCount) 次骑行未记录轨迹，里程、爬升与均速按已记录部分统计。")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text("统计仅包含已完成的骑行记录，数据来自每次骑行的真实定位。")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .refreshable { await store.load() }
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .hidesAppTabBar()
    }

    private var rangeSelection: Binding<String> {
        Binding(
            get: { range.title },
            set: { range = StatsRange(title: $0) ?? .month }
        )
    }

    // MARK: - 里程主数据

    private func hero(summary: PeriodSummary, previous: PeriodSummary) -> some View {
        let missingDistance = summary.trackedCount == 0
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(range.title)里程")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(missingDistance ? "未记录" : String(format: "%.1f", summary.distanceKm))
                    .font(.system(
                        size: missingDistance ? 22 : 44,
                        weight: missingDistance ? .medium : .bold
                    ))
                    .monospacedDigit()
                    .foregroundStyle(missingDistance ? Theme.textSecondary : Theme.textPrimary)
                if !missingDistance {
                    Text("km")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Text(comparisonText(previous: previous))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(range.title)里程，"
                + (missingDistance
                    ? "未记录轨迹"
                    : "\(String(format: "%.1f", summary.distanceKm)) 公里")
                + "，\(comparisonText(previous: previous))"
        )
    }

    private func comparisonText(previous: PeriodSummary) -> String {
        let noun = range == .week ? "上周" : "上月"
        if previous.count == 0 { return "\(noun)没有骑行" }
        if previous.trackedCount == 0 { return "\(noun) \(previous.count) 次，未记录轨迹" }
        return "\(noun) \(previous.count) 次 · \(String(format: "%.1f", previous.distanceKm)) km"
    }

    // MARK: - 指标行

    private func metrics(summary: PeriodSummary) -> some View {
        let duration = durationMetricParts(summary.durationS)
        return MetricRowLayout {
            metric(summary.count == 0 ? "0" : "\(summary.count)", unit: "次", label: "骑行")
            divider
            metric(duration.value, unit: duration.unit ?? "", label: "时长")
            divider
            metric(speedText(summary), unit: summary.averageSpeedKmh == nil ? "" : "km/h", label: "均速")
            divider
            metric(summary.elevationM > 0 ? "\(summary.elevationM)" : "0", unit: "m", label: "爬升")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "骑行 \(summary.count) 次，时长 \(RideDurationText.spoken(seconds: summary.durationS))，"
                + "平均速度 \(speedText(summary))\(summary.averageSpeedKmh == nil ? "" : " 公里每小时")，"
                + "爬升 \(summary.elevationM) 米"
        )
    }

    private func speedText(_ summary: PeriodSummary) -> String {
        guard let speed = summary.averageSpeedKmh else { return "—" }
        return String(format: "%.1f", speed)
    }

    /// 统计周期总时长可能不足一分钟；复用「分钟」会让新用户看到 0 分钟。
    private func durationMetricParts(_ seconds: Int) -> (value: String, unit: String?) {
        let total = max(0, seconds)
        if total < 60 { return ("\(total)", "秒") }
        return RideDurationText.metricParts(minutes: total / 60)
    }

    private func metric(_ value: String, unit: String, label: String) -> some View {
        let missing = value == "—"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: missing ? 16 : 22, weight: missing ? .medium : .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .baselineOffset(missing ? 3 : 0)
                    .foregroundStyle(missing ? Theme.textSecondary : Theme.textPrimary)
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)
            .allowsTightening(true)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: 1, height: 34)
            .padding(.horizontal, 8)
            .metricRowFixed()
    }

    // MARK: - 每日里程

    private func chart(summary: PeriodSummary) -> some View {
        let maxKm = summary.buckets.map(\.distanceKm).max() ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("每日里程")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                if maxKm > 0 {
                    Text("最高 \(String(format: "%.1f", maxKm)) km")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(summary.buckets) { bucket in
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(bucket.distanceKm > 0 ? Theme.textPrimary : Theme.lightField)
                            .frame(height: barHeight(bucket.distanceKm, maxKm: maxKm))
                        Text(bucket.label)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize()
                            .frame(height: 14)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 148)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "每日里程图表，"
                    + (maxKm > 0 ? "单日最高 \(String(format: "%.1f", maxKm)) 公里" : "本周期没有记录到里程")
            )
        }
    }

    private func barHeight(_ km: Double, maxKm: Double) -> CGFloat {
        guard km > 0, maxKm > 0 else { return 2 }
        return max(4, 126 * CGFloat(km / maxKm))
    }

    // MARK: - 周期与汇总

    private func makePeriod(_ range: StatsRange) -> StatsPeriod {
        let now = Date()
        let component: Calendar.Component = range == .week ? .weekOfYear : .month
        let interval = calendar.dateInterval(of: component, for: now)
            ?? DateInterval(start: now, duration: 0)
        let previousInterval: DateInterval
        if range == .week {
            let previousStart = calendar.date(byAdding: .day, value: -7, to: interval.start) ?? interval.start
            previousInterval = DateInterval(start: previousStart, end: interval.start)
        } else {
            // 本月起点往前一秒即落在上个月，再取上个月的完整区间。
            previousInterval = calendar.dateInterval(of: .month, for: interval.start.addingTimeInterval(-1))
                ?? DateInterval(start: interval.start, end: interval.start)
        }
        return StatsPeriod(interval: interval, previous: previousInterval)
    }

    private func makeSummary(_ records: [RideRecord], in interval: DateInterval) -> PeriodSummary {
        let rides = records.filter { record in
            guard record.isCompleted,
                  let date = ISO8601DateFormatter.wellwayDate(from: record.startedAt) else { return false }
            return date >= interval.start && date < interval.end
        }
        let tracked = rides.filter(\.hasRecordedTrack)
        let distanceM = tracked.reduce(0) { $0 + max(0, $1.distanceM) }
        let durationS = rides.reduce(0) { $0 + max(0, $1.durationS) }
        let elevationM = tracked.reduce(0) { $0 + max(0, $1.elevationGainM) }

        let samples = tracked.compactMap { record -> (speed: Double, seconds: Double)? in
            guard record.durationS > 0 else { return nil }
            // 早期记录可能没写均速，用里程/时长补一个按时间加权的样本，
            // 否则整段均速会被少数带均速的记录拉偏。
            let speed = record.avgSpeedKmh
                ?? (record.distanceM > 0
                    ? Double(record.distanceM) / Double(record.durationS) * 3.6
                    : nil)
            guard let speed, speed > 0 else { return nil }
            return (speed, Double(record.durationS))
        }
        let sampleSeconds = samples.reduce(0) { $0 + $1.seconds }
        let averageSpeedKmh: Double?
        if sampleSeconds > 0 {
            averageSpeedKmh = samples.reduce(0) { $0 + $1.speed * $1.seconds } / sampleSeconds
        } else {
            let trackedSeconds = tracked.reduce(0) { $0 + max(0, $1.durationS) }
            averageSpeedKmh = trackedSeconds > 0
                ? Double(distanceM) / Double(trackedSeconds) * 3.6
                : nil
        }

        return PeriodSummary(
            count: rides.count,
            trackedCount: tracked.count,
            missingTrackCount: rides.count - tracked.count,
            distanceKm: Double(distanceM) / 1_000,
            durationS: durationS,
            elevationM: elevationM,
            averageSpeedKmh: averageSpeedKmh,
            buckets: makeBuckets(tracked, in: interval)
        )
    }

    private func makeBuckets(_ tracked: [RideRecord], in interval: DateInterval) -> [DayBucket] {
        let dayCount = max(1, calendar.dateComponents(
            [.day],
            from: interval.start,
            to: interval.end
        ).day ?? 7)
        let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]

        return (0..<dayCount).map { index in
            let dayStart = calendar.date(byAdding: .day, value: index, to: interval.start) ?? interval.start
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let km = tracked.reduce(0.0) { total, record in
                guard let date = ISO8601DateFormatter.wellwayDate(from: record.startedAt),
                      date >= dayStart, date < dayEnd else { return total }
                return total + Double(max(0, record.distanceM)) / 1_000
            }
            let day = calendar.component(.day, from: dayStart)
            let weekday = calendar.component(.weekday, from: dayStart)
            let label: String
            if dayCount <= 7 {
                label = weekdayNames[max(0, min(6, weekday - 1))]
            } else if day == 1 || (day - 1) % 7 == 0 {
                label = "\(day)"
            } else {
                label = ""
            }
            return DayBucket(date: dayStart, label: label, distanceKm: km)
        }
    }
}

private enum StatsRange: String, CaseIterable {
    case week
    case month

    var title: String {
        switch self {
        case .week: "本周"
        case .month: "本月"
        }
    }

    init?(title: String) {
        guard let value = Self.allCases.first(where: { $0.title == title }) else { return nil }
        self = value
    }
}

private struct StatsPeriod {
    let interval: DateInterval
    let previous: DateInterval
}

private struct PeriodSummary {
    let count: Int
    let trackedCount: Int
    let missingTrackCount: Int
    let distanceKm: Double
    let durationS: Int
    let elevationM: Int
    let averageSpeedKmh: Double?
    let buckets: [DayBucket]
}

private struct DayBucket: Identifiable {
    let date: Date
    let label: String
    let distanceKm: Double

    var id: Date { date }
}
