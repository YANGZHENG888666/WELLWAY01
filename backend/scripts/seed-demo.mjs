// 幂等补种 Figma 演示数据:3 条北京路线 + 打卡点 + 路线徽章 + 2 个活动
// 用 service_role 直插(绕过 RLS),不依赖 DDL。
import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) { console.error('缺少 SUPABASE_SERVICE_ROLE_KEY'); process.exit(1); }
const sb = createClient(url, key, { auth: { persistSession: false } });

const routes = [
  {
    name: '四惠桥通勤线', start_name: '四惠桥', end_name: '国贸',
    distance_m: 12600, elevation_m: 120, difficulty: '简单', duration_min: 45,
    checkpoints: [
      { name: '四惠桥', seq: 1, lat: 39.9087, lng: 116.4975, radius_m: 80 },
      { name: '东四环桥洞', seq: 2, lat: 39.9110, lng: 116.4920, radius_m: 80 },
      { name: '国贸', seq: 3, lat: 39.9086, lng: 116.4598, radius_m: 80 },
    ],
    badge: { name: '通勤骑士', condition: '完成「四惠桥通勤线」全路段', seq: 4 },
  },
  {
    name: '香山压弯线', start_name: '香山脚下', end_name: '鬼笑石',
    distance_m: 18200, elevation_m: 640, difficulty: '困难', duration_min: 130,
    checkpoints: [
      { name: '香山脚下', seq: 1, lat: 39.9906, lng: 116.1900, radius_m: 100 },
      { name: '鬼笑石', seq: 2, lat: 39.9720, lng: 116.1850, radius_m: 100 },
    ],
    badge: { name: '跑山骑士', condition: '完成「香山压弯线」全程', seq: 5 },
  },
  {
    name: '长安街夜骑线', start_name: '西单', end_name: '建国门',
    distance_m: 9800, elevation_m: 40, difficulty: '简单', duration_min: 35,
    checkpoints: [
      { name: '西单路口', seq: 1, lat: 39.9075, lng: 116.3740, radius_m: 80 },
      { name: '建国门桥', seq: 2, lat: 39.9078, lng: 116.4350, radius_m: 80 },
    ],
    badge: { name: '夜骑骑士', condition: '沿「长安街夜骑线」完成一次骑行', seq: 6 },
  },
];

for (const r of routes) {
  const { data: row, error } = await sb.from('routes')
    .insert({
      name: r.name, start_name: r.start_name, end_name: r.end_name,
      distance_m: r.distance_m, elevation_m: r.elevation_m,
      difficulty: r.difficulty, duration_min: r.duration_min, is_active: true,
    })
    .select('id, name')
    .single();
  if (error && error.code !== '23505') { console.error('route error', r.name, error.message); continue; }
  const routeId = row?.id ?? (await sb.from('routes').select('id').eq('name', r.name).single()).data?.id;
  if (!routeId) { console.error('no route id', r.name); continue; }

  for (const cp of r.checkpoints) {
    await sb.from('checkpoints').upsert(
      { route_id: routeId, name: cp.name, seq: cp.seq, lat: cp.lat, lng: cp.lng, radius_m: cp.radius_m },
      { onConflict: 'route_id,seq' }
    );
  }
  await sb.from('badges').upsert(
    { route_id: routeId, name: r.badge.name, condition_desc: r.badge.condition, seq: r.badge.seq },
    { onConflict: 'name' }
  );
  console.log('✓ 路线', r.name, routeId);
}

// 活动
const acts = [
  {
    name: '周末骑行挑战', route_name: '四惠桥通勤线', slots: 12,
    reward_desc: '完成挑战可获得限定徽章;完赛前 20 名额外获得骑行装备',
    starts: '2026-08-15T07:00:00+08:00', ends: '2026-08-15T12:00:00+08:00', status: 'upcoming',
  },
  {
    name: '夜骑长安街', route_name: '长安街夜骑线', slots: 28,
    reward_desc: '完赛可获得夜骑限定徽章与骑行装备',
    starts: '2026-08-22T20:00:00+08:00', ends: '2026-08-22T23:00:00+08:00', status: 'upcoming',
  },
];
for (const a of acts) {
  const { data: routeRow } = await sb.from('routes').select('id').eq('name', a.route_name).single();
  if (!routeRow) { console.error('no route for activity', a.route_name); continue; }
  const { data: exists } = await sb.from('activities').select('id').eq('name', a.name).maybeSingle();
  if (exists) { console.log('✓ 活动(已存在)', a.name); continue; }
  const { error: actErr } = await sb.from('activities').insert({
    name: a.name, route_id: routeRow.id, slots: a.slots,
    reward_desc: a.reward_desc, starts_at: a.starts, ends_at: a.ends, status: a.status,
  });
  if (actErr) { console.error('✗ 活动失败', a.name, actErr.message); continue; }
  console.log('✓ 活动', a.name);
}
console.log('补种完成');
