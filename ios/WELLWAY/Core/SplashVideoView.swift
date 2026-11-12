import SwiftUI

/// 开屏动画(黑底品牌标):白色品牌标放大进场 → 回落定格，
/// 随后 WellWay 字标淡入停留，整体淡出后回调 onFinish。
struct SplashView: View {
    let onFinish: () -> Void

    /// 与启动图一致的纯黑，避免首帧闪色
    private let background = Color.black
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var markScale: CGFloat = 0.82
    @State private var markOpacity: Double = 0
    @State private var wordOpacity: Double = 0
    @State private var wordOffset: CGFloat = 14
    @State private var shown = true

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 26) {
                Image("BrandMarkLight")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 118)
                    .scaleEffect(markScale)
                    .opacity(markOpacity)

                Image("Wordmark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.white)
                    .frame(width: 232)
                    .opacity(wordOpacity)
                    .offset(y: wordOffset)
            }
        }
        .opacity(shown ? 1 : 0)
        // 状态栏外观由 RootView 统一控制（showSplash 期间切深色）；
        // 这里再声明 preferredColorScheme 不会生效，只会让人误以为已处理。
        .onAppear {
            // 黑底需要白字状态栏；RootView 只认 ScreenAppearance 这一个真源，
            // SplashView 自己的 preferredColorScheme 不会生效。
            ScreenAppearance.shared.push(.dark)
            play()
        }
        .onDisappear { ScreenAppearance.shared.pop(.dark) }
    }

    private func play() {
        if reduceMotion {
            // 减弱动态效果：只做淡入，品牌标不放大、不回落，字标不上移。
            markScale = 1
            wordOffset = 0
            withAnimation(.easeOut(duration: 0.32)) {
                markOpacity = 1
                wordOpacity = 1
            }
        } else {
            withAnimation(.easeOut(duration: 0.32)) {
                markOpacity = 1
            }
            withAnimation(.spring(response: 0.62, dampingFraction: 0.74)) {
                markScale = 1.10
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
                withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) {
                    markScale = 1.0
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.64) {
                withAnimation(.easeOut(duration: 0.45)) {
                    wordOpacity = 1
                    wordOffset = 0
                }
            }
        }

        // 品牌记忆点保留约 1 秒即可；总时长控制在 2 秒内，避免每次冷启动都像在等广告。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.62) {
            withAnimation(.easeInOut(duration: 0.3)) { shown = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onFinish()
            }
        }
    }
}
