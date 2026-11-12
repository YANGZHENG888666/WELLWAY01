import SwiftUI

/// 冷启动发现未收尾的骑行快照时展示的恢复页。
/// 只处理已落盘的真实骑行，不复用演示 HUD；页面本身不创建新记录。
struct RideRecoveryView: View {
    let session: ActiveRideSession
    /// 继续记录：交给外层 dismiss 恢复页后再打开 RidingView
    var onContinue: () -> Void
    /// 关闭恢复页，回到正常 Tab
    var onClose: () -> Void

    @Environment(AuthManager.self) private var auth
    @State private var phase = RideRecoveryPhase.idle
    @State private var outcome: RideRecoveryOutcome?
    @State private var errorText: String?
    @State private var endedLocally = false

    private enum RideRecoveryPhase {
        case idle
        case saving
    }

    private var isEnded: Bool { endedLocally || session.phase == "ended" }
    private var isSaving: Bool { phase == .saving }

    private var title: String {
        isEnded ? "上次骑行尚未保存" : "上次骑行未结束"
    }

    var body: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: title, onBack: onClose)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.route.name)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)

                    metrics
                        .padding(.top, 22)

                    if let stale = session.staleText {
                        Text(stale)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 12)
                    }

                    Text(explanation)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 18)

                    if let outcome {
                        resultBlock(outcome)
                            .padding(.top, 22)
                    } else if let errorText {
                        errorBlock(errorText)
                            .padding(.top, 22)
                    }

                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(Color.white)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .preferredColorScheme(.light)
        .interactiveDismissDisabled(isSaving)
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            metricValue(session.distanceText, label: "已骑里程")
            Rectangle()
                .fill(Theme.separator)
                .frame(width: 1, height: 34)
                .padding(.horizontal, 20)
            metricValue(session.durationText, label: "累计时长")
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { hairline }
        .overlay(alignment: .bottom) { hairline }
    }

    private func metricValue(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityRepresentation {
            Text("\(label) \(spokenMeasurement(value))")
        }
    }

    private func spokenMeasurement(_ value: String) -> String {
        value
            .replacingOccurrences(of: " km", with: " 公里")
            .replacingOccurrences(of: " m", with: " 米")
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
    }

    private var explanation: String {
        if isEnded {
            return "这次骑行已经结束，但记录还没有确认保存到服务器。轨迹和打卡已留在手机上，补存后不会丢失。"
        }
        return "系统终止了 App，这次骑行仍然保留在手机上。继续记录会沿用同一条骑行记录，不会重复生成。"
    }

    private func resultBlock(_ outcome: RideRecoveryOutcome) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(outcome.warning == nil ? "骑行记录已保存" : "骑行记录已保存，轨迹未补全")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(outcome.warning == nil ? Theme.successText : Theme.textPrimary)
            if let warning = outcome.warning {
                Text(warning)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if outcome.alreadySaved {
                Text("云端此前已收到这条记录，本次只补传了本机剩余数据。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.lightField)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func errorBlock(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.danger)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.lightField)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            if outcome != nil {
                if outcome?.warning != nil {
                    Button {
                        Task { await save() }
                    } label: {
                        Text("重试补传")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(height: 44)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }

                primaryButton(isSaving ? "正在补存" : "完成") {
                    onClose()
                }
            } else {
                primaryButton(primaryTitle) {
                    if isEnded {
                        Task { await save() }
                    } else {
                        onContinue()
                    }
                }

                if !isEnded {
                    Button {
                        Task { await save() }
                    } label: {
                        Text(isSaving ? "正在保存" : "结束并保存")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isSaving ? Theme.listGray : Theme.textPrimary)
                            .frame(height: 44)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.white)
    }

    private var primaryTitle: String {
        if isSaving { return isEnded ? "正在补存" : "正在保存" }
        return isEnded ? "补存记录" : "继续记录"
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isSaving && outcome == nil {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Theme.primary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SolidPressStyle())
        .disabled(isSaving)
    }

    private func save() async {
        guard !isSaving else { return }
        phase = .saving
        errorText = nil
        // 用户点了「结束并保存」，先把终态落盘：即使网络不可达、补存超时，
        // 下次冷启动也会按“已结束待补存”恢复，而不是又回到骑行中。
        if !isEnded {
            endedLocally = true
            var ended = session
            ended.phase = "ended"
            ended.updatedAt = Date()
            ActiveRideSessionStore.save(ended)
        }

        let client = auth.client
        let result: (outcome: RideRecoveryOutcome?, message: String?)? =
            await AsyncDeadline.run(seconds: 8) { @MainActor in
            do {
                return (
                    try await RecoveredRideFinalizer.finish(session: session, client: client),
                    nil
                )
            } catch {
                return (nil, error.wellwayUserMessage)
            }
        }
        switch result {
        case let value?:
            if let saved = value.outcome {
                outcome = saved
                // 记录已确认完成且没有缺轨迹时才清快照；
                // 部分轨迹失败时保留，下次冷启动可以继续补传。
                if saved.warning == nil {
                    ActiveRideSessionStore.clear()
                } else {
                    var ended = session
                    ended.phase = "ended"
                    ended.updatedAt = Date()
                    ActiveRideSessionStore.save(ended)
                }
            } else {
                errorText = value.message ?? "保存失败，请稍后重试。"
            }
        case nil:
            errorText = "网络较慢，记录还没有同步完成。骑行快照已保留在本机，恢复网络后可重试补存。"
        }
        phase = .idle
    }
}

/// 调试入口：不依赖真实后台，直接展示恢复页的两种状态。
struct DebugRideRecoveryLoader: View {
    let ended: Bool

    private var session: ActiveRideSession {
        let route = Route(
            id: 1,
            name: "四明山盘山公路",
            startName: "梁弄镇",
            endName: "四明山国家森林公园",
            distanceM: 62_400,
            elevationM: 1_180,
            difficulty: "进阶",
            durationMin: 95,
            mapUrl: nil,
            coverImageUrl: nil,
            province: "浙江",
            city: "宁波"
        )
        let checkpoints = [
            Checkpoint(id: 1, routeId: 1, name: "梁弄镇起点", seq: 1, lat: 29.87, lng: 121.10, radiusM: 120),
            Checkpoint(id: 2, routeId: 1, name: "四明山垭口", seq: 2, lat: 29.78, lng: 121.04, radiusM: 100)
        ]
        let start = Date().addingTimeInterval(-2_700)
        let samples = (0..<8).map { index in
            RideTrackSample(
                lat: 29.87 - Double(index) * 0.01,
                lng: 121.10 - Double(index) * 0.007,
                recordedAt: start.addingTimeInterval(Double(index) * 60),
                speedKmh: 42,
                bearing: 210
            )
        }
        return ActiveRideSession(
            userId: UUID(),
            rideId: UUID(),
            route: route,
            checkpoints: checkpoints,
            vehicleId: nil,
            vehicleName: "春风动力 800NK",
            startedAt: start,
            updatedAt: start.addingTimeInterval(2_400),
            phase: ended ? "ended" : "riding",
            durationS: 2_400,
            distanceM: 28_600,
            track: samples,
            pendingPoints: [],
            checkedCheckpointIds: [1]
        )
    }

    var body: some View {
        RideRecoveryView(session: session, onContinue: {}, onClose: {})
    }
}

/// 冷启动恢复只有一个全屏 cover：内部先展示恢复页，用户点「继续记录」后
/// 直接换成骑行 HUD。不要在外层再叠第二个 fullScreenCover，否则第二次
/// presentation 会拿到空状态，只显示一块白屏。
struct RideRecoveryFlow: View {
    let session: ActiveRideSession
    let onClose: () -> Void

    @State private var isResuming = false

    var body: some View {
        Group {
            if isResuming {
                RidingView(
                    route: session.route,
                    checkpoints: session.checkpoints,
                    vehicleId: session.vehicleId,
                    vehicleName: session.vehicleName,
                    resumeSession: session
                )
                .transition(.opacity)
            } else {
                RideRecoveryView(
                    session: session,
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isResuming = true
                        }
                    },
                    onClose: onClose
                )
                .transition(.opacity)
            }
        }
    }
}
