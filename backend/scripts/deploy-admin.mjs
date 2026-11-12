// 把管理后台(admin/index.html)部署到 Supabase 公开存储桶,得到公网地址
// 用法: node backend/scripts/deploy-admin.mjs
import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const env = Object.fromEntries(
  readFileSync(new URL('../.env', import.meta.url), 'utf8')
    .split('\n')
    .filter((l) => l.includes('='))
    .map((l) => {
      const i = l.indexOf('=');
      return [l.slice(0, i).trim(), l.slice(i + 1).trim()];
    })
);
const url = env.SUPABASE_URL;
const key = env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) {
  console.error('缺少 SUPABASE_URL 或 SUPABASE_SERVICE_ROLE_KEY');
  process.exit(1);
}

const sb = createClient(url, key, { auth: { persistSession: false } });
const BUCKET = 'admin-site';

const { data: buckets } = await sb.storage.listBuckets();
if (!buckets?.some((b) => b.name === BUCKET)) {
  const { error } = await sb.storage.createBucket(BUCKET, { public: true });
  if (error) {
    console.error('创建桶失败:', error.message);
    process.exit(1);
  }
  console.log('已创建公开桶', BUCKET);
} else {
  console.log('桶已存在');
}

const html = readFileSync(
  new URL('../../admin/index.html', import.meta.url),
  'utf8'
);
// 用带 type 的 Blob 上传(与浏览器 File 行为一致,Content-Type 会写入对象元数据)
const blob = new Blob([html], { type: 'text/html' });
let { error } = await sb.storage.from(BUCKET).upload('index.html', blob, {
  upsert: true,
});
if (error) {
  console.error('上传失败:', error.message);
  process.exit(1);
}

const { data } = sb.storage.from(BUCKET).getPublicUrl('index.html');
console.log('后台公网地址:', data.publicUrl);
const { data: info } = await sb.storage.from(BUCKET).info('index.html');
console.log('对象完整元数据:', JSON.stringify(info));
