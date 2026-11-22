import SwiftUI

/// 登录/进入页(Figma「登录页」):随便看看 / 创建新账户 / 已有账户立即登录
struct AuthView: View {
    @Environment(AuthManager.self) private var auth

    @State private var showSignup = false
    @State private var showCodeLogin = false
    @State private var showPasswordLogin = false
    @State private var agreementKind: AgreementView.Kind?

    var body: some View {
        DesignLoginView(
            onSignup: { showSignup = true },
            onPasswordLogin: { showPasswordLogin = true },
            onAnonymous: { Task { await auth.signInAnonymously() } },
            onAgreement: { agreementKind = .userAgreement },
            onPrivacy: { agreementKind = .privacyPolicy }
        )
        .overlay {
            if showSignup || showCodeLogin {
                EmailSignupView(
                    onBack: {
                        showSignup = false
                        showCodeLogin = false
                    },
                    onLogin: {
                        showSignup = false
                        showCodeLogin = false
                        showPasswordLogin = true
                    },
                    onAgreement: { agreementKind = .userAgreement },
                    onPrivacy: { agreementKind = .privacyPolicy },
                    codeLoginMode: showCodeLogin
                )
                    .transition(.opacity)
            }
        }
        .overlay {
            if showPasswordLogin {
                PasswordLoginView(
                    onBack: { showPasswordLogin = false },
                    onSignup: {
                        showPasswordLogin = false
                        showSignup = true
                    },
                    onCodeLogin: {
                        showPasswordLogin = false
                        showCodeLogin = true
                    },
                    onAgreement: { agreementKind = .userAgreement },
                    onPrivacy: { agreementKind = .privacyPolicy }
                )
                    .transition(.opacity)
            }
        }
        .fullScreenCover(item: $agreementKind) { kind in
            AgreementView(kind: kind)
        }
        .task {
            // 调试：-guest 直接以匿名身份进入，便于验证新用户空车库
            guard ProcessInfo.processInfo.arguments.contains("-guest") else { return }
            // 状态切到 loading 后本视图会被移除，必须用非结构化任务，避免请求被取消
            Task { await auth.signInAnonymously() }
        }
    }
}

/// 键盘弹起状态：小屏登录页隐藏品牌头图，避免表单被键盘挤压后只露出半截 logo。
private struct KeyboardVisibilityReader: ViewModifier {
    @Binding var isVisible: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation(.easeOut(duration: 0.18)) { isVisible = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.18)) { isVisible = false }
            }
    }
}

private extension View {
    func tracksKeyboardVisibility(_ isVisible: Binding<Bool>) -> some View {
        modifier(KeyboardVisibilityReader(isVisible: isVisible))
    }
}
/// 认证页公共组件(Figma 认证页统一风格：白底 / 顶部品牌 / 黑按钮 / 底部协议)


private struct AuthTopBar: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(IconPressStyle())
            .accessibilityLabel("返回")
            Spacer()
        }
        .padding(.leading, 16)
        .padding(.top, 18)
    }
}

private struct AuthFieldView: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var keyboardType: UIKeyboardType = .default
    /// 焦点必须绑在真实的 TextField / SecureField 上。
    /// `.focused` 修饰在外层容器上不会生效：点输入框不会弹键盘。
    var focused: FocusState<Bool>.Binding

    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if secure && !isRevealed {
                    SecureField(placeholder, text: $text)
                        .focused(focused)
                } else {
                    TextField(placeholder, text: $text)
                        .focused(focused)
                }
            }
            .font(.system(size: 14))
            .keyboardType(keyboardType)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())

            if secure {
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.listGray)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(IconPressStyle())
                .accessibilityLabel(isRevealed ? "隐藏密码" : "显示密码")
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(Theme.lightField)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // 整行 52pt 都可点：TextField 本身只有文字高度，点在上下留白会落空。
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = true }
    }
}

private struct BlackActionButton: View {
    let title: String
    let isLoading: Bool
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isEnabled ? .white : Theme.listGray)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            // 禁用态用浅灰底：全站只有这一种禁用表达，白底描边会读成"次级描边按钮"
            .background(isEnabled ? Color.black : Theme.lightField)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SolidPressStyle())
        .disabled(!isEnabled || isLoading)
        .accessibilityHint(isLoading ? "正在提交" : (isEnabled ? "" : "请先填写有效信息"))
    }
}

private struct CodeBoxes: View {
    @Binding var code: String
    var error = false

    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 10
            let boxWidth = min(48, max(34, (proxy.size.width - gap * 5) / 6))
            ZStack {
                HStack(spacing: gap) {
                    ForEach(0..<6, id: \.self) { index in
                        Text(digit(at: index))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(error ? Theme.danger : Theme.textPrimary)
                            .frame(width: boxWidth, height: 52)
                            .background(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(
                                        error
                                            ? Theme.danger
                                            : Theme.separator,
                                        lineWidth: 1
                                    )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity)

                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focused)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                    .opacity(0.02)
                    .onTapGesture { focused = true }
                    .onChange(of: code) { _, newValue in
                        code = String(newValue.filter(\.isNumber).prefix(6))
                    }
            }
        }
        .frame(height: 52)
        .onAppear { focused = true }
    }

    private func digit(at index: Int) -> String {
        guard index < code.count else { return "" }
        return String(code[code.index(code.startIndex, offsetBy: index)])
    }
}

/// 返回箭头(Figma 注册页路径：M31 80 L25 74 L31 68,stroke 2 round,中心 (28,74))
struct BackChevron: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 15, y: 18))
            path.addLine(to: CGPoint(x: 9, y: 12))
            path.addLine(to: CGPoint(x: 15, y: 6))
        }
        .stroke(Color.black, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

/// 创建新账户：邮箱 → 验证码 → 进入(Figma「注册页」288:16 /「输入验证码」135:799 /「验证码错误」135:868,按节点坐标 1:1)
/// 验证码发送倒计时基于 UserDefaults 持久化：切后台/杀进程后重新进入仍显示剩余秒数，防止绕过 30s 限制
@MainActor
enum CodeCooldown {
    private static let key = "authCodeCooldownUntil"

    /// 剩余秒数；无进行中倒计时返回 0
    static func remaining() -> Int {
        guard let until = UserDefaults.standard.object(forKey: key) as? Date else { return 0 }
        return max(0, Int(ceil(until.timeIntervalSinceNow)))
    }

    static func start() {
        UserDefaults.standard.set(Date().addingTimeInterval(30), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// ScrollView 可视高度：由 `AuthViewportReader` 注入，供 `AuthVerticalFill` 撑满内容。
private struct AuthViewportHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

private extension EnvironmentValues {
    var authViewportHeight: CGFloat? {
        get { self[AuthViewportHeightKey.self] }
        set { self[AuthViewportHeightKey.self] = newValue }
    }
}

/// 认证页是「一两个输入框 + 底部主行动」的短页面：内容贴顶会在下半屏留下整块空白，像套模板。
/// 只在键盘收起时用顶部留白做垂直居中；键盘弹起时保持自然高度，避免输入区被压缩。
///
/// 不能给 ScrollView 内容加高度约束（`containerRelativeFrame(.vertical)` / `frame(minHeight:)`）。
/// iOS 26 上内容一旦被强制撑高，内部 TextField 就无法成为 first responder，
/// 点击输入框和代码设置 FocusState 都不会弹键盘。
private struct AuthVerticalFill: ViewModifier {
    let enabled: Bool
    @State private var contentHeight: CGFloat = 0
    @Environment(\.authViewportHeight) private var viewportHeight

    /// 小屏内容本来就接近满屏，且旧设备更容易出现键盘遮挡，保持顶部对齐。
    private var fills: Bool { enabled && UIScreen.main.bounds.height >= 800 }

    private var topPadding: CGFloat {
        guard fills,
              let viewportHeight,
              contentHeight > 0,
              viewportHeight > contentHeight else { return 0 }
        return (viewportHeight - contentHeight) / 2
    }

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { contentHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, height in
                            contentHeight = height
                        }
                }
            )
            .padding(.top, topPadding)
    }
}

/// 调试预填：`-signupemail=test@example.com` / `-passwordloginemail=...`。
/// 只在 Debug 构建且显式传参时生效，正常启动路径完全不变。
private enum AuthDebugPrefill {
    static func value(for key: String) -> String? {
        #if DEBUG
        let prefix = key + "="
        guard let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return String(raw.dropFirst(prefix.count))
        #else
        return nil
        #endif
    }
}

struct EmailSignupView: View {
    @Environment(AuthManager.self) private var auth

    var onBack: () -> Void = {}
    var onLogin: () -> Void = {}
    var onAgreement: () -> Void = {}
    var onPrivacy: () -> Void = {}
    /// true：从「登录账户 → 用邮箱验证码登录」进来。链路完全一样(验证码会自动建号)，
    /// 只是文案要按「登录」而不是「注册」来说。
    var codeLoginMode: Bool = false

    /// 勾选状态全局持久化：点过一次之后后续页面不再要求重复勾选
    @AppStorage("agreementAccepted") private var agreed = false
    @State private var shakeCount: CGFloat = 0
    @State private var email = AuthDebugPrefill.value(for: "-signupemail") ?? ""
    @State private var code = ""
    /// 调试：-codelogincooldown 直接停在已验证码、冷却中的状态
    @State private var step = ProcessInfo.processInfo.arguments.contains("-codelogincooldown") ? 1 : 0
    @State private var isLoading = false
    @State private var cooldown = ProcessInfo.processInfo.arguments.contains("-codelogincooldown") ? 20 : 0
    @State private var errorText: String?
    @State private var codeError = false
    @State private var kbActive = false
    @State private var isResending = false

    @FocusState private var emailFocused: Bool

    private var screenWidth: CGFloat { UIScreen.main.bounds.width }
    private var contentWidth: CGFloat { max(screenWidth - 40, 280) }
    private var centerX: CGFloat { screenWidth / 2 }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                        Spacer(minLength: 0)
                        if !(kbActive && UIScreen.main.bounds.height < 700) {
                            brand
                                .transition(.opacity)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(step == 0 ? (codeLoginMode ? "邮箱验证码登录" : "创建新账户") : "验证码已发送")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(Theme.textPrimary)
                            Text(step == 0 ? (codeLoginMode ? "输入邮箱，验证码会发到这个邮箱" : "输入你的邮箱") : (codeError ? "验证码填写错误" : "请输入验证码"))
                                .font(.system(size: 13))
                                .foregroundColor(codeError ? Theme.danger : Theme.textSecondary)
                        }
                        .padding(.top, 36)

                        if step == 0 {
                            AuthFieldView(
                                placeholder: "请输入邮箱",
                                text: $email,
                                keyboardType: .emailAddress,
                                focused: $emailFocused
                            )
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .submitLabel(.send)
                            .onSubmit {
                                guard EmailValidator.isValid(email.trimmingCharacters(in: .whitespaces)) else { return }
                                Task { await submit() }
                            }
                            .padding(.top, 22)

                            if let errorText {
                                Text(errorText)
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                    .padding(.top, 10)
                            }

                            // 注册页只有返回箭头，已有账号的用户要退回去再点一次；
                            // 邮箱输入框下方直接给一条登录入口，和「忘记密码」同级。
                            Button {
                                onLogin()
                            } label: {
                                // 下划线是网页写法，原生登录页用「灰提示 + 黑动作」表达同一件事
                                HStack(spacing: 2) {
                                    Text(codeLoginMode ? "想用密码登录？" : "已有账户？")
                                        .foregroundColor(Theme.textSecondary)
                                    Text(codeLoginMode ? "返回登录" : "直接登录")
                                        .fontWeight(.semibold)
                                        .foregroundColor(Theme.textPrimary)
                                }
                                .font(.system(size: 13, weight: .medium))
                                .frame(height: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                            .padding(.top, 4)

                        } else {
                            CodeBoxes(code: $code, error: codeError)
                                .frame(height: 52)
                                .padding(.top, 26)

                            if let errorText {
                                Text(errorText)
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                    .padding(.top, 10)
                            }

                            Button {
                                Task { await resend() }
                            } label: {
                                Text(cooldown > 0 ? "\(cooldown) 秒后可重新发送" : "重新发送验证码")
                                    .font(.system(size: 12, weight: cooldown > 0 ? .regular : .medium))
                                    .foregroundColor(cooldown > 0 ? Theme.listGray : .black)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                            .disabled(cooldown > 0 || isResending)
                            .padding(.top, 12)

                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .modifier(AuthVerticalFill(enabled: step == 0 && !kbActive))
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollDisabled(kbActive && UIScreen.main.bounds.height < 700)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 0) {
                        primaryAction
                            .padding(.horizontal, 20)
                            .padding(.top, 10)

                        AuthAgreementLine(agreed: $agreed, onAgreement: onAgreement, onPrivacy: onPrivacy)
                            .modifier(ShakeEffect(shakes: shakeCount))
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                    }
                    .background(Color.white)
                }
                .environment(\.authViewportHeight, geometry.size.height)
                }
        }
        }
        .tracksKeyboardVisibility($kbActive)
        .background(Color.white)
        .pageMark(step == 0 ? 18 : (codeError ? 27 : 25))
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: code) { _, newValue in
            if codeError { codeError = false }
            // 六位验证码填完即收起数字键盘，让「确定」按钮回到可见区域。
            if newValue.count == 6 {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .task {
            restoreCooldown()
            focusDebugFieldIfNeeded()
        }
        .onChange(of: agreed) { _, newValue in
            if newValue, errorText == "请先阅读并同意《用户服务协议》及《隐私政策》" {
                errorText = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button {
                onBack()
            } label: {
                BackChevron()
                    .frame(width: 24, height: 24)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconPressStyle())
            .accessibilityLabel("返回")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
    }

    /// 主行动固定在键盘上方；输入邮箱时也不会被滚出可视区域。
    @ViewBuilder
    private var primaryAction: some View {
        if step == 0 {
            BlackActionButton(
                title: "发送验证码",
                isLoading: isLoading,
                isEnabled: EmailValidator.isValid(email.trimmingCharacters(in: .whitespaces))
            ) {
                Task { await submit() }
            }
            .frame(height: 52)
        } else {
            BlackActionButton(
                title: "确定",
                isLoading: isLoading,
                isEnabled: code.count == 6
            ) {
                Task { await submit() }
            }
            .frame(height: 52)
        }
    }

    private var brand: some View {
        VStack(spacing: 12) {
            Image("BrandMarkFull")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .accessibilityHidden(true)
            Text("好路当骑 同行当悉")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private func promptAgree() {
        errorText = "请先阅读并同意《用户服务协议》及《隐私政策》"
        withAnimation(.linear(duration: 0.5)) { shakeCount += 2 }
    }

    private func submit() async {
        if isLoading { return }
        if !agreed {
            promptAgree()
            return
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if step == 0 {
            if trimmedEmail.isEmpty {
                errorText = "请输入邮箱"
                return
            }
            if !EmailValidator.isValid(trimmedEmail) {
                errorText = "请输入有效的邮箱地址"
                return
            }
        } else {
            if code.count < 6 {
                codeError = true
                return
            }
        }
        isLoading = true
        errorText = nil
        if step == 0 {
            // 真实链路：发送邮箱验证码；倒计时未结束则复用剩余时间，不重新发码
            let ok = await auth.sendEmailCode(trimmedEmail)
            if ok {
                step = 1
                if CodeCooldown.remaining() > 0 {
                    restoreCooldown()
                } else {
                    startCooldown()
                }
            } else {
                errorText = auth.errorMessage
            }
        } else {
            // 真实链路：校验验证码并登录
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            await auth.verifyEmailCode(email: trimmedEmail, token: code)
            if let message = auth.errorMessage {
                codeError = true
                errorText = message
            }
        }
        isLoading = false
    }

    /// 重新发送验证码：冷却中不可点，成功后重新开始倒计时
    private func resend() async {
        guard cooldown == 0, !isResending else { return }
        isResending = true
        errorText = nil
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        let ok = await auth.sendEmailCode(trimmed)
        if ok {
            startCooldown()
        } else {
            errorText = auth.errorMessage
        }
        isResending = false
    }

    private func startCooldown() {
        cooldown = 30
        CodeCooldown.start()
        runCooldownLoop()
    }

    /// 重新进入页面时从持久化截止时间恢复剩余秒数
    private func restoreCooldown() {
        let remaining = CodeCooldown.remaining()
        guard remaining > 0, cooldown == 0 else { return }
        cooldown = remaining
        runCooldownLoop()
    }

    private func focusDebugFieldIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-signupfocus") else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            emailFocused = true
        }
    }

    private func runCooldownLoop() {
        Task {
            while cooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                cooldown = CodeCooldown.remaining()
            }
            CodeCooldown.clear()
        }
    }
}

/// 账号密码登录(Figma「账号密码登录页」288:661 /「-输入邮箱弹出键盘」368:187:
/// 键盘态整块表单上移：标题 -100,输入框 -103.5,按钮 -110,协议 -104.5,避免输入框与标题重叠)
struct PasswordLoginView: View {
    @Environment(AuthManager.self) private var auth

    var onBack: () -> Void = {}
    var onSignup: () -> Void = {}
    /// 验证码注册的账号没有密码，这里必须给一条和注册链路一致的入口
    var onCodeLogin: () -> Void = {}
    var onAgreement: () -> Void = {}
    var onPrivacy: () -> Void = {}

    /// 勾选状态全局持久化：点过一次之后后续页面不再要求重复勾选
    @AppStorage("agreementAccepted") private var agreed = false
    @State private var shakeCount: CGFloat = 0
    @State private var email = AuthDebugPrefill.value(for: "-passwordloginemail") ?? ""
    @State private var password = AuthDebugPrefill.value(for: "-passwordloginpassword") ?? ""
    @State private var isLoading = false
    @State private var showForgot = false
    @State private var keyboardVisible = false

    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer(minLength: 0)
                            // 键盘态隐藏品牌头图：设计稿键盘态直接从标题开始，
                            // 保留品牌会把密码框挤到底部操作区下面。
                            if !keyboardVisible {
                                brand
                                    .transition(.opacity)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("登录账户")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(Theme.textPrimary)
                                if !(keyboardVisible && UIScreen.main.bounds.height < 700) {
                                    Text("使用绑定邮箱和密码登录")
                                        .font(.system(size: 13))
                                        .foregroundColor(Theme.textSecondary)
                                }
                            }
                            .padding(.top, keyboardVisible ? 8 : 36)

                            VStack(spacing: 12) {
                                AuthFieldView(
                                    placeholder: "请输入登录邮箱",
                                    text: $email,
                                    keyboardType: .emailAddress,
                                    focused: $emailFocused
                                )
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .submitLabel(.next)
                                .onSubmit { emailFocused = false; passwordFocused = true }
                                .id("email")

                                AuthFieldView(
                                    placeholder: "请输入登录密码",
                                    text: $password,
                                    secure: true,
                                    focused: $passwordFocused
                                )
                                .submitLabel(.go)
                                .onSubmit { Task { await login() } }
                                .id("password")
                            }
                            .padding(.top, keyboardVisible ? 16 : 22)

                            if let message = auth.errorMessage {
                                Text(message)
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                    .padding(.top, 10)
                            }

                            if !keyboardVisible {
                                // 「忘记密码」和「创建新账户」同一行：两个都是离开当前表单的出口，
                                // 竖着堆两行灰色文字会让人以为其中一个是说明。
                                HStack(spacing: 12) {
                                    Button {
                                        showForgot = true
                                    } label: {
                                        Text("忘记密码")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(Theme.textSecondary)
                                            .frame(minHeight: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(IconPressStyle(pressedOpacity: 0.5))

                                    Spacer(minLength: 12)

                                    Button {
                                        onSignup()
                                    } label: {
                                        Text("创建新账户")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(Theme.textPrimary)
                                            .frame(minHeight: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                                }
                                .frame(height: 44)
                                .padding(.top, 4)

                                // 「创建新账户」走的是邮箱验证码，注册出来的账号没有密码；
                                // 只留「忘记密码」等于让这类用户绕一圈才能回来。
                                Button {
                                    onCodeLogin()
                                } label: {
                                    Text("用邮箱验证码登录")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Theme.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .modifier(AuthVerticalFill(enabled: !keyboardVisible))
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollDisabled(keyboardVisible && UIScreen.main.bounds.height < 700)
                    .safeAreaInset(edge: .bottom) {
                        VStack(spacing: 0) {
                            if keyboardVisible {
                                forgotButton
                            }

                            loginButton
                                .padding(.top, keyboardVisible ? 10 : 8)

                            AuthAgreementLine(agreed: $agreed, onAgreement: onAgreement, onPrivacy: onPrivacy)
                                .modifier(ShakeEffect(shakes: shakeCount))
                                .padding(.horizontal, 20)
                                .padding(.top, keyboardVisible ? 8 : 0)
                                .padding(.bottom, 8)
                        }
                        .background(Color.white)
                    }
                .environment(\.authViewportHeight, geometry.size.height)
                }
            }
        }
        .tracksKeyboardVisibility($keyboardVisible)
        .background(Color.white)
        .pageMark(20)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showForgot) {
            ForgotPasswordView()
        }
        .task { focusDebugFieldIfNeeded() }
        .onChange(of: agreed) { _, newValue in
            if newValue, auth.errorMessage == "请先阅读并同意《用户服务协议》及《隐私政策》" {
                auth.errorMessage = nil
            }
        }
    }

    private var forgotButton: some View {
        Button {
            showForgot = true
        } label: {
            Text("忘记密码")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
    }

    private var loginButton: some View {
        BlackActionButton(
            title: "登录",
            isLoading: isLoading,
            isEnabled: !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
        ) {
            Task { await login() }
        }
        .frame(height: 52)
        .padding(.horizontal, 20)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button {
                onBack()
            } label: {
                BackChevron()
                    .frame(width: 24, height: 24)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconPressStyle())
            .accessibilityLabel("返回")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
    }

    private var brand: some View {
        VStack(spacing: 12) {
            Image("BrandMarkFull")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .accessibilityHidden(true)
            Text("好路当骑 同行当悉")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private func promptAgree() {
        auth.errorMessage = "请先阅读并同意《用户服务协议》及《隐私政策》"
        withAnimation(.linear(duration: 0.5)) { shakeCount += 2 }
    }

    private func focusDebugFieldIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-passwordloginfocus") else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            emailFocused = true
        }
    }

    private func login() async {
        if isLoading { return }
        if !agreed {
            promptAgree()
            return
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if trimmedEmail.isEmpty {
            auth.errorMessage = "请输入登录邮箱"
            return
        }
        if !EmailValidator.isValid(trimmedEmail) {
            auth.errorMessage = "请输入有效的邮箱地址"
            return
        }
        if password.isEmpty {
            auth.errorMessage = "请输入登录密码"
            return
        }
        isLoading = true
        emailFocused = false
        passwordFocused = false
        // 真实链路：账号密码登录
        await auth.signInWithPassword(email: trimmedEmail, password: password)
        isLoading = false
    }
}

/// 忘记密码 → 验证码 → 重置密码(Figma「忘记密码」/「填写验证码」/「重置密码」,坐标见各 step)
struct ForgotPasswordView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var email = ProcessInfo.processInfo.arguments.contains("-forgotcooldown")
        || ProcessInfo.processInfo.arguments.contains("-forgotresend")
        ? "rider@wellway.app" : ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    /// 调试：-forgotstep2 直接停在「创建新密码」这一步；-forgotcooldown 停在验证码冷却态；
    /// -forgotresend 停在验证码重发可用态
    @State private var step = ProcessInfo.processInfo.arguments.contains("-forgotstep2")
        ? 2
        : (ProcessInfo.processInfo.arguments.contains("-forgotcooldown")
            || ProcessInfo.processInfo.arguments.contains("-forgotresend")) ? 1 : 0
    @State private var isLoading = false
    @State private var cooldown = ProcessInfo.processInfo.arguments.contains("-forgotcooldown") ? 20 : 0
    @State private var errorText: String?
    @State private var isResending = false
    @State private var keyboardVisible = false

    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool
    @FocusState private var confirmPasswordFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer(minLength: 0)
                            if step < 3, !(keyboardVisible && UIScreen.main.bounds.height < 700) {
                                brand
                                    .transition(.opacity)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(headline)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(Theme.textPrimary)
                                if let subhead {
                                    Text(subhead)
                                        .font(.system(size: 13))
                                        .foregroundColor(Theme.textSecondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            .padding(.top, step < 3 ? (keyboardVisible && UIScreen.main.bounds.height < 700 ? 8 : 36) : 24)

                            stepContent

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .modifier(AuthVerticalFill(enabled: step < 3 && !keyboardVisible))
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollDisabled(keyboardVisible && UIScreen.main.bounds.height < 700)
                    .safeAreaInset(edge: .bottom) {
                        primaryAction
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                            .background(Color.white)
                    }
                .environment(\.authViewportHeight, geometry.size.height)
                }
            }
        }
        .tracksKeyboardVisibility($keyboardVisible)
        .background(Color.white)
        .pageMark(step == 0 ? 19 : (step == 1 ? (errorText != nil ? 30 : 26) : (step == 2 ? 28 : 29)))
        .toolbar(.hidden, for: .navigationBar)
        .task {
            restoreCooldown()
            focusDebugFieldIfNeeded()
        }
    }

    private var headline: String {
        switch step {
        case 0: return "忘记密码"
        case 1: return "验证码已发送"
        case 2: return "创建新密码"
        default: return "修改成功"
        }
    }

    private var subhead: String? {
        switch step {
        case 0: return "输入绑定邮箱，我们会发送验证码"
        case 1: return "已发送至 \(email.trimmingCharacters(in: .whitespaces))"
        case 2: return nil
        default: return "密码已更新，请用新密码登录"
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            AuthFieldView(
                placeholder: "请输入邮箱",
                text: $email,
                keyboardType: .emailAddress,
                focused: $emailFocused
            )
            .autocapitalization(.none)
            .autocorrectionDisabled()
            .submitLabel(.send)
            .onSubmit {
                guard EmailValidator.isValid(email.trimmingCharacters(in: .whitespaces)) else { return }
                Task { await submit() }
            }
            .padding(.top, 22)
            .id("email")

            if let errorText {
                Text(errorText)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.top, 10)
            }

        case 1:
            CodeBoxes(code: $code)
                .frame(height: 52)
                .padding(.top, 26)
                .onChange(of: code) { _, newValue in
                    if newValue.count == 6 {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.top, 10)
            }

            Button {
                Task { await resend() }
            } label: {
                Text(cooldown > 0 ? "\(cooldown) 秒后可重新发送" : "重新发送验证码")
                    .font(.system(size: 12, weight: cooldown > 0 ? .regular : .medium))
                    .foregroundColor(cooldown > 0 ? Theme.listGray : .black)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
            .disabled(cooldown > 0 || isResending)
            .padding(.top, 12)

        case 2:
            VStack(spacing: 12) {
                AuthFieldView(
                    placeholder: "请输入新密码",
                    text: $newPassword,
                    secure: true,
                    focused: $passwordFocused
                )
                .submitLabel(.next)
                .onSubmit { confirmPasswordFocused = true }
                .id("newPassword")

                AuthFieldView(
                    placeholder: "再次输入新密码",
                    text: $confirmPassword,
                    secure: true,
                    focused: $confirmPasswordFocused
                )
                .submitLabel(.done)
                .onSubmit { Task { await submit() } }
                .id("confirmPassword")
            }
            .padding(.top, 22)

            // 「完成」按钮在不足 6 位时是灰的，但界面上没有任何说明告诉用户为什么点不动
            Text("密码至少 6 位")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .padding(.top, 8)

            if let message = passwordStepError {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.top, 10)
            }

        default:
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.top, 40)
            }
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch step {
        case 0:
            BlackActionButton(
                title: "发送验证码",
                isLoading: isLoading,
                isEnabled: EmailValidator.isValid(email.trimmingCharacters(in: .whitespaces))
            ) {
                Task { await submit() }
            }
            .frame(height: 52)
        case 1:
            BlackActionButton(
                title: "下一步",
                isLoading: isLoading,
                isEnabled: code.count == 6
            ) {
                Task { await submit() }
            }
            .frame(height: 52)
        case 2:
            BlackActionButton(
                title: "完成",
                isLoading: isLoading,
                isEnabled: newPassword.count >= 6 && newPassword == confirmPassword
            ) {
                Task { await submit() }
            }
            .frame(height: 52)
        default:
            BlackActionButton(title: "去登录", isLoading: false) {
                dismiss()
            }
            .frame(height: 52)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button {
                if step == 1 || step == 2 {
                    // 流程内返回上一步，而不是直接关掉整个找回密码流程
                    errorText = nil
                    code = ""
                    withAnimation(.easeOut(duration: 0.2)) { step -= 1 }
                } else {
                    dismiss()
                }
            } label: {
                BackChevron()
                    .frame(width: 24, height: 24)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconPressStyle())
            .accessibilityLabel("返回")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
    }

    private var brand: some View {
        VStack(spacing: 12) {
            Image("BrandMarkFull")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .accessibilityHidden(true)
            Text("好路当骑 同行当悉")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var passwordStepError: String? {
        if !newPassword.isEmpty, !confirmPassword.isEmpty, newPassword != confirmPassword {
            return "两次输入的密码不一致"
        }
        return errorText
    }

    private func focusDebugFieldIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-forgotfocus") else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            emailFocused = true
        }
    }

    private func submit() async {
        if isLoading { return }
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        switch step {
        case 0:
            if trimmedEmail.isEmpty {
                errorText = "请输入邮箱"
                return
            }
            if !EmailValidator.isValid(trimmedEmail) {
                errorText = "请输入有效的邮箱地址"
                return
            }
        case 1:
            if code.count < 6 {
                errorText = "请输入 6 位验证码"
                return
            }
        default:
            if newPassword.count < 6 {
                errorText = "新密码至少 6 位"
                return
            }
            if newPassword != confirmPassword {
                errorText = "两次输入的密码不一致"
                return
            }
        }
        isLoading = true
        errorText = nil
        passwordFocused = false
        confirmPasswordFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        switch step {
        case 0:
            // 真实链路：发送邮箱验证码；倒计时未结束则复用剩余时间，不重新发码
            let ok = await auth.sendEmailCode(trimmedEmail)
            if ok {
                step = 1
                if CodeCooldown.remaining() > 0 {
                    restoreCooldown()
                } else {
                    startCooldown()
                }
            } else {
                errorText = auth.errorMessage
            }
        case 1:
            // 真实链路：校验验证码(不进入主界面),通过后进入设置新密码
            await auth.verifyEmailCode(email: trimmedEmail, token: code, enterApp: false)
            if let message = auth.errorMessage {
                errorText = message
            } else {
                step = 2
            }
        case 2:
            // 真实链路：设置新密码
            await auth.setNewPassword(newPassword)
            if let message = auth.errorMessage {
                errorText = message
            } else {
                step = 3
            }
        default:
            break
        }
        isLoading = false
    }

    /// 重新发送验证码：冷却中不可点，成功后重新开始倒计时
    private func resend() async {
        guard cooldown == 0, !isResending else { return }
        isResending = true
        errorText = nil
        let ok = await auth.sendEmailCode(email.trimmingCharacters(in: .whitespaces))
        if ok {
            startCooldown()
        } else {
            errorText = auth.errorMessage
        }
        isResending = false
    }

    private func startCooldown() {
        cooldown = 30
        CodeCooldown.start()
        runCooldownLoop()
    }

    /// 重新进入页面时从持久化截止时间恢复剩余秒数
    private func restoreCooldown() {
        let remaining = CodeCooldown.remaining()
        guard remaining > 0, cooldown == 0 else { return }
        cooldown = remaining
        runCooldownLoop()
    }

    private func runCooldownLoop() {
        Task {
            while cooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                cooldown = CodeCooldown.remaining()
            }
            CodeCooldown.clear()
        }
    }
}

/// 登录链路共用的本地邮箱格式校验，避免明显无效的地址先发到服务端。
enum EmailValidator {
    static func isValid(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 254 else { return false }
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}
