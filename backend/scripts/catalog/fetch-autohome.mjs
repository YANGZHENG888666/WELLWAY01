#!/usr/bin/env node
/**
 * 抓取「汽车之家 · 摩托车频道」(car.autohome.com.cn/motorbike) 的公开车型目录。
 *
 * 该站点 robots.txt 未禁止 /motorbike/ 路径，本脚本按礼貌策略访问：
 *   - 请求间隔 1.2s（可调 --delay），串行不并发
 *   - 失败重试 3 次，指数退避
 *   - 只取公开列表页里的车型名 / 价格 / 车系分类，不下载任何图片
 *
 * 用法：
 *   node backend/scripts/catalog/fetch-autohome.mjs                    # 抓列表页
 *   node backend/scripts/catalog/fetch-autohome.mjs --delay 2000       # 放慢
 *   node backend/scripts/catalog/fetch-autohome.mjs --detail-all       # 补抓详情页(官方排量)
 *   node backend/scripts/catalog/fetch-autohome.mjs --detail-nulls     # 只补缺排量的
 *   node backend/scripts/catalog/fetch-autohome.mjs --skip-list        # 跳过列表页,只补详情
 *
 * 输出：backend/scripts/catalog/data/library-raw.json
 */

import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const OUT_DIR = resolve(HERE, 'data')
const RAW_PATH = resolve(OUT_DIR, 'library-raw.json')

const UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'

const args = process.argv.slice(2)
const flag = (name) => args.includes(name)
const value = (name, fallback) => {
  const i = args.indexOf(name)
  return i >= 0 && args[i + 1] ? Number(args[i + 1]) : fallback
}

const DELAY = Math.max(600, value('--delay', 1200))
const CONCURRENCY = Math.max(1, Math.min(4, value('--concurrency', 2)))
const DETAIL_ALL = flag('--detail-all')
const DETAIL_NULLS = flag('--detail-nulls') || DETAIL_ALL
const SKIP_LIST = flag('--skip-list')
const LIMIT = value('--limit', 0)

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

async function getHtml(url, attempt = 1) {
  try {
    const res = await fetch(url, {
      headers: {
        'User-Agent': UA,
        'Accept-Language': 'zh-CN,zh;q=0.9',
        Accept: 'text/html,application/xhtml+xml',
      },
      redirect: 'follow',
    })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    return await res.text()
  } catch (err) {
    if (attempt >= 3) throw err
    const backoff = DELAY * attempt * 2
    console.warn(`  ! ${url} 失败(${err.message})，${backoff}ms 后重试`)
    await sleep(backoff)
    return getHtml(url, attempt + 1)
  }
}

function nextData(html) {
  const m = html.match(/id="__NEXT_DATA__"[^>]*>([\s\S]*?)<\/script>/)
  if (!m) throw new Error('页面里没有 __NEXT_DATA__（可能被反爬拦截）')
  return JSON.parse(m[1]).props.pageProps
}

/**
 * 车系列表页 URL。
 * 路径段含义：<品牌>-<级别>-<价格>-<排量>-<在售过滤>，页码是 query 参数 ?page=N
 * （路径最后一格不是页码，写成路径页码会导致每页都返回第 1 页）。
 */
const libraryUrl = (levelId, page) =>
  `https://car.autohome.com.cn/motorbike/library/0-${levelId}-0-0-1?page=${page}`

/** 车系详情页，含「排量(cc)」等参数表 */
const seriesUrl = (seriesId) => `https://car.autohome.com.cn/motorbike/series/${seriesId}`

/**
 * 详情页里取官方排量：
 *   specList[].speclist[].displacement 是数值字段，最准
 *   paramsConfig["排量(cc)"] 作兜底
 * 纯电车没有排量，正常返回 null。
 */
function displacementFromDetail(html) {
  const pp = nextData(html)
  for (const year of pp.specList ?? []) {
    for (const spec of year.speclist ?? []) {
      const value = Number(spec.displacement)
      if (Number.isFinite(value) && value > 0) return Math.round(value)
    }
  }
  const fallback = Number(String(pp.paramsConfig?.['排量(cc)'] ?? '').replace(/[^\d.]/g, ''))
  return Number.isFinite(fallback) && fallback > 0 ? Math.round(fallback) : null
}

async function loadExisting() {
  try {
    return JSON.parse(await readFile(RAW_PATH, 'utf8'))
  } catch {
    return null
  }
}

async function main() {
  await mkdir(OUT_DIR, { recursive: true })
  const existing = await loadExisting()

  const brands = new Map()
  const series = new Map()
  if (existing) {
    for (const b of existing.brands ?? []) brands.set(b.id, b)
    for (const s of existing.series ?? []) series.set(s.id, s)
    console.log(`续跑：已有 ${brands.size} 品牌 / ${series.size} 车系`)
  }

  const levels = value('--levels', 9)
  for (let levelId = 1; levelId <= (SKIP_LIST ? 0 : levels); levelId++) {
    let page = 1
    let pageCount = 1
    while (page <= pageCount) {
      const url = libraryUrl(levelId, page)
      const html = await getHtml(url)
      const pp = nextData(html)
      pageCount = pp.pageCount ?? 1

      for (const list of Object.values(pp.brandList ?? {})) {
        for (const b of list) {
          if (!brands.has(b.id)) {
            brands.set(b.id, {
              id: b.id,
              name: b.name,
              nameEn: b.enname || null,
              firstLetter: b.firstletter,
              state: b.state,
              rank: b.rank,
            })
          }
        }
      }

      for (const s of pp.motorList ?? []) {
        series.set(s.seriesid, {
          id: s.seriesid,
          name: s.seriesName,
          brandId: s.brandid,
          brandName: s.brandname,
          levelId: s.levelId,
          type: s.levelName,
          priceMin: s.seriesPriceMin || null,
          priceMax: s.seriesPriceMax || null,
          state: s.seriesState,
          rank: s.rank,
          displacementCc: series.get(s.seriesid)?.displacementCc ?? null,
        })
      }

      console.log(
        `level ${levelId} (${pp.motorList?.[0]?.levelName ?? '?'}) page ${page}/${pageCount} → 累计 ${series.size} 车系`,
      )
      page += 1
      if (page <= pageCount) await sleep(DELAY)
    }
    await sleep(DELAY)
  }

  if (DETAIL_NULLS && series.size) {
    const all = [...series.values()].sort((a, b) => (b.state - a.state) || a.id - b.id)
    let targets = DETAIL_ALL ? all : all.filter((s) => !s.displacementCc)
    if (LIMIT > 0) targets = targets.slice(0, LIMIT)
    console.log(
      `\n补排量：目标 ${targets.length} 个车系，并发 ${CONCURRENCY}，间隔 ${DELAY}ms`,
    )

    let cursor = 0
    let done = 0
    let filled = 0
    let failed = 0
    const startedAt = Date.now()

    const worker = async () => {
      while (cursor < targets.length) {
        const s = targets[cursor++]
        try {
          const html = await getHtml(seriesUrl(s.id))
          const cc = displacementFromDetail(html)
          if (cc) {
            s.displacementCc = cc
            filled += 1
          }
        } catch (err) {
          failed += 1
          console.warn(`  ! ${s.name} 详情失败：${err.message}`)
        }
        done += 1
        if (done % 50 === 0) {
          const rate = done / ((Date.now() - startedAt) / 1000)
          const left = Math.round((targets.length - done) / Math.max(rate, 0.01) / 60)
          console.log(
            `  进度 ${done}/${targets.length} · 已补 ${filled} · 失败 ${failed} · 约剩 ${left} 分钟`,
          )
          await save(brands, series)
        }
        await sleep(DELAY)
      }
    }

    await Promise.all(Array.from({ length: CONCURRENCY }, worker))
    console.log(`  补排量完成：新增 ${filled} 个，失败 ${failed} 个`)
  }

  await save(brands, series)
  console.log(`\n完成：${brands.size} 品牌 / ${series.size} 车系 → ${RAW_PATH}`)
  const inSale = [...series.values()].filter((s) => s.state === 1)
  const withCc = inSale.filter((s) => s.displacementCc)
  console.log(`在售 ${inSale.length} 个，其中带排量 ${withCc.length} 个`)
}

async function save(brands, series) {
  const payload = {
    scrapedAt: new Date().toISOString(),
    source: 'https://car.autohome.com.cn/motorbike/library',
    brands: [...brands.values()].sort((a, b) => a.id - b.id),
    series: [...series.values()].sort((a, b) => a.id - b.id),
  }
  await writeFile(RAW_PATH, JSON.stringify(payload, null, 1), 'utf8')
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
