import SwiftUI

/// 设计稿全页画廊：把 Figma 全部页面 1:1 静态还原，供验收与后续逐页接入逻辑
struct DesignGalleryView: View {
    private let screens = DesignGallery.allScreens

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(screens) { screen in
                        NavigationLink {
                            DesignScreenPreview(screen: screen)
                        } label: {
                            VStack(spacing: 6) {
                                Image(uiImage: screen.image)
                                    .resizable()
                                    .aspectRatio(375 / 812, contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Theme.cardStroke, lineWidth: 1)
                                    )
                                Text(screen.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.black)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Color(red: 0xf7/255, green: 0xf7/255, blue: 0xf8/255))
            .navigationTitle("设计稿页面")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// 全屏 1:1 预览(等宽缩放适配屏幕)
struct DesignScreenPreview: View {
    let screen: DesignScreen
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: screen.image)
                .resizable()
                .aspectRatio(375 / 812, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(12)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(screen.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }
}

/// 设计稿页面清单(从 Resources/DesignScreens 加载，mapping.json 提供中文名)
struct DesignScreen: Identifiable {
    let id: String
    let name: String
    var image: UIImage {
        guard let url = bundleURL(id, ext: "png") else {
            debugLog("image url nil:", id)
            return UIImage()
        }
        guard let img = UIImage(contentsOfFile: url.path) else {
            debugLog("UIImage load failed:", id, "path:", url.path)
            return UIImage()
        }
        return img
    }
}

/// 兼容两种打包方式：DesignScreens 子目录 或 展平到 Bundle 根目录
private func bundleURL(_ name: String, ext: String) -> URL? {
    if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "DesignScreens") {
        return url
    }
    return Bundle.main.url(forResource: name, withExtension: ext)
}

private func debugLog(_ items: Any...) {
    let msg = "[DesignGallery] " + items.map { String(describing: $0) }.joined(separator: " ")
    #if DEBUG
    print(msg)
    #endif
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let logURL = docs.appendingPathComponent("gallery_debug.log")
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile()
        h.write((msg + "\n").data(using: .utf8)!)
        try? h.close()
    } else {
        try? (msg + "\n").data(using: .utf8)?.write(to: logURL)
    }
}

enum DesignGallery {
    static let allScreens: [DesignScreen] = {
        let url = bundleURL("mapping", ext: "json")
        debugLog("mapping url:", url as Any)
        guard let url, let data = try? Data(contentsOf: url) else {
            debugLog("mapping data load failed, bundle path:", Bundle.main.bundlePath)
            return []
        }
        debugLog("mapping data bytes:", data.count)
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let map = obj as? [String: String] else {
            debugLog("mapping JSON parse failed")
            return []
        }
        debugLog("mapping entries:", map.count)
        return map.sorted { $0.key < $1.key }.map { key, name in
            DesignScreen(id: (key as NSString).deletingPathExtension, name: name)
        }
    }()
}
