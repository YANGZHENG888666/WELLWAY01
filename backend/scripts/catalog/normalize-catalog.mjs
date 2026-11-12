#!/usr/bin/env node
/**
 * 把 fetch-autohome.mjs 抓到的原始车系表，整理成可直接入库的车型目录。
 *
 * 输出：backend/scripts/catalog/data/catalog.json
 *   {
 *     generatedAt, source, stats,
 *     brands: [{ name, nameEn, firstLetter, isHot, sort, models: [...] }]
 *   }
 *
 * 规则：
 *   - 车系分类 冒险 → ADV（与 App 里已有的「ADV」保持一致），其余分类原样沿用
 *   - 排量优先取详情页抓到的真实值，其次从车系名里解析，解析不出就留空（不编造）
 *   - 只保留事实字段：品牌、车系名、分类、排量、指导价区间；不存第三方图片
 */

import { readFile, writeFile, mkdir } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const DATA = resolve(HERE, 'data')
const RAW_PATH = resolve(DATA, 'library-raw.json')
const OVERRIDES_PATH = resolve(DATA, 'overrides.json')
const OUT_PATH = resolve(DATA, 'catalog.json')

/** 汽车之家的分类名 → App 使用的 model_type */
const TYPE_MAP = {
  跑车: '跑车',
  街车: '街车',
  踏板: '踏板',
  复古: '复古',
  巡航: '巡航',
  冒险: 'ADV',
  旅行: '旅行',
  越野: '越野',
  MINI: 'MINI',
}

/** 常见别名 → 库里已有的品牌名，保证同一品牌不会被拆成两条 */
const BRAND_ALIAS = {
  春风: '春风动力',
  春风摩托: '春风动力',
  CFMOTO: '春风动力',
  KTMR2R: 'KTM',
  三阳SYM: '三阳',
}

/** 热门品牌，按这个顺序排在品牌列表最前面；其余品牌按首字母 A-Z 排 */
const HOT_BRANDS = [
  '春风动力',
  '钱江',
  '无极',
  '赛科龙',
  '豪爵铃木',
  '豪爵',
  '宗申',
  '隆鑫',
  '凯越',
  '升仕',
  '奔达',
  '本田',
  '雅马哈',
  '川崎',
  '铃木',
  '宝马',
  'KTM',
  '杜卡迪',
  '凯旋',
  '哈雷戴维森',
  '阿普利亚',
  '贝纳利',
  '光阳',
  '三阳',
  '力帆',
  '大阳',
  '比亚乔',
]

/**
 * 从车系名里解析排量，例如：
 *   「春风 450SR」→ 450，「Ninja 400」→ 400，「Z900」→ 900，「PCX160」→ 160
 * 拿不准的一律返回 null（宁可留空，也不要写错排量）。
 */
function parseDisplacement(name) {
  const text = name.normalize('NFKC')
  const candidates = []
  for (const m of text.matchAll(/\d+(?:\.\d+)?/g)) {
    const value = Number(m[0])
    const before = text.slice(Math.max(0, m.index - 2), m.index)
    // 年份 / 款号不是排量
    if (/年|款/.test(text.slice(m.index + m[0].length, m.index + m[0].length + 1))) continue
    if (value >= 1900 && value <= 2035) continue
    if (value < 48 || value > 2500) continue
    // 「V2」「V4」「R3 版本」这类气缸/代号数字不算排量
    if (/^[Vv]$/.test(before.slice(-1))) continue
    candidates.push(value)
  }
  if (!candidates.length) return null
  return Math.max(...candidates)
}

async function loadOverrides() {
  try {
    return JSON.parse(await readFile(OVERRIDES_PATH, 'utf8'))
  } catch {
    return { brands: {}, models: {} }
  }
}

async function main() {
  await mkdir(DATA, { recursive: true })
  const raw = JSON.parse(await readFile(RAW_PATH, 'utf8'))
  const overrides = await loadOverrides()

  const brandByRawId = new Map(raw.brands.map((b) => [b.id, b]))
  const byBrand = new Map()
  const unmatchedTypes = new Set()

  for (const s of raw.series) {
    const modelType = TYPE_MAP[s.type]
    if (!modelType) {
      unmatchedTypes.add(s.type)
      continue
    }
    const rawBrand = brandByRawId.get(s.brandId)
    const brandName =
      overrides.brands?.[s.brandName] ?? BRAND_ALIAS[s.brandName] ?? s.brandName ?? rawBrand?.name
    if (!brandName) continue

    if (!byBrand.has(brandName)) {
      byBrand.set(brandName, {
        name: brandName,
        nameEn: rawBrand?.nameEn ?? null,
        firstLetter: rawBrand?.firstLetter ?? null,
        isHot: HOT_BRANDS.includes(brandName),
        models: [],
      })
    }

    const override = overrides.models?.[s.name] ?? {}
    const displacementCc =
      override.displacementCc ?? s.displacementCc ?? parseDisplacement(s.name) ?? null

    byBrand.get(brandName).models.push({
      name: override.name ?? s.name,
      modelType: override.modelType ?? modelType,
      displacementCc,
      displacementSource: s.displacementCc
        ? 'detail'
        : override.displacementCc
          ? 'override'
          : parseDisplacement(s.name)
            ? 'name'
            : null,
      priceMin: override.priceMin ?? s.priceMin ?? null,
      priceMax: override.priceMax ?? s.priceMax ?? s.priceMin ?? null,
      // 榜单热度：数字越小越热，0 表示未上榜
      heat: s.rank || 0,
      sourceId: s.id,
      seriesState: s.state,
    })
  }

  const brands = [...byBrand.values()]
  for (const brand of brands) {
    // 热门品牌优先；同品牌内先按榜单热度，再按排量、车系名
    brand.models.sort(
      (a, b) =>
        (a.heat || 9999) - (b.heat || 9999) ||
        (a.displacementCc ?? 9999) - (b.displacementCc ?? 9999) ||
        a.name.localeCompare(b.name, 'zh'),
    )
    brand.models.forEach((m, i) => {
      m.sort = i + 1
      delete m.heat
      delete m.seriesState
    })
  }
  // 热门品牌按策展顺序置顶，其余按首字母（A-Z）排，和「摩托范」的品牌库一致
  const hotOrder = new Map(HOT_BRANDS.map((name, i) => [name, i]))
  brands.sort((a, b) => {
    const hotA = hotOrder.has(a.name)
    const hotB = hotOrder.has(b.name)
    if (hotA !== hotB) return hotA ? -1 : 1
    if (hotA && hotB) return hotOrder.get(a.name) - hotOrder.get(b.name)
    return (
      (a.firstLetter ?? 'Z').localeCompare(b.firstLetter ?? 'Z') ||
      a.name.localeCompare(b.name, 'zh')
    )
  })
  brands.forEach((b, i) => {
    b.sort = i + 1
  })

  const models = brands.flatMap((b) => b.models)
  const stats = {
    brands: brands.length,
    models: models.length,
    withDisplacement: models.filter((m) => m.displacementCc).length,
    missingDisplacement: models.filter((m) => !m.displacementCc).length,
    withPrice: models.filter((m) => m.priceMin).length,
    missingPrice: models.filter((m) => !m.priceMin).length,
    byType: models.reduce((acc, m) => ((acc[m.modelType] = (acc[m.modelType] ?? 0) + 1), acc), {}),
    byDisplacementSource: models.reduce(
      (acc, m) => ((acc[m.displacementSource ?? 'none'] = (acc[m.displacementSource ?? 'none'] ?? 0) + 1), acc),
      {},
    ),
  }

  await writeFile(
    OUT_PATH,
    JSON.stringify({ generatedAt: new Date().toISOString(), source: raw.source, stats, brands }, null, 1),
    'utf8',
  )

  console.log(`品牌 ${stats.brands} / 车型 ${stats.models}`)
  console.log('分类：', stats.byType)
  console.log('排量来源：', stats.byDisplacementSource)
  console.log(`缺排量 ${stats.missingDisplacement}，缺价格 ${stats.missingPrice}`)
  if (unmatchedTypes.size) console.log('未识别的分类：', [...unmatchedTypes])
  console.log('→', OUT_PATH)
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
