import SwiftUI

/// 用户协议 / 隐私政策 文本页（Figma「用户协议」「隐私政策」「隐私说明」）
struct AgreementView: View {
    enum Kind {
        case userAgreement
        case privacyPolicy
        case privacyIntro

        var title: String {
            switch self {
            case .userAgreement: return "用户服务协议"
            case .privacyPolicy: return "隐私政策"
            case .privacyIntro: return "隐私说明"
            }
        }
    }

    let kind: Kind
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white

            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("适用版本 \(appVersion)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: 1)
                    }
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, para in
                        paragraphView(para, isTitle: kind == .privacyIntro && index == 0)
                    }
                    Color.clear.frame(height: 1).id("agreementBottom")
                }
                .padding(.horizontal, 20)
                .padding(.top, 100)
                // 协议页不显示 Tab 栏，尾部留白按二级页算（32 + 8），
                // 原来的 104 会在最后一段之后空出半屏。
                .padding(.bottom, 40)
            }
            .onAppear {
                guard ProcessInfo.processInfo.arguments.contains("-agreement-bottom") else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo("agreementBottom", anchor: .bottom)
                    }
                }
            }
            }

            // 页头实底到 86pt；正文滚到这里会被硬切，且紧贴标题下沿。
            // 在页头下方补一段白→透明的渐隐，正文淡出而不是被切断。
            LinearGradient(
                stops: [
                    .init(color: Color.white, location: 0),
                    .init(color: Color.white.opacity(0.985), location: 0.45),
                    .init(color: Color.white.opacity(0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 26)
            .padding(.top, 86)
            .allowsHitTesting(false)

            DesignPageHeader(title: kind.title)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .hidesAppTabBar()
        .pageMark(kind == .privacyIntro ? 14 : (kind == .privacyPolicy ? 54 : 55))
    }

    private var paragraphs: [String] {
        content
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    @ViewBuilder
    private func paragraphView(_ para: String, isTitle: Bool) -> some View {
        let lines = para.components(separatedBy: "\n")
        if isTitle {
            Text(para)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 2)
        } else if lines.count > 1 {
            VStack(alignment: .leading, spacing: 0) {
                Text(lines[0])
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                ForEach(Array(lines.dropFirst().enumerated()), id: \.offset) { index, line in
                    bodyLine(line)
                        .lineSpacing(6)
                        // 同一条款内的多个「标签：内容」要分段，否则正文连成一片
                        .padding(.bottom, index == lines.count - 2 ? 0 : 14)
                }
            }
        } else if para.count <= 14, !para.contains("。"), !para.contains("，") {
            Text(para)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 12)
        } else {
            bodyLine(para)
                .lineSpacing(6)
        }
    }

    /// 正文行：把「账号信息：」这类短标签加粗，长段落更易扫读。
    private func bodyLine(_ line: String) -> Text {
        if let colon = line.firstIndex(of: "：") {
            let label = String(line[line.startIndex...colon])
            let rest = String(line[line.index(after: colon)...])
            if label.count <= 9, !rest.isEmpty {
                return Text(label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.ink)
                + Text(rest)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textPrimary)
            }
        }
        return Text(line)
            .font(.system(size: 14))
            .foregroundColor(Theme.textPrimary)
    }

    private var content: String {
        switch kind {
        case .userAgreement:
            return """
            欢迎使用 WellWay。本协议是你与本应用运营方之间就使用本应用服务订立的协议。你注册、登录或使用本应用，即视为已阅读并同意本协议全部条款。

            一、服务内容
            本应用为摩托车骑行爱好者提供路线浏览、轨迹记录、打卡与徽章、车辆管理，以及同一目的地和附近骑手的匿名汇总人数。骑手之间不提供关注、私信、评论或查看彼此身份的功能。你无需注册即可浏览大部分内容；骑行记录、收藏等功能使用匿名账号或绑定邮箱后可用。

            二、账号与行为规范
            你应对账号下的所有行为负责，不得转借、出租或出售账号，不得利用本应用从事任何违法违规活动。我们有权对违反本协议或法律法规的账号采取警告、限制功能、封禁等处理。

            三、骑行安全
            骑行活动存在固有风险。你应自行确认具备相应驾驶资质，遵守《道路交通安全法》等法律法规，佩戴安全装备，并确保安全前提下使用本应用。请勿在骑行过程中操作手机或阅读弹窗。

            四、知识产权
            本应用的品牌、界面设计、文字、图片、商标等归运营方或其权利人所有，未经许可不得复制、修改或商用。路线、打卡点、徽章等运营内容由运营方提供与维护，可能随时调整或下线。

            五、数据与隐私
            我们处理你的个人信息遵循《隐私政策》。定位用于天气查询、路线起点判断、轨迹记录和匿名骑手统计；精确位置与轨迹仅本人可见，其他用户只能看到聚合人数。你可在「我的 → 注销账号」永久删除账号及全部数据。

            六、免责声明
            本应用按「现状」提供，不对服务持续可用、无中断、无错误作绝对保证。路线信息、路况、坐标可能存在偏差，不构成道路安全指引，实际驾驶请以现场交通状况为准。因不可抗力、网络故障、第三方服务导致的数据丢失或服务中断，我们在法律允许范围内不承担责任。

            七、未成年人
            本应用面向成年摩托车爱好者。若你未满 18 周岁，请在监护人指导下使用。

            八、协议变更与联系我们
            我们可能适时更新本协议，更新后通过本页面或应用内公告发布。如对本协议有疑问，可通过「我的 → 设置 → 关于与反馈」与我们联系。
            """
        case .privacyPolicy:
            return """
            欢迎使用 WellWay。我们深知个人信息对你的重要性，将尽全力保护你的个人信息安全。本政策说明我们如何收集、使用、存储与共享你的信息。

            一、我们收集的信息
            账号信息：你可匿名使用；绑定邮箱后，我们会保存邮箱地址，用于换设备恢复数据与账号安全。你主动设置的头像与昵称仅用于「我的」页面展示。
            位置信息：在你查看天气、判断是否到达路线起点或使用骑行模式时获取。骑行过程中会在后台持续记录位置、速度与航向，用于生成轨迹、里程、打卡和安全提示，骑行结束后停止。骑行期间的在场状态仅用于匿名人数统计，结束后删除，并由服务端自动清理过期记录。
            行程与匿名统计：你选择路线并出发时，我们会保存目的地名称与坐标、起终点及行程状态，用于计算计划前往同一目的地、附近后方同向或对向驶来的匿名骑手人数。统计结果只有数字，不包含其他骑手的账号、昵称、车型、精确位置或联系方式。
            车辆信息：你自行录入的车辆品牌、车型、昵称、颜色与照片（我们不收集车牌号）。
            骑行数据：轨迹、里程、时长、打卡点、徽章、收藏与车辆关联。
            事故现场记录：仅在你主动提交时，保存事故类型、经过、时间、路线名称、当时的真实坐标与应用版本，用于本人留存及客服只读核对。该功能不用于救援调度，不会自动报警或通知任何第三方；无定位时也可提交，此时不保存坐标。
            设备与网络信息：系统版本、网络状态等保障功能正常运行的必要信息。

            二、我们如何使用信息
            提供路线、轨迹记录、打卡徽章、天气参考、路线起点判断与对向提醒等功能；生成不含身份信息的匿名骑手人数；保障账号安全与数据同步；仅使用脱敏统计改进产品。我们不会出售你的个人信息，不用于个性化广告。

            三、信息存储与跨境传输
            数据托管于云服务商（位于国际标准数据中心），可能传输并存储于境外服务器，传输过程采用 HTTPS 加密并采取访问控制等安全措施。继续使用本应用即视为你同意上述跨境存储。你可在应用内申请删除数据或注销账号。

            四、第三方共享
            为提供服务，我们会与以下第三方共享必要信息：云服务商 Supabase（账号、骑行、车辆、匿名在场心跳等数据存储）；天气服务商和风天气 QWeather（仅在展示天气时发送查询地点的经纬度，不含账号身份信息）；当你选择跳转高德地图或苹果地图导航时，将把路线起点或终点名称及坐标传递给对应地图应用（仅本次跳转使用）。第三方仅在提供对应服务所需范围内处理信息。

            五、权限说明
            定位（使用期间/后台）：用于天气、路线起点判断、骑行轨迹和匿名骑手统计；仅在相关功能触发或骑行时获取，结束后停止持续定位。
            通知：对向提醒、打卡完成与骑行完成提醒。
            相册：仅在你主动上传头像、车辆照片或保存骑行分享卡时使用。
            我们仅在功能直接相关时请求权限，你可拒绝或随时关闭。

            六、注销与删除
            你可随时在「我的 → 注销账号」永久删除账号及全部数据（含事故现场记录），删除后不可恢复。骑行结束后在场心跳会立即删除，服务端也会自动清理超过有效期的临时记录。也可通过「关于与反馈」联系我们协助处理。

            七、未成年人保护
            本应用面向成年摩托车爱好者。若你未满 18 周岁，请在监护人指导下使用。

            八、政策更新与联系我们
            我们可能适时更新本政策，重大变更会显著提示。联系方式：我的 → 设置 → 关于与反馈。
            """
        case .privacyIntro:
            return """
            我们如何收集与使用你的数据

            位置与轨迹
            用于天气查询、路线起点判断、轨迹记录与打卡。骑行时会在后台持续获取位置，结束后停止。精确位置与轨迹仅本人可见；其他用户只能看到匿名汇总人数。你可随时在系统设置中关闭定位。

            行程与匿名统计
            出发时会保存目的地坐标、起终点与行程状态，用于计算同一目的地及附近同向、对向骑手的匿名人数。不同骑手之间不能查看彼此身份、位置或发送消息，统计人数不可作为会车与避险依据。

            事故现场记录
            仅在你主动提交时保存事故类型、经过、时间、路线、当时的真实坐标与版本，用于本人留存及客服只读核对；不用于救援调度，不会自动报警或通知第三方。无定位时也可提交，此时不保存坐标。

            车辆信息
            你自行录入的车辆品牌、车型、昵称、颜色与照片，用于车库展示与骑行关联，仅自己可见。我们不收集车牌号。

            账号数据
            可匿名使用；绑定邮箱后，数据同步至你的账号以支持换设备恢复。你主动设置的头像与昵称仅用于「我的」页面展示。

            数据存储
            数据存储于云服务商（国际标准数据中心），传输加密。

            注销与删除
            你可在「我的 → 注销账号」永久删除账号及全部数据，不可恢复。
            """
        }
    }
}

extension AgreementView.Kind: Identifiable {
    var id: Int {
        switch self {
        case .userAgreement: return 0
        case .privacyPolicy: return 1
        case .privacyIntro: return 2
        }
    }
}
