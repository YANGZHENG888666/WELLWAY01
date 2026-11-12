#!/usr/bin/env python3
"""生成车型库「按分类」的插画(1x/2x/3x PNG)，用于车型列表里的缩略图。

为什么要自己画：车型缩略图原本是空占位(灰底 + photo 图标)。第三方车图(汽车之家 /
摩托范)都有版权，不能直接抓进 App，所以这里按 9 个分类各画一张线稿摩托车。
墨色 #24262B、透明背景 —— 车型行里真车抠图也是透明 PNG 直接落在白卡上，
插画用同一个墨色才和真图是一套(早期是米白 #F2EFE9，只能压在深色块上，已废弃)。

model_type → 插画资源名(与后端 models.model_type 取值一一对应):
    跑车 → ModelTypeSport      街车 → ModelTypeStreet    踏板 → ModelTypeScooter
    复古 → ModelTypeRetro      巡航 → ModelTypeCruiser   ADV  → ModelTypeAdventure
    越野 → ModelTypeOffroad    旅行 → ModelTypeTouring   MINI → ModelTypeMini

真实车图后补时不用改这里：models.image_url 有值时 App 优先显示真图，没值才回落到插画。

用法:
    python3 ios/tools/make_model_type_art.py            # 生成 SVG + 资产 + 预览图
    python3 ios/tools/make_model_type_art.py --sheet    # 只出预览拼图
"""
import argparse, base64, json, os, sys
from PIL import Image
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
ASSETS = os.path.join(REPO, "ios", "WELLWAY", "Resources", "Assets.xcassets")
SVG_DIR = os.path.join(HERE, "model-art-svg")
SHEET_PATH = os.path.join(REPO, "outputs", "model-type-art", "model-type-art-preview.png")

CANVAS = 160          # 画布边长(SVG 用户单位)
STROKE = 5.0          # 统一线宽,保证 9 张看起来是一套
CONTENT = 124         # 归一化后墨迹要铺满的内容区(画布留 18 单位边距)
INK = "#24262B"       # 与 Theme.ink / 车型行墨色一致(白卡上可见)
TILE_BG = "#F5F7FA"   # 预览拼图底色(和墨色 #24262B 反着来,否则黑压黑看不清)
RENDER_PX = 640       # Playwright 渲染分辨率,再降采样到各倍率

# 每个分类的骨架:两轮 + 线稿 + 圆
#   wheels: (cx, cy, r, hub)   hub=True 时画一个轮毂小圆
#   lines:  折线点列
#   circles:(cx, cy, r) 其他圆(大灯等)
TYPES = {
    "sport": {
        "label": "跑车", "set": "ModelTypeSport",
        "wheels": [(48, 106, 18, False), (116, 106, 18, False)],
        "lines": [
            [(42, 58), (60, 55), (78, 58), (100, 62), (118, 68), (130, 78)],
            [(130, 78), (118, 92), (100, 96), (88, 96)],
            [(116, 106), (110, 70)],
            [(110, 70), (118, 73)],
            [(48, 106), (78, 96)],
            [(88, 98), (64, 94)],
            [(74, 58), (74, 68), (58, 70), (44, 62)],
        ],
        "circles": [],
    },
    "street": {
        "label": "街车", "set": "ModelTypeStreet",
        "wheels": [(48, 106, 19, False), (118, 106, 19, False)],
        "lines": [
            [(118, 106), (112, 72)],
            [(112, 70), (102, 62), (92, 64)],
            [(104, 68), (92, 60), (78, 66)],
            [(78, 66), (58, 66)],
            [(58, 66), (44, 70)],
            [(76, 80), (96, 80), (96, 98), (76, 98), (76, 80)],
            [(78, 100), (52, 96)],
            [(60, 86), (52, 70)],
        ],
        "circles": [(112, 74, 7)],
    },
    "scooter": {
        "label": "踏板", "set": "ModelTypeScooter",
        "wheels": [(50, 110, 16, False), (116, 110, 16, False)],
        "lines": [
            [(70, 118), (102, 114)],
            [(102, 114), (112, 94), (110, 78)],
            [(110, 78), (118, 72)],
            [(70, 118), (62, 88)],
            [(62, 88), (86, 86)],
            [(62, 88), (54, 108)],
        ],
        "circles": [],
    },
    "retro": {
        "label": "复古", "set": "ModelTypeRetro",
        "wheels": [(48, 106, 19, True), (118, 106, 19, True)],
        "lines": [
            [(102, 84), (118, 78), (132, 86)],
            [(34, 86), (48, 78), (64, 86)],
            [(118, 106), (114, 74)],
            [(114, 72), (104, 66)],
            [(102, 70), (90, 60), (76, 68)],
            [(76, 68), (56, 68)],
            [(56, 68), (46, 72)],
            [(62, 88), (52, 72)],
            [(70, 88), (60, 72)],
            [(78, 82), (100, 82), (100, 100), (78, 100), (78, 82)],
            [(80, 102), (54, 98)],
        ],
        "circles": [(116, 76, 8)],
    },
    "cruiser": {
        "label": "巡航", "set": "ModelTypeCruiser",
        "wheels": [(42, 108, 17, True), (128, 108, 17, True)],
        "lines": [
            [(128, 108), (122, 80)],
            [(122, 80), (116, 66), (98, 58)],
            [(106, 76), (86, 68), (70, 76)],
            [(70, 76), (50, 80)],
            [(50, 80), (36, 94)],
            [(88, 100), (46, 96)],
            [(98, 106), (108, 106)],
        ],
        "circles": [],
    },
    "adventure": {
        "label": "ADV", "set": "ModelTypeAdventure",
        "wheels": [(48, 104, 20, False), (120, 104, 20, False)],
        "lines": [
            [(120, 104), (112, 64)],
            [(124, 80), (140, 72)],
            [(112, 60), (116, 48)],
            [(110, 58), (100, 52)],
            [(102, 64), (84, 56), (70, 62)],
            [(70, 62), (50, 58)],
            [(50, 58), (38, 62)],
            [(78, 86), (102, 88)],
            [(80, 92), (58, 90)],
        ],
        "circles": [],
    },
    "offroad": {
        "label": "越野", "set": "ModelTypeOffroad",
        "wheels": [(48, 102, 20, False), (120, 102, 20, False)],
        "lines": [
            [(120, 102), (110, 52)],
            [(114, 64), (136, 54)],
            [(108, 50), (98, 42)],
            [(76, 54), (48, 52)],
            [(46, 56), (30, 64)],
            [(76, 54), (92, 68), (104, 70)],
            [(48, 102), (76, 76)],
        ],
        "circles": [],
    },
    "touring": {
        "label": "旅行", "set": "ModelTypeTouring",
        "wheels": [(48, 106, 19, False), (118, 106, 19, False)],
        "lines": [
            [(112, 70), (126, 84), (110, 98), (98, 74), (112, 70)],
            [(110, 66), (118, 48)],
            [(104, 64), (94, 60)],
            [(88, 66), (58, 66)],
            [(34, 74), (58, 74), (58, 96), (34, 96), (34, 74)],
            [(54, 50), (78, 50), (78, 66), (54, 66), (54, 50)],
            [(118, 106), (112, 72)],
            [(80, 100), (58, 98)],
        ],
        "circles": [],
    },
    "mini": {
        "label": "MINI", "set": "ModelTypeMini",
        "wheels": [(58, 112, 14, False), (114, 112, 14, False)],
        "lines": [
            [(114, 112), (110, 88)],
            [(110, 88), (102, 80)],
            [(104, 90), (94, 82), (84, 88)],
            [(84, 88), (68, 88)],
            [(68, 88), (58, 94)],
            [(88, 102), (70, 100)],
        ],
        "circles": [],
    },
}


def ink_bbox(spec: dict):
    xs, ys = [], []
    for cx, cy, r, hub in spec["wheels"]:
        xs += [cx - r, cx + r]
        ys += [cy - r, cy + r]
    for cx, cy, r in spec["circles"]:
        xs += [cx - r, cx + r]
        ys += [cy - r, cy + r]
    for line in spec["lines"]:
        for x, y in line:
            xs.append(x)
            ys.append(y)
    return min(xs), min(ys), max(xs), max(ys)


def normalize(spec: dict):
    """按墨迹包围盒把每张插画居中,并统一到同一内容宽度,让 9 张看起来是一套。"""
    x0, y0, x1, y1 = ink_bbox(spec)
    s = CONTENT / max(x1 - x0, y1 - y0)
    tx = CANVAS / 2 - s * (x0 + x1) / 2
    ty = CANVAS / 2 - s * (y0 + y1) / 2
    return s, tx, ty


def svg_text(spec: dict) -> str:
    s, tx, ty = normalize(spec)
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS} {CANVAS}" '
        f'width="{CANVAS}" height="{CANVAS}">',
        f'<g transform="translate({tx:.2f} {ty:.2f}) scale({s:.4f})" fill="none" '
        f'stroke="{INK}" stroke-width="{STROKE / s:.2f}" '
        'stroke-linecap="round" stroke-linejoin="round">',
    ]
    for cx, cy, r, hub in spec["wheels"]:
        parts.append(f'<circle cx="{cx}" cy="{cy}" r="{r}"/>')
        if hub:
            parts.append(f'<circle cx="{cx}" cy="{cy}" r="3.5"/>')
    for cx, cy, r in spec["circles"]:
        parts.append(f'<circle cx="{cx}" cy="{cy}" r="{r}"/>')
    for line in spec["lines"]:
        pts = " ".join(f"{x},{y}" for x, y in line)
        parts.append(f'<polyline points="{pts}"/>')
    parts.append("</g></svg>")
    return "\n".join(parts)


def render_svg_png(svg: str, px: int, out_png: str):
    b64 = base64.b64encode(svg.encode()).decode()
    html = (
        f'<html><body style="margin:0;width:{px}px;height:{px}px;background:transparent">'
        f'<img src="data:image/svg+xml;base64,{b64}" style="width:{px}px;height:{px}px">'
        "</body></html>"
    )
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": px, "height": px})
        pg.set_content(html)
        pg.screenshot(path=out_png, omit_background=True)
        b.close()


def emit_imageset(png: Image.Image, set_name: str, slug: str):
    out = os.path.join(ASSETS, set_name + ".imageset")
    os.makedirs(out, exist_ok=True)
    files = {}
    for s, pt in ((1, 72), (2, 144), (3, 216)):
        img = png.resize((pt, pt), Image.LANCZOS)
        fn = f"{slug}.png" if s == 1 else f"{slug}@{s}x.png"
        img.save(os.path.join(out, fn))
        files[s] = fn
    json.dump({
        "images": [
            {"filename": files[s], "idiom": "universal", "scale": f"{s}x"} for s in (1, 2, 3)
        ],
        "info": {"author": "xcode", "version": 1},
    }, open(os.path.join(out, "Contents.json"), "w"), indent=2)


def render_sheet(svgs: "dict[str, str]", out_png: str):
    """9 张插画铺在一张深色底图上,方便肉眼过一遍设计。"""
    tiles = []
    for key, spec in TYPES.items():
        b64 = base64.b64encode(svgs[key].encode()).decode()
        tiles.append(
            '<div class="item">'
            f'<div class="tile"><img src="data:image/svg+xml;base64,{b64}"></div>'
            f'<div class="label">{spec["label"]}</div>'
            "</div>"
        )
    html = f"""<html><head><style>
    body{{margin:0;background:#0E0F12;font-family:-apple-system,sans-serif;
         display:grid;grid-template-columns:repeat(3,1fr);gap:18px;padding:26px}}
    .item{{display:flex;flex-direction:column;align-items:center;gap:8px}}
    .tile{{width:120px;height:120px;background:{TILE_BG};border-radius:16px;
          display:flex;align-items:center;justify-content:center}}
    .tile img{{width:104px;height:104px}}
    .label{{color:#8C8F98;font-size:13px;letter-spacing:.08em}}
    </style></head><body>{''.join(tiles)}</body></html>"""
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": 520, "height": 520})
        pg.set_content(html)
        pg.screenshot(path=out_png, full_page=True)
        b.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", action="store_true", help="只生成预览拼图")
    args = ap.parse_args()

    os.makedirs(SVG_DIR, exist_ok=True)
    os.makedirs(os.path.join(ASSETS), exist_ok=True)
    svgs = {}
    for key, spec in TYPES.items():
        svg = svg_text(spec)
        svgs[key] = svg
        open(os.path.join(SVG_DIR, f"{key}.svg"), "w", encoding="utf-8").write(svg + "\n")

    if not args.sheet:
        import tempfile
        for key, spec in TYPES.items():
            tmp = tempfile.mktemp(suffix=".png")
            render_svg_png(svgs[key], RENDER_PX, tmp)
            emit_imageset(Image.open(tmp).convert("RGBA"), spec["set"], f"modeltype-{key}")
            os.unlink(tmp)
            print(f"  {spec['label']:>4} → {spec['set']}.imageset")

    os.makedirs(os.path.dirname(SHEET_PATH), exist_ok=True)
    render_sheet(svgs, SHEET_PATH)
    print("预览图:", os.path.relpath(SHEET_PATH, REPO))
    print("SVG 源文件:", os.path.relpath(SVG_DIR, REPO))


if __name__ == "__main__":
    sys.exit(main())
