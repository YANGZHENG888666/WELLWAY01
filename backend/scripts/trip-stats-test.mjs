// 《V1 内测接口清单》第 5/6 节端到端验证:行程计划 + 匿名骑手统计 + 限行。
// 用两个真实账号(匿名登录,role=authenticated)走 HTTP API,验证:
//   trip_plan_create / trip_status_update / rider_count_to_dest / riders_nearby / moto_rule
// 跑完自动清理测试账号与测试数据。
// 用法: cd backend/scripts && node --env-file=../.env trip-stats-test.mjs
import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL;
const anonKey = process.env.SUPABASE_ANON_KEY;
const svcKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !anonKey || !svcKey) {
  console.error('缺少 SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY');
  process.exit(1);
}

let passed = 0;
let failed = 0;
const check = (name, ok, extra = '') => {
  if (ok) { passed += 1; console.log(`  ✓ ${name}`); }
  else { failed += 1; console.error(`  ✗ ${name}${extra ? ` → ${extra}` : ''}`); }
};

const newAnon = () => createClient(url, anonKey, { auth: { persistSession: false } });
const svc = createClient(url, svcKey, { auth: { persistSession: false } });

// 测试坐标:天安门附近
const DEST = { lat: 39.9042, lon: 116.4074 };
const createdUserIds = [];

const rpc = async (client, fn, params) => {
  const { data, error } = await client.rpc(fn, params);
  if (error) return { error: error.message };
  return { data: Array.isArray(data) ? data[0] : data };
};

console.log('行程 / 匿名统计 端到端测试\n');

// 0) 拿一条真实路线 id(ride_presence.route_id 外键)
const { data: routes, error: routeErr } = await svc.from('routes').select('id,name').limit(1);
if (routeErr || !routes?.length) {
  console.error('拿不到路线 id,无法测 riders_nearby:', routeErr?.message);
  process.exit(1);
}
const routeId = routes[0].id;

// 1) 两个账号
const A = newAnon();
const B = newAnon();
const { data: a, error: aErr } = await A.auth.signInAnonymously();
const { data: b, error: bErr } = await B.auth.signInAnonymously();
check('账号 A 登录', !aErr && !!a?.user, aErr?.message ?? '');
check('账号 B 登录', !bErr && !!b?.user, bErr?.message ?? '');
if (a?.user?.id) createdUserIds.push(a.user.id);
if (b?.user?.id) createdUserIds.push(b.user.id);
if (!a?.user || !b?.user) process.exit(1);

// 2) 限行:anon 也能查(不需要登录)
{
  const anonClient = newAnon();
  const r = await rpc(anonClient, 'moto_rule', { p_city_code: '110100' });
  check('moto_rule 匿名可查', !r.error && r.data?.found === true, r.error ?? '');
  check('moto_rule 带免责文案', !!r.data?.disclaimer, '');
  const miss = await rpc(anonClient, 'moto_rule', { p_city_code: '999999' });
  check('moto_rule 未收录城市 found=false', !miss.error && miss.data?.found === false, miss.error ?? '');
}

// 3) A 上报行程计划
const plan = await rpc(A, 'trip_plan_create', {
  p_dest_lat: DEST.lat, p_dest_lon: DEST.lon, p_dest_name: '测试目的地',
});
const tripId = plan.data?.trip_id;
check('trip_plan_create 返回 trip_id', !!tripId, plan.error ?? '');
check('新行程状态 = planned', plan.data?.status === 'planned', plan.error ?? '');

// 无鉴权调用必须失败(AUTH_REQUIRED)
{
  const anonClient = newAnon();
  const r = await rpc(anonClient, 'trip_plan_create', {
    p_dest_lat: DEST.lat, p_dest_lon: DEST.lon, p_dest_name: '越权',
  });
  check('未登录上报行程被拒', !!r.error, '居然成功了');
}

// 4) 人数统计:A 自己看不到自己,B 能看到 A
{
  const own = await rpc(A, 'rider_count_to_dest', { p_dest_lat: DEST.lat, p_dest_lon: DEST.lon });
  check('rider_count_to_dest 不含自己', own.data?.count === 0, JSON.stringify(own.data ?? own.error));
  const other = await rpc(B, 'rider_count_to_dest', { p_dest_lat: DEST.lat, p_dest_lon: DEST.lon });
  check('rider_count_to_dest B 看到 1 人', other.data?.count === 1, JSON.stringify(other.data ?? other.error));
  const far = await rpc(B, 'rider_count_to_dest', { p_dest_lat: 31.2304, p_dest_lon: 121.4737 });
  check('rider_count_to_dest 异地为 0', far.data?.count === 0, JSON.stringify(far.data ?? far.error));
}

// 5) riders_nearby:三种方位场景(只返回数字)
const setPresence = async (lat, lng, bearing) => {
  const { error } = await A.from('ride_presence').upsert({
    user_id: a.user.id, route_id: routeId, lat, lng, bearing, speed_kmh: 42.5,
    trip_id: tripId, nickname: '不应被返回', vehicle_name: '不应被返回',
  });
  return error?.message;
};
const B_POS = { lat: 39.9042, lon: 116.4074 };

{
  // 场景 1:A 在 B 正北 333m,同向北行 → 前方同向,不算"后方同向"
  const err = await setPresence(39.9072, 116.4074, 0);
  check('写入位置心跳', !err, err ?? '');
  const r = await rpc(B, 'riders_nearby', { p_lat: B_POS.lat, p_lon: B_POS.lon, p_bearing: 0 });
  check('riders_nearby 总数 = 1', r.data?.total === 1, JSON.stringify(r.data ?? r.error));
  check('前方同向不计入 behind', r.data?.behind_same_direction === 0, JSON.stringify(r.data ?? r.error));
  check('riders_nearby 不泄露昵称/车型', !JSON.stringify(r.data ?? {}).includes('不应被返回'), '');
}
{
  // 场景 2:A 在 B 正南 333m 同向北行 → 后方同向
  await setPresence(39.9012, 116.4074, 0);
  const r = await rpc(B, 'riders_nearby', { p_lat: B_POS.lat, p_lon: B_POS.lon, p_bearing: 0 });
  check('后方同向 = 1', r.data?.behind_same_direction === 1, JSON.stringify(r.data ?? r.error));
  check('对向 = 0', r.data?.oncoming === 0, JSON.stringify(r.data ?? r.error));
}
{
  // 场景 3:A 在 B 正南 333m 反向(南行)→ 对向驶来
  await setPresence(39.9012, 116.4074, 180);
  const r = await rpc(B, 'riders_nearby', { p_lat: B_POS.lat, p_lon: B_POS.lon, p_bearing: 0 });
  check('对向驶来 = 1', r.data?.oncoming === 1, JSON.stringify(r.data ?? r.error));
  check('对向时 behind = 0', r.data?.behind_same_direction === 0, JSON.stringify(r.data ?? r.error));
}
{
  // 场景 4:超出半径(5km 外)
  await setPresence(39.9500, 116.4074, 0);
  const r = await rpc(B, 'riders_nearby', { p_lat: B_POS.lat, p_lon: B_POS.lon, p_bearing: 0 });
  check('超出半径不计入', r.data?.total === 0, JSON.stringify(r.data ?? r.error));
}
{
  // 自己看不到自己
  const r = await rpc(A, 'riders_nearby', { p_lat: 39.9500, p_lon: 116.4074, p_bearing: 0 });
  check('riders_nearby 不含自己', r.data?.total === 0, JSON.stringify(r.data ?? r.error));
}

// 6) 行程状态流转
{
  const riding = await rpc(A, 'trip_status_update', { p_trip_id: tripId, p_status: 'riding' });
  check('状态 → riding', riding.data?.status === 'riding', riding.error ?? '');
  const bad = await rpc(A, 'trip_status_update', { p_trip_id: tripId, p_status: 'nonsense' });
  check('非法状态被拒', !!bad.error, '居然成功了');

  // riding 中 B 仍能看到 A 计划前往
  const cnt = await rpc(B, 'rider_count_to_dest', { p_dest_lat: DEST.lat, p_dest_lon: DEST.lon });
  check('riding 中仍计入人数', cnt.data?.count === 1, JSON.stringify(cnt.data ?? cnt.error));

  const fin = await rpc(A, 'trip_status_update', { p_trip_id: tripId, p_status: 'finished' });
  check('状态 → finished', fin.data?.status === 'finished', fin.error ?? '');

  const cnt2 = await rpc(B, 'rider_count_to_dest', { p_dest_lat: DEST.lat, p_dest_lon: DEST.lon });
  check('结束后退出人数统计', cnt2.data?.count === 0, JSON.stringify(cnt2.data ?? cnt2.error));

  const { data: rows } = await svc.from('ride_presence').select('user_id').eq('user_id', a.user.id);
  check('结束后位置心跳被清掉', (rows?.length ?? 0) === 0, `仍有 ${rows?.length ?? 0} 行`);
}

// 7) 轨迹删除(清单:历史轨迹仅本人可见,支持用户删除)
{
  const { data: rec, error } = await A.from('ride_records')
    .insert({ user_id: a.user.id, status: 'completed', distance_m: 1000, duration_s: 60 })
    .select('id').single();
  if (error) {
    check('建轨迹记录', false, error.message);
  } else {
    const { error: ptErr } = await A.from('ride_points').insert({
      ride_id: rec.id, lat: DEST.lat, lng: DEST.lon,
      bearing: 12.5, recorded_at: new Date().toISOString(),
    });
    const { data: pts } = await A.from('ride_points').select('bearing').eq('ride_id', rec.id);
    check('轨迹点带 bearing 落库', !ptErr && pts?.[0]?.bearing === 12.5, ptErr?.message ?? JSON.stringify(pts ?? ''));
    const { error: delErr } = await A.from('ride_records').delete().eq('id', rec.id);
    check('本人可删除自己的轨迹', !delErr, delErr?.message ?? '');
    const { data: left } = await svc.from('ride_points').select('id').eq('ride_id', rec.id);
    check('轨迹点级联删除', (left?.length ?? 0) === 0, `残留 ${left?.length ?? 0}`);
  }
}

// 8) 隐私协议确认落库
{
  const { error } = await A.from('profiles')
    .update({ privacy_agreed_at: new Date().toISOString() }).eq('id', a.user.id);
  check('profiles.privacy_agreed_at 可写', !error, error?.message ?? '');
}

// 清理:测试行程 + 测试账号
await svc.from('ride_presence').delete().in('user_id', createdUserIds);
await svc.from('trip_plans').delete().in('user_id', createdUserIds);
for (const id of createdUserIds) {
  const { error } = await svc.auth.admin.deleteUser(id);
  if (error) console.error('  清理账号失败:', id, error.message);
}
console.log(`\n清理完成:删掉 ${createdUserIds.length} 个测试账号及其行程/心跳`);

console.log(`\n结果:${passed} 通过,${failed} 失败`);
process.exit(failed ? 1 : 0);
