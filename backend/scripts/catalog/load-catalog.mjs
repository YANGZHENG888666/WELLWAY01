#!/usr/bin/env node
/**
 * 把 catalog.json 灌进 Supabase 的 brands / models 表。
 *
 * 用法：
 *   node backend/scripts/catalog/load-catalog.mjs            # 预演(只生成 SQL)
 *   node backend/scripts/catalog/load-catalog.mjs --apply    # 真的写库
 *
 * 特性：
 *   - 幂等：品牌按 name、车型按 (brand_id, name) upsert，可反复执行
 *   - 不覆盖人工数据：排量/价格为空时保留库里已有的值
 *   - 不改动不在目录里的老车型（用户车辆可能还在引用）
 */

import { readFile, writeFile } from 'node:fs/promises'
import { execFileSync } from 'node:child_process'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const CATALOG_PATH = resolve(HERE, 'data/catalog.json')
const SQL_PATH = resolve(HERE, 'data/load-catalog.sql')

const PSQL = process.env.PSQL ?? '/Applications/Postgres.app/Contents/Versions/18/bin/psql'
const DBURL = process.env.DBURL

const APPLY = process.argv.includes('--apply')

const q = (value) => (value === null || value === undefined ? 'null' : `'${String(value).replace(/'/g, "''")}'`)
const n = (value) => (value === null || value === undefined ? 'null' : String(Number(value)))
const b = (value) => (value ? 'true' : 'false')

const { brands } = JSON.parse(await readFile(CATALOG_PATH, 'utf8'))

const brandRows = brands
  .map((brand) => `  (${q(brand.name)}, ${q(brand.nameEn)}, ${b(brand.isHot)}, ${n(brand.sort)})`)
  .join(',\n')

const modelRows = brands
  .flatMap((brand) => brand.models.map((model) => ({ brand: brand.name, ...model })))
  .map(
    (m) =>
      `  (${q(m.brand)}, ${q(m.name)}, ${q(m.modelType)}, ${n(m.displacementCc)}, ${n(m.priceMin)}, ${n(
        m.priceMax ?? m.priceMin,
      )}, ${n(m.sort)})`,
  )
  .join(',\n')

const sql = `-- 由 backend/scripts/catalog/load-catalog.mjs 生成，请勿手改
-- 数据源：汽车之家摩托车频道公开车系表（见 data/catalog.json）
begin;

create temp table _catalog_brands (name text primary key, name_en text, is_hot boolean, sort integer) on commit drop;
insert into _catalog_brands (name, name_en, is_hot, sort) values
${brandRows};

insert into public.brands (name, name_en, is_hot, sort)
select name, name_en, is_hot, sort from _catalog_brands
on conflict (name) do update set
  name_en = coalesce(excluded.name_en, public.brands.name_en),
  is_hot  = public.brands.is_hot or excluded.is_hot,
  sort    = excluded.sort;

create temp table _catalog_models (
  brand text, name text, model_type text, displacement_cc integer,
  price_min integer, price_max integer, sort integer
) on commit drop;
insert into _catalog_models (brand, name, model_type, displacement_cc, price_min, price_max, sort) values
${modelRows};

insert into public.models (brand_id, name, model_type, displacement_cc, price_min, price_max, sort, is_active)
select b.id, m.name, m.model_type, m.displacement_cc, m.price_min, m.price_max, m.sort, true
from _catalog_models m
join public.brands b on b.name = m.brand
on conflict (brand_id, name) do update set
  model_type      = excluded.model_type,
  displacement_cc = coalesce(excluded.displacement_cc, public.models.displacement_cc),
  price_min       = coalesce(excluded.price_min, public.models.price_min),
  price_max       = coalesce(excluded.price_max, public.models.price_max),
  sort            = excluded.sort,
  is_active       = true;

commit;
`

await writeFile(SQL_PATH, sql, 'utf8')

const modelCount = brands.reduce((sum, brand) => sum + brand.models.length, 0)
console.log(`品牌 ${brands.length} / 车型 ${modelCount} → ${SQL_PATH}`)

if (!APPLY) {
  console.log('预演模式，未写库。加 --apply 执行。')
  process.exit(0)
}

if (!DBURL) {
  console.error('缺少 DBURL 环境变量')
  process.exit(1)
}

console.log('写入云端数据库…')
const out = execFileSync(PSQL, [DBURL, '-v', 'ON_ERROR_STOP=1', '-f', SQL_PATH], {
  encoding: 'utf8',
  env: process.env,
})
console.log(out.trim() || '(psql 无输出)')

const verify = execFileSync(
  PSQL,
  [
    DBURL,
    '-c',
    `select count(*) as brands from public.brands;
     select count(*) as models, count(displacement_cc) as with_cc, count(price_min) as with_price from public.models;
     select model_type, count(*) from public.models group by 1 order by 2 desc;`,
  ],
  { encoding: 'utf8', env: process.env },
)
console.log(verify)
