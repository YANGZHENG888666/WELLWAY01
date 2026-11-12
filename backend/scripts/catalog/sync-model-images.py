#!/usr/bin/env python3
"""把「汽车之家」车系抠图(pnglogo)拉下来 → 压缩 → 传 Supabase Storage → 写回 models.image_url。

为什么单独一步：抓取脚本(node)只负责拿 URL，真正的图片处理用 PIL 更省事，所以这一步是 Python。

流程：
  1. data/catalog.json 提供 (品牌名, 车型名, sourceId)
  2. data/series-logos.json 提供 sourceId → pngLogo 地址
  3. 逐个下载原图（约 0.5~1.3MB/张），PIL 缩到最长边 720、保留透明通道
  4. 上传到 catalog-images 桶的 models/<sourceId>.png（用 service role，x-upsert 覆盖）
  5. 生成 data/model-images.sql（默认只填 image_url 为空的行，--force 才覆盖）

图片本地缓存：data/model-images/<sourceId>.png（存的是压过的小图，断点续跑不用重新下载）。

礼貌策略：图片走的是 CDN（car2/car3.autoimg.cn），默认并发 3、每批之间歇 delay 秒，
比浏览器打开一个图集页还保守；想更慢就 --concurrency 1 --delay 2。

用法（在仓库根目录）：
  python3 backend/scripts/catalog/sync-model-images.py --limit 20     # 先试 20 台
  python3 backend/scripts/catalog/sync-model-images.py               # 全量
  python3 backend/scripts/catalog/sync-model-images.py --sql-only     # 不联网，只按缓存生成 SQL
  python3 backend/scripts/catalog/sync-model-images.py --force        # 覆盖已有 image_url
"""

import argparse
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
DATA = os.path.join(HERE, "data")
CATALOG = os.path.join(DATA, "catalog.json")
LOGOS = os.path.join(DATA, "series-logos.json")
CACHE = os.path.join(DATA, "model-images")
SQL_OUT = os.path.join(DATA, "model-images.sql")

BUCKET = "catalog-images"
PREFIX = "models"
MAX_EDGE = 720
UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)


def env_file(path):
    out = {}
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    return out


def fetch_bytes(url, attempts=3, delay=1.0):
    last = None
    for i in range(attempts):
        try:
            req = urllib.request.Request(
                url,
                headers={
                    "User-Agent": UA,
                    "Referer": "https://car.autohome.com.cn/",
                    "Accept": "image/avif,image/webp,image/png,image/*,*/*;q=0.8",
                },
            )
            with urllib.request.urlopen(req, timeout=45) as res:
                return res.read()
        except Exception as err:  # noqa: BLE001
            last = err
            if i < attempts - 1:
                time.sleep(delay * (i + 2))
    raise RuntimeError(f"下载失败 {url}: {last}")


def shrink(raw):
    """原图 → 最长边 MAX_EDGE 的透明 PNG 字节。"""
    img = Image.open(io.BytesIO(raw))
    img = img.convert("RGBA")
    img.thumbnail((MAX_EDGE, MAX_EDGE), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue(), img.size


def upload(supabase_url, service_key, data, path, attempts=3):
    url = f"{supabase_url}/storage/v1/object/{BUCKET}/{path}"
    for i in range(attempts):
        try:
            req = urllib.request.Request(
                url,
                data=data,
                method="PUT",
                headers={
                    # 新版密钥(sb_secret_…)要放在 apikey 头里；放进 Authorization: Bearer
                    # 会被 Storage 当成旧版 JWT 解析，报 "Invalid Compact JWS"。
                    "apikey": service_key,
                    "Content-Type": "image/png",
                    "Cache-Control": "31536000",
                    "x-upsert": "true",
                },
            )
            with urllib.request.urlopen(req, timeout=60) as res:
                if res.status not in (200, 201):
                    raise RuntimeError(f"HTTP {res.status}")
                return
        except urllib.error.HTTPError as err:
            body = err.read().decode("utf-8", "ignore")[:200]
            if i >= attempts - 1:
                raise RuntimeError(f"上传失败 {path}: HTTP {err.code} {body}") from err
            time.sleep(1.5 * (i + 1))


def remote_size(supabase_url, service_key, path):
    """桶里已有对象的字节数；不存在返回 None。用于跳过重复上传，让重跑只补缺的。"""
    url = f"{supabase_url}/storage/v1/object/info/{BUCKET}/{path}"
    try:
        req = urllib.request.Request(url, headers={"apikey": service_key})
        with urllib.request.urlopen(req, timeout=20) as res:
            return int(json.load(res).get("size") or 0)
    except Exception:  # noqa: BLE001
        return None


def sql_quote(text):
    return "'" + str(text).replace("'", "''") + "'"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="只处理前 N 台（试跑用）")
    ap.add_argument("--delay", type=float, default=0.6, help="每批之间的间隔秒数")
    ap.add_argument("--concurrency", type=int, default=3, help="同时下载+上传几个（默认 3）")
    ap.add_argument("--force", action="store_true", help="覆盖已有 image_url")
    ap.add_argument("--reupload", action="store_true", help="桶里已有同尺寸对象也重传")
    ap.add_argument("--sql-only", action="store_true", help="不下载/不上传，只用本地缓存生成 SQL")
    args = ap.parse_args()

    with open(CATALOG, encoding="utf-8") as fh:
        catalog = json.load(fh)
    with open(LOGOS, encoding="utf-8") as fh:
        logos = json.load(fh)
    logo_by_id = {s["id"]: s.get("pngLogo") for s in logos["series"]}

    env = env_file(os.path.join(REPO, "backend", ".env"))
    supabase_url = env.get("SUPABASE_URL", "").rstrip("/")
    service_key = env.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not args.sql_only and (not supabase_url or not service_key):
        sys.exit("backend/.env 缺少 SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY")

    targets = []
    for brand in catalog["brands"]:
        for model in brand["models"]:
            sid = model.get("sourceId")
            logo = logo_by_id.get(sid)
            if sid and logo:
                targets.append((brand["name"], model["name"], sid, logo))
    if args.limit:
        targets = targets[: args.limit]

    print(f"目标 {len(targets)} 台（目录共 {sum(len(b['models']) for b in catalog['brands'])} 台）")
    os.makedirs(CACHE, exist_ok=True)

    rows = []
    done = cached = failed = 0
    total_bytes = 0
    started = time.time()

    def process(item):
        """单台车：命中缓存就直接用，否则下载+压缩+落缓存，最后上传。异常以返回值形式回传。"""
        brand_name, model_name, sid, logo = item
        cache_path = os.path.join(CACHE, f"{sid}.png")
        from_cache = os.path.exists(cache_path)
        try:
            if from_cache:
                with open(cache_path, "rb") as fh:
                    data = fh.read()
            elif args.sql_only:
                return None
            else:
                raw = fetch_bytes(logo)
                data, _size = shrink(raw)
                with open(cache_path, "wb") as fh:
                    fh.write(data)

            if not args.sql_only:
                path = f"{PREFIX}/{sid}.png"
                # 桶里已有同尺寸对象就跳过上传：重跑只补失败的，不用把 478MB 再传一遍
                if args.reupload or remote_size(supabase_url, service_key, path) != len(data):
                    upload(supabase_url, service_key, data, path)

            url = f"{supabase_url}/storage/v1/object/public/{BUCKET}/{PREFIX}/{sid}.png"
            return (brand_name, model_name, url, from_cache, len(data))
        except Exception as err:  # noqa: BLE001
            return err

    batch = max(1, args.concurrency)
    print(f"并发 {batch}，每批间歇 {args.delay}s")
    with ThreadPoolExecutor(max_workers=batch) as pool:
        for start in range(0, len(targets), batch):
            chunk = targets[start : start + batch]
            for item, result in zip(chunk, pool.map(process, chunk)):
                brand_name, model_name, sid, _logo = item
                if isinstance(result, Exception):
                    failed += 1
                    print(f"  ! {brand_name} {model_name} ({sid})：{result}", flush=True)
                    continue
                if result is None:
                    continue
                _b, _m, url, from_cache, size = result
                rows.append((brand_name, model_name, url))
                if from_cache:
                    cached += 1
                else:
                    done += 1
                    total_bytes += size

            if start + batch < len(targets):
                time.sleep(args.delay)
            if (start // batch) % 25 == 24:
                seen = done + cached + failed
                rate = seen / max(time.time() - started, 1)
                eta = (len(targets) - seen) / rate if rate > 0 else 0
                print(
                    f"  {seen}/{len(targets)}  新上传 {done} 复用缓存 {cached} 失败 {failed}  "
                    f"{rate:.2f} 台/秒  预计剩余 {eta / 60:.0f} 分钟",
                    flush=True,
                )

    guard = "" if args.force else "\n  and m.image_url is null"
    values = ",\n  ".join(
        f"({sql_quote(b)}, {sql_quote(n)}, {sql_quote(u)})" for b, n, u in rows
    )
    sql = f"""-- 由 sync-model-images.py 生成，可反复执行（幂等）
-- 默认只填空值；要覆盖已有 image_url 用 --force 重新生成
update models m
set image_url = v.url
from (values
  {values}
) as v(brand_name, model_name, url)
join brands b on b.name = v.brand_name
where m.brand_id = b.id
  and m.name = v.model_name{guard};
"""
    with open(SQL_OUT, "w", encoding="utf-8") as fh:
        fh.write(sql)

    print(
        f"\n下载并上传 {done}，复用缓存 {cached}，失败 {failed}，"
        f"上行 {total_bytes / 1024 / 1024:.1f} MB，用时 {time.time() - started:.0f}s"
    )
    print("SQL:", os.path.relpath(SQL_OUT, REPO), f"（{len(rows)} 行）")


if __name__ == "__main__":
    main()
