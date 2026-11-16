import SwiftUI

/// 认证页底部协议统一组件(Figma「登录页/注册页/账号密码登录」Frame:勾选圆点中心 (74, y),
/// 文字 10pt #828282 自 x=85 起，与圆点间留出约 7pt 间距，避免贴字)。
/// 未勾选：空心圆 #D9D9D9;已勾选：黑色对勾；「用户服务协议」「隐私政策」可点击打开详情。
/// 协议行内容（不定位）：复选框 + 可点击的《用户服务协议》《隐私政策》。
/// 供栈式布局页面直接内联使用；旧页面用 `AuthAgreementRow` 包一层定位。
struct AuthAgreementLine: View {
    @Binding var agreed: Bool
    var onAgreement: () -> Void = {}
    var onPrivacy: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                agreed.toggle()
            } label: {
                Image(systemName: agreed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundColor(
                        agreed
                            ? .black
                            : Theme.chevron
                    )
                    .frame(width: 24, height: 24)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconPressStyle(pressedOpacity: 0.6))
            .accessibilityLabel("同意用户服务协议及隐私政策")
            .accessibilityValue(agreed ? "已勾选" : "未勾选")

            AgreementCopyLinks(onAgreement: onAgreement, onPrivacy: onPrivacy)
            Spacer(minLength: 0)
        }
    }

}

/// 协议文案：两段链接各自是独立按钮，读屏可以逐个聚焦、逐个打开。
/// （整段 AttributedString 在无障碍树里只会是一个文本节点。）
struct AgreementCopyLinks: View {
    var onAgreement: () -> Void
    var onPrivacy: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("我已阅读并同意")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
            link("《用户服务协议》", opens: "用户服务协议", action: onAgreement)
            Text("及")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
            link("《隐私政策》", opens: "隐私政策", action: onPrivacy)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func link(_ title: String, opens name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(Theme.textPrimary)
                .underline()
                .padding(.vertical, 15)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看\(name)")
        .accessibilityAddTraits(.isLink)
    }
}

/// 固定在某个 y 上的协议行（Figma 坐标页使用）
struct AuthAgreementRow: View {
    var y: CGFloat = 601.5
    @Binding var agreed: Bool
    var onAgreement: () -> Void = {}
    var onPrivacy: () -> Void = {}

    var body: some View {
        GeometryReader { proxy in
            AuthAgreementLine(agreed: $agreed, onAgreement: onAgreement, onPrivacy: onPrivacy)
                .frame(width: max(proxy.size.width - 32, 240), alignment: .leading)
                .position(x: proxy.size.width / 2, y: y)
        }
    }
}

/// 未勾选协议时的左右颤动提醒(振幅 8pt,每次触发两轮摆动)
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 8
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(shakes * 2 * .pi), y: 0))
    }
}
