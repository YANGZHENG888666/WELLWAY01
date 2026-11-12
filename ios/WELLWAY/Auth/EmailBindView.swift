import SwiftUI

/// 邮箱绑定(Figma「绑定邮箱」112:xxx,按节点 1:1 还原)
/// 说明 + 邮箱输入 + 验证码输入(右侧获取验证码) + 提示 + 保存
struct EmailBindView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var otp = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var message: String?
    @State private var isError = false
    @State private var countdown = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var showSuccess = false
    @State private var successWasRebinding = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case otp
    }

    private var canSendCode: Bool {
        EmailValidator.isValid(email.trimmingCharacters(in: .whitespaces))
            && countdown == 0
            && !isSending
    }

    private var isRebinding: Bool {
        auth.profile?.emailBound == true
    }

    private var pageTitle: String {
        isRebinding ? "更换绑定邮箱" : "绑定邮箱"
    }

    var body: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: pageTitle)

            ScrollView(showsIndicators: false) {
                formContent
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            // 主行动和其他表单页一样固定在底部：留在表单流里会停在屏幕中段，
            // 下面空掉三分之二屏，整页读起来像没排完。
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .hidesAppTabBar()
        .overlay {
            if showSuccess {
                bindSuccessPage
            }
        }
        .onAppear {
            restoreCountdown()
            focusDebugFieldIfNeeded()
        }
        .onDisappear { timerTask?.cancel() }
        .pageMark(message == "绑定成功" ? 59 : 34)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 0) {
                // 说明(y=104)
                Text(isRebinding ? "验证新邮箱后完成更换" : "绑定后换设备不丢数据")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.top, 28)
                    .motionAppear(delay: 0.05)
                Text(isRebinding ? "车辆、骑行与徽章不会受影响" : "骑行、徽章与车辆会同步到同一账号")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.top, 10)
                    .motionAppear(delay: 0.10)

                if isRebinding,
                   let current = auth.user?.email?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !current.isEmpty {
                    HStack(spacing: 6) {
                        Text("当前邮箱")
                            .foregroundStyle(Theme.textSecondary)
                        Text(current)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 12))
                    .padding(.top, 12)
                }

                // 邮箱输入(y=160)
                TextField("输入邮箱地址", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .otp }
                    .font(.system(size: 15))
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(Theme.lightField)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 24)
                    .motionAppear(delay: 0.16)

                // 验证码输入 + 获取验证码(y=232)
                HStack(spacing: 0) {
                    TextField("输入验证码", text: $otp)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focusedField, equals: .otp)
                        .font(.system(size: 15))
                        .padding(.horizontal, 16)
                        .onChange(of: otp) { _, newValue in
                            let digits = newValue.filter { $0.isNumber }
                            let limited = String(digits.prefix(6))
                            if limited != newValue { otp = limited }
                            // 六位验证码输入完成后自动收起键盘，避免数字键盘没有“完成”键。
                            if limited.count == 6 { focusedField = nil }
                        }

                    Rectangle()
                        .fill(Theme.separator)
                        .frame(width: 1, height: 22)

                    Button {
                        Task { await sendCode() }
                    } label: {
                        Group {
                            if isSending {
                                ProgressView().controlSize(.small)
                            } else if countdown > 0 {
                                Text("\(countdown) 秒")
                                    .monospacedDigit()
                            } else {
                                Text("获取验证码")
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(canSendCode ? Theme.textPrimary : Theme.listGray)
                        .frame(width: 96, height: 52)
                    }
                    .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                    .disabled(!canSendCode)
                    .accessibilityLabel(isSending ? "正在发送验证码" : (countdown > 0 ? "\(countdown) 秒后可重新获取验证码" : "获取验证码"))
                    .accessibilityHint(isSending ? "正在发送验证码" : (countdown > 0 ? "请等待倒计时结束后重新获取" : (canSendCode ? "" : "请先输入有效邮箱地址")))
                }
                .frame(height: 52)
                .background(Theme.lightField)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 12)

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(isError ? Theme.danger : Theme.successText)
                        .padding(.top, 8)
                }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            saveButton
                .padding(.horizontal, 20)
                .padding(.top, 10)
            Text("邮箱仅用于登录与数据同步，不会用于营销推送")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
        }
        .wellwayBottomBar()
    }

    private var saveButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Group {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("保存")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(canSubmit ? .white : Theme.listGray)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            // 禁用态用浅灰底，而不是白底描边：描边在本项目里不是按钮样式
            .background(canSubmit ? Color.black : Theme.lightField)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SolidPressStyle())
        .disabled(!canSubmit || isLoading)
        .accessibilityLabel(isLoading ? "正在保存" : "保存")
        .accessibilityHint(isLoading ? "正在保存" : (canSubmit ? "" : "请先输入有效邮箱和 6 位验证码"))
    }

    /// 绑定成功页(Figma「绑定成功」227:358):20 Bold 标题 + 12 说明 + 15 Bold 完成
    private var bindSuccessPage: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Theme.success)
                Text(successWasRebinding ? "更换成功" : "绑定成功")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.top, 16)
                Text(successWasRebinding ? "下次可使用新邮箱登录" : "换设备登录同一账号即可恢复数据")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.top, 6)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("完成")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(SolidPressStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var canSubmit: Bool {
        emailIsValid && otp.count == 6
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var emailIsValid: Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Z0-9a-z.-]+\.[A-Za-z]{2,}$"#
        return trimmedEmail.range(of: pattern, options: .regularExpression) != nil
    }

    private func sendCode() async {
        guard !trimmedEmail.isEmpty else {
            isError = true
            message = "请先输入邮箱地址"
            return
        }
        guard emailIsValid else {
            isError = true
            message = "请输入有效邮箱地址"
            return
        }
        isSending = true
        message = nil
        // 真实链路：向该邮箱发送验证码
        let ok = await auth.sendEmailOTP(trimmedEmail)
        if ok {
            isError = false
            message = "验证码已发送"
            startCountdown()
            focusedField = .otp
        } else {
            isError = true
            message = auth.errorMessage ?? "验证码发送失败，请稍后重试"
        }
        isSending = false
    }

    /// 验证码倒计时持久化：记录发送时刻，杀进程/切后台后恢复剩余秒数
    private static let countdownKey = "emailBind.countdownSentAt"
    private static let countdownTotal: Double = 30

    private func restoreCountdown() {
        let sentAt = UserDefaults.standard.double(forKey: Self.countdownKey)
        guard sentAt > 0 else { return }
        let elapsed = Date().timeIntervalSince1970 - sentAt
        let remain = Int(Self.countdownTotal - elapsed)
        guard remain > 0 else {
            UserDefaults.standard.removeObject(forKey: Self.countdownKey)
            return
        }
        countdown = remain
        timerTask?.cancel()
        timerTask = Task {
            while countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                countdown -= 1
            }
            UserDefaults.standard.removeObject(forKey: Self.countdownKey)
        }
    }

    private func focusDebugFieldIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-focusotp") else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            focusedField = .otp
        }
    }

    private func startCountdown() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.countdownKey)
        countdown = 30
        timerTask?.cancel()
        timerTask = Task {
            while countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                countdown -= 1
            }
            UserDefaults.standard.removeObject(forKey: Self.countdownKey)
        }
    }

    private func submit() async {
        focusedField = nil
        guard canSubmit else {
            isError = true
            message = "请输入有效邮箱和 6 位验证码"
            return
        }
        isLoading = true
        message = nil
        successWasRebinding = isRebinding
        // 真实链路：校验验证码完成绑定
        let ok = await auth.verifyEmailOTP(email: trimmedEmail, token: otp)
        if ok {
            isError = false
            message = "绑定成功"
            showSuccess = true
        } else {
            isError = true
            message = auth.errorMessage ?? "验证码错误或已过期，请重试"
        }
        isLoading = false
    }
}
