import SwiftUI
import CoreLocation

/// 骑行结束-轨迹总结(Figma「骑行结束-轨迹总结」112:889,按节点数据 1:1 还原)
struct RideSummaryView: View {
    let route: Route
    let checkpoints: [Checkpoint]
    let summary: RideSummary
    var onFinish: () -> Void
    /// 记录同步失败时的重试入口；nil 时只显示提示
    var onRetrySave: (() async -> Bool)? = nil

    @State private var showBadge = false
    @State private var isRetryingSave = false
    @State private var saveFixed = false
    /// 重试过一次仍失败：必须给回执，否则「转一下还是原样」等于没反应
    @State private var retryAttemptFailed = false
    @State private var showLeaveConfirm = false
    /// 徽章弹层是否已经看过:看过之后主按钮改为「完成」,避免反复打开弹层无法结束
    @State private var hasSeenBadge = false
    @State private var sharePayload: SharePayload?
    private var screenAppearance: ScreenAppearance { .shared }

    var body: some View {
        VStack(spacing: 0) {
            // 用统一页头：自定义 HStack 里 44pt 命中区会把箭头和标题整体右移 14pt，
            // 从别的页面进来时标题会「跳」一下。
            DesignPageHeader(title: "骑行总结", onBack: requestFinish)

            GeometryReader { proxy in
                let contentWidth = max(proxy.size.width - 40, 260)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: blockSpacing) {
                        if !saveFixed, let warning = summary.saveWarning {
                            saveWarningBanner(warning)
                        }
                        summaryHeader
                            .motionAppear(delay: 0.04)
                        if summary.track.count >= 2 {
                            trackCard(width: contentWidth)
                                .motionAppear(delay: 0.08)
                        } else if !sketchPoints.isEmpty {
                            routeSketchCard(width: contentWidth)
                                .motionAppear(delay: 0.08)
                        }
                        statsCard
                            .motionAppear(delay: 0.16)
                        checkpointsSection
                            .motionAppear(delay: 0.24)
                        Color.clear.frame(height: 16)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            }
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if let badge = summary.awardedBadge, showBadge {
                BadgeEarnedView(
                    badge: badge,
                    checkpoints: checkpoints,
                    checkedIds: summary.checkedCheckpointIds,
                    rideDistanceM: summary.record?.distanceM,
                    rideDurationS: summary.record?.durationS,
                    rideAvgSpeedKmh: summary.record?.avgSpeedKmh,
                    onClose: { showBadge = false }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.2), value: showBadge)
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items, fileName: payload.fileName)
        }
        .wellwayDialog(
            isPresented: $showLeaveConfirm,
            title: summary.canRetrySave ? "记录尚未同步" : "本次记录未保存",
            message: summary.canRetrySave
                ? "本次骑行记录还没有成功保存到服务器，离开后可能无法在骑行记录中查看。可先重试同步，或仍然离开。"
                : "本次骑行没有在服务器上建立记录，离开后里程、轨迹与打卡都无法再查看。",
            buttons: summary.canRetrySave
                ? [
                    WellwayDialogButton(title: "重试同步", role: .primary) { retrySave() },
                    WellwayDialogButton(title: "仍然离开", role: .destructive) { onFinish() }
                ]
                : [
                    WellwayDialogButton(title: "离开", role: .destructive) { onFinish() }
                ],
            onCancel: {}
        )
        .pageMark(3)
        .preferredColorScheme(.light)
        .onAppear { screenAppearance.push(.light) }
        .onDisappear { screenAppearance.pop(.light) }
    }

    /// 记录写库失败：不假报“已保存”，给用户明确提示
    private func saveWarningBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.danger)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.canRetrySave ? "记录同步失败" : "本次记录未保存")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                // 重试过一次还是失败时换成回执文案：否则按钮转一圈恢复原样，看不出有没有动作
                Text(retryAttemptFailed ? "仍未同步成功，请检查网络后重试" : text)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if onRetrySave != nil, summary.canRetrySave {
                Button {
                    retrySave()
                } label: {
                    if isRetryingSave {
                        ProgressView()
                            .tint(Theme.textSecondary)
                            .frame(width: 44, height: 44)
                    } else {
                        Text("重试")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                .disabled(isRetryingSave)
                .accessibilityLabel("重试同步")
            }
        }
        .padding(12)
        .background(Theme.danger.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 统一的「重试同步」入口：成功就撤掉提示，失败留下明确回执
    private func retrySave() {
        guard let onRetrySave, !isRetryingSave else { return }
        isRetryingSave = true
        Task {
            let fixed = await onRetrySave()
            if fixed {
                saveFixed = true
                retryAttemptFailed = false
            } else {
                retryAttemptFailed = true
            }
            isRetryingSave = false
        }
    }

    // MARK: - 标题(哪条路线、什么时候骑的)

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(route.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !summaryMetaLine.isEmpty {
                Text(summaryMetaLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryMetaLine: String {
        var parts: [String] = []
        if let startedAt = summary.record?.startedAt,
           let date = ISO8601DateFormatter.wellwayDate(from: startedAt) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M月d日 HH:mm"
            parts.append(formatter.string(from: date))
        }
        if let start = route.startName, let end = route.endName, !start.isEmpty, !end.isEmpty {
            parts.append("\(start) → \(end)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 轨迹卡

    /// 没有轨迹时不做大块占位，只在页尾补一句说明，避免看起来像错误态
    private var noTrackNote: some View {
        let hasStats = (summary.record?.distanceM ?? 0) > 0
        // 「记录未能创建」时根本没有骑行记录可依，再说「按骑行记录统计」等于自相矛盾；
        // 这种状态下数字只来自本次骑行过程中的本地统计。
        let text: String
        if hasStats {
            text = summary.canRetrySave
                ? "本次骑行未记录轨迹，里程、均速与爬升按骑行记录统计"
                : "本次骑行未记录轨迹，数据来自骑行中的实时统计"
        } else if summary.canRetrySave {
            text = "本次骑行未记录轨迹，开启定位后才能记录轨迹"
        } else {
            text = "本次骑行未记录轨迹，暂无里程与速度数据"
        }
        return HStack(spacing: 6) {
            Image(systemName: "map")
                .font(.system(size: 11, weight: .regular))
                .accessibilityHidden(true)
            // 有里程/时长时说明这些数字来自哪里；反过来写「没有里程」会和上面四列数字自相矛盾。
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.textSecondary)
    }

    /// 有轨迹时卡片是页面里最高的一块。短屏上仍要保证 3 个打卡点完整可见，
    /// 否则第三行只剩一个圆点露在底栏上方，看起来像排版事故。
    private var trackCardHeight: CGFloat {
        guard isShortScreen else { return 200 }
        return titleNeedsTwoLines ? 132 : 160
    }

    private func trackCard(width: CGFloat) -> some View {
        let height: CGFloat = trackCardHeight
        let points = trackUnitPoints(coordinates: summary.track)
        return ZStack {
            Theme.darkCard
            TrackPreview(
                unitPoints: points,
                trackRect: CGRect(x: 26, y: 26, width: max(width - 52, 60), height: height - 52),
                startDot: CGPoint(x: 34, y: height - 40),
                endDot: CGPoint(x: width - 40, y: 40),
                dotSize: 10
            )
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 未记录 GPS 轨迹时，用路线打卡点的真实坐标画一条虚线示意，避免页面出现大片空白
    private var sketchPoints: [CGPoint] {
        trackUnitPoints(checkpoints)
    }

    /// 短屏（SE 类）判定：这些机型首屏放不下三行打卡，需要主动收紧纵向节奏。
    private var isShortScreen: Bool {
        let screenHeight = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .screen.bounds.height ?? 800
        return screenHeight < 700
    }

    /// 区块间距：短屏收到 16，避免最后一个打卡点被底栏切掉半行。
    private var blockSpacing: CGFloat { isShortScreen ? 16 : 22 }

    /// 路线名最多两行；两行时会多吃约 28pt，示意卡要再让出同样的高度，
    /// 否则 SE 上第三个打卡点又会被底栏压住。
    private var titleNeedsTwoLines: Bool {
        let width = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .screen.bounds.width ?? 390
        let font = UIFont.systemFont(ofSize: 22, weight: .bold)
        let rect = (route.name as NSString).boundingRect(
            with: CGSize(width: max(width - 40, 200), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return rect.height > font.lineHeight * 1.5
    }

    /// 短屏上「路线示意」只是虚线，占满 200pt 会把第三个打卡点推出首屏；
    /// SE 收到 144（标题两行时 116），仍能看清起终点方向。
    private var sketchCardHeight: CGFloat {
        guard isShortScreen else { return 200 }
        return titleNeedsTwoLines ? 116 : 144
    }

    private func routeSketchCard(width: CGFloat) -> some View {
        let height: CGFloat = sketchCardHeight
        return ZStack(alignment: .bottomLeading) {
            Theme.lightField
            TrackPreview(
                unitPoints: sketchPoints,
                trackRect: CGRect(x: 28, y: 26, width: max(width - 56, 60), height: height - 74),
                startDot: CGPoint(x: 34, y: height - 58),
                endDot: CGPoint(x: width - 40, y: 40),
                dotSize: 8,
                // 0.45 在 #F2F2F4 上只有约 1.6:1，虚线几乎看不见；0.58 仍弱于真实轨迹，
                // 但能一眼读出路线走向（「示意」语义靠虚线本身表达，不靠变淡）。
                trackColor: Theme.textSecondary.opacity(0.58),
                // 与赛道图同一套方向语言：起点绿点、终点方块。
                // 红色只留给危险与错误，不能拿来做起点装饰。
                startColor: Theme.success,
                endColor: Theme.textPrimary,
                dashed: true,
                endSquare: true
            )
            Text("路线示意")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 14)
                .padding(.bottom, 12)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 数据卡

    private var elevationText: String {
        guard let gain = summary.record?.elevationGainM, gain > 0 else { return "—" }
        return "\(gain)"
    }

    private var elevationUnit: String? {
        guard let gain = summary.record?.elevationGainM, gain > 0 else { return nil }
        // 指标行统一用 km / m，和其他页面保持一致；
        // 屏幕上的「公里」只出现在读屏文案里。
        return "m"
    }

    private var hasDistance: Bool {
        (summary.record?.distanceM ?? 0) > 0
    }

    private var statsCard: some View {
        // 没有轨迹时里程/均速/爬升都是未知：四列里三列显示「—」既占位置又像加载失败，
        // 此时只保留确实有值的时长，其余交给下方那句「本次骑行未记录轨迹」说明。
        guard hasDistance else { return AnyView(durationDetailRow) }
        let metrics: [(label: String, value: String, unit: String?)] = [
            ("里程", String(format: "%.1f", Double(summary.record?.distanceM ?? 0) / 1000), "km"),
            ("时长", RideDurationText.elapsed(seconds: summary.record?.durationS ?? 0), nil),
            ("均速",
             (summary.record?.avgSpeedKmh).flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil } ?? "—",
             (summary.record?.avgSpeedKmh ?? 0) > 0 ? "km/h" : nil),
            ("爬升", elevationText, elevationUnit)
        ]

        return AnyView(MetricRowLayout {
            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                if index > 0 { statDivider }
                statColumn(metric.label, value: metric.value, unit: metric.unit)
            }
        }
        .frame(height: 72)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        // 四列按布局顺序会念成「里程、时长、均速、爬升、42.1、km、2:08:00…」
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statsAccessibilityLabel))
    }

    /// 只剩时长一项时不要独占 72pt 指标行：数字被放大成标题，
    /// 下方打卡明细却是「名称左、状态右」，两种读法在同一屏打架。
    private var durationDetailRow: some View {
        let seconds = summary.record?.durationS ?? 0
        return HStack {
            Text("时长")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            Text(RideDurationText.elapsed(seconds: seconds))
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(height: 56)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("时长 \(RideDurationText.spoken(seconds: seconds))")
    }

    /// 台面上时长用 h:mm:ss 保持数字节奏，VoiceOver 仍读中文时长
    private var statsAccessibilityLabel: String {
        let seconds = summary.record?.durationS ?? 0
        guard hasDistance else { return "时长 \(RideDurationText.spoken(seconds: seconds))" }
        let distance = String(format: "%.1f", Double(summary.record?.distanceM ?? 0) / 1000)
        var parts = ["里程 \(distance) 公里", "时长 \(RideDurationText.spoken(seconds: seconds))"]
        if let speed = summary.record?.avgSpeedKmh, speed > 0 {
            parts.append("均速 \(String(format: "%.1f", speed)) 公里每小时")
        }
        let gain = summary.record?.elevationGainM ?? 0
        if gain > 0 { parts.append("爬升 \(gain) 米") }
        return parts.joined(separator: "，")
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: 1, height: 34)
            .padding(.horizontal, 12)
            .metricRowFixed()
    }

    private func statColumn(_ label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .motionPop(delay: 0.22)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 打卡完成

    private var checkpointsSection: some View {
        let done = summary.checkedCheckpointIds
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                // 记录没写成的时候，上方横幅刚说「打卡没有保存」，
                // 这里再写「打卡完成」会自相矛盾：标成「本次打卡（未保存）」。
                Text(summary.canRetrySave ? "打卡完成" : "本次打卡（未保存）")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                Text("\(checkpoints.filter { done.contains($0.id) }.count)/\(checkpoints.count)")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(summary.canRetrySave ? "打卡完成" : "本次打卡，未保存") \(checkpoints.filter { done.contains($0.id) }.count) 个，共 \(checkpoints.count) 个")

            if checkpoints.isEmpty {
                Text("本路线暂无打卡点")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(checkpoints.enumerated()), id: \.element.id) { index, cp in
                        if index > 0 {
                            Rectangle()
                                .fill(Theme.separator)
                                .frame(height: 1)
                                .padding(.leading, 34)
                        }
                        checkpointRow(cp, index: index)
                    }
                }
            }
        }
    }

    private func checkpointRow(_ cp: Checkpoint, index: Int) -> some View {
        let done = summary.checkedCheckpointIds.contains(cp.id)
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(done ? Theme.textPrimary : Theme.lightField)
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(done ? Color.white : Theme.textSecondary)
            }
            .frame(width: 22, height: 22)

            Text(cp.name.withoutEmoji)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(done ? "已打卡" : "未打卡")
                .font(.system(size: 12))
                // 记录未能创建时，绿色对勾会给出「已保存」的错觉，
                // 这里统一降为次要色：打卡事实仍保留，成功感交给上方横幅的失败语义。
                .foregroundStyle(done && summary.canRetrySave ? Theme.successText : Theme.textSecondary)
        }
        .padding(.horizontal, 0)
        .padding(.vertical, isShortScreen ? 10 : 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(index + 1) 个打卡点，\(cp.name.withoutEmoji)，\(done ? "已打卡" : "未打卡")")
    }

    // MARK: - 底部

    private var bottomBar: some View {
        VStack(spacing: 0) {
            // 无轨迹说明放在操作栏上方常驻，避免长内容时被底栏裁掉半行。
            if summary.track.count < 2 {
                noTrackNote
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }
            HStack(spacing: 10) {
                // 骑完想发出去是最自然的动作；隐私政策里也写了「保存骑行分享卡」。
                Button {
                    prepareShare()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 52, height: 52)
                        .background(Theme.lightField)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(CardPressStyle(scale: 0.94))
                .accessibilityLabel("分享本次骑行")
                Button {
                    if summary.awardedBadge != nil, !hasSeenBadge {
                        hasSeenBadge = true
                        showBadge = true
                    } else {
                        requestFinish()
                    }
                } label: {
                    Text(summary.awardedBadge != nil && !hasSeenBadge ? "查看徽章" : "完成")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(SolidPressStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .wellwayBottomBar()
    }

    /// 纯文字分享：无轨迹时只报路线与时长，不编造里程 / 均速
    private var shareText: String {
        var parts = ["我在 WellWay 完成了「\(route.name)」"]
        if hasDistance {
            parts.append("里程 \(String(format: "%.1f", Double(summary.record?.distanceM ?? 0) / 1000)) km")
        }
        let seconds = summary.record?.durationS ?? 0
        if seconds > 0 {
            parts.append("时长 \(RideDurationText.elapsed(seconds: seconds))")
        }
        if let avg = summary.record?.avgSpeedKmh, avg > 0 {
            parts.append("均速 \(String(format: "%.1f", avg)) km/h")
        }
        return parts.joined(separator: "，") + "。"
    }

    /// 分享卡与文字一起进系统面板：没有轨迹时卡片不画路线，指标也只用真实值。
    private func prepareShare() {
        var payload: [Any] = [shareText]
        if let image = RideShareCardRenderer.image(
            routeName: route.name,
            dateText: shareDateText,
            endpoints: shareEndpoints,
            metrics: shareCardMetrics,
            unitPoints: trackUnitPoints(coordinates: summary.track),
            hasTrack: summary.track.count >= 2
        ) {
            payload.append(image)
        }
        sharePayload = SharePayload(items: payload, fileName: "\(route.name)-骑行记录")
    }

    private var shareDateText: String {
        guard let startedAt = summary.record?.startedAt,
              let date = ISO8601DateFormatter.wellwayDate(from: startedAt) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private var shareEndpoints: String {
        let start = route.startName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let end = route.endName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !start.isEmpty, !end.isEmpty else { return "" }
        return "\(start) → \(end)"
    }

    private var shareCardMetrics: [(label: String, value: String)] {
        var metrics: [(label: String, value: String)] = []
        if hasDistance {
            metrics.append(("里程", String(format: "%.1f km", Double(summary.record?.distanceM ?? 0) / 1000)))
        }
        let seconds = summary.record?.durationS ?? 0
        if seconds > 0 {
            metrics.append(("时长", RideDurationText.elapsed(seconds: seconds)))
        }
        if let avg = summary.record?.avgSpeedKmh, avg > 0 {
            metrics.append(("均速", String(format: "%.1f km/h", avg)))
        }
        if let gain = summary.record?.elevationGainM, gain > 0 {
            metrics.append(("爬升", "\(gain) m"))
        }
        // 没有轨迹的骑行只剩「时长」一项，卡面下半张是空的，看起来像没做完。
        // 打卡是这类骑行唯一真实存在的成绩，补成第二栏；没打卡就还是只留时长。
        if !hasDistance {
            let done = checkpoints.filter { summary.checkedCheckpointIds.contains($0.id) }.count
            if done > 0, !checkpoints.isEmpty {
                metrics.append(("打卡", "\(done)/\(checkpoints.count)"))
            }
        }
        return Array(metrics.prefix(4))
    }

    private func requestFinish() {
        if !saveFixed, summary.saveWarning != nil {
            showLeaveConfirm = true
        } else {
            onFinish()
        }
    }

    /// 打卡点经纬度归一化为 0~1 单位点(纬度翻转，保证 y 向下)
    private func trackUnitPoints(_ checkpoints: [Checkpoint]) -> [CGPoint] {
        let coords = checkpoints.compactMap { cp -> (lat: Double, lng: Double)? in
            guard let lat = cp.lat, let lng = cp.lng else { return nil }
            return (lat, lng)
        }
        return trackUnitPoints(coordinates: coords.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) })
    }

    private func trackUnitPoints(coordinates: [CLLocationCoordinate2D]) -> [CGPoint] {
        let coords = coordinates.map { (lat: $0.latitude, lng: $0.longitude) }
        guard coords.count >= 2 else { return [] }
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
}

/// 打卡完成-徽章：自适应布局，与徽章详情页共用同一套信息层级
struct BadgeEarnedView: View {
    let badge: Badge
    let checkpoints: [Checkpoint]
    let checkedIds: Set<Int>
    var rideDistanceM: Int? = nil
    var rideDurationS: Int? = nil
    var rideAvgSpeedKmh: Double? = nil
    var onClose: (() -> Void)? = nil

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            // 与其它二级页共用同一套页头：返回 44pt + 左对齐 18pt 标题。
            // 这页虽然是从骑行总结里覆盖上来的，标题居中会让它在整组页面里变成孤例。
            DesignPageHeader(title: "打卡完成", onBack: onClose)

            // 打卡完成是仪式感页面：内容少时整块垂直居中，
            // 不要贴着顶部、把下半屏空成一片白。
            GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .stroke(Theme.textPrimary.opacity(appeared ? 0 : 0.18), lineWidth: 1)
                            .frame(width: 126, height: 126)
                            .scaleEffect(appeared ? 1.55 : 1)
                            .opacity(appeared ? 0 : 1)

                        Circle()
                            .fill(Theme.darkCard)
                        BadgeIcon(badge: badge, size: 126)
                    }
                    .frame(width: 126, height: 126)
                    .scaleEffect(appeared ? 1 : 0.86)
                    .opacity(appeared ? 1 : 0)
                    .onAppear {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { appeared = true }
                    }

                    Text(badge.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 22)
                        .padding(.horizontal, 24)

                    Text(checkpoints.isEmpty || checkedIds.count >= checkpoints.count
                         ? "本路线全部打卡点已点亮"
                         : "已点亮 \(checkpoints.filter { checkedIds.contains($0.id) }.map { $0.name.withoutEmoji }.joined(separator: " · "))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.top, 8)
                        .padding(.horizontal, 32)

                    progressCard
                        .padding(.horizontal, 20)
                        .padding(.top, 28)

                    Text("徽章已点亮，可在「我的」中查看")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                    Color.clear.frame(height: 24)
                }
                .frame(minHeight: proxy.size.height, alignment: .center)
            }
            }
            .frame(maxWidth: .infinity)

            Divider()
                .overlay(Theme.separator)

            Button {
                onClose?()
            } label: {
                Text("收下徽章")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(SolidPressStyle())
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .background(Color.white.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .pageMark(4)
    }

    private var progressCard: some View {
        let total = checkpoints.count
        let done = checkedIds.count
        let allDone = total > 0 && done >= total
        return VStack(alignment: .leading, spacing: 14) {
            if hasRideStats {
                rideStatsRow
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 1)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("本路线打卡点")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Text("\(done)/\(total)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(allDone ? Theme.textPrimary : Theme.textSecondary)
            }

            if allDone {
                FlowLayout(spacing: 10, lineSpacing: 8) {
                    ForEach(checkpoints) { cp in
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.success)
                            Text(cp.name.withoutEmoji)
                                .font(.system(size: 12))
                                .fixedSize()
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            } else {
                GeometryReader { geo in
                    Capsule()
                        .fill(Theme.separator)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Theme.textPrimary)
                                .frame(width: max(geo.size.width * CGFloat(done) / CGFloat(max(total, 1)), done > 0 ? 6 : 0))
                        }
                }
                .frame(height: 6)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.lightField)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var hasRideStats: Bool {
        (rideDistanceM ?? 0) > 0 || (rideDurationS ?? 0) > 0 || (rideAvgSpeedKmh ?? 0) > 0
    }

    private var rideStatsRow: some View {
        let distance = rideDistanceM ?? 0
        let duration = rideDurationS ?? 0
        let speed = rideAvgSpeedKmh ?? 0
        return HStack(spacing: 0) {
            rideStat("里程", value: distance > 0 ? String(format: "%.1f", Double(distance) / 1000) : "—", unit: distance > 0 ? "km" : nil)
            Rectangle().fill(Theme.separator).frame(width: 1, height: 30)
            rideStat("时长", value: duration > 0 ? RideDurationText.elapsed(seconds: duration) : "—", unit: nil)
            Rectangle().fill(Theme.separator).frame(width: 1, height: 30)
            rideStat("均速", value: speed > 0 ? String(format: "%.1f", speed) : "—", unit: speed > 0 ? "km/h" : nil)
        }
    }

    private func rideStat(_ label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let unit {
                    Text(unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}


/// 简单流式布局：打卡点全部完成时按可用宽度换行，避免长名称被截断
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? max(0, x - spacing), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
