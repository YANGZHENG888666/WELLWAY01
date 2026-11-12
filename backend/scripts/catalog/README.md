# 车型库目录（catalog）

App「添加车辆 → 选择车型」用的车型库，全部由这里的脚本生成，人工不直接改数据库。

## 数据来源

「汽车之家 · 摩托车频道」的公开车系列表 `https://car.autohome.com.cn/motorbike/library`。
该站 `robots.txt` 未禁止 `/motorbike/`，脚本按礼貌策略访问：串行/低并发、请求间隔 0.9~1.2s、
失败重试 3 次、**只取车型名/分类/价格/排量等事实字段，不下载任何图片**。

> 关于车型缩略图：事实字段部分确实不抓图。车型缩略图是另一条独立链路（见下「车型缩略图」），
> 用的是列表页里本来就带着的 `pnglogo`——汽车之家官方出的透明底整车抠图，
> 抓取范围、节奏、以及版权注意事项都单独写在那一节。

## 目录结构

```
backend/scripts/catalog/
├── fetch-autohome.mjs      # 抓取：列表页 + 车系详情页(官方排量)
├── fetch-series-logos.mjs  # 抓取：列表页里的车系抠图 URL(pnglogo)
├── normalize-catalog.mjs   # 整理：分类映射、排量解析、品牌归并、排序
├── sync-model-images.py    # 图片：下载抠图 → 压缩 → 传 Storage → 生成更新 SQL
├── load-catalog.mjs        # 入库：幂等 upsert 到 brands / models
└── data/
    ├── library-raw.json    # 原始抓取结果（抓取脚本的断点续跑缓存）
    ├── series-logos.json   # 车系 → 抠图 URL（fetch-series-logos.mjs 的产出）
    ├── model-images/       # 压缩后的抠图本地缓存（供断点续跑 / --sql-only）
    ├── model-images.sql    # 写回 models.image_url 的 SQL
    ├── overrides.json      # 人工修正（可选，见下）
    ├── catalog.json        # 整理后的目录，入库的唯一依据
    └── load-catalog.sql    # 生成的 SQL（可单独拿去 SQL Editor 跑）
```

## 车型缩略图

App 里车型列表那一格缩略图，用的是「汽车之家」车系列表页 `__NEXT_DATA__` 里每条车系自带的
`pnglogo`：**透明底、官方出的整车抠图**（1920×1440 左右），比整张场景照更适合当列表缩略图。

```bash
# 1. 抓所有车系的抠图 URL（只重跑列表页，约 70 次请求 / 2 分钟，可断点续跑）
node backend/scripts/catalog/fetch-series-logos.mjs

# 2. 下载 → 缩到最长边 720 → 传 catalog-images 桶 → 生成 model-images.sql
python3 backend/scripts/catalog/sync-model-images.py --limit 20   # 先试 20 台
python3 backend/scripts/catalog/sync-model-images.py             # 全量（约 20 分钟）

# 3. 写回数据库
psql "$SUPABASE_DB_URL" -f backend/scripts/catalog/data/model-images.sql
```

要点：

- **存自己的桶，不盗链**：图片下载后压到最长边 720 的透明 PNG，传到 Supabase Storage 的
  `catalog-images` 桶（公开读），`models.image_url` 存这个公开地址，App 不直连汽车之家的图床。
- **`image_url` 有值就用真图，没值回落分类插画**：9 张按分类手绘的线稿在
  `ios/WELLWAY/Resources/Assets.xcassets/ModelType*.imageset`，由 `ios/tools/make_model_type_art.py` 生成。
  这条回落链路保证「目录里新增车型但还没图」时列表不会开天窗。
- **SQL 默认只填空值**（`m.image_url is null`），不会覆盖后台手工传过的图；要全量重刷用 `--force` 重新生成。
- **礼貌策略**：图片走 CDN（car2/car3.autoimg.cn），默认并发 3、每批间歇 0.6s，比浏览器开一个图集页还保守；
  想更慢就 `--concurrency 1 --delay 2`。断点续跑靠 `data/model-images/` 本地缓存，中断后重跑只补缺的。
- **版权**：抠图是汽车之家的资源，只适合内部测试/TestFlight 自用；正式上架前应换成品牌方授权素材
  或用户自拍图（后台 `admin/index.html` 支持逐个车型上传到 `catalog-images`）。这一点务必让产品方知情。

## 常用命令

```bash
# 1. 抓列表页（9 个分类，约 70 页，2~3 分钟）
node backend/scripts/catalog/fetch-autohome.mjs

# 2. 补官方排量（详情页，约 1900 个车系，可断点续跑）
node backend/scripts/catalog/fetch-autohome.mjs --skip-list --detail-all --delay 900 --concurrency 2

# 3. 整理成 catalog.json
node backend/scripts/catalog/normalize-catalog.mjs

# 4. 入库（预演 / 真写）
node backend/scripts/catalog/load-catalog.mjs
DBURL="postgresql://...:5432/postgres?sslmode=require" node backend/scripts/catalog/load-catalog.mjs --apply
```

## 人工修正

`data/overrides.json` 用来纠正个别车系，不用改脚本：

```json
{
  "brands": { "QJMOTOR": "钱江" },
  "models": {
    "凯旋 Bonneville T120": { "displacementCc": 1200 },
    "哈雷戴维森 肥仔 114": { "displacementCc": 1868 }
  }
}
```

优先级：overrides > 详情页官方排量 > 从车系名解析 → 都没有就留空。
**留空好过写错**，App 里排量未知的车型不会参与排量筛选。

## 维护约定

- 品牌名以 `brands.name` 为唯一键；分类以 `models.model_type` 为唯一键，取值固定为
  `跑车 / 街车 / 踏板 / 巡航 / 复古 / ADV / 越野 / 旅行 / MINI`（汽车之家叫「冒险」，这里映射成 `ADV`）。
- `load-catalog.mjs` 是幂等的，可以反复执行刷新价格；排量/价格为空时保留库里已有值，不覆盖人工补过的数据。
- 不在目录里的老车型不会被删除（用户车辆可能还引用着），需要下架时在后台管理里手工处理。
- App 端 `GarageService.loadCatalog()` 按 500 条/页翻页拉取全量车型，
  以后目录再涨也不需要改代码。
