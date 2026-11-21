import SwiftUI
import PhotosUI

/// 个人中心(Figma「个人中心」112:1067,按节点数据 1:1 还原)
/// 头像 + 昵称/账号 + 绑定邮箱卡 + 菜单(我的车辆/我的徽章/我的骑行记录/设置)
/// 设计稿未含「通知/退出」,为保证功能完整，以同风格菜单行附加在下方
struct ProfileView: View {
    @Environment(AuthManager.self) private var auth
    @State private var showEmailBind = false
    @State private var nicknameDraft = ""
    @State private var showNicknameEditor = false
    @State private var showNicknameError = false
    @State private var nicknameErrorMessage: String?
    @State private var showDeleteConfirm = false
    @State private var showDeleteFinal = false
    @State private var showDeleteFailed = false
    @State private var isDeletingAccount = false
    @State private var showSignOutConfirm = false
    @State private var avatarImage: UIImage?
    @State private var avatarItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var showAvatarError = false
    /// 账号级骑行合计；加载失败时整条隐藏，不显示一排破折号
    @State private var rideTotals: RideTotals?

    private struct RideTotals: Equatable {
        var totalKm: Double
        var rideCount: Int
        var totalSeconds: Int
    }

    private var nickname: String { auth.profile?.nickname ?? "骑友" }
    private var isBound: Bool { auth.profile?.emailBound == true }

    /// SE 等 667pt 高的小屏：保持 56pt 行高会让「应用」标题单独露在 Tab 上方。
    /// 仅在小屏收紧到 48pt 行高（仍大于 44pt 命中区）和 12pt 分组间距。
    private var isShortScreen: Bool {
        let height = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .screen.bounds.height ?? 800
        return height < 700
    }

    private var profileRowHeight: CGFloat { isShortScreen ? 48 : 56 }
    private var profileSectionTop: CGFloat { isShortScreen ? 12 : 20 }

    var body: some View {
            VStack(spacing: 0) {
            DesignPageHeader(title: "我的", showsBack: false, compact: true)
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("profile-top")
                    // 身份区：头像 + 昵称/账号 + 编辑。头像下角一个相机标记即可，不写提示小字。
                    HStack(spacing: 16) {
                        PhotosPicker(selection: $avatarItem, matching: .images) {
                            ZStack(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(Theme.cardStroke)
                                    .frame(width: 76, height: 76)
                                    .overlay {
                                        if let avatarImage {
                                            Image(uiImage: avatarImage)
                                                .resizable()
                                                .scaledToFill()
                                        } else {
                                            Text(String(nickname.prefix(1)))
                                                .font(.system(size: 30, weight: .bold))
                                                .foregroundColor(Theme.ink)
                                        }
                                    }
                                    .clipShape(Circle())
                                if isUploadingAvatar {
                                    ProgressView()
                                        .tint(.white)
                                        .frame(width: 24, height: 24)
                                        .background(Color.black)
                                        .clipShape(Circle())
                                        .offset(x: 2, y: 2)
                                } else {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 22, height: 22)
                                        .background(Color.black)
                                        .clipShape(Circle())
                                        // 灰色头像上用一圈白色描边托住黑色相机标，边界更干净
                                        .padding(2)
                                        .background(Color.white)
                                        .clipShape(Circle())
                                        .offset(x: 1, y: 1)
                                }
                            }
                        }
                        .buttonStyle(SolidPressStyle())
                        .accessibilityLabel("更换头像")
                        .accessibilityHint("从相册选择一张新头像")

                        Button {
                            nicknameDraft = nickname
                            nicknameErrorMessage = nil
                            showNicknameEditor = true
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(nickname)
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundColor(Theme.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Text(isBound ? "邮箱已绑定" : "匿名账号")
                                        .font(.system(size: 13))
                                        .foregroundColor(Theme.textSecondary)
                                }
                                Spacer(minLength: 8)
                                HStack(spacing: 2) {
                                    Text("编辑")
                                        .font(.system(size: 13, weight: .medium))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .foregroundColor(Theme.textSecondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityLabel("编辑昵称")
                        .accessibilityValue(nickname)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, isShortScreen ? 8 : 12)
                    .padding(.bottom, isShortScreen ? 8 : 12)
                    .motionAppear(delay: 0.05)

                    if rideTotals != nil {
                        rideTotalsStrip
                            .padding(.horizontal, 20)
                            .padding(.top, 2)
                            .motionAppear(delay: 0.08)
                    }

                    sectionTitle("账号")
                    ledgerGroup {
                        Button {
                            showEmailBind = true
                        } label: {
                            HStack(spacing: 12) {
                                Text("邮箱")
                                    .font(.system(size: 16))
                                    .foregroundColor(Theme.ink)
                                Spacer(minLength: 8)
                                Text(isBound ? "已绑定" : "未绑定")
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.textSecondary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Theme.chevron)
                            }
                            .padding(.horizontal, 20)
                            .frame(height: profileRowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                    }
                    .motionAppear(delay: 0.12)

                    sectionTitle("路线")
                    ledgerGroup {
                        menuRow("我的收藏") { FavoriteRoutesView() }
                    }
                    .motionAppear(delay: 0.16)

                    sectionTitle("骑行")
                    ledgerGroup {
                        menuRow("车辆") { MyVehiclesView() }
                        ledgerDivider
                        menuRow("徽章") { BadgesView() }
                        ledgerDivider
                        menuRow("骑行记录") { RecordsView() }
                    }
                    .motionAppear(delay: 0.20)

                    sectionTitle("应用")
                    ledgerGroup {
                        menuRow("设置") { SettingsView() }
                        ledgerDivider
                        menuRow("通知") { NotificationsView() }
                    }
                    .motionAppear(delay: 0.26)

                    // 账号操作和上面的列表同构：同为 20pt 起始的扁平文字行，
                    // 注销只是换成语义红，不再居中缩成另一套样式。
                    ledgerGroup {
                        Button {
                            showSignOutConfirm = true
                        } label: {
                            Text("退出登录")
                                .font(.system(size: 16))
                                .foregroundColor(Theme.ink)
                                .padding(.horizontal, 20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: profileRowHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())

                        ledgerDivider

                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Text("注销账号")
                                .font(.system(size: 16))
                                .foregroundColor(Theme.danger)
                                .padding(.horizontal, 20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: profileRowHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                    }
                    // 单独一组、没有小标题：补一条上分隔线，否则会被读成新的版块标题
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: 1)
                            .padding(.leading, 20)
                    }
                    .padding(.top, 24)
                    .motionAppear(delay: 0.30)
                    // 调试：-profilebottom 滚到页尾，检查最后一行是否被悬浮 Tab 胶囊压住
                    if ProcessInfo.processInfo.arguments.contains("-profilebottom") {
                        Color.clear.frame(height: 1).id("profile-bottom")
                    }
                }
                // 悬浮 Tab 胶囊会盖住内容：按全 App 统一的 108pt 预留，滚到底时最后一行仍能完整露出
                .padding(.bottom, 108)
            }
            .refreshable {
                await refreshProfile()
                await loadRideTotals()
            }
            // Tab 切回来时重新取一次，避免刚结束骑行后摘要还是上一次的数字。
            .onAppear { Task { await loadRideTotals() } }
            .onAppear {
                // 从子页返回时 ScrollView 会停在错误的偏移上（头像被页头裁掉），
                // 回到这一页时把位置拉回顶部，保证头像与昵称完整可见。
                guard !ProcessInfo.processInfo.arguments.contains("-profilebottom") else { return }
                DispatchQueue.main.async { proxy.scrollTo("profile-top", anchor: .top) }
            }
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-profilebottom") else { return }
                try? await Task.sleep(nanoseconds: 600_000_000)
                proxy.scrollTo("profile-bottom", anchor: .bottom)
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                proxy.scrollTo("profile-bottom", anchor: .bottom)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                proxy.scrollTo("profile-bottom", anchor: .bottom)
            }
            }
            }
            .background(Color.white)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showEmailBind) {
                EmailBindView()
            }
            .wellwayPrompt(
                isPresented: $showNicknameEditor,
                title: "修改昵称",
                placeholder: "昵称",
                text: $nicknameDraft
            ) {
                let name = nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    nicknameErrorMessage = "昵称不能为空，请输入昵称"
                    showNicknameError = true
                    return
                }
                guard name.count <= 20 else {
                    nicknameErrorMessage = "昵称最多 20 个字符"
                    showNicknameError = true
                    return
                }
                nicknameErrorMessage = nil
                Task {
                    let ok = await auth.updateNickname(name)
                    if !ok {
                        nicknameErrorMessage = nil
                        showNicknameError = true
                    }
                }
            }
            .wellwayDialog(
                isPresented: $showSignOutConfirm,
                title: "退出登录？",
                message: isBound
                    ? "退出后可用邮箱验证码重新登录，车辆与骑行记录不会丢失。"
                    : "当前账号尚未绑定邮箱，退出后将无法恢复车辆、骑行记录与徽章。建议先绑定邮箱。",
                buttons: [
                    WellwayDialogButton(
                        title: "退出登录",
                        role: isBound ? .primary : .destructive
                    ) {
                        Task { await auth.signOut() }
                    }
                ]
            )
            .wellwayDialog(
                isPresented: $showDeleteConfirm,
                title: "注销账号",
                message: "注销后，账号及骑行记录、徽章、车辆、收藏等全部数据将被永久删除，且无法恢复。确定继续吗？",
                buttons: [
                    WellwayDialogButton(title: "继续注销", role: .destructive) {
                        showDeleteFinal = true
                    }
                ]
            )
            .wellwayDialog(
                isPresented: $showDeleteFinal,
                title: "确认永久删除？",
                message: "删除后账号、车辆、骑行轨迹与徽章均无法恢复。",
                buttons: [
                    WellwayDialogButton(title: "永久删除", role: .destructive) {
                        guard !isDeletingAccount else { return }
                        isDeletingAccount = true
                        Task {
                            await auth.deleteAccount()
                            isDeletingAccount = false
                            if auth.state == .signedIn {
                                showDeleteFailed = true
                            }
                        }
                    }
                ]
            )
            .wellwayDialog(
                isPresented: $showDeleteFailed,
                title: "注销失败",
                message: auth.errorMessage ?? "请稍后重试",
                buttons: []
            )
            .task {
                await refreshProfile()
            }
            .onChange(of: avatarItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    isUploadingAvatar = true
                    defer {
                        isUploadingAvatar = false
                        avatarItem = nil
                    }
                    guard let raw = try? await newItem.loadTransferable(type: Data.self),
                          let jpeg = Self.normalizedAvatarData(raw) else {
                        showAvatarError = true
                        return
                    }
                    let ok = await auth.updateAvatar(imageData: jpeg)
                    if ok {
                        // 上传数据就在内存里，先立即回显，避免再下载一次造成“看起来失败”
                        if let local = UIImage(data: jpeg) {
                            avatarImage = local
                        } else {
                            avatarImage = await auth.loadAvatarImage()
                        }
                    } else {
                        showAvatarError = true
                    }
                }
            }
            .wellwayDialog(
                isPresented: $showAvatarError,
                title: "头像更新失败",
                message: auth.errorMessage ?? "图片读取失败，请换一张试试",
                buttons: []
            )
            .wellwayDialog(
                isPresented: $showNicknameError,
                title: "昵称更新失败",
                message: nicknameErrorMessage ?? auth.errorMessage ?? "请稍后重试",
                buttons: []
            )
            .pageMark(8)
        .overlay {
            if isDeletingAccount {
                deletingAccountOverlay
            }
        }
    }

    /// 永久注销包含 Storage 清理与账号级联删除，耗时不可控；明确告知正在进行。
    private var deletingAccountOverlay: some View {
        ZStack {
            Color.black.opacity(0.16).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(Theme.textPrimary)
                Text("正在注销账号…")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("正在删除车辆、轨迹与徽章数据，请稍候")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 22, y: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在注销账号，请稍候")
    }

    /// 刷新昵称、绑定状态与头像；失败时保留当前本地展示，不清空用户资料
    private func refreshProfile() async {
        await auth.refreshProfile()
        if let img = await auth.loadAvatarImage() {
            avatarImage = img
        }
    }

    /// 头像统一压缩为 512×512 JPEG,避免原图过大导致上传失败
    private static func normalizedAvatarData(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side: CGFloat = 512
        let scale = max(side / image.size.width, side / image.size.height)
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let squared = renderer.image { _ in
            let origin = CGPoint(x: (side - target.width) / 2, y: (side - target.height) / 2)
            image.draw(in: CGRect(origin: origin, size: target))
        }
        return squared.jpegData(compressionQuality: 0.85)
    }

    /// 全宽账本行：16pt 标题 + 弱化箭头，不加卡片、不加前置图标
    private func menuRow<Destination: View>(
        _ title: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            rowLabel(title)
        }
        .buttonStyle(RowPressStyle())
    }

    private func ledgerGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
    }

    private func rowLabel(_ title: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(Theme.ink)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.chevron)
        }
        .padding(.horizontal, 20)
        .frame(height: profileRowHeight)
        .contentShape(Rectangle())
    }

    private var ledgerDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
            .padding(.leading, 20)
    }

    /// 分组标题：只承担层级，不与行标题抢字号
    // MARK: - 骑行合计

    private var rideTotalsStrip: some View {
        MetricRowLayout {
            totalsColumn(value: kmParts.value, unit: kmParts.unit, label: "总里程")
            totalsDivider
            totalsColumn(value: rideCountText, unit: "", label: "骑行次数")
            totalsDivider
            totalsColumn(value: durationParts.value, unit: durationParts.unit, label: "累计时长")
        }
        .frame(height: isShortScreen ? 62 : 68)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            // 屏幕上是「11 分」，读屏要念「11 分钟」：单念「分」会被听成「十一分」的分数
            kmParts.unit.isEmpty
                ? "总里程未记录，骑行 \(rideCountText) 次，累计时长 \(durationParts.value) \(durationSpokenUnit)"
                : "总里程 \(kmParts.value) \(kmParts.spokenUnit)，骑行 \(rideCountText) 次，累计时长 \(durationParts.value) \(durationSpokenUnit)"
        )
    }

    private var durationSpokenUnit: String { durationParts.unit }

    private func totalsColumn(value: String, unit: String, label: String) -> some View {
        // 「未记录」/「—」按缺失值渲染：21pt 的粗体破折号会被读成一根分隔线
        let missing = value == "未记录" || value == "—"
        return VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    // 缺失值和记录页保持同一套：16pt medium + 3pt 基线偏移，
                    // 落在数字位上但明显比数据轻，不会读成第二个数据。
                    .font(.system(size: missing ? 16 : 21, weight: missing ? .medium : .semibold).monospacedDigit())
                    .baselineOffset(missing ? 3 : 0)
                    .foregroundStyle(missing ? Theme.textSecondary : Theme.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var totalsDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: 1, height: 30)
            .metricRowFixed()
    }

    private var kmParts: (value: String, unit: String, spokenUnit: String) {
        guard let rideTotals else { return ("—", "", "") }
        let km = rideTotals.totalKm
        if km >= 1 {
            return (km >= 100 ? String(format: "%.0f", km) : String(format: "%.1f", km), "km", "公里")
        }
        // 不足 1 公里时用米，避免「骑了 6 次却显示 —」的观感
        let meters = Int((km * 1000).rounded())
        if meters > 0 {
            return ("\(meters)", "m", "米")
        }
        // 骑过但没有任何轨迹里程时是「未记录」，不能写成 0.0 km：
        // 和同一行的「骑行 6 次」并排会被读成数据算错了。
        if rideTotals.rideCount > 0 { return ("未记录", "", "公里") }
        // 一次都没骑时，右边两列已经是真实的 0 次 / 0 秒，
        // 里程继续留「—」会被读成数据没加载出来；统一成 0.0 km。
        return ("0.0", "km", "公里")
    }

    private var rideCountText: String {
        rideTotals.map { "\($0.rideCount)" } ?? "—"
    }

    private var durationParts: (value: String, unit: String) {
        guard let rideTotals else { return ("—", "") }
        // 与车库首页同一口径：一次都没骑时写「0 分钟」而不是「0 秒」，
        // 单位也跟着车库走「分钟」，两页展示同一份账号数据不能两种写法；
        // 十小时以上去掉小数，避免「100.0 小时」这种没有意义的精度。
        let seconds = max(0, rideTotals.totalSeconds)
        if seconds == 0 { return ("0", "分钟") }
        if seconds < 60 { return ("\(seconds)", "秒") }
        if seconds < 3_600 { return ("\(seconds / 60)", "分钟") }
        let hours = Double(seconds) / 3_600
        return (hours < 10 ? String(format: "%.1f", hours) : String(format: "%.0f", hours), "小时")
    }

    /// 只聚合已完成记录，和车库首页、记录页保持同一口径。
    @MainActor
    private func loadRideTotals() async {
        guard let uid = auth.user?.id else { return }
        struct Row: Decodable {
            let distanceM: Int
            let durationS: Int
            enum CodingKeys: String, CodingKey {
                case distanceM = "distance_m"
                case durationS = "duration_s"
            }
        }
        guard let rows: [Row] = try? await auth.client
            .from("ride_records")
            .select("distance_m, duration_s")
            .eq("user_id", value: uid)
            .eq("status", value: "completed")
            .execute()
            .value else { return }
        rideTotals = RideTotals(
            totalKm: rows.reduce(0.0) { $0 + Double($1.distanceM) / 1000 },
            rideCount: rows.count,
            totalSeconds: rows.reduce(0) { $0 + max(0, $1.durationS) }
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.leading, 20)
            .padding(.top, profileSectionTop)
            .padding(.bottom, 4)
    }
}
