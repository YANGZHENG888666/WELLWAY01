import SwiftUI

/// 品牌标识(登录/注册/登录成功页):方形徽标 + 好路当骑 同行当悉
/// textCenterY:文字中心保持设计稿 Y,slogan 相对 logo 下移，logo 自动排在文字上方
struct BrandMarkView: View {
    var textCenterY: CGFloat
    var logoWidth: CGFloat = 48
    var centerX: CGFloat = 187.5

    /// BrandMarkFull 资源为方形徽标
    private var logoHeight: CGFloat { logoWidth }
    /// slogan 单行高(24pt 粗体)
    private let textHeight: CGFloat = 34

    var body: some View {
        VStack(spacing: 12) {
            Image("BrandMarkFull")
                .resizable()
                .scaledToFit()
                .frame(width: logoWidth, height: logoHeight)
                .accessibilityHidden(true)
            Text("好路当骑 同行当悉")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .frame(width: 280, height: textHeight)
                .offset(y: 6)
        }
        .frame(width: max(logoWidth, 280), height: logoHeight + 12 + textHeight)
        .position(x: centerX, y: textCenterY - (logoHeight + 12) / 2)
    }
}
