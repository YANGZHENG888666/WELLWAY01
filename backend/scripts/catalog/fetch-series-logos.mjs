#!/usr/bin/env node
/**
 * 抓「汽车之家 · 摩托车频道」车系列表页里的车型抠图(pnglogo)地址。
 *
 * 为什么要单开一个脚本：`fetch-autohome.mjs` 只取车型名/分类/价格/排量这些事实字段，
 * 不带图片。列表页的 __NEXT_DATA__ 里其实每台车都带了 `pnglogo`——一张透明底、
 * 官方出的整车抠图，正好当车型缩略图用，而且一次列表请求就能拿到一整页（28 台），
 * 比逐个详情页便宜得多（70 次请求 vs 1900+ 次）。
 *
 * 礼貌策略与 fetch-autohome.mjs 保持一致：串行、请求间隔 1.2s、失败重试 3 次、
 * 断点续跑（已抓到的车系不重复请求），输出写到 data/series-logos.json。
 *
 * 用法：
 *   node backend/scripts/catalog/fetch-series-logos.mjs
 *   node backend/scripts/catalog/fetch-series-logos.mjs --delay 2000
 */

import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const OUT_DIR = resolve(HERE, 'data')
const OUT_PATH = resolve(OUT_DIR, 'series-logos.json')

const UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'

const args = process.argv.slice(2)
const value = (name, fallback) => {
  const i = args.indexOf(name)
  return i >= 0 && args[i + 1] ? Number(args[i + 1]) : fallback
}

const DELAY = Math.max(600, value('--delay', 1200))
const LEVELS = value('--levels', 9)

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

const libraryUrl = (levelId, page) =>
  `https://car.autohome.com.cn/motorbike/library/0-${levelId}-0-0-1?page=${page}`

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

async function loadExisting() {
  try {
    return JSON.parse(await readFile(OUT_PATH, 'utf8'))
  } catch {
    return null
  }
}

async function main() {
  await mkdir(OUT_DIR, { recursive: true })
  const existing = await loadExisting()
  const byId = new Map()
  if (existing?.series) {
    for (const s of existing.series) byId.set(s.id, s)
    console.log(`续跑：已有 ${byId.size} 个车系的抠图地址`)
  }

  let pages = 0
  for (let levelId = 1; levelId <= LEVELS; levelId++) {
    let page = 1
    let pageCount = 1
    while (page <= pageCount) {
      const html = await getHtml(libraryUrl(levelId, page))
      const pp = nextData(html)
      pageCount = pp.pageCount ?? 1
      pages += 1

      for (const s of pp.motorList ?? []) {
        byId.set(s.seriesid, {
          id: s.seriesid,
          name: s.seriesName,
          brandId: s.brandid,
          brandName: s.brandname,
          brandLogo: s.brandlogo ?? null,
          type: s.levelName,
          levelId: s.levelId,
          pngLogo: s.pnglogo ?? null,
        })
      }

      console.log(
        `level ${levelId} page ${page}/${pageCount} → 累计 ${byId.size} 个车系` +
          `（有抠图 ${[...byId.values()].filter((s) => s.pngLogo).length}）`,
      )
      page += 1
      if (page <= pageCount) await sleep(DELAY)
    }
    await sleep(DELAY)
  }

  const series = [...byId.values()].sort((a, b) => a.id - b.id)
  const out = {
    scrapedAt: new Date().toISOString(),
    source: 'https://car.autohome.com.cn/motorbike/library',
    pagesFetched: pages,
    stats: {
      series: series.length,
      withPngLogo: series.filter((s) => s.pngLogo).length,
      withBrandLogo: series.filter((s) => s.brandLogo).length,
    },
    series,
  }
  await writeFile(OUT_PATH, JSON.stringify(out, null, 1) + '\n')
  console.log(`\n写出 ${OUT_PATH}`)
  console.log(`车系 ${out.stats.series}，有抠图 ${out.stats.withPngLogo}`)
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
