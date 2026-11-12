import AVFoundation
import SwiftUI
import UIKit

/// 路线卡主视觉：16:9 循环播放的地图动画。
///
/// 使用 `AVPlayerLayer` 而不是 `VideoPlayer`，避免系统播放控件出现在卡片里；
/// 本地静音视频用 `AVPlayerLooper` 无缝循环。卡片在 3D 翻折时跟随 SwiftUI 的
/// transform 一起运动，不改变原来的折叠交互。
struct RouteMapAnimationView: View {
    static let cardWidth: CGFloat = 339
    static let cardHeight: CGFloat = cardWidth * 9 / 16

    var isPlaying: Bool = true
    /// 卡片宽度(详情页按屏幕宽度自适应，默认 339 设计稿宽)
    var width: CGFloat = cardWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var height: CGFloat { width * 9 / 16 }

    var body: some View {
        ZStack {
            Color.black

            if let url = Bundle.main.url(forResource: "MapCardLoop", withExtension: "mp4") {
                // 海报垫在播放器下面：冷启动时播放器还没吐出第一帧，
                // 透出来的是同帧静态图，而不是一块纯黑。
                // 不能用「就绪回调再撤海报」：AVPlayerLooper 播放的是它自己复制的
                // item，模板 item 永远不会进 readyToPlay，回调不触发，海报会把视频盖死。
                Image("MapCardPoster")
                    .resizable()
                    .scaledToFill()
                    .allowsHitTesting(false)
                // 减弱动态效果时停在首帧：海报仍在下面兜底，不会出现黑块。
                LoopingVideoView(url: url, isPlaying: isPlaying && !reduceMotion)
            } else {
                Image("BrandMarkLight")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96)
                    .opacity(0.72)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        // 纯视觉：不解码会把资源名「MapCardPoster」念出来。
        .accessibilityHidden(true)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        context.coordinator.setPlaying(isPlaying)
        context.coordinator.configure(url: url, on: view)
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        context.coordinator.configure(url: url, on: uiView)
        context.coordinator.setPlaying(isPlaying)
    }

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        coordinator.tearDown()
        uiView.playerLayer.player = nil
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            playerLayer.videoGravity = .resizeAspectFill
            // 透明底：首帧出来之前让下面的海报透上来
            playerLayer.backgroundColor = UIColor.clear.cgColor
            playerLayer.cornerRadius = 18
            playerLayer.cornerCurve = .continuous
            playerLayer.masksToBounds = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    final class Coordinator {
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var loadedURL: URL?
        private var wantsPlayback = true

        func configure(url: URL, on view: PlayerView) {
            guard loadedURL != url || player == nil else { return }
            tearDown()

            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.isMuted = true
            player.actionAtItemEnd = .advance
            player.automaticallyWaitsToMinimizeStalling = false

            looper = AVPlayerLooper(player: player, templateItem: item)
            self.player = player
            loadedURL = url
            view.playerLayer.player = player

            if wantsPlayback {
                player.play()
            }
        }

        func setPlaying(_ playing: Bool) {
            guard wantsPlayback != playing else { return }
            wantsPlayback = playing
            if playing {
                player?.play()
            } else {
                player?.pause()
            }
        }

        func tearDown() {
            player?.pause()
            looper?.disableLooping()
            looper = nil
            player = nil
            loadedURL = nil
        }
    }
}
