// WELL WAY 骑行闭环契约测试:与 iOS RideService 调用完全一致
import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL;
const anonKey = process.env.SUPABASE_ANON_KEY;
const client = createClient(url, anonKey, { auth: { persistSession: false } });

let passed = 0, failed = 0;
const check = (name, ok, extra = '') => {
  ok ? (passed += 1, console.log(`  ✓ ${name}`)) : (failed += 1, console.error(`  ✗ ${name} → ${extra}`));
};

console.log('骑行闭环契约测试\n');
const { data: anon } = await client.auth.signInAnonymously();
const uid = anon?.user?.id;
check('匿名登录', !!uid, 'no user');

const iso = (d) => d.toISOString();

// 1. 取演示路线(四惠桥通勤线)+ 打卡点
const { data: routes } = await client.from('routes').select('id, name').eq('name', '四惠桥通勤线').limit(1);
const routeId = routes?.[0]?.id;
check('演示路线存在', !!routeId, JSON.stringify(routes));
const { data: cps } = await client.from('checkpoints').select('id, seq, lat, lng, radius_m').eq('route_id', routeId).order('seq');
check('打卡点存在', Array.isArray(cps) && cps.length > 0, JSON.stringify(cps));

// 2. 建骑行记录(in_progress)
const started = new Date();
const { data: rec, error: recErr } = await client.from('ride_records')
  .insert({ user_id: uid, route_id: routeId, started_at: iso(started), ended_at: iso(started), status: 'riding' })
  .select().single();
check('插入骑行记录', !recErr && rec?.id, recErr?.message ?? '');
const rideId = rec?.id;

// 3. 插入轨迹点(模拟 12 个点)
if (rideId) {
  const points = [];
  for (let i = 0; i < 12; i++) {
    points.push({
      ride_id: rideId,
      lat: 39.9 + i * 0.001,
      lng: 116.4 + i * 0.001,
      speed_kmh: 20 + (i % 5) * 3,
      recorded_at: iso(new Date(started.getTime() + i * 10000)),
    });
  }
  const { error: ptErr } = await client.from('ride_points').insert(points);
  check('批量插入轨迹点', !ptErr, ptErr?.message ?? '');

  // 4. 打卡(第一个打卡点)
  const { error: ckErr } = await client.from('ride_checkins')
    .insert({ ride_id: rideId, checkpoint_id: cps[0].id, user_id: uid });
  check('插入打卡记录', !ckErr, ckErr?.message ?? '');
}

// 5. 结束:更新状态
if (rideId) {
  const { error: upErr } = await client.from('ride_records')
    .update({ ended_at: iso(new Date()), status: 'completed' }).eq('id', rideId);
  check('更新记录为完成', !upErr, upErr?.message ?? '');

  // 6. 重算统计 RPC
  const { error: rpcErr } = await client.rpc('recalculate_ride_stats', { p_ride_id: rideId });
  check('recalculate_ride_stats RPC', !rpcErr, rpcErr?.message ?? '');

  const { data: stats } = await client.from('ride_records')
    .select('distance_m, duration_s, avg_speed_kmh, max_speed_kmh').eq('id', rideId).single();
  check('统计已回写', stats?.distance_m > 0 && stats?.duration_s > 0, JSON.stringify(stats));
}

// 7. 徽章:路线徽章 + award_badge;无路线徽章时兜底发全局徽章(与 App 一致)
const { data: badges } = await client.from('badges').select('id, name').eq('route_id', routeId).limit(1);
check('路线徽章存在', badges?.length > 0, JSON.stringify(badges));
let targetBadge = badges?.[0];
if (!targetBadge) {
  const { data: global } = await client.from('badges').select('id, name').is('route_id', null).order('seq').limit(1);
  targetBadge = global?.[0];
  check('全局徽章兜底', !!targetBadge, 'no global badge');
}
if (targetBadge && rideId) {
  const { error: badgeErr } = await client.rpc('award_badge', {
    p_user_id: uid, p_badge_id: targetBadge.id, p_ride_id: rideId,
  });
  check('award_badge RPC', !badgeErr, badgeErr?.message ?? '');
  const { data: mine } = await client.from('user_badges').select('id').eq('user_id', uid);
  check('徽章已入库', mine?.length > 0, JSON.stringify(mine));
}

// 8. 活动列表 + 报名
const { data: acts } = await client.from('activities_current').select('id, name, current_status');
check('活动视图可查', Array.isArray(acts), JSON.stringify(acts));
if (acts?.length) {
  const { error: regErr } = await client.from('activity_registrations')
    .insert({ activity_id: acts[0].id, user_id: uid });
  check('活动报名', !regErr, regErr?.message ?? '');
  const { error: dupErr } = await client.from('activity_registrations')
    .insert({ activity_id: acts[0].id, user_id: uid });
  check('重复报名被拦截(唯一约束)', !!dupErr, '预期冲突');
  const { data: myRegs } = await client.from('activity_registrations').select('activity_id').eq('user_id', uid);
  check('我的报名可查', myRegs?.length > 0, JSON.stringify(myRegs));
} else {
  check('活动报名', false, '无活动数据(可在管理后台添加)');
}

console.log(`\n结果: ${passed} 通过, ${failed} 失败`);
process.exit(failed > 0 ? 1 : 0);
