#!/usr/bin/env python3
"""生成「出发」Tab 图标(1x/2x/3x PNG)。

源文件:第五版logo反色.svg —— 深墨(#101115)实心标。App 的 Tab 栏是白底
(RootView 里 UITabBarAppearance.backgroundColor = .white),白底上直接铺这只
深墨标就是对的;之前用「浅底版」(第五版logo.svg)只剩一圈深色线框,所以看着不对。

未选中 / 选中两个状态用同一张图:不做旋转等点击变换。

处理细节:
1. 去掉 Illustrator 残留的青色(aqua)投影滤镜(反色版 cls-3 上挂了 drop-shadow),
   否则拍平成墨后会多出一圈半透明灰影。
2. 浅底(米白 #EFEEEA / 白)算「没墨」拍平成透明,只留深墨,留白按墨迹算 => 不裁切。
3. 墨迹水平居中、底边与其它 4 个 Tab 图标同一条基线(29.5pt),等比缩放。

用法:
    python3 tools/make_tab_depart_icon.py [logo.svg]

默认 logo: /Users/young/wellway/第五版logo/第五版logo反色.svg
"""
import base64, json, os, re, sys, tempfile
import numpy as np
from PIL import Image
from playwright.sync_api import sync_playwright

CANVAS_PT = 30.0        # 画布尺寸(与其它 tab 图标一致)
SLOT_W_PT = 24.0        # 墨迹最大宽度
SLOT_H_PT = 23.5        # 墨迹最大高度
BASELINE_PT = 29.5      # 墨迹底边(其它 tab 图标底边在 30,留 0.5pt 防尖端贴边)
CENTER_X_PT = 15.0      # 墨迹水平中心
INK_RGB = (0x10, 0x11, 0x15)  # 品牌深墨 #101115
WHITE_LUM = 240         # 米白垫色(#EFEEEA 亮度约 238)及以上算「没墨」
RENDER_BOX = 1000       # 源 SVG 渲染分辨率

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "..", "WELLWAY", "Resources", "Assets.xcassets")
DEFAULT_SVG = "/Users/young/wellway/第五版logo/第五版logo反色.svg"
SET_NAME = "TabDepart"


def strip_filters(svg: str) -> str:
    """去掉滤镜(青色投影残留),避免拍平成墨时多出一圈灰影。"""
    svg = re.sub(r"<filter\b.*?</filter>", "", svg, flags=re.S)
    svg = re.sub(r"\s*filter:\s*url\([^)]*\);", "", svg)
    return svg


def render_svg(svg: str, box: int, out_png: str):
    raw = strip_filters(open(svg, encoding="utf-8").read())
    vb = re.search(r'viewBox="([\d.\s]+)"', raw).group(1).split()
    vw, vh = float(vb[2]), float(vb[3])
    w, h = (box, box * vh / vw) if vw >= vh else (box * vw / vh, box)
    b64 = base64.b64encode(raw.encode()).decode()
    html = (
        f'<html><body style="margin:0;width:{box}px;height:{box}px;background:transparent">'
        f'<img src="data:image/svg+xml;base64,{b64}" style="position:absolute;'
        f'left:{(box-w)/2}px;top:{(box-h)/2}px;width:{w}px;height:{h}px"></body></html>'
    )
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": box, "height": box})
        pg.set_content(html)
        pg.screenshot(path=out_png, omit_background=True)
        b.close()


def alpha(im: Image.Image) -> np.ndarray:
    return np.array(im)[:, :, 3].astype(float)


def flatten_to_ink(im: Image.Image) -> Image.Image:
    """把 logo 压成「深墨 + 透明」:浅底垫色 = 透明,只留看得见的墨。"""
    bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
    lum = np.array(Image.alpha_composite(bg, im).convert("L")).astype(float)
    ink_lum = float(np.dot(INK_RGB, (0.299, 0.587, 0.114)))
    a = np.clip((WHITE_LUM - lum) / (WHITE_LUM - ink_lum), 0.0, 1.0)
    out = np.zeros((im.height, im.width, 4), dtype=np.uint8)
    out[:, :, 0], out[:, :, 1], out[:, :, 2] = INK_RGB
    out[:, :, 3] = (a * 255).round().astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def bbox(im: Image.Image):
    ys, xs = np.where(alpha(im) > 8)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def emit(im: Image.Image, vis, scale_k: float, name: str):
    """按 scale_k(pt/px) 缩放:墨迹水平中心落 CENTER_X_PT、底边落 BASELINE_PT。"""
    out = os.path.join(ASSETS, name + ".imageset")
    os.makedirs(out, exist_ok=True)
    vx0, vy0, vx1, vy1 = vis
    vcx, vby = (vx0 + vx1) / 2, vy1
    files = {}
    for s in (1, 2, 3):
        r = im.resize((max(1, round(im.width * scale_k * s)),
                       max(1, round(im.height * scale_k * s))), Image.LANCZOS)
        canvas = Image.new("RGBA", (round(CANVAS_PT * s),) * 2, (0, 0, 0, 0))
        px = round(CENTER_X_PT * s - vcx * scale_k * s)
        py = round(BASELINE_PT * s - vby * scale_k * s)
        canvas.paste(r, (px, py), r)
        fn = "tabdepart.png" if s == 1 else f"tabdepart@{s}x.png"
        canvas.save(os.path.join(out, fn))
        files[s] = fn
        x0, y0, x1, y1 = bbox(canvas)
        n = canvas.size[0]
        print(f"  {name} @{s}x 墨迹 x{x0}-{x1 - 1} y{y0}-{y1 - 1}"
              f"  留白 L{x0} R{n - 1 - (x1 - 1)} T{y0} B{n - 1 - (y1 - 1)}")
    json.dump({
        "images": [{"filename": files[s], "idiom": "universal", "scale": f"{s}x"} for s in (1, 2, 3)],
        "info": {"author": "xcode", "version": 1},
    }, open(os.path.join(out, "Contents.json"), "w"), indent=2)


def make_set(src_png: str):
    img = flatten_to_ink(Image.open(src_png).convert("RGBA"))
    vis = bbox(img)
    w, h = vis[2] - vis[0], vis[3] - vis[1]
    k = min(SLOT_W_PT / w, SLOT_H_PT / h)
    print(f"wrote {SET_NAME}: 墨迹 {w * k:.1f}x{h * k:.1f}pt")
    emit(img, vis, k, SET_NAME)
    print(f"缩放 k={k:.5f} pt/px")


def main():
    svg = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SVG
    tmp = tempfile.mktemp(suffix=".png")
    render_svg(svg, RENDER_BOX, tmp)
    make_set(tmp)
    print("source:", svg)


if __name__ == "__main__":
    main()
