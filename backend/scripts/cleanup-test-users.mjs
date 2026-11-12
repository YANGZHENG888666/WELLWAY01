// 清理自动化测试产生的匿名账号(8/12-8/21 测试残留)。
// 默认 dry-run 只打印将删除的账号;加 --apply 才真正执行(级联删除其 profiles/vehicles/rides 等)。
// 用法:
//   node --env-file=../.env cleanup-test-users.mjs            # 预览
//   node --env-file=../.env cleanup-test-users.mjs --apply    # 执行
// 保留名单见下方 KEEP,如需保留其他账号把 id 加进去。
import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) { console.error('缺少 SUPABASE_SERVICE_ROLE_KEY'); process.exit(1); }
const sb = createClient(url, key, { auth: { persistSession: false } });

// 保留名单:用户主账号(管理员)+ 截图演示账号
const KEEP = new Set([
  '67fecbe4-dc9a-49ab-b850-ccb1916aed0b', // 421975135@qq.com(你的账号,is_admin)
  'cd4f33a1-2e91-4c44-b6c3-5e5a57529ee7', // 截图演示数据账号
]);

const APPLY = process.argv.includes('--apply');

const { data, error } = await sb.auth.admin.listUsers({ perPage: 1000 });
if (error) { console.error('listUsers 失败:', error.message); process.exit(1); }

const users = data.users.filter(u => !KEEP.has(u.id));
console.log(`共 ${data.users.length} 个账号,保留 ${data.users.length - users.length} 个,待清理 ${users.length} 个` + (APPLY ? '(执行)' : '(dry-run)'));

for (const u of users) {
  console.log(`- ${u.id}  ${u.email || '(匿名)'}  创建:${(u.created_at || '').slice(0, 10)}  最近登录:${(u.last_sign_in_at || '').slice(0, 10) || '-'}`);
}

if (!APPLY) {
  console.log('\n未执行删除。确认无误后加 --apply 运行。');
  process.exit(0);
}

let ok = 0, fail = 0;
for (const u of users) {
  const { error: delErr } = await sb.auth.admin.deleteUser(u.id);
  if (delErr) { console.error(`删除失败 ${u.id} (${u.email || '匿名'}): ${delErr.message}`); fail++; }
  else { ok++; }
}
console.log(`\n删除完成:成功 ${ok},失败 ${fail}`);
