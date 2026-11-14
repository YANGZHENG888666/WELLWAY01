import SwiftUI

/// App 内统一弹窗(替代系统 alert / confirmationDialog):
/// 半透明遮罩 + 白色圆角卡片(标题 / 说明)+ 纵向按钮列表 + 底部取消按钮
struct WellwayDialogButton: Identifiable {
    let id = UUID()
    let title: String
    var role: WellwayButtonRole = .primary
    let action: () -> Void
}

enum WellwayButtonRole {
    /// 黑色加粗(主操作)
    case primary
    /// 红色(危险操作)
    case destructive
    /// 常规黑色(次操作)
    case plain
}

private struct WellwayDialogModifier: ViewModifier {
    @Binding var isPresented: Bool
    var title: String
    var message: String?
    var buttons: [WellwayDialogButton]
    var showsCancel: Bool
    var onCancel: (() -> Void)?

    func body(content: Content) -> some View {
        // 用透明全屏呈现而不是 overlay：TabView 的浮动 Tab 栏绘制在页面内容之上，
        // 页面内 overlay 出来的面板底部会被 Tab 栏压住（「暂时跳过」这类最后一颗按钮被切掉一半）。
        // 模态呈现能盖住 Tab 栏，背景透明所以外观与之前一致。
        content.fullScreenCover(isPresented: $isPresented) {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                panel
            }
            .presentationBackground(.clear)
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Theme.separator)
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 16)

            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            // 只有一个按钮的提示框（「知道了」）里那个按钮就是主行动，
            // 不能因为角色写成 plain 就变成浅灰次要按钮。
            let singleButton = buttons.count == 1
            let filled = singleButton ? buttons : buttons.filter { $0.role != .plain }
            let outlined = singleButton ? [] : buttons.filter { $0.role == .plain }

            VStack(spacing: 10) {
                ForEach(filled) { button in
                    Button {
                        dismiss()
                        button.action()
                    } label: {
                        Text(button.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(color(for: button.role))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(SolidPressStyle())
                }
            }
            .padding(.top, 22)

            // 次行动与取消统一成 50pt 文字行（发丝线分隔），只有主行动是实心色块：
            // 两个同尺寸实心块堆叠会把「取消」挤成第三个按钮，层级全平。
            if !outlined.isEmpty || showsCancel {
                divider.padding(.top, filled.isEmpty ? 14 : 8)

                VStack(spacing: 0) {
                    ForEach(outlined) { button in
                        Button {
                            dismiss()
                            button.action()
                        } label: {
                            textRow(button.title, color: Theme.textPrimary)
                        }
                        .buttonStyle(RowPressStyle())

                        divider
                    }

                    if showsCancel {
                        Button {
                            dismiss()
                            onCancel?()
                        } label: {
                            textRow("取消", color: Theme.textSecondary)
                        }
                        .buttonStyle(RowPressStyle())
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                .fill(Color.white)
                .ignoresSafeArea(edges: .bottom)
        }
        .transition(.move(edge: .bottom))
    }

    private func textRow(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .contentShape(Rectangle())
    }

    private var divider: some View {
        Rectangle().fill(Theme.separator).frame(height: 1)
    }

    private func color(for role: WellwayButtonRole) -> Color {
        switch role {
        case .primary: return .black
        case .destructive: return Theme.danger
        case .plain: return Theme.textPrimary
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
    }
}

extension View {
    /// App 内统一弹窗(替代系统 alert / confirmationDialog)。
    /// `buttons` 为空时显示一个「确定」按钮。
    func wellwayDialog(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        buttons: [WellwayDialogButton],
        onCancel: (() -> Void)? = nil
    ) -> some View {
        modifier(
            WellwayDialogModifier(
                isPresented: isPresented,
                title: title,
                message: message,
                buttons: buttons.isEmpty
                    ? [WellwayDialogButton(title: "确定", role: .primary, action: {})]
                    : buttons,
                showsCancel: showsImplicitCancel(for: buttons),
                onCancel: onCancel
            )
        )
    }
}

/// 弹窗按钮已经包含「取消 / 暂时跳过」等收尾动作时，不再追加默认取消；
/// 只有一个确认类按钮的提示框也不需要取消。
private func showsImplicitCancel(for buttons: [WellwayDialogButton]) -> Bool {
    guard !buttons.isEmpty else { return false }
    let dismissive: Set<String> = ["取消", "暂时跳过", "稍后", "稍后再说"]
    if buttons.contains(where: { dismissive.contains($0.title) }) { return false }
    if buttons.count == 1, ["知道了", "好的", "确定"].contains(buttons[0].title) { return false }
    return true
}

/// 带输入框的 App 内弹窗(替代系统 TextField alert,用于重命名/修改昵称)
private struct WellwayPromptModifier: ViewModifier {
    @Binding var isPresented: Bool
    var title: String
    var placeholder: String
    @Binding var text: String
    var confirmTitle: String
    var onConfirm: () -> Void

    func body(content: Content) -> some View {
        // 与 wellwayDialog 一致走全屏呈现：Tab 根页面（「我的」）上的浮层会被
        // 悬浮 Tab 胶囊压住，面板底部「取消」整行落在胶囊后面，点不到。
        content.fullScreenCover(isPresented: $isPresented) {
            WellwayPromptPanel(
                isPresented: $isPresented,
                title: title,
                placeholder: placeholder,
                text: $text,
                confirmTitle: confirmTitle,
                onConfirm: onConfirm
            )
        }
    }
}

/// 面板必须独占一个视图：`FocusState` 声明在呈现方时，跨
/// `fullScreenCover` 边界设置不会生效，键盘不会自动弹出。
private struct WellwayPromptPanel: View {
    @Binding var isPresented: Bool
    var title: String
    var placeholder: String
    @Binding var text: String
    var confirmTitle: String
    var onConfirm: () -> Void

    /// 弹窗唯一目的就是改名：出现即聚焦，省掉一次点击。
    @FocusState private var fieldFocused: Bool
    @State private var didAutoFocus = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            panel
        }
        .presentationBackground(.clear)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Theme.separator)
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 16)

            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            TextField(placeholder, text: $text)
                .focused($fieldFocused)
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Theme.lightField)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 18)

            Button {
                dismiss()
                onConfirm()
            } label: {
                Text(confirmTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(SolidPressStyle())
            .padding(.top, 18)

            Rectangle()
                .fill(Theme.separator)
                .frame(height: 1)
                .padding(.top, 6)

            Button {
                dismiss()
            } label: {
                Text("取消")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(SolidPressStyle())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                .fill(Color.white)
                .ignoresSafeArea(edges: .bottom)
        }
        .task {
            guard !didAutoFocus else { return }
            didAutoFocus = true
            // 等全屏转场落位后再聚焦，否则首帧设置会被键盘服务忽略。
            try? await Task.sleep(for: .milliseconds(450))
            fieldFocused = true
        }
    }

    private func dismiss() {
        isPresented = false
    }
}

extension View {
    /// 带输入框的 App 内弹窗(替代系统 TextField alert)
    func wellwayPrompt(
        isPresented: Binding<Bool>,
        title: String,
        placeholder: String,
        text: Binding<String>,
        confirmTitle: String = "保存",
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(
            WellwayPromptModifier(
                isPresented: isPresented,
                title: title,
                placeholder: placeholder,
                text: text,
                confirmTitle: confirmTitle,
                onConfirm: onConfirm
            )
        )
    }
}
