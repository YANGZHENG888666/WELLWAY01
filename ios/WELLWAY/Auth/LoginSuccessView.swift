import SwiftUI

/// 登录成功页(Figma「登录成功页」screen_43):白底 + 品牌 + 黑色「进入」文本按钮
/// 布局：WELL WAY / 好路当骑 同行当悉 24pt 粗体居中(y≈295/330),「进入」15pt 居中(y≈550)
struct LoginSuccessView: View {
    var onEnter: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                Image("BrandMarkFull")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .accessibilityHidden(true)
                Text("好路当骑 同行当悉")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.center)
            }
            .motionAppear(delay: 0.05)

            Text("账号已就绪，开始你的骑行")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .padding(.top, 14)
                .motionAppear(delay: 0.18)

            Spacer()

            Button(action: onEnter) {
                Text("进入 WellWay")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(SolidPressStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .motionAppear(delay: 0.35)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .pageMark(21)
    }

}
