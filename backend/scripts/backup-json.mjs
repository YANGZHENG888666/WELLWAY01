// WELL WAY 数据备份(JSON 方式,无需数据库连接串,仅需 service role key)
//
// 用法(在 backend/scripts 目录):
//   node --env-file=../.env backup-json.mjs [输出目录]
// 环境变量:SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY(必须);
//   TABLE_FILTER=表名,逗号分隔 可只备份指定表(默认全部)。

import { createClient } from '@supabase/supabase-js';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) {
  console.error('缺少 SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY(请先配置 backend/.env)');
  process.exit(1);
}

// 全部业务表(按依赖顺序导出)
const ALL_TABLES = [
  'brands', 'models', 'routes', 'checkpoints', 'badges',
  'activities', 'activity_registrations', 'profiles',
  'route_favorites', 'ride_presence', 'ride_records', 'ride_points',
  'ride_checkins', 'user_badges', 'feedback', 'admin_logs',
];
const tables = (process.env.TABLE_FILTER ? process.env.TABLE_FILTER.split(',') : ALL_TABLES)
  .map(s => s.trim()).filter(Boolean);

const client = createClient(url, key, { auth: { persistSession: false } });
const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
const outDir = process.argv[2] || join(dirname(new URL(import.meta.url).pathname), '..', 'backups');
const dir = join(outDir, stamp);
mkdirSync(dir, { recursive: true });

const summary = {};
for (const t of tables) {
  let all = [];
  let from = 0;
  const page = 1000;
  for (;;) {
    const { data, error } = await client.from(t).select('*').range(from, from + page - 1);
    if (error) {
      console.error(`  ✗ ${t}: ${error.message}`);
      summary[t] = { error: error.message };
      break;
    }
    all = all.concat(data || []);
    if (!data || data.length < page) break;
    from += page;
  }
  if (!summary[t]) {
    writeFileSync(join(dir, `${t}.json`), JSON.stringify(all, null, 2));
    summary[t] = { rows: all.length };
    console.log(`  ✓ ${t}: ${all.length} 行`);
  }
}

writeFileSync(join(dir, 'backup-summary.json'), JSON.stringify({ createdAt: new Date().toISOString(), summary }, null, 2));
console.log(`\n备份完成:${dir}`);
