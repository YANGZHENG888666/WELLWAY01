import SwiftUI
import MapKit
import Observation
import Supabase

/// 我的骑行记录(Figma「我的骑行记录」112:986,按节点数据 1:1 还原)
/// 全部/已完成 筛选 + 白色记录卡(日期/路线名/里程时长/状态)
struct RecordsView: View {
    var initialRecordId: UUID? = nil
    @Environment(AuthManager.self) private var auth
    @State private var store: RecordsStore?
    @State private var showRename = false
    @State private var renameDraft = ""
    @State private var renamingRecord: RideRecord?
    @State private var filter = "全部"
    @State private var deepLinkRecord: RideRecord?
    @State private var viewportHeight: CGFloat = 0

    private var filteredRecords: [RideRecord] {
        guard let records = store?.records else { return [] }
        if filter == "已完成" {
            return records.filter { $0.isCompleted }
        }
        return records
    }

    var body: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: "骑行记录")
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if let store {
                        if let errorMessage = store.errorMessage, store.records.isEmpty {
                            NetworkErrorView(message: errorMessage) {
                                Task { await store.load() }
                            }
                        } else if store.isLoading && store.records.isEmpty {
                            recordsSkeleton
                        } else {
                            // 一条记录都没有时，「全部 / 已完成」没有可筛内容，隐藏这排控件
                            if !store.records.isEmpty {
                                segmentedControl
                                    .motionAppear(delay: 0.05)
                            }

                            if let errorMessage = store.errorMessage {
                                inlineErrorBanner(errorMessage) {
                                    Task { await store.load() }
                                }
                            }

                            if store.records.isEmpty {
                                emptyState
                            } else if filteredRecords.isEmpty {
                                filteredEmptyState
                            } else {
                                recentSummary
                                    .motionAppear(delay: 0.08)
                                VStack(alignment: .leading, spacing: 8) {
                                    recordsSectionHeader
                                    recordsCard(store: store)
                                }
                                .motionAppear(delay: 0.12)
                            }
                        }
                    } else {
                        recordsSkeleton
                    }
                    if ProcessInfo.processInfo.arguments.contains("-recordsbottom") {
                        Color.clear.frame(height: 1).id("records-bottom")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            // 空态主行动统一落在底部栏：和车库、徽章空态保持同一个位置，
            // 不能悬在页面中部、下面空掉半屏。
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsEmptyAction {
                    Button {
                        NotificationCenter.default.post(name: .switchToRoutesTab, object: nil)
                    } label: {
                        Text("去挑一条路线")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(SolidPressStyle())
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                    .wellwayBottomBar()
                }
            }
            .task(id: filteredRecords.count) {
                guard ProcessInfo.processInfo.arguments.contains("-recordsbottom"),
                      !filteredRecords.isEmpty else { return }
                try? await Task.sleep(nanoseconds: 250_000_000)
                withAnimation(.easeOut(duration: 0.24)) {
                    proxy.scrollTo("records-bottom", anchor: .bottom)
                }
            }
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: RecordsViewportHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(RecordsViewportHeightKey.self) { viewportHeight = $0 }
        .refreshable { await store?.load() }
        .navigationDestination(item: $deepLinkRecord) { record in
            if let store {
                RecordDetailView(store: store, recordId: record.id)
            }
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .hidesAppTabBar()
        .task {
            if ProcessInfo.processInfo.arguments.contains("-recordcompleted") {
                filter = "已完成"
            }
            let service = store ?? RecordsStore(client: auth.client, userId: auth.user?.id ?? UUID())
            store = service
            if ProcessInfo.processInfo.arguments.contains("-recordridingsample") {
                service.applyRidingSample()
                return
            }
            await service.load()
            if let initialRecordId,
               let record = service.records.first(where: { $0.id == initialRecordId }) {
                deepLinkRecord = record
            } else if ProcessInfo.processInfo.arguments.contains("-recordfirst"),
                      let first = service.records.first {
                deepLinkRecord = first
            }
        }
        .wellwayPrompt(
            isPresented: $showRename,
            title: "重命名记录",
            placeholder: "新的记录名称",
            text: $renameDraft
        ) {
            guard let renamingRecord else { return }
            store?.rename(record: renamingRecord, to: renameDraft)
        }
        .pageMark(showRename ? 74 : (store?.records.isEmpty == true ? 39 : 6))
    }

    private var segmentedControl: some View {
        HStack(spacing: 4) {
            segment("全部", isSelected: filter == "全部") { filter = "全部" }
            segment("已完成", isSelected: filter == "已完成") { filter = "已完成" }
        }
        .padding(3)
        .background(Theme.lightField)
        .clipShape(Capsule())
    }

    private func segment(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Theme.textSecondary)
                .frame(width: 76, height: 30)
                .background(isSelected ? Theme.textPrimary : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(CardPressStyle(scale: 0.96))
        // 选中态只靠黑底白字表达时，旁白读不出当前筛选；补上系统选中特征。
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// 近 30 天概览：只使用已完成记录，和下方列表筛选解耦
    private var recentSummary: some View {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        let recent = (store?.records ?? []).filter { record in
            guard record.isCompleted,
                  let date = ISO8601DateFormatter.wellwayDate(from: record.startedAt) else { return false }
            return date >= cutoff
        }
        let distance = recent.reduce(0) { $0 + Double($1.distanceM) } / 1000
        let seconds = recent.reduce(0) { $0 + max(0, $1.durationS) }
        let duration: (value: String, unit: String) = {
            // 概览已经明确写了 0 次，里程和时长应呈现真实的 0，而不是像加载失败
            if recent.isEmpty { return ("0", "分钟") }
            if seconds < 60 { return ("\(seconds)", "秒") }
            if seconds < 3_600 { return ("\(seconds / 60)", "分钟") }
            return (String(format: "%.1f", Double(seconds) / 3_600), "小时")
        }()
        let hasDistance = recent.contains { $0.hasRecordedTrack }
        let distanceValue: String
        if recent.isEmpty {
            distanceValue = "0"
        } else if hasDistance {
            distanceValue = String(format: "%.1f", distance)
        } else {
            // 破折号放在 22pt 数字位会被读成一条分隔线，直接写「未记录」
            distanceValue = "未记录"
        }

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("近 30 天")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("仅统计已完成")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            MetricRowLayout {
                summaryMetric("\(recent.count)", unit: "", label: "骑行次数")
                summaryDivider
                summaryMetric(distanceValue, unit: recent.isEmpty || hasDistance ? "km" : "", label: "里程")
                summaryDivider
                summaryMetric(duration.value, unit: duration.unit, label: "时长")
            }
        }
        .padding(16)
        .background(Theme.lightField)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // 不合成一句会念成「近 30 天、仅统计已完成、5、次、—、56、秒、骑行、里程、时长」
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "近 30 天，完成 \(recent.count) 次，"
                + (hasDistance ? "里程 \(distanceValue) 公里" : "里程未记录")
                + "，时长 \(duration.value) \(duration.unit)"
        )
    }

    private func summaryMetric(_ value: String, unit: String, label: String) -> some View {
        let missing = (value == "—" || value == "未记录")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: missing ? 16 : 22, weight: missing ? .medium : .bold))
                    .baselineOffset(missing ? 3 : 0)
                    .foregroundStyle(missing ? Theme.textSecondary : Theme.textPrimary)
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: 1, height: 34)
            .padding(.horizontal, 12)
            .metricRowFixed()
    }

    /// 概览只统计近 30 天，列表却包含全部记录；明确分组避免用户误以为数据矛盾。
    private var recordsSectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(filter == "已完成" ? "已完成记录" : "全部记录")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Text("\(filteredRecords.count) 条")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 2)
    }

    /// 空数据且不是加载/错误态时，页底固定「去挑一条路线」，与其它空态一致。
    private var showsEmptyAction: Bool {
        guard let store else { return false }
        return store.records.isEmpty && store.errorMessage == nil && !store.isLoading
    }

    private var emptyState: some View {
        // 空态只留一句话会让人卡在这里（本页隐藏了 Tab 栏，只能返回）。
        // 给一个下一步：跳到路线页挑一条，跳转时会收起当前导航栈。
        DesignEmptyState(
            icon: "clock.arrow.circlepath",
            title: "还没有骑行记录",
            message: "完成第一次骑行后，记录会出现在这里"
        )
        // 和车辆切换页同一个做法：在滚动容器里按高度居中，
        // 不依赖手动测量的视口高度（加底部安全区后测量值会失效）。
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical)
    }

    private func inlineErrorBanner(_ message: String, retry: @escaping () -> Void) -> some View {
        InlineRefreshNotice(message: "记录刷新失败，当前显示上次数据", retry: retry)
            .accessibilityHint(message)
    }

    /// 有记录、但当前筛选下没有结果
    private var filteredEmptyState: some View {
        let unfinished = (store?.records ?? []).filter { !$0.isCompleted }
        let riding = unfinished.filter { $0.status == "riding" && !$0.isStaleRiding }.count
        return VStack(spacing: 24) {
            DesignEmptyState(
                icon: "checkmark.circle",
                title: "还没有已完成的记录",
                message: riding > 0
                    ? "有 \(riding) 条进行中的记录，完成后会显示在这里"
                    : (unfinished.isEmpty
                        ? "完成一次骑行后，已完成的记录会出现在这里"
                        : "有 \(unfinished.count) 条未完成的记录，不会计入已完成")
            )
            // 复位筛选不是本页主行动：用文字操作（44pt 热区）表达，
            // 实心黑块留给「去挑一条路线」这类真正的下一步。
            Button {
                filter = "全部"
            } label: {
                Text("查看全部记录")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
            .accessibilityHint("关闭已完成筛选，显示全部骑行记录")
        }
        .frame(
            maxWidth: .infinity,
            minHeight: max(0, viewportHeight - 44),
            alignment: .center
        )
    }

    /// 首次加载骨架：筛选条 / 近 30 天概览 / 记录卡同构，刷新时保留已有内容
    private var recordsSkeleton: some View {
        let block = Theme.cardStroke
        return VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(Theme.lightField)
                .frame(width: 160, height: 36)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(block)
                        .frame(width: 76, height: 30)
                        .padding(3)
                }

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    block.frame(width: 64, height: 12).clipShape(Capsule())
                    Spacer()
                    block.frame(width: 44, height: 10).clipShape(Capsule())
                }
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 7) {
                            block.frame(width: 54, height: 21).clipShape(Capsule())
                            block.frame(width: 40, height: 10).clipShape(Capsule())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(16)
            .background(Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 9) {
                            block.frame(width: 138, height: 16).clipShape(Capsule())
                            block.frame(width: 196, height: 11).clipShape(Capsule())
                            block.frame(width: 90, height: 11).clipShape(Capsule())
                        }
                        Spacer()
                        block.frame(width: 20, height: 20).clipShape(Circle())
                    }
                    .padding(.vertical, 16)
                    if index < 2 {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 20)
            .background(Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.top, 4)
    }

    private func recordsCard(store: RecordsStore) -> some View {
        let records = filteredRecords
        return VStack(spacing: 0) {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                NavigationLink {
                    RecordDetailView(store: store, recordId: record.id)
                } label: {
                    recordRow(
                        record,
                        store: store,
                        showsDate: index == 0 || !isSameDay(records[index - 1].startedAt, record.startedAt)
                    )
                }
                .buttonStyle(RowPressStyle())

                if index < records.count - 1 {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 1)
                        .padding(.leading, 56)
                }
            }
        }
    }

    private func recordRow(_ record: RideRecord, store: RecordsStore, showsDate: Bool) -> some View {
        HStack(spacing: 12) {
            dateBadge(record.startedAt, showsDate: showsDate)

            VStack(alignment: .leading, spacing: 5) {
                Text(store.displayName(for: record).withoutEmoji)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                // 同一天可能有多条同类记录（例如连着几次短途练习），
                // 只靠日期块无法区分先后，副标题固定带上出发时刻。
                // 375pt 小屏放不下「时刻 · 距离 · 时长 · 均速」四段时，
                // 先去掉均速（详情页仍有），而不是把 km/h 截成半个单位。
                ViewThatFits(in: .horizontal) {
                    subtitleText(recordSubtitle(record, includesSpeed: true))
                    subtitleText(recordSubtitle(record, includesSpeed: false))
                }
            }

            Spacer(minLength: 8)

            if !record.isCompleted {
                Text(record.displayStatus)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(record.statusForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(record.statusBackground)
                    .clipShape(Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.chevron)
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        // 同一天的后续记录没有日期块，读屏逐行滑动时会失去日期；
        // 副标题里的「km」又会被念成字母。整行合成一句话，日期、时刻、状态都带上。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(routeRowAccessibilityLabel(record, store: store))
        .accessibilityAddTraits(.isButton)
    }

    /// 同一天的多条记录只保留第一个日期块，避免重复日期把列表切碎
    private func isSameDay(_ lhs: String, _ rhs: String) -> Bool {
        guard let a = ISO8601DateFormatter.wellwayDate(from: lhs),
              let b = ISO8601DateFormatter.wellwayDate(from: rhs) else { return false }
        return Calendar.current.isDate(a, inSameDayAs: b)
    }

    private func dateBadge(_ iso: String, showsDate: Bool = true) -> some View {
        let parts = dateParts(iso)
        return VStack(spacing: 0) {
            if showsDate {
                Text(parts.day)
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(parts.month)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: 44, height: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsDate ? "\(parts.month)\(Int(parts.day) ?? 0)日" : "")
        .accessibilityHidden(!showsDate)
    }

    /// 记录副标题：时刻 · 距离 · 时长 · 均速。
    /// 没跑起来的记录时长是 0 秒，写出来只是噪音（还会让人以为数据缺失），直接省略。
    /// 没有轨迹的记录不再逐行写「轨迹未记录」：一屏七八行都在重复同一个负面状态，
    /// 概览卡已经写了里程「未记录」，详情页也会说明原因。
    /// 时长用 m:ss / h:mm:ss 而不是「1 小时 30 分」：副标题只有一行，
    /// 中文时长会把长骑行的「均速 xx.x km/h」挤出屏幕、连单位一起截掉。
    /// 读屏仍走 recordSubtitleSpoken 的完整中文，不受影响。
    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
    }

    private func recordSubtitle(_ record: RideRecord, includesSpeed: Bool = true) -> String {
        var parts = [timeText(record.startedAt)]
        if record.hasRecordedTrack {
            parts.append(String(format: "%.1f km", Double(record.distanceM) / 1000))
        }
        if record.durationS > 0 {
            parts.append(RideDurationText.elapsed(seconds: record.durationS))
        }
        if includesSpeed, record.hasRecordedTrack, let speed = record.avgSpeedKmh, speed > 0 {
            parts.append("均速 \(String(format: "%.1f", speed)) km/h")
        }
        return parts.joined(separator: " · ")
    }

    /// 读屏用副标题：屏幕上「km / km/h / ·」会被念成字母和停顿，换成中文与逗号。
    private func recordSubtitleSpoken(_ record: RideRecord) -> String {
        var parts = [timeText(record.startedAt)]
        if record.hasRecordedTrack {
            parts.append(String(format: "%.1f 公里", Double(record.distanceM) / 1000))
        }
        if record.durationS > 0 {
            parts.append(formatDuration(record.durationS))
        }
        if record.hasRecordedTrack, let speed = record.avgSpeedKmh, speed > 0 {
            parts.append("均速 " + String(format: "%.1f", speed) + " 公里每小时")
        }
        return parts.joined(separator: "，")
    }

    /// 整行读屏文案。日期块只出现在当天第一条，所以日期要由每行自己播报。
    private func routeRowAccessibilityLabel(_ record: RideRecord, store: RecordsStore) -> String {
        let parts = dateParts(record.startedAt)
        var spoken: [String] = []
        if let day = Int(parts.day) { spoken.append("\(parts.month)\(day)日") }
        spoken.append(store.displayName(for: record).withoutEmoji)
        spoken.append(recordSubtitleSpoken(record))
        if !record.isCompleted { spoken.append(record.displayStatus) }
        return spoken
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .filter { $0 != "—" }
            .joined(separator: "，")
    }

    /// 出发时刻，HH:mm
    private func timeText(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.wellwayDate(from: iso) else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func dateParts(_ iso: String) -> (day: String, month: String) {
        guard let date = ISO8601DateFormatter.wellwayDate(from: iso) else { return ("", "") }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd"
        let day = formatter.string(from: date)
        formatter.dateFormat = "M月"
        return (day, formatter.string(from: date))
    }

    private func avgSpeedText(_ record: RideRecord) -> String {
        guard record.isCompleted,
              let speed = record.avgSpeedKmh,
              speed > 0 else { return "—" }
        return String(format: "%.1f", speed)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: selected ? .bold : .regular))
                .foregroundColor(selected ? .white : Theme.textSecondary)
                .frame(width: 88, height: 32)
                .background(selected ? Color.black : Theme.chipBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(CardPressStyle(scale: 0.96))
    }

    private func formatDate(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.wellwayDate(from: iso) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM.dd"
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: Int) -> String {
        RideDurationText.words(seconds: seconds)
    }
}

/// 全屏轨迹：记录详情里的 190pt 缩略图放不开缩放，全屏才允许双指缩放与拖动。
private struct RecordTrackFullScreenView: View {
    let points: [CLLocationCoordinate2D]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.07, green: 0.07, blue: 0.07)
                .ignoresSafeArea()

            RecordTrackMap(points: points, interactive: true)
                .ignoresSafeArea()

            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        // ultraThinMaterial 在深色地图上会泛白，白 X 压在浅灰圆上几乎看不见；
                        // 固定半透明黑底 + 细描边，任何底图上都读得清。
                        .background(Color.black.opacity(0.45), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(IconPressStyle(pressedOpacity: 0.6))
                .accessibilityLabel("关闭全屏轨迹")

                Text("骑行轨迹")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
        // 全屏是深色地图：状态栏不改浅色会变成黑字压深底，时间电量都看不清。
        .preferredColorScheme(.dark)
        // 与路线「全览」保持同一套全屏地图语言：沉浸浏览时收起状态栏。
        .statusBarHidden()
    }
}

/// 已保存轨迹的静态回放地图：只展示路线与起终点，不与页面滚动手势冲突。
private struct RecordTrackMap: View {
    let points: [CLLocationCoordinate2D]
    /// 记录详情里的缩略图锁死手势，避免和页面滚动打架；全屏页才放开缩放与拖动。
    var interactive: Bool = false
    @State private var camera: MapCameraPosition = .automatic

    /// 长骑行只抽稀展示；原始点位仍完整保存在记录里。
    private var displayPoints: [CLLocationCoordinate2D] {
        let maxCount = 1_200
        guard points.count > maxCount else { return points }
        let step = Int(ceil(Double(points.count) / Double(maxCount)))
        var sampled = stride(from: 0, to: points.count, by: step).map { points[$0] }
        if let last = points.last,
           sampled.last.map({ $0.latitude == last.latitude && $0.longitude == last.longitude }) != true {
            sampled.append(last)
        }
        return sampled
    }

    var body: some View {
        Map(position: $camera, interactionModes: interactive ? .all : []) {
            MapPolyline(coordinates: displayPoints)
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            if let first = displayPoints.first {
                Annotation("", coordinate: first) {
                    Circle()
                        .fill(Theme.success)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }

            if let last = displayPoints.last {
                Annotation("", coordinate: last) {
                    Circle()
                        .fill(.white)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Theme.darkBackground, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .environment(\.colorScheme, .dark)
        .onAppear { camera = .region(region) }
    }

    private var region: MKCoordinateRegion {
        let lats = points.map(\.latitude)
        let lngs = points.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 25.8, longitude: 100.2),
                span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
            )
        }
        let latDelta = max((maxLat - minLat) * 1.55, 0.008)
        let lngDelta = max((maxLng - minLng) * 1.55, 0.008)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
        )
    }
}

/// 骑行记录数据(记录列表 + 打卡明细 + 本地重命名)
@MainActor
@Observable
final class RecordsStore {
    private(set) var records: [RideRecord] = []
    private(set) var isLoading = false
    private(set) var routesById: [Int: Route] = [:]
    private(set) var checkpointsById: [Int: Checkpoint] = [:]
    private(set) var vehiclesById: [UUID: Vehicle] = [:]
    private var brandsById: [Int: Brand] = [:]
    private var modelsById: [Int: VehicleModel] = [:]
    private(set) var checkinsByRide: [UUID: [RideCheckin]] = [:]
    private(set) var trackByRide: [UUID: [RidePoint]] = [:]
    private(set) var trackLoadFailedForRide: Set<UUID> = []
    private(set) var checkinLoadFailedForRide: Set<UUID> = []
    var errorMessage: String?

    private let client: SupabaseClient
    private let userId: UUID

    init(client: SupabaseClient, userId: UUID) {
        self.client = client
        self.userId = userId
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        // 调试入口：-recordsempty 直接按空数据渲染「还没有骑行记录」
        if ProcessInfo.processInfo.arguments.contains("-recordsempty") {
            records = []
            errorMessage = nil
            return
        }
        errorMessage = nil
        async let routesTask: () = loadRoutes()
        async let checkpointsTask: () = loadCheckpoints()
        async let vehiclesTask: () = loadVehicles()
        async let recordsTask: () = loadRecords()
        _ = await (routesTask, checkpointsTask, vehiclesTask, recordsTask)
    }

    private func loadRoutes() async {
        do {
            let loaded: [Route] = try await client
                .from("routes")
                .select("id, name, start_name, end_name, distance_m, elevation_m, difficulty, duration_min, map_url, cover_image_url, province, city")
                .eq("is_active", value: true)
                .execute()
                .value
            routesById = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        } catch {
            errorMessage = error.wellwayUserMessage
        }
    }

    private func loadCheckpoints() async {
        do {
            let loaded: [Checkpoint] = try await client
                .from("checkpoints")
                .select("id, route_id, name, seq, lat, lng, radius_m")
                .order("seq")
                .execute()
                .value
            checkpointsById = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        } catch {
            errorMessage = error.wellwayUserMessage
        }
    }

    /// 车辆信息是记录详情的补充：失败时静默降级，不影响记录列表主流程
    private func loadVehicles() async {
        guard let vehicles: [Vehicle] = try? await client
            .from("vehicles")
            .select("id, user_id, brand_id, model_id, nickname, color, photo_url, is_default")
            .eq("user_id", value: userId)
            .execute()
            .value else { return }
        vehiclesById = Dictionary(uniqueKeysWithValues: vehicles.map { ($0.id, $0) })
        guard !vehicles.isEmpty else { return }

        let brandIds = Array(Set(vehicles.map(\.brandId)))
        let modelIds = Array(Set(vehicles.map(\.modelId)))

        if let brands: [Brand] = try? await client
            .from("brands")
            .select("id, name, name_en, is_hot, sort")
            .in("id", values: brandIds)
            .execute()
            .value {
            brandsById = Dictionary(uniqueKeysWithValues: brands.map { ($0.id, $0) })
        }
        if let models: [VehicleModel] = try? await client
            .from("models")
            .select("id, brand_id, name, series, model_type, displacement_cc, price_min, price_max, rating, is_new, sort, image_url")
            .in("id", values: modelIds)
            .execute()
            .value {
            modelsById = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        }
    }

    /// 记录详情里的本次车辆；无法关联到车辆时返回 nil，不伪造名称。
    func vehicleName(for record: RideRecord) -> String? {
        guard let vehicleId = record.vehicleId,
              let vehicle = vehiclesById[vehicleId] else { return nil }
        // 与车库首页保持一致：统一显示「品牌(中文优先) + 车型」。
        // 昵称是早期添加车辆时自动写入的车型名副本，展示出来会和品牌车型重复。
        let brand = brandsById[vehicle.brandId]
        let brandZh = (brand?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let brandName = brandZh.isEmpty
            ? (brand?.nameEn ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            : brandZh
        let modelName = modelsById[vehicle.modelId]?
            .displayName(removingBrand: brand)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = [brandName, modelName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? nil : name
    }

    /// 调试用(-recordridingsample)：只注入一条进行中的记录，用于验证筛选空态
    func applyRidingSample() {
        records = [
            RideRecord(
                id: UUID(),
                userId: userId,
                routeId: 1,
                vehicleId: nil,
                name: ProcessInfo.processInfo.arguments.contains("-longnames")
                    ? "大理古城到双廊的环洱海长距离耐力骑行挑战路线"
                    : "洱海环湖骑行",
                startedAt: "2026-11-05T09:10:00Z",
                endedAt: nil,
                distanceM: 0,
                durationS: 0,
                avgSpeedKmh: nil,
                maxSpeedKmh: nil,
                elevationGainM: 0,
                status: "riding"
            )
        ]
    }

    func loadRecords() async {
        do {
            records = try await selectRecords(includeName: true)
        } catch {
            // 云端尚无 name 列(0006 迁移未执行),退回不带 name 的查询
            do {
                records = try await selectRecords(includeName: false)
            } catch {
                errorMessage = error.wellwayUserMessage
            }
        }
    }

    private func selectRecords(includeName: Bool) async throws -> [RideRecord] {
        let columns = includeName
            ? "id, name, user_id, route_id, vehicle_id, started_at, ended_at, distance_m, duration_s, avg_speed_kmh, max_speed_kmh, elevation_gain_m, status"
            : "id, user_id, route_id, vehicle_id, started_at, ended_at, distance_m, duration_s, avg_speed_kmh, max_speed_kmh, elevation_gain_m, status"
        return try await client
            .from("ride_records")
            .select(columns)
            .eq("user_id", value: userId)
            .order("started_at", ascending: false)
            .execute()
            .value
    }

    func loadCheckins(for rideId: UUID) async {
        // 打卡明细为尽力而为的补充数据：失败不应破坏列表主流程，也不覆盖主错误
        do {
            let loaded: [RideCheckin] = try await client
                .from("ride_checkins")
                .select("id, ride_id, checkpoint_id, checked_at")
                .eq("ride_id", value: rideId)
                .execute()
                .value
            checkinsByRide[rideId] = loaded
            checkinLoadFailedForRide.remove(rideId)
        } catch {
            checkinsByRide[rideId] = checkinsByRide[rideId] ?? []
            checkinLoadFailedForRide.insert(rideId)
        }
    }

    /// 轨迹回放数据：失败或为空都只影响地图卡，不覆盖记录页主错误。
    func loadTrack(for rideId: UUID) async {
        // 调试预览注入的轨迹不写库，重新拉取会用空结果把它覆盖掉
        if ProcessInfo.processInfo.arguments.contains("-recordtrackpreview") { return }
        guard trackByRide[rideId] == nil || trackLoadFailedForRide.contains(rideId) else { return }
        do {
            var loaded: [RidePoint] = []
            var offset = 0
            let pageSize = 1000
            while true {
                let page: [RidePoint] = try await client
                    .from("ride_points")
                    .select("lat, lng, speed_kmh, recorded_at")
                    .eq("ride_id", value: rideId)
                    .order("recorded_at", ascending: true)
                    .range(from: offset, to: offset + pageSize - 1)
                    .execute()
                    .value
                loaded.append(contentsOf: page)
                if page.count < pageSize { break }
                offset += pageSize
            }
            trackByRide[rideId] = loaded
            trackLoadFailedForRide.remove(rideId)
        } catch {
            trackByRide[rideId] = []
            trackLoadFailedForRide.insert(rideId)
        }
    }

    /// 调试(-recordtrackpreview):把记录换成一条有完整指标的已完成骑行，
    /// 用于截图复检里程/均速/爬升与轨迹图版式(线上数据里不一定有轨迹)
    func applyDebugTrackPreview(for rideId: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == rideId }) else { return }
        let base = records[idx]
        records[idx] = RideRecord(
            id: base.id,
            userId: base.userId,
            routeId: base.routeId,
            vehicleId: base.vehicleId,
            name: base.name,
            startedAt: base.startedAt,
            endedAt: base.endedAt,
            distanceM: 8240,
            durationS: 1284,
            avgSpeedKmh: 23.1,
            maxSpeedKmh: 46.8,
            elevationGainM: 138,
            status: "completed"
        )
        applyDebugTrack(for: rideId)
    }

    /// 调试用：给详情地图注入一段洱海示例轨迹，不写数据库。
    func applyDebugTrack(for rideId: UUID) {
        let samples: [(Double, Double)] = [
            (25.6930, 100.1620), (25.7060, 100.1580), (25.7240, 100.1510),
            (25.7440, 100.1460), (25.7660, 100.1430), (25.7880, 100.1420),
            (25.8100, 100.1450), (25.8320, 100.1520), (25.8520, 100.1610),
            (25.8700, 100.1740), (25.8850, 100.1880), (25.8980, 100.2030),
            (25.9070, 100.2190), (25.9130, 100.2360), (25.9180, 100.2540)
        ]
        trackByRide[rideId] = samples.enumerated().map { index, point in
            RidePoint(
                lat: point.0,
                lng: point.1,
                speedKmh: Double(38 + (index % 5) * 4),
                recordedAt: "2026-11-05T10:\(String(format: "%02d", index)):00Z"
            )
        }
    }

    @discardableResult
    func delete(record: RideRecord) async -> Bool {
        do {
            try await client.from("ride_records").delete().eq("id", value: record.id).execute()
            records.removeAll { $0.id == record.id }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.wellwayUserMessage
            return false
        }
    }

    /// 重命名记录：云端 name 列优先(0006 迁移后生效),列不存在时降级本地存储
    func rename(record: RideRecord, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: "rideName-\(record.id.uuidString)")
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.client
                    .from("ride_records")
                    .update(["name": trimmed])
                    .eq("id", value: record.id)
                    .execute()
                self.records = self.records.map { $0.id == record.id ? $0.withName(trimmed) : $0 }
            } catch {
                // 云端列不存在等错误：保留本地名称
            }
        }
    }

    func displayName(for record: RideRecord) -> String {
        if let cloud = record.name, !cloud.isEmpty {
            return cloud
        }
        if let custom = UserDefaults.standard.string(forKey: "rideName-\(record.id.uuidString)"), !custom.isEmpty {
            return custom
        }
        if let routeId = record.routeId, let route = routesById[routeId] {
            return route.name
        }
        return "骑行记录"
    }
}

private extension RideRecord {
    func withName(_ name: String) -> RideRecord {
        .init(
            id: id, userId: userId, routeId: routeId, vehicleId: vehicleId, name: name,
            startedAt: startedAt, endedAt: endedAt, distanceM: distanceM, durationS: durationS,
            avgSpeedKmh: avgSpeedKmh, maxSpeedKmh: maxSpeedKmh, elevationGainM: elevationGainM, status: status
        )
    }
}

/// 骑行记录详情(Figma「骑行记录详情」)
struct RecordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let store: RecordsStore
    let recordId: UUID

    @State private var record: RideRecord?
    @State private var showRename = false
    @State private var renameDraft = ""
    @State private var showDelete = false
    @State private var showDeleteFailed = false
    @State private var isDeleting = false
    @State private var trackLoaded = false
    @State private var recordLookupFinished = false
    @State private var showShare = false
    @State private var sharePayload: [Any] = []
    @State private var showFullScreenTrack = false

    var body: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: "记录详情")

            if let record {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        headerBlock(record)
                        statsCard(record)
                        if record.hasRecordedTrack {
                            trackSection(record)
                        }
                        checkpointsSection(record)
                        actionsCard(record)
                        if !record.hasRecordedTrack {
                            noTrackFootnote(record)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            } else if recordLookupFinished {
                VStack(spacing: 18) {
                    DesignEmptyState(
                        icon: "doc.text.magnifyingglass",
                        title: "记录不存在",
                        message: "这条记录可能已被删除，或尚未同步到当前账号"
                    )
                    Button("返回记录列表") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.white)
        .toolbar(.hidden, for: .navigationBar)
        .hidesAppTabBar()
        .ignoresSafeArea(edges: .top)
        .overlay {
            if isDeleting {
                deletingOverlay
            }
        }
        .fullScreenCover(isPresented: $showFullScreenTrack) {
            RecordTrackFullScreenView(
                points: (store.trackByRide[recordId] ?? []).map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
                }
            )
        }
        .task {
            if record == nil {
                record = store.records.first { $0.id == recordId }
                if let record {
                    await store.loadCheckins(for: record.id)
                    // 记录本身没有有效轨迹时，ride_points 一定为空；直接展示
                    // 「未上传有效轨迹」，避免先闪一个 190pt 的加载块再给结论。
                    if record.hasRecordedTrack {
                        await store.loadTrack(for: record.id)
                    }
                    trackLoaded = true
                }
                recordLookupFinished = true
            }
        }
        .wellwayPrompt(
            isPresented: $showRename,
            title: "重命名记录",
            placeholder: "输入新的记录名称",
            text: $renameDraft
        ) {
            if let record {
                store.rename(record: record, to: renameDraft)
            }
        }
        .wellwayDialog(
            isPresented: $showDelete,
            title: "删除这条骑行记录？",
            message: "删除后无法恢复，徽章不会受影响",
            buttons: [
                WellwayDialogButton(title: "删除", role: .destructive) {
                    guard let record, !isDeleting else { return }
                    isDeleting = true
                    Task {
                        let deleted = await store.delete(record: record)
                        isDeleting = false
                        if deleted {
                            dismiss()
                        } else {
                            showDeleteFailed = true
                        }
                    }
                }
            ]
        )
        .wellwayDialog(
            isPresented: $showDeleteFailed,
            title: "删除失败",
            message: store.errorMessage ?? "请检查网络后重试",
            buttons: [WellwayDialogButton(title: "知道了", role: .plain) {}]
        )
        .sheet(isPresented: $showShare) {
            ShareSheet(items: sharePayload)
        }
        .pageMark(showRename ? 74 : (showDelete ? 44 : 7))
    }

    /// 删除请求可能受网络影响：明确显示进行中，并阻断重复点击。
    private var deletingOverlay: some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Theme.textPrimary)
                Text("正在删除…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 18, y: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在删除骑行记录")
    }

    // MARK: - 头部

    private func headerBlock(_ record: RideRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.displayName(for: record).withoutEmoji)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(formatDate(record.startedAt))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                if !record.isCompleted {
                    Text(record.displayStatus)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(record.statusForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(record.statusBackground)
                        .clipShape(Capsule())
                }
            }
            if let vehicleName = store.vehicleName(for: record) {
                Text("本次车辆 · \(vehicleName)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 2)
                    // 间隔号读出来是一个停顿，读屏改成逗号更清楚。
                    .accessibilityLabel("本次车辆，\(vehicleName)")
            }
        }
        .motionAppear(delay: 0.06)
    }

    // MARK: - 数据卡

    private func statsCard(_ record: RideRecord) -> some View {
        Group {
            if record.hasRecordedTrack {
                trackStats(record)
            } else {
                // 没上传轨迹时里程/均速/爬升都是空的：与其排三个破折号，不如只留真实有值的时长。
                // 单独一项撑满整行会变成一个 20pt 的数字横在那里，像重点被放大；
                // 改成「标签左、数值右」的明细行，和下方打卡明细同一种读法。
                HStack(spacing: 12) {
                    Text("时长")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 8)
                    Text(formatDuration(record.durationS))
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                }
                .frame(height: 56)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("时长，\(formatDuration(record.durationS))")
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        .motionAppear(delay: 0.12)
    }

    private func trackStats(_ record: RideRecord) -> some View {
        MetricRowLayout {
            statColumn("里程", value: record.hasRecordedTrack ? String(format: "%.1f", Double(record.distanceM) / 1000) : "—", unit: record.hasRecordedTrack ? "km" : nil)
            statDivider
            // 「21 分 24 秒」在四列里会被截成「21 分 24…」，改用运动 App 的紧凑写法
            statColumn("时长", value: compactDuration(record.durationS), unit: nil)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("时长，\(formatDuration(record.durationS))")
            statDivider
            statColumn("均速", value: avgSpeedText(record), unit: avgSpeedUnit(record))
            statDivider
            statColumn(
                "爬升",
                value: record.elevationGainM > 0 ? "\(record.elevationGainM)" : "—",
                unit: record.elevationGainM > 0 ? "m" : nil
            )
        }
        .frame(height: 72)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: 1, height: 34)
            .padding(.horizontal, 12)
            .metricRowFixed()
    }

    /// 四列指标里时长必须单行放得下：21:24 / 1:21:24
    private func compactDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let sec = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    private func statColumn(_ label: String, value: String, unit: String?) -> some View {
        // 缺数据时用灰色小号占位，避免一条又粗又长的黑色破折号抢走整个指标行的注意力
        let missing = (value == "—")
        return VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: missing ? .regular : .semibold))
                    .monospacedDigit()
                    .foregroundStyle(missing ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 四列分成 12 个朗读元素时，用户要听「里程 / 5.2 / km / 时长…」；
        // 每列合成为一句，缺失值也直接读成「未记录」。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label)，\(spokenStatValue(value, unit: unit))")
    }

    private func spokenStatValue(_ value: String, unit: String?) -> String {
        guard value != "—" else { return "未记录" }
        switch unit {
        case "km": return "\(value) 公里"
        case "m": return "\(value) 米"
        case "km/h": return "\(value) 公里每小时"
        default: return value
        }
    }

    private func legendDot(fill: Color, ring: Color?, text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(fill)
                .frame(width: 8, height: 8)
                .overlay {
                    if let ring {
                        Circle().stroke(ring, lineWidth: 1.2)
                    }
                }
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - 骑行轨迹

    /// 没有轨迹时不在页首占一整块：说明降为页尾一行，页面先呈现指标与打卡。
    private func noTrackFootnote(_ record: RideRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "map")
                .font(.system(size: 11, weight: .medium))
                // 纯装饰：SF Symbol 默认会念出英文「Show Map」。
                .accessibilityHidden(true)
            // 里程/时长来自骑行记录本身：有数字时说清楚出处，
            // 没有数字时再说缺失，避免和上方指标打架。
            Text(record.distanceM > 0
                 ? "本次骑行未记录轨迹，里程与均速按骑行记录统计"
                 : (record.isCompleted
                    ? "本次骑行未记录轨迹，里程与均速无法统计"
                    : "骑行没有正常结束，没有里程与配速"))
                .font(.system(size: 12))
        }
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trackSection(_ record: RideRecord) -> some View {
        let points = (store.trackByRide[record.id] ?? []).map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
        }
        let failed = store.trackLoadFailedForRide.contains(record.id)
        return VStack(alignment: .leading, spacing: 10) {
            Text("骑行轨迹")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            if !trackLoaded {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.lightField)
                    .frame(height: 190)
                    .overlay(ProgressView())
            } else if points.count >= 2 {
                VStack(alignment: .leading, spacing: 8) {
                    RecordTrackMap(points: points)
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Theme.separator, lineWidth: 1)
                        }
                        // 190pt 只能看个大概：点开全屏才能看清弯道和起终点。
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(7)
                                .background(Color.black.opacity(0.45), in: Circle())
                                .padding(10)
                                .allowsHitTesting(false)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onTapGesture { showFullScreenTrack = true }
                        .accessibilityElement()
                        .accessibilityLabel("骑行轨迹地图")
                        .accessibilityHint("点按查看全屏轨迹")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { showFullScreenTrack = true }

                    // 地图上只有两个圆点，标一下哪个是起点哪个是终点
                    HStack(spacing: 14) {
                        legendDot(fill: Theme.success, ring: nil, text: "起点")
                        legendDot(fill: .white, ring: Theme.textPrimary, text: "终点")
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "map")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 40)
                        // 旁边的标题已经说明状态，图标只是装饰。
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(failed ? "轨迹暂时无法加载" : (record.isCompleted ? "本次骑行未上传有效轨迹" : "骑行没有正常结束"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(failed ? "请检查网络后重新进入" : (record.isCompleted ? "里程、速度与打卡可能不完整" : "轨迹与打卡可能未完整保存"))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if failed {
                        Button("重试") {
                            Task { await store.loadTrack(for: record.id) }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                    }
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        .motionAppear(delay: 0.16)
    }

    // MARK: - 打卡明细

    private func checkpointsSection(_ record: RideRecord) -> some View {
        let routeCheckpoints = store.checkpointsById.values
            .filter { $0.routeId == record.routeId }
            .sorted { $0.seq < $1.seq }
        let checked = checkedIds(record)
        let total = max(routeCheckpoints.count, store.checkinsByRide[record.id]?.count ?? 0)
        let checkins = store.checkinsByRide[record.id] ?? []
        let checkinFailed = store.checkinLoadFailedForRide.contains(record.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("打卡明细")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                Text(checkinFailed ? "—" : "\(checked.count)/\(total)")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    // 「0/2」会被念成「零斜杠二」。
                    .accessibilityLabel(checkinFailed ? "打卡进度未知" : "已打卡 \(checked.count) 个，共 \(total) 个")
            }

            if total > 0 && checked.count > 0 && !checkinFailed {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.lightField)
                        Capsule()
                            .fill(Theme.textPrimary)
                            .frame(width: max(geo.size.width * CGFloat(checked.count) / CGFloat(total), 4))
                    }
                }
                .frame(height: 4)
                .padding(.bottom, 2)
            }

            if checkinFailed {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                    Text("打卡明细暂时无法加载")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 8)
                    Button("重试") {
                        Task { await store.loadCheckins(for: record.id) }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Theme.lightField)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if routeCheckpoints.isEmpty && checkins.isEmpty {
                Text("本次骑行未打卡")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    if routeCheckpoints.isEmpty {
                        ForEach(Array(checkins.enumerated()), id: \.element.id) { index, checkin in
                            if index > 0 {
                                Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, 34)
                            }
                            checkinRow(
                                seq: index + 1,
                                name: (store.checkpointsById[checkin.checkpointId]?.name ?? "打卡点").withoutEmoji,
                                done: true
                            )
                        }
                    } else {
                        ForEach(Array(routeCheckpoints.enumerated()), id: \.element.id) { index, cp in
                            if index > 0 {
                                Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, 34)
                            }
                            checkinRow(seq: index + 1, name: cp.name.withoutEmoji, done: checked.contains(cp.id))
                        }
                    }
                }
                .background(Color.white)
            }
        }
        .motionAppear(delay: 0.18)
    }

    private func checkedIds(_ record: RideRecord) -> Set<Int> {
        Set((store.checkinsByRide[record.id] ?? []).map(\.checkpointId))
    }

    private func checkinRow(seq: Int, name: String, done: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(done ? Theme.textPrimary : Theme.lightField)
                Text("\(seq)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(done ? Color.white : Theme.textSecondary)
            }
            .frame(width: 22, height: 22)

            Text(name)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(done ? "已打卡" : "未打卡")
                .font(.system(size: 12))
                .foregroundStyle(done ? Theme.successText : Theme.textSecondary)
        }
        // 页面容器已给 20pt 边距：行内再加一份会把编号推到标题右侧，左侧出现两套对齐线
        .padding(.vertical, 14)
        // 分开念是「1、西单路口、未打卡」三个碎片，序号和名称对不上
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(seq) 个打卡点，\(name)，\(done ? "已打卡" : "未打卡")")
    }

    // MARK: - 操作

    private func actionsCard(_ record: RideRecord) -> some View {
        VStack(spacing: 0) {
            Button {
                renameDraft = store.displayName(for: record)
                showRename = true
            } label: {
                actionRow("重命名", color: Theme.textPrimary, showsChevron: true)
            }
            .buttonStyle(RowPressStyle())

            Rectangle().fill(Theme.separator).frame(height: 1)

            Button {
                prepareShare(record)
            } label: {
                HStack(spacing: 8) {
                    Text("分享记录")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.chevron)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())

            Rectangle().fill(Theme.separator).frame(height: 1)

            Button {
                showDelete = true
            } label: {
                actionRow("删除记录", color: Theme.danger)
            }
            .buttonStyle(RowPressStyle())
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        .motionAppear(delay: 0.24)
    }

    /// 可点的行必须有指向性：纯文字和上方的「打卡明细」标题长得一样，
    /// 用户看不出这是一行操作，所以给非破坏性操作补一个 chevron。
    private func actionRow(_ title: String, color: Color, showsChevron: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.chevron)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 56)
        .contentShape(Rectangle())
    }

    /// 分享文案只写真实存在的字段：无轨迹时不出现里程与均速
    private func shareText(_ record: RideRecord) -> String {
        var parts = ["我在 WellWay 完成了「\(store.displayName(for: record))」"]
        if record.hasRecordedTrack, record.distanceM > 0 {
            parts.append("里程 \(String(format: "%.1f", Double(record.distanceM) / 1000)) km")
        }
        if record.durationS > 0 {
            parts.append("时长 \(RideDurationText.elapsed(seconds: record.durationS))")
        }
        if record.hasRecordedTrack, let avg = record.avgSpeedKmh, avg > 0 {
            parts.append("均速 \(String(format: "%.1f", avg)) km/h")
        }
        return parts.joined(separator: "，") + "。"
    }

    /// 记录详情与骑行总结共用同一张分享卡；轨迹还没拉回来时先等它，
    /// 失败就按「未记录轨迹」分享，不拿打卡点伪造一条路线。
    private func prepareShare(_ record: RideRecord) {
        Task {
            if record.hasRecordedTrack, (store.trackByRide[record.id]?.count ?? 0) < 2 {
                await store.loadTrack(for: record.id)
            }
            let coordinates = (store.trackByRide[record.id] ?? []).map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
            }
            let route = record.routeId.flatMap { store.routesById[$0] }
            let start = route?.startName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let end = route?.endName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let endpoints = !start.isEmpty && !end.isEmpty ? "\(start) → \(end)" : ""

            var metrics: [(label: String, value: String)] = []
            if record.hasRecordedTrack, record.distanceM > 0 {
                metrics.append(("里程", String(format: "%.1f km", Double(record.distanceM) / 1000)))
            }
            if record.durationS > 0 {
                metrics.append(("时长", RideDurationText.elapsed(seconds: record.durationS)))
            }
            if record.hasRecordedTrack, let avg = record.avgSpeedKmh, avg > 0 {
                metrics.append(("均速", String(format: "%.1f km/h", avg)))
            }
            if record.hasRecordedTrack, record.elevationGainM > 0 {
                metrics.append(("爬升", "\(record.elevationGainM) m"))
            }

            sharePayload = [shareText(record)]
            if let image = RideShareCardRenderer.image(
                routeName: store.displayName(for: record),
                dateText: formatDate(record.startedAt),
                endpoints: endpoints,
                metrics: Array(metrics.prefix(4)),
                unitPoints: trackUnitPoints(coordinates),
                hasTrack: coordinates.count >= 2
            ) {
                sharePayload.append(image)
            }
            showShare = true
        }
    }

    private func trackUnitPoints(_ coordinates: [CLLocationCoordinate2D]) -> [CGPoint] {
        guard coordinates.count >= 2 else { return [] }
        let coords = coordinates.map { (lat: $0.latitude, lng: $0.longitude) }
        let minLat = coords.map(\.lat).min()!
        let maxLat = coords.map(\.lat).max()!
        let minLng = coords.map(\.lng).min()!
        let maxLng = coords.map(\.lng).max()!
        let latSpan = max(maxLat - minLat, 0.0001)
        let lngSpan = max(maxLng - minLng, 0.0001)
        return coords.map { coord in
            CGPoint(x: (coord.lng - minLng) / lngSpan, y: 1 - (coord.lat - minLat) / latSpan)
        }
    }

    private func formatDate(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.wellwayDate(from: iso) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
            ? "M月d日 HH:mm"
            : "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func avgSpeedText(_ record: RideRecord) -> String {
        guard record.isCompleted,
              let speed = record.avgSpeedKmh,
              speed > 0 else { return "—" }
        return String(format: "%.1f", speed)
    }

    private func avgSpeedUnit(_ record: RideRecord) -> String? {
        guard record.isCompleted,
              let speed = record.avgSpeedKmh,
              speed > 0 else { return nil }
        return "km/h"
    }

    private func formatDuration(_ seconds: Int) -> String {
        RideDurationText.words(seconds: seconds)
    }
}

private extension RideRecord {
    /// 只有 24 小时内仍在进行的记录才算「进行中」；超时记录继续用中性灰，避免误以为仍在记录。
    var isLiveRiding: Bool {
        status == "riding" && !isStaleRiding
    }

    var statusForeground: Color {
        isLiveRiding ? Theme.success : Theme.textSecondary
    }

    var statusBackground: Color {
        isLiveRiding ? Theme.success.opacity(0.10) : Theme.lightField
    }
}

private struct RecordsViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
