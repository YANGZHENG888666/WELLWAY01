import SwiftUI
import CoreLocation
import UserNotifications
import UIKit

/// 设置页(Figma「设置页」115:1239,按节点数据 1:1 还原)
/// 权限卡 + 绑定邮箱/隐私说明 + 通知开关 + 关于与反馈
struct SettingsView: View {
    @Environment(AuthManager.self) private var auth

    @AppStorage("notifySameway") private var notifySameway = true
    @AppStorage("notifyCheckin") private var notifyCheckin = true
    @AppStorage("notifyRide") private var notifyRide = true
    @State private var notificationOK = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var locationStatus: CLAuthorizationStatus = CLLocationManager().authorizationStatus
    @State private var showNotifyBlocked = ProcessInfo.processInfo.arguments.contains("-settingsnotifydialog")

    var body: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: "设置")
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sectionTitle("后台运行与权限", top: 16)
                    groupBox {
                        permissionRow("定位权限", text: locationStatusText, color: locationStatusColor, detail: locationStatusDetail) { openSettings() }
                        divider
                        permissionRow(
                            "通知权限",
                            text: notificationOK ? "已开启" : "未开启",
                            color: notificationOK ? Theme.textSecondary : Theme.danger,
                            detail: notificationStatusDetail
                        ) { handleNotificationPermission() }
                    }
                    .padding(.top, 8)
                    .motionAppear(delay: 0.06)

                    sectionTitle("账号与安全", top: 28)
                    groupBox {
                        NavigationLink { EmailBindView() } label: {
                            row(
                                auth.profile?.emailBound == true ? "更换绑定邮箱" : "绑定邮箱",
                                value: auth.profile?.emailBound == true ? "已绑定" : "未绑定",
                                showsChevron: true
                            )
                        }
                        .buttonStyle(RowPressStyle())
                        divider
                        NavigationLink { AgreementView(kind: .privacyIntro) } label: {
                            // 右侧已有 chevron 表示可进入，再写一个「查看」是两套导航暗示
                            row("隐私说明", value: nil, showsChevron: true)
                        }
                        .buttonStyle(RowPressStyle())
                    }
                    .padding(.top, 8)
                    .motionAppear(delay: 0.14)

                    sectionTitle("通知提醒", top: 28)

                    groupBox {
                        switchRow("对向提醒", isOn: notifyBinding($notifySameway))
                        divider
                        switchRow("打卡完成", isOn: notifyBinding($notifyCheckin))
                        divider
                        switchRow("骑行完成", isOn: notifyBinding($notifyRide))
                    }
                    .padding(.top, 8)
                    .motionAppear(delay: 0.22)

                    // 权限说明放在开关下方：开关是用户能设置的，说明只解释为什么不会送达。
                    // 放在上面会把 SE 首屏最后一行开关顶到折线处，看起来像被切掉。
                    if !notificationOK {
                        HStack(spacing: 8) {
                            Text("通知权限未开启，上述提醒不会送达")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer(minLength: 8)
                            // 12pt 文字的默认命中区只有一行高，这又是页面上唯一的补救入口；
                            // 撑到 44pt 高，保留 12pt 的视觉字号。
                            Button {
                                handleNotificationPermission()
                            } label: {
                                Text("去开启")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                            .accessibilityLabel("去开启通知权限")
                        }
                        .padding(.horizontal, 20)
                        // 不再把整行合并成一个读屏元素：合并后「去开启」不再是一个可点按的按钮。
                        .padding(.top, 8)
                    }

                    sectionTitle("其他", top: 28)

                    groupBox {
                        NavigationLink { AboutFeedbackView() } label: {
                            row("关于与反馈", value: AppBuildInfo.version, showsChevron: true)
                        }
                        .buttonStyle(RowPressStyle())
                    }
                    .padding(.top, 6)
                    .motionAppear(delay: 0.30)
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .hidesAppTabBar()
        .onAppear { refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
        .wellwayDialog(
            isPresented: $showNotifyBlocked,
            title: "通知权限未开启",
            message: "系统通知被关闭时，对向、打卡和骑行完成提醒都无法送达。去系统设置里允许通知后即可生效。",
            buttons: [
                WellwayDialogButton(title: "开启通知", role: .primary) { handleNotificationPermission() }
            ]
        )
        .pageMark(11)
    }

    private func sectionTitle(_ title: String, top: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.leading, 20)
            .padding(.top, top)
            .padding(.bottom, 2)
    }

    private func groupBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
            .padding(.leading, 20)
    }

    private func permissionRow(_ title: String, text: String, color: Color, detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textPrimary)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(color)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.chevron)
            }
            .padding(.horizontal, 20)
            .frame(height: detail == nil ? 56 : 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    private var locationStatusDetail: String? {
        switch locationStatus {
        case .authorizedAlways: return nil
        case .authorizedWhenInUse: return "锁屏后可能中断轨迹记录"
        case .denied, .restricted: return "需要定位权限才能记录骑行"
        case .notDetermined: return "开始骑行时会请求授权"
        @unknown default: return nil
        }
    }

    /// 定位权限用系统真实授权级别表述，避免“正常/去设置”二值化误导
    private var locationStatusText: String {
        switch locationStatus {
        case .authorizedAlways: return "始终允许"
        case .authorizedWhenInUse: return "仅使用期间"
        case .denied, .restricted: return "未允许"
        case .notDetermined: return "未设置"
        @unknown default: return "未设置"
        }
    }

    private var locationStatusColor: Color {
        // 权限值属于说明性信息：正常时保持中性灰，被拒绝才用警示色。
        switch locationStatus {
        case .denied, .restricted: return Theme.danger
        default: return Theme.textSecondary
        }
    }

    private func row(_ title: String, value: String? = nil, valueColor: Color = Theme.textSecondary, showsChevron: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(valueColor)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.chevron)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .contentShape(Rectangle())
    }

    /// 通知开关：系统权限没开时，不允许假装打开（否则用户以为提醒生效了）
    private func notifyBinding(_ stored: Binding<Bool>) -> Binding<Bool> {
        Binding(
            // 系统未授权时，分类开关必须显示为关闭，避免“看起来已开启但收不到提醒”。
            get: { notificationOK && stored.wrappedValue },
            set: { newValue in
                if newValue && !notificationOK {
                    showNotifyBlocked = true
                } else {
                    stored.wrappedValue = newValue
                }
            }
        )
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            // iOS 26 的 SwiftUI Toggle 会在辅助功能树里同时暴露带标签的包装节点
            // 和内部无标签 UISwitch，读屏要停两次。直接用系统 UISwitch：
            // 标签挂在控件自身，树里只有一个开关元素。
            SettingSwitch(
                title: title,
                hint: notificationOK ? "允许或关闭\(title)通知" : "系统通知未开启，请先开启通知权限",
                isOn: isOn
            )
        }
        .opacity(notificationOK ? 1 : 0.45)
        .padding(.horizontal, 20)
        .frame(height: 56)
    }

    private var notificationStatusDetail: String? {
        if notificationOK { return nil }
        switch notificationStatus {
        // 未决定时不再重复「开始骑行时会请求授权」：下方通知提醒区已经给出更具体的说明，
        // 这里只保留右侧状态，避免同一屏里出现两遍权限说明。
        case .notDetermined: return nil
        // 拒绝时下方通知提醒区已有「通知权限未开启，上述提醒不会送达」+「去开启」，
        // 这里再写「提醒无法送达」等于同一屏说三遍。
        case .denied: return nil
        default: return nil
        }
    }

    private func refreshPermissions() {
        if ProcessInfo.processInfo.arguments.contains("-settingsnotifyoff")
            || ProcessInfo.processInfo.arguments.contains("-settingsnotifydialog") {
            locationStatus = .authorizedWhenInUse
            notificationStatus = .denied
            notificationOK = false
            return
        }
        // 定位权限可能刚在系统设置里被改动：读取到 @State 才会触发重绘，
        // 不能只在 body 里直接读 CLLocationManager.authorizationStatus。
        locationStatus = CLLocationManager().authorizationStatus
        Task {
            await refreshNotificationStatus()
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            notificationStatus = settings.authorizationStatus
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                notificationOK = true
            default:
                notificationOK = false
            }
        }
    }

    /// 未决定时直接请求系统授权；已拒绝时再引导到系统设置。
    private func handleNotificationPermission() {
        if notificationStatus == .notDetermined {
            Task {
                _ = try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                await refreshNotificationStatus()
                if !notificationOK {
                    showNotifyBlocked = true
                }
            }
        } else {
            openSettings()
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// 设置页通知开关。SwiftUI Toggle 在 iOS 26 会多暴露一个无标签开关节点，
/// 这里用系统 UISwitch 承接同一套外观与开关语义。
private struct SettingSwitch: UIViewRepresentable {
    let title: String
    let hint: String
    @Binding var isOn: Bool

    func makeCoordinator() -> Coordinator { Coordinator(isOn: $isOn) }

    func makeUIView(context: Context) -> UISwitch {
        let control = UISwitch()
        control.onTintColor = .black
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        return control
    }

    func updateUIView(_ control: UISwitch, context: Context) {
        control.setOn(isOn, animated: false)
        control.accessibilityLabel = title
        control.accessibilityHint = hint
    }

    final class Coordinator: NSObject {
        private var isOn: Binding<Bool>

        init(isOn: Binding<Bool>) {
            self.isOn = isOn
        }

        @objc func valueChanged(_ sender: UISwitch) {
            isOn.wrappedValue = sender.isOn
            // 系统通知未授权时，绑定的 getter 会拒绝打开；UISwitch 自己已经
            // 先翻过去了，这里同步回真实值，避免界面假装已开启。
            if sender.isOn != isOn.wrappedValue {
                sender.setOn(isOn.wrappedValue, animated: true)
            }
        }
    }
}

private struct FeedbackInput: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    @State private var didAutoFocus = false

    var body: some View {
        TextField("请描述你遇到的问题或建议…", text: $text, axis: .vertical)
            .font(.system(size: 14))
            .lineLimit(5...8)
            .textFieldStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
            .accessibilityLabel("反馈内容")
            .focused($focused)
            .padding(.bottom, 12)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 132, alignment: .topLeading)
            .background(Theme.lightField)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Text("\(text.count)/500")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .padding(9)
            }
            .onAppear {
                guard !didAutoFocus else { return }
                didAutoFocus = true
                // 等 sheet 完成转场后再聚焦
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    focused = true
                }
            }
    }
}

/// 版本信息统一从 Info.plist 读取，避免发版后页面里还写死旧版本号。
private enum AppBuildInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}

/// 关于与反馈(Figma「关于与反馈」133:241)+ 提交反馈弹窗(Figma「提交反馈」261:283)
struct AboutFeedbackView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var showFeedback = ProcessInfo.processInfo.arguments.contains("-feedback")
        || ProcessInfo.processInfo.arguments.contains("-feedbackerror")
    @State private var feedback = ProcessInfo.processInfo.arguments.contains("-feedbackerror")
        ? "路线详情页的排版很清楚，希望路线筛选可以再快一点。"
        : ""
    @State private var submitted = false
    @State private var submitting = false
    @State private var feedbackError: String? = ProcessInfo.processInfo.arguments.contains("-feedbackerror")
        ? "提交失败，请检查网络后重试"
        : nil

    var body: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: "关于与反馈")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Theme.darkCard)
                            Image("BrandMarkLight")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 52, height: 52)
                        }
                        .frame(width: 80, height: 80)
                        .motionAppear(delay: 0.08)
                        .motionPop(delay: 0.10)
                        .accessibilityHidden(true)

                        Image("Wordmark")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 160, height: 49)
                            .accessibilityHidden(true)
                            .padding(.top, 20)
                            .motionAppear(delay: 0.18)

                        Text("版本 \(AppBuildInfo.version)")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.top, 6)
                            .motionAppear(delay: 0.24)

                        Text("好路当骑 同行当悉")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.top, 18)
                            .padding(.bottom, 6)
                            .motionAppear(delay: 0.30)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                    VStack(spacing: 0) {
                        Button {
                            showFeedback = true
                        } label: {
                            aboutLinkRow("意见反馈")
                        }
                        .buttonStyle(RowPressStyle())

                        Divider().padding(.leading, 20)

                        NavigationLink {
                            AgreementView(kind: .userAgreement)
                        } label: {
                            aboutLinkRow("用户服务协议")
                        }
                        .buttonStyle(RowPressStyle())

                        Divider().padding(.leading, 20)

                        NavigationLink {
                            AgreementView(kind: .privacyPolicy)
                        } label: {
                            aboutLinkRow("隐私政策")
                        }
                        .buttonStyle(RowPressStyle())
                    }
                    // 与设置页一致：整宽账本行 + 发丝线，不再套一层描边卡片
                    .padding(.top, 12)

                    VStack(spacing: 0) {
                        // 关于页落款：免责提示是产品硬性要求，放在页脚比塞进协议正文更容易被看到
                        // 左对齐跟上面的账本行同一条网格线；居中时末行只剩「为准。」两个字，非常碎。
                        Text("路线、限行与天气信息仅供参考，请以官方公告为准。")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 24)
                            .motionAppear(delay: 0.34)

                        Text("© 2026 WellWay")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)

                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .hidesAppTabBar()
        .wellwayDialog(
            isPresented: $submitted,
            title: "反馈已提交",
            message: "感谢你的建议，我们会认真阅读每一份反馈",
            buttons: [
                WellwayDialogButton(title: "好的", role: .primary) {
                    feedback = ""
                    showFeedback = false
                }
            ]
        )
        .sheet(isPresented: $showFeedback) {
            feedbackSheet
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
                .presentationBackground(Color.white)
        }
        .pageMark(16)
    }

    /// 底部反馈工作表：输入区随键盘上移，提交状态清晰，不再用居中弹窗遮挡键盘。
    private var feedbackSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("意见反馈")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("你的建议将帮助我们做得更好")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button {
                    showFeedback = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(IconPressStyle())
                .allowsHitTesting(!submitting)
                .opacity(submitting ? 0.4 : 1)
                .accessibilityLabel("关闭")
                .accessibilityHint(submitting ? "正在提交反馈，暂不可关闭" : "")
            }

            FeedbackInput(text: $feedback)
                .onChange(of: feedback) { _, value in
                    feedbackError = nil
                    if value.count > 500 { feedback = String(value.prefix(500)) }
                }
                .padding(.top, 18)

            Color.clear.frame(height: 18)

            if let feedbackError {
                Text(feedbackError)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
            }

            // 半屏工作表固定 340pt，内容不足时按钮会被顶在半空、下方留一大块空白；
            // 撑一段弹性间距让主按钮落在工作表底部，读起来才像有收口。
            Spacer(minLength: 12)

            let canSubmit = !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button {
                saveFeedback()
            } label: {
                Group {
                    if submitting {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text("正在提交…")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white)
                        }
                    } else {
                        Text("提交反馈")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(canSubmit ? Color.white : Theme.listGray)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(canSubmit ? Color.black : Theme.lightField)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(submitting ? 0.65 : 1)
            }
            .buttonStyle(SolidPressStyle())
            // 不用 .disabled：plain 样式会把整块按钮再压到 50% 透明度，
            // 浅灰底上的灰字几乎看不见。这里自行控制可点击区域。
            .allowsHitTesting(canSubmit && !submitting)
            .accessibilityHint(canSubmit ? "" : "请先输入反馈内容")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(Color.white)
        .interactiveDismissDisabled(submitting)
    }

    private func aboutLinkRow(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.chevron)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .contentShape(Rectangle())
    }

    private func saveFeedback() {
        let content = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !submitting else { return }
        submitting = true
        feedbackError = nil
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        Task { @MainActor in
            do {
                try await auth.client
                    .from("feedback")
                    .insert(FeedbackInsert(content: content, contact: nil, appVersion: version))
                    .execute()
            } catch {
                submitting = false
                feedbackError = "提交失败，请检查网络后重试"
                return
            }
            submitting = false
            showFeedback = false
            try? await Task.sleep(for: .milliseconds(260))
            submitted = true
        }
    }
}
