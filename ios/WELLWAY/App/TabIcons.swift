import SwiftUI
import UIKit

/// 设计稿 Tab Bar 图标(Figma「Tab Bar」292:36),形状与 Figma 逐点一致。
/// 通过 UIImage + template 渲染，让系统 Tab Bar 自动处理选中/未选中着色。
enum TabIcons {
    // MARK: - 路径数据(Figma export_svg 原样)

    /// 首页：U 形描边(26x25,stroke 2)
    private static let homePathD = "M1 25V1H25V25"

    /// 队伍：双人形(每个 17x21,第二个 x+9)
    private static let person17D = "M8.4975 0C11.2648 0 13.5017 2.24 13.5017 5C13.5017 7.76 11.2648 10 8.4975 10C5.73517 10 3.49327 7.76 3.49327 5C3.49327 2.24 5.73517 0 8.4975 0ZM8.4975 2C6.8411 2 5.49496 3.345 5.49496 5C5.49496 6.655 6.8411 8 8.4975 8C10.1589 8 11.5 6.655 11.5 5C11.5 3.345 10.1589 2 8.4975 2ZM8.4975 11.5C13.6468 11.5 16.8345 14.995 16.9997 20C17.0097 20.275 16.7845 20.5 16.5043 20.5H15.5034C15.2282 20.5 15.008 20.275 14.998 20C14.8479 16.08 12.5459 13.5 8.4975 13.5C4.45408 13.5 2.15214 16.08 2.00201 20C1.992 20.275 1.77182 20.5 1.49158 20.5H0.490735C0.215503 20.5 -0.00968723 20.275 0.000321225 20C0.165461 14.995 3.35315 11.5 8.4975 11.5Z"

    /// 热力轨迹：指南针(22x22,evenodd 环形 + 指针)
    private static let compassRingD = "M11 19.9375C15.936 19.9375 19.9375 15.936 19.9375 11C19.9375 6.06396 15.936 2.0625 11 2.0625C6.06396 2.0625 2.0625 6.06396 2.0625 11C2.0625 15.936 6.06396 19.9375 11 19.9375ZM22 11C22 17.0751 17.0751 22 11 22C4.92487 22 0 17.0751 0 11C0 4.92487 4.92487 0 11 0C17.0751 0 22 4.92487 22 11Z"
    private static let compassNeedleD = "M13.0896 13.1212C13.4107 12.927 13.6351 12.6065 13.7078 12.2384L14.9351 6.0176C15.0024 5.67675 14.633 5.41811 14.3357 5.59788L8.90991 8.87887C8.58879 9.07305 8.36436 9.39356 8.29172 9.76172L7.06435 15.9825C6.9971 16.3233 7.36647 16.582 7.66376 16.4022L13.0896 13.1212ZM9.72745 12.8171L11.8026 11.5622L12.272 9.18302L10.1969 10.4379L9.72745 12.8171Z"

    /// 个人中心：单人人像(24x24)
    private static let person24D = "M11.9975 2C14.7648 2 17.0017 4.24 17.0017 7C17.0017 9.76 14.7648 12 11.9975 12C9.23517 12 6.99327 9.76 6.99327 7C6.99327 4.24 9.23517 2 11.9975 2ZM11.9975 4C10.3411 4 8.99496 5.345 8.99496 7C8.99496 8.655 10.3411 10 11.9975 10C13.6589 10 15 8.655 15 7C15 5.345 13.6589 4 11.9975 4ZM11.9975 13.5C17.1468 13.5 20.3345 16.995 20.4997 22C20.5097 22.275 20.2845 22.5 20.0043 22.5H19.0034C18.7282 22.5 18.508 22.275 18.498 22C18.3479 18.08 16.0459 15.5 11.9975 15.5C7.95408 15.5 5.65214 18.08 5.50201 22C5.492 22.275 5.27182 22.5 4.99158 22.5H3.99074C3.7155 22.5 3.49031 22.275 3.50032 22C3.66546 16.995 6.85315 13.5 11.9975 13.5Z"

    // MARK: - 渲染

    /// 统一画布 30x30pt:四周留白，防描边/抗锯齿被裁切
    private static let canvas = CGSize(width: 30, height: 30)
    /// 所有 Tab 图标共用同一视觉槽：26pt 宽 x 24pt 高，水平居中、底部对齐
    private static let slot = CGRect(x: 2, y: 6, width: 26, height: 24)

    /// 把 path 的视觉 bbox 等比缩放后平移到 slot 内(水平居中、底部对齐)
    private static func fitTransform(forVisual bbox: CGRect) -> CGAffineTransform {
        let s = min(slot.width / bbox.width, slot.height / bbox.height)
        return CGAffineTransform(scaleX: s, y: s)
            .concatenating(CGAffineTransform(translationX: slot.midX - bbox.midX * s,
                                             y: slot.maxY - bbox.maxY * s))
    }

    static let home = makeImage(trim: 0.17) { c in
        let p = SVGPathParser.bezierPath(from: homePathD)
        // 描边 2pt 居中于路径，视觉 bbox 外扩 1pt
        let tf = fitTransform(forVisual: p.cgPath.boundingBox.insetBy(dx: -1, dy: -1))
        var t = tf
        c.setStrokeColor(UIColor.black.cgColor)
        c.setLineWidth(2 * tf.a)
        c.addPath(p.cgPath.copy(using: &t)!)
        c.strokePath()
        // Pit 文字跟随 U 形同比例缩放，保持 Figma 相对位置(Figma 文字中心 12,12.5)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11 * tf.a, weight: .semibold),
            .foregroundColor: UIColor.black,
            .kern: -1 * tf.a,
        ]
        let s = NSAttributedString(string: "Pit", attributes: attrs)
        let sz = s.size()
        let center = CGPoint(x: 12, y: 12.5).applying(tf)
        s.draw(at: CGPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2))
    }

    /// 线宽统一：第 3 个 Tab 是用户定稿的品牌 logo(TabDepart,实测笔画 1.65pt),
    /// 其它 4 个 Figma 图标原始笔画 2.0~2.7pt 各不相同，这里按各自的原始线宽
    /// 收细到同一重量(trim = 每边收细的 pt 数；收细后 4 只实测均为 1.67pt)。
    static let team = makeImage(trim: 0.28) { c in
        let p1 = SVGPathParser.bezierPath(from: person17D)
        let p2 = SVGPathParser.bezierPath(from: person17D)
        p2.apply(CGAffineTransform(translationX: 9, y: 0))
        let tf = fitTransform(forVisual: p1.cgPath.boundingBox.union(p2.cgPath.boundingBox))
        p1.apply(tf)
        p2.apply(tf)
        fill(c, [p1, p2])
    }

    static let compass = makeImage(trim: 0.39) { c in
        let ring = SVGPathParser.bezierPath(from: compassRingD)
        let needle = SVGPathParser.bezierPath(from: compassNeedleD)
        let tf = fitTransform(forVisual: ring.cgPath.boundingBox.union(needle.cgPath.boundingBox))
        ring.apply(tf)
        needle.apply(tf)
        c.addPath(ring.cgPath)
        c.fillPath(using: .evenOdd)
        c.addPath(needle.cgPath)
        c.fillPath(using: .evenOdd)
    }

    static let person = makeImage(trim: 0.46) { c in
        let p = SVGPathParser.bezierPath(from: person24D)
        let tf = fitTransform(forVisual: p.cgPath.boundingBox)
        p.apply(tf)
        fill(c, [p])
    }

    private static func makeImage(trim: CGFloat = 0, draw: (CGContext) -> Void) -> UIImage {
        let hi = UIGraphicsImageRendererFormat()
        hi.scale = 6          // 先按 6x 画，才够精度做亚像素收细
        hi.opaque = false
        var image = UIGraphicsImageRenderer(size: canvas, format: hi).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor.black.cgColor)
            draw(c)
        }
        if trim > 0 { image = trimAlpha(image, radiusPt: trim) }
        let lo = UIGraphicsImageRendererFormat()
        lo.scale = 3
        lo.opaque = false
        return UIGraphicsImageRenderer(size: canvas, format: lo).image { _ in
            image.draw(in: CGRect(origin: .zero, size: canvas))
        }
    }

    /// 按半径 r(pt/边)把线条整体收细：先求到背景的 chamfer 距离场(5/7 权重，单位 1/5px),
    /// 再按 r 截断 alpha,边界 0.6px 线性过渡做反锯齿。
    /// 图形是黑色的，预乘后 RGB 恒为 0,只改 alpha 即可。
    private static func trimAlpha(_ image: UIImage, radiusPt: CGFloat) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let w = cg.width, h = cg.height
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let srcCtx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                     bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return image }
        srcCtx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // 距离场：笔画内为到最近背景像素的距离，背景为 0
        let far = Int32(w + h) * 5
        var dist = [Int32](repeating: 0, count: w * h)
        for i in 0..<(w * h) where buf[i * 4 + 3] > 100 { dist[i] = far }

        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                guard dist[i] > 0 else { continue }
                var v = dist[i]
                if y > 0 {
                    v = min(v, dist[i - w] + 5)
                    if x > 0 { v = min(v, dist[i - w - 1] + 7) }
                    if x < w - 1 { v = min(v, dist[i - w + 1] + 7) }
                }
                if x > 0 { v = min(v, dist[i - 1] + 5) }
                dist[i] = v
            }
        }
        for y in stride(from: h - 1, through: 0, by: -1) {
            for x in stride(from: w - 1, through: 0, by: -1) {
                let i = y * w + x
                guard dist[i] > 0 else { continue }
                var v = dist[i]
                if y < h - 1 {
                    v = min(v, dist[i + w] + 5)
                    if x > 0 { v = min(v, dist[i + w - 1] + 7) }
                    if x < w - 1 { v = min(v, dist[i + w + 1] + 7) }
                }
                if x < w - 1 { v = min(v, dist[i + 1] + 5) }
                dist[i] = v
            }
        }

        // 6x 渲染 → 1pt = 6px,距离场单位 1/5px
        let edge = Double(radiusPt) * 30
        for i in 0..<(w * h) {
            let a = Int(buf[i * 4 + 3])
            let d = Double(dist[i]) - edge          // >0 表示仍在目标笔画内
            let out: Int
            if d >= 3 { out = 255 }
            else if d <= -3 { out = 0 }
            else { out = Int(((d + 3) / 6 * 255).rounded()) }
            buf[i * 4] = 0
            buf[i * 4 + 1] = 0
            buf[i * 4 + 2] = 0
            buf[i * 4 + 3] = UInt8(min(a, out))
        }

        let outCG: CGImage? = buf.withUnsafeMutableBytes { raw in
            guard let outCtx = CGContext(data: raw.baseAddress, width: w, height: h,
                                         bitsPerComponent: 8, bytesPerRow: w * 4,
                                         space: space, bitmapInfo: info) else { return nil }
            return outCtx.makeImage()
        }
        guard let cgOut = outCG else { return image }
        return UIImage(cgImage: cgOut, scale: image.scale, orientation: .up)
    }

    private static func fill(_ c: CGContext, _ paths: [UIBezierPath]) {
        for p in paths {
            c.addPath(p.cgPath)
            c.fillPath(using: .winding)
        }
    }

}

/// 极简 SVG path 解析器：支持 M/L/H/V/C/Z 及小写相对写法、隐式重复参数、科学计数法。
enum SVGPathParser {
    static func bezierPath(from d: String) -> UIBezierPath {
        var path = UIBezierPath()
        let pattern = "[MmZzLlHhVvCcSsQqTtAa]|[-+]?(?:\\d*\\.\\d+|\\d+\\.?)(?:[eE][-+]?\\d+)?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return path }
        let ns = d as NSString
        let matches = regex.matches(in: d, range: NSRange(location: 0, length: ns.length))
        var tokens: [String] = []
        for m in matches {
            tokens.append(ns.substring(with: m.range))
        }
        var i = 0
        var cur = CGPoint.zero
        var start = CGPoint.zero
        func isLetter(_ t: String) -> Bool { t.count == 1 && t.first!.isLetter }
        func nextNum() -> CGFloat {
            defer { i += 1 }
            return CGFloat(Double(tokens[i])!)
        }
        var cmd: Character = " "
        var lastCtrl: CGPoint? // S/s 平滑曲线的反射控制点

        while i < tokens.count {
            if isLetter(tokens[i]) {
                cmd = Character(tokens[i]); i += 1
            }
            switch cmd {
            case "M", "m":
                guard i < tokens.count, !isLetter(tokens[i]) else { cmd = " "; continue }
                let x = nextNum(), y = nextNum()
                let p = cmd == "m" ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
                path.move(to: p)
                cur = p; start = p
                cmd = cmd == "M" ? "L" : "l"
            case "L", "l":
                guard i < tokens.count, !isLetter(tokens[i]) else { cmd = " "; continue }
                let x = nextNum(), y = nextNum()
                let p = cmd == "l" ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
                path.addLine(to: p); cur = p
            case "H", "h":
                guard i < tokens.count, !isLetter(tokens[i]) else { cmd = " "; continue }
                let x = nextNum()
                cur = cmd == "h" ? CGPoint(x: cur.x + x, y: cur.y) : CGPoint(x: x, y: cur.y)
                path.addLine(to: cur)
            case "V", "v":
                guard i < tokens.count, !isLetter(tokens[i]) else { cmd = " "; continue }
                let y = nextNum()
                cur = cmd == "v" ? CGPoint(x: cur.x, y: cur.y + y) : CGPoint(x: cur.x, y: y)
                path.addLine(to: cur)
            case "C", "c":
                guard i < tokens.count, !isLetter(tokens[i]) else { cmd = " "; continue }
                let x1 = nextNum(), y1 = nextNum(), x2 = nextNum(), y2 = nextNum(), x3 = nextNum(), y3 = nextNum()
                let p0 = cur
                let p1 = cmd == "c" ? CGPoint(x: p0.x + x1, y: p0.y + y1) : CGPoint(x: x1, y: y1)
                let p2 = cmd == "c" ? CGPoint(x: p0.x + x2, y: p0.y + y2) : CGPoint(x: x2, y: y2)
                let p3 = cmd == "c" ? CGPoint(x: p0.x + x3, y: p0.y + y3) : CGPoint(x: x3, y: y3)
                path.addCurve(to: p3, controlPoint1: p1, controlPoint2: p2)
                lastCtrl = p2
                cur = p3
            case "S", "s":
                guard i < tokens.count, !isLetter(tokens[i]) else { cmd = " "; continue }
                let x2 = nextNum(), y2 = nextNum(), x3 = nextNum(), y3 = nextNum()
                let p0 = cur
                let p1: CGPoint
                if let lc = lastCtrl {
                    p1 = CGPoint(x: 2 * p0.x - lc.x, y: 2 * p0.y - lc.y)
                } else {
                    p1 = p0
                }
                let p2 = cmd == "s" ? CGPoint(x: p0.x + x2, y: p0.y + y2) : CGPoint(x: x2, y: y2)
                let p3 = cmd == "s" ? CGPoint(x: p0.x + x3, y: p0.y + y3) : CGPoint(x: x3, y: y3)
                path.addCurve(to: p3, controlPoint1: p1, controlPoint2: p2)
                lastCtrl = p2
                cur = p3
            case "A", "a":
                guard i < tokens.count, !isLetter(tokens[i]) else { cmd = " "; continue }
                let rx = nextNum(), ry = nextNum(), rot = nextNum()
                let largeArc = nextNum() != 0, sweep = nextNum() != 0
                let x = nextNum(), y = nextNum()
                let target = cmd == "a" ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
                addArc(to: &path, from: cur, to: target, rx: rx, ry: ry, rotation: rot, largeArc: largeArc, sweep: sweep)
                lastCtrl = nil
                cur = target
            case "Z", "z":
                path.close()
                cur = start
                cmd = " "
            default:
                cmd = " "
                lastCtrl = nil
            }
            if cmd == " ", i < tokens.count, !isLetter(tokens[i]) {
                i += 1
            }
        }
        return path
    }

    /// SVG 椭圆弧(A/a)→ 三次贝塞尔，按 W3C 算法(端点→中心参数化)
    private static func addArc(to path: inout UIBezierPath, from p0: CGPoint, to p1: CGPoint, rx: CGFloat, ry: CGFloat, rotation: CGFloat, largeArc: Bool, sweep: Bool) {
        guard p0 != p1, rx > 0, ry > 0 else { return }
        var rx = abs(rx), ry = abs(ry)
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        let lambda = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s
            ry *= s
        }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coef = (largeArc == sweep ? -1.0 : 1.0) * sqrt(max(0, num) / max(den, 0.000001))
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func vectorAngle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = max(hypot(ux, uy) * hypot(vx, vy), 0.000001)
            var a = acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }

        let theta1 = vectorAngle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var deltaTheta = vectorAngle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && deltaTheta > 0 { deltaTheta -= 2 * .pi }
        else if sweep && deltaTheta < 0 { deltaTheta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(deltaTheta) / (.pi / 2))))
        let delta = deltaTheta / CGFloat(segments)
        let t = tan(delta / 2)
        let alpha = sin(delta) * (sqrt(4 + 3 * t * t) - 1) / 3

        var theta = theta1
        for _ in 0..<segments {
            let theta2 = theta + delta
            let c1x = cos(theta), c1y = sin(theta)
            let c2x = cos(theta2), c2y = sin(theta2)
            let px1 = cx + rx * c1x * cosPhi - ry * c1y * sinPhi
            let py1 = cy + rx * c1x * sinPhi + ry * c1y * cosPhi
            let px2 = cx + rx * c2x * cosPhi - ry * c2y * sinPhi
            let py2 = cy + rx * c2x * sinPhi + ry * c2y * cosPhi
            let qx1 = px1 + alpha * (-rx * c1x * sinPhi - ry * c1y * cosPhi)
            let qy1 = py1 + alpha * (-rx * c1x * cosPhi + ry * c1y * sinPhi)
            let qx2 = px2 - alpha * (-rx * c2x * sinPhi - ry * c2y * cosPhi)
            let qy2 = py2 - alpha * (-rx * c2x * cosPhi + ry * c2y * sinPhi)
            path.addCurve(to: CGPoint(x: px2, y: py2), controlPoint1: CGPoint(x: qx1, y: qy1), controlPoint2: CGPoint(x: qx2, y: qy2))
            theta = theta2
        }
    }
}
