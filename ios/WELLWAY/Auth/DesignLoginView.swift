import SwiftUI

/// 登录页(Figma「登录页」135:290,按节点数据 1:1 还原)
/// 创建新账户 / 已有账户立即登录 / 随便看看 + 协议勾选
struct DesignLoginView: View {
    var onSignup: () -> Void
    var onPasswordLogin: () -> Void
    var onAnonymous: () -> Void
    var onAgreement: () -> Void
    var onPrivacy: () -> Void

    /// 勾选状态全局持久化：点过一次之后后续页面不再要求重复勾选
    @AppStorage("agreementAccepted") private var agreed = false
    @Environment(AuthManager.self) private var auth
    @State private var shakeCount: CGFloat = 0
    @State private var showAgreeHint = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // 品牌区在「状态栏 → 操作区」这段空间里居中：
                    // 固定 96pt 顶距会让标语和按钮之间空掉近半屏
                    Spacer(minLength: max(72, proxy.size.height * 0.11))

                    brand

                    // 与上方 Spacer 平分剩余空间，品牌落在视觉中上位置
                    Spacer(minLength: 48)

                    actionStack

                    if let message = auth.errorMessage {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.danger)
                            .multilineTextAlignment(.center)
                            .padding(.top, 10)
                            .onAppear { showAgreeHint = false }
                    } else if showAgreeHint {
                        Text("请先阅读并同意《用户服务协议》与《隐私政策》")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.danger)
                            .multilineTextAlignment(.center)
                            .padding(.top, 10)
                    }

                    Spacer().frame(height: 24)

                    agreementRow
                        .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
                .frame(minHeight: proxy.size.height)
            }
            .background(Color.white)
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .pageMark(17)
    }

    private var brand: some View {
        VStack(spacing: 14) {
            Image("BrandMarkFull")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                // 装饰图形：不隐藏会被念成资源名「BrandMarkFull」
                .accessibilityHidden(true)
            Text("好路当骑 同行当悉")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionStack: some View {
        VStack(spacing: 12) {
            Button {
                requireAgreement(onSignup)
            } label: {
                Text("创建新账户")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(SolidPressStyle())

            HStack(spacing: 12) {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 1)
                Text("或")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize()
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 1)
            }
            .frame(height: 28)
            // 纯装饰分隔，读屏里突然冒出一个「或」反而打断两个按钮的连续性
            .accessibilityHidden(true)

            Button {
                requireAgreement(onPasswordLogin)
            } label: {
                Text("已有账户立即登录")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconPressStyle(pressedOpacity: 0.5))

            Button {
                requireAgreement(onAnonymous)
            } label: {
                Text("随便看看")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
        }
    }

    private var agreementRow: some View {
        AuthAgreementLine(agreed: $agreed, onAgreement: onAgreement, onPrivacy: onPrivacy)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(ShakeEffect(shakes: shakeCount))
    }

    private func promptAgree() {
        withAnimation(.linear(duration: 0.5)) { shakeCount += 2 }
    }

    /// 三个入口共用同一套协议校验，避免登录或匿名路径绕过同意步骤。
    private func requireAgreement(_ action: () -> Void) {
        guard agreed else {
            showAgreeHint = true
            promptAgree()
            return
        }
        showAgreeHint = false
        action()
    }
}
