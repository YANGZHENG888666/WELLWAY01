import CoreMotion
import Observation
import SwiftUI

/// WELL WAY 动效规范(黑白云淡雅风格，参照 motion-design 的 Premium 档位):
/// - 入场：淡入 + 上浮 14pt + 微缩放 0.98→1,spring(response 0.42, damping 0.85)
/// - 按压反馈：scale 0.96,spring(response 0.22, damping 0.55)
/// - 错峰：列表项按 index * 0.06 递增 delay,总延迟控制在 0.5s 内
/// - 无障碍：开启「减弱动态效果」时只淡入，不做位移/缩放
enum Motion {
    /// 入场弹簧(柔和收尾，无明显过冲)
    static let appear = Animation.spring(response: 0.42, dampingFraction: 0.85)
    /// 按压弹簧(干脆)
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.55)
    /// 列表错峰步长
    static let stagger: Double = 0.06
}

// MARK: - 入场

private struct MotionAppearModifier: ViewModifier {
    var delay: Double
    var rise: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: reduceMotion || appeared ? 0 : rise)
            .scaleEffect(reduceMotion || appeared ? 1 : 0.98)
            .onAppear {
                guard !appeared else { return }
                withAnimation(Motion.appear.delay(delay)) { appeared = true }
            }
    }
}

// MARK: - 按压反馈

private struct MotionPressModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1 : (pressed ? 0.96 : 1))
            .animation(Motion.press, value: pressed)
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 24) {
            } onPressingChanged: { isPressing in
                pressed = isPressing
            }
    }
}

// MARK: - 卡片按压样式

/// 可点卡片的按压反馈。用 ButtonStyle 而不是手势：Button 自己管 pressed 状态，
/// 不会和内部的点击、外层的滚动抢手势（`onLongPressGesture` 版本在嵌套按钮里会拖慢点击）。
struct CardPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        CardPressBody(configuration: configuration, scale: scale)
    }

    private struct CardPressBody: View {
        let configuration: Configuration
        let scale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : scale)
                .animation(Motion.press, value: configuration.isPressed)
        }
    }
}

/// 账簿行/整行可点列表的按压反馈：垫一层浅底，不缩放。
/// 行与行之间共用发丝线，缩放会撕裂分隔线，所以这里只做底色。
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.lightField : Color.clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 纯图标按钮（刷新、加号）的按压反馈：按下压到 35%，命中区不变。
struct IconPressStyle: ButtonStyle {
    /// 图标压到 0.35 就够明显；纯文字链用 0.5，压太狠会像被禁用。
    var pressedOpacity: Double = 0.35

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// 实心主行动的按压反馈：整块压暗一档，不缩放、不位移。
/// 主按钮此前一律 .buttonStyle(.plain)，按下没有任何变化，只在松手后跳页。
struct SolidPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 整块可点、但内部还嵌着子按钮的数据块（如油价三档）：
/// 用 Button 包起来会吞掉子按钮的点击，所以这里只垫底色，不接管手势。
struct TilePressHighlight: ViewModifier {
    @State private var pressed = false

    func body(content: Content) -> some View {
        content
            .background(pressed ? Theme.lightField : Color.clear)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        withAnimation(.easeOut(duration: 0.12)) { pressed = true }
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.12)) { pressed = false }
                    }
            )
    }
}

extension View {
    /// 数据块整块可点、内部还有子按钮时的按压反馈（浅底，不缩放）。
    func tilePressHighlight() -> some View {
        modifier(TilePressHighlight())
    }
}

// MARK: - 数值弹跳(用于总结页关键数字)

private struct MotionPopModifier: ViewModifier {
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false

    func body(content: Content) -> some View {
        content
            .opacity(popped ? 1 : 0)
            .scaleEffect(reduceMotion || popped ? 1 : 0.82)
            .onAppear {
                guard !popped else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.72).delay(delay)) { popped = true }
            }
    }
}

extension View {
    /// 入场动效：淡入 + 上浮 + 微缩放。列表项用 `delay: Double(index) * Motion.stagger` 错峰。
    func motionAppear(delay: Double = 0, rise: CGFloat = 14) -> some View {
        modifier(MotionAppearModifier(delay: delay, rise: rise))
    }

    /// 按压反馈：按下缩小到 0.96,松手回弹(不拦截点击)。
    func motionPress() -> some View {
        modifier(MotionPressModifier())
    }

    /// 关键数字弹跳入场(用于骑行总结等页面)。
    func motionPop(delay: Double = 0) -> some View {
        modifier(MotionPopModifier(delay: delay))
    }
}

// MARK: - 灯带跟随(陀螺仪)

/// 灯带跟随：读取重力方向，手机倾斜时高光/光锥随之偏移。
/// - 竖屏手持时 `gravity.z` 表示前后俯仰，`gravity.x` 表示左右侧倾。
/// - 模拟器没有陀螺仪：默认保持中位(0,0),加 `-tiltdemo` 启动参数可跑正弦演示。
@MainActor
@Observable
final class TiltLight {
    /// 左右偏移 -1…1(右倾为正)
    private(set) var x: CGFloat = 0
    /// 前后偏移 -1…1(上仰为正)
    private(set) var y: CGFloat = 0

    private let manager = CMMotionManager()
    private var running = false
    private var demo: Task<Void, Never>?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard !running else { return }
        running = true

        guard manager.isDeviceMotionAvailable else {
            if ProcessInfo.processInfo.arguments.contains("-tiltdemo") {
                startDemo()
            }
            return
        }

        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            let tx = max(-1, min(1, CGFloat(g.x) / 0.55))
            let ty = max(-1, min(1, CGFloat(g.z) / 0.55))
            MainActor.assumeIsolated {
                self.x += (tx - self.x) * 0.22
                self.y += (ty - self.y) * 0.22
            }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopDeviceMotionUpdates()
        demo?.cancel()
        demo = nil
        x = 0
        y = 0
    }

    private func startDemo() {
        demo = Task { @MainActor in
            var t: Double = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                t += 0.033
                self.x = CGFloat(sin(t * 0.9)) * 0.8
                self.y = CGFloat(sin(t * 1.4)) * 0.5
            }
        }
    }
}
