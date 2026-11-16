import SwiftUI
import UIKit

/// SwiftUI `Menu` 在 iOS 26 的辅助功能树里会额外暴露一个无标签按钮，
/// 把标签挂到 `Menu` 外层只会再加一条带名称节点，空按钮仍然保留。
/// 这里用系统 `UIButton` 承载 `UIMenu`：视觉仍是原生下拉菜单，
/// 但辅助功能只暴露一个带名称、带提示的按钮。
struct AccessibleFilterMenu: UIViewRepresentable {
    let title: String
    let accessibilityLabel: String
    let accessibilityHint: String
    let fontSize: CGFloat
    let fontWeight: UIFont.Weight
    let color: Color
    let menu: UIMenu

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.configuration = .plain()
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        let uiColor = UIColor(color)
        var configuration = button.configuration ?? .plain()
        configuration.contentInsets = .zero
        configuration.image = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        )
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 4
        configuration.baseForegroundColor = uiColor

        var attributedTitle = AttributedString(title)
        attributedTitle.font = UIFont.systemFont(ofSize: fontSize, weight: fontWeight)
        attributedTitle.foregroundColor = uiColor
        configuration.attributedTitle = attributedTitle

        button.configuration = configuration
        button.menu = menu
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityHint = accessibilityHint
        button.accessibilityTraits = .button
    }
}
