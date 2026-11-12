// WELL WAY API 冒烟测试
// 验证匿名登录、RLS、车型筛选、聊天等核心链路是否可用。
//
// 用法(在 backend/scripts 目录):
//   npm install
//   npm run smoke
// 或:
//   node --env-file=../.env smoke-test.mjs

import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL;
const anonKey = process.env.SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  console.error('缺少 SUPABASE_URL / SUPABASE_ANON_KEY(请先配置 backend/.env)');
  process.exit(1);
}

const client = createClient(url, anonKey, { auth: { persistSession: false } });

let passed = 0;
let failed = 0;
const check = (name, ok, extra = '') => {
  if (ok) {
    passed += 1;
    console.log(`  ✓ ${name}`);
  } else {
    failed += 1;
    console.error(`  ✗ ${name}${extra ? ` → ${extra}` : ''}`);
  }
};

console.log('WELL WAY 冒烟测试开始\n');

// 1. 匿名登录
const { data: anon, error: signInErr } = await client.auth.signInAnonymously();
check('匿名登录', !signInErr && !!anon?.user, signInErr?.message ?? '');
const userId = anon?.user?.id;

// 2. 匿名账号自动建档
if (userId) {
  const { data: profile, error: profileErr } = await client
    .from('profiles')
    .select('id, nickname, email_bound')
    .eq('id', userId)
    .maybeSingle();
  check('匿名账号自动建档', !profileErr && profile?.id === userId, profileErr?.message ?? '');
} else {
  check('匿名账号自动建档', false, '无用户');
}

// 3. 品牌列表(公开读)
const { data: brands, error: brandsErr } = await client
  .from('brands')
  .select('id, name')
  .order('sort');
check('品牌列表', !brandsErr && Array.isArray(brands) && brands.length > 0, brandsErr?.message ?? '');

// 4. 车型筛选:类型 + 排量 + 评分排序
const { data: sport, error: sportErr } = await client
  .from('models')
  .select('id, name, model_type, displacement_cc, rating')
  .eq('model_type', '跑车')
  .gte('displacement_cc', 400)
  .order('rating', { ascending: false })
  .limit(5);
check('车型筛选(跑车/排量/评分)', !sportErr && Array.isArray(sport) && sport.length > 0, sportErr?.message ?? '');
if (sport?.length) {
  const sample = sport
    .slice(0, 3)
    .map((m) => `${m.name}(${m.displacement_cc}cc/${m.rating}分)`)
    .join('、');
  console.log(`     示例:${sample}`);
}

// 5. 关键字搜索
const { data: search, error: searchErr } = await client
  .from('models')
  .select('id, name')
  .ilike('name', '%450%');
check('关键字搜索(450)', !searchErr && Array.isArray(search) && search.length > 0, searchErr?.message ?? '');

// 6. 添加车辆(RLS 只允许自己的数据)
if (userId) {
  const { data: firstModel, error: modelErr } = await client
    .from('models')
    .select('id, brand_id')
    .limit(1)
    .maybeSingle();
  if (!modelErr && firstModel) {
    const { error: insertErr } = await client.from('vehicles').insert({
      user_id: userId,
      brand_id: firstModel.brand_id,
      model_id: firstModel.id,
      nickname: '冒烟测试车',
    });
    check('添加车辆(RLS)', !insertErr, insertErr?.message ?? '');
    if (!insertErr) {
      await client
        .from('vehicles')
        .delete()
        .eq('user_id', userId)
        .eq('nickname', '冒烟测试车');
    }
  } else {
    check('添加车辆(RLS)', false, '无车型数据');
  }
} else {
  check('添加车辆(RLS)', false, '无用户');
}

// 7. 无 UGC:聊天/活动/报名等社交表必须不存在(清单「骑手之间无任何交互」)
for (const table of ['route_chat_messages', 'activities', 'activity_registrations']) {
  const { error } = await client.from(table).select('*').limit(1);
  check(`UGC 表 ${table} 已下线`, !!error, '居然还能读到');
}

// 8. 城市限行(V1 清单新增,匿名即可查)
{
  const { data, error } = await client.rpc('moto_rule', { p_city_code: '110100' });
  const row = Array.isArray(data) ? data[0] : data;
  check('限行接口 moto_rule', !error && row?.found === true, error?.message ?? '');
}

if (userId) {
  await client.auth.signOut();
}

console.log(`\n结果:${passed} 通过,${failed} 失败`);
process.exit(failed > 0 ? 1 : 0);
