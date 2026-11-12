// 通用迁移执行器: 把指定 SQL 文件跑在云端数据库上(可重复执行)
// 前提: backend/.env 里配置 SUPABASE_DB_URL(数据库连接串)
// 用法: cd backend/scripts && node --env-file=../.env run-migration.mjs [相对路径]
// 默认执行 migrations/0013_admin_dashboard.sql
import { readFileSync } from 'node:fs';
import pg from 'pg';

const env = Object.fromEntries(
  readFileSync(new URL('../.env', import.meta.url), 'utf8')
    .split('\n')
    .filter((l) => l.includes('='))
    .map((l) => {
      const i = l.indexOf('=');
      return [l.slice(0, i).trim(), l.slice(i + 1).trim()];
    })
);

const dbUrl = env.SUPABASE_DB_URL;
if (!dbUrl || dbUrl.includes('你的')) {
  console.error(
    '缺少 SUPABASE_DB_URL。请在 backend/.env 里加一行:\n' +
      'SUPABASE_DB_URL=postgresql://postgres.<ref>:<密码>@aws-0-<区域>.pooler.supabase.com:5432/postgres\n' +
      '(在 Supabase Dashboard → 项目设置 → 数据库 → 连接字符串 复制整段)'
  );
  process.exit(1);
}

const rel = process.argv[2] || '../supabase/migrations/0013_admin_dashboard.sql';
const sqlPath = new URL(rel, import.meta.url);
const sql = readFileSync(sqlPath, 'utf8');

const client = new pg.Client({ connectionString: dbUrl, ssl: { rejectUnauthorized: false } });
await client.connect();
try {
  await client.query('begin');
  await client.query(sql);
  await client.query('commit');
  console.log('✅ 迁移执行成功:', rel);
} catch (e) {
  await client.query('rollback').catch(() => {});
  console.error('❌ 执行失败:', e.message);
  console.error('说明: 脚本可重复执行,若某一步报"已存在"说明之前已跑过,重跑即可。');
  process.exit(1);
} finally {
  await client.end().catch(() => {});
}
