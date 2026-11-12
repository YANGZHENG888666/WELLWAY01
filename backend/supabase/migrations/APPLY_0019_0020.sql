-- ===== WELL WAY V1 内测迁移合并包:0019 + 0020 =====

-- ================= 0019: 行程计划 + 匿名骑手统计 + 轨迹删除 + 隐私确认 =================
-- 对应《V1 内测・最终定稿 接口清单》:
--   · 行程与匿名骑手统计(POST /api/trip/plan、PUT /api/trip/status、
--     GET /api/rider/count、GET /api/rider/nearby)
--   · 骑行轨迹:点位 bearing 上报、用户删除自己的轨迹
--   · 用户账号:隐私协议确认落库
-- 全部可重复执行;骑手统计一律只返回聚合数字,不返回任何个人信息。
-- 在 Supabase Dashboard → SQL Editor 整体粘贴执行。

-- ---------------------------------------------------------------
-- 0) 固定免责文案(唯一来源,接口与 App 共用同一份)
-- ---------------------------------------------------------------
create or replace function public.disclaimer_text()
returns text
language sql
immutable
as $$
  select '⚠️ 提示:本 APP 仅展示城市摩托车限行政策文字摘要、天气参考。点击导航将跳转至高德地图,请手动切换高德摩托车路线。位置统计存在 GPS 延迟、定位误差;骑手数量仅匿名汇总数字,不可作为道路会车、避险判断依据。政策、天气存在变动,信息仅供参考,出行请以交管、气象官方公告为准,不可作为通行唯一依据。'
$$;

grant execute on function public.disclaimer_text() to anon, authenticated;

-- 公共地理计算(haversine 距离 / 航向角差),供下面两个统计函数复用
create or replace function public.haversine_m(
  p_lat1 double precision, p_lon1 double precision,
  p_lat2 double precision, p_lon2 double precision
)
returns double precision
language sql
immutable
as $$
  select 6371000 * 2 * asin(least(1.0, sqrt(
    power(sin(radians(p_lat2 - p_lat1) / 2), 2) +
    cos(radians(p_lat1)) * cos(radians(p_lat2)) *
    power(sin(radians(p_lon2 - p_lon1) / 2), 2)
  )))
$$;

-- 两个航向角的最小夹角(0..180)
create or replace function public.bearing_delta(p_a double precision, p_b double precision)
returns double precision
language sql
immutable
as $$
  -- double precision 没有 % 运算符,统一转 numeric 再取模
  select abs((((p_a - p_b + 540)::numeric % 360) - 180)::double precision)
$$;

grant execute on function public.haversine_m(double precision, double precision, double precision, double precision) to anon, authenticated;
grant execute on function public.bearing_delta(double precision, double precision) to anon, authenticated;

-- ---------------------------------------------------------------
-- 1) 隐私协议确认落库
-- ---------------------------------------------------------------
alter table public.profiles add column if not exists privacy_agreed_at timestamptz;

-- ---------------------------------------------------------------
-- 2) 行程计划 trip_plans
--    一个人同一时间只有一条状态为 planned/riding 的行程(部分唯一索引保证)
-- ---------------------------------------------------------------
create table if not exists public.trip_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'planned'
    check (status in ('planned', 'riding', 'finished', 'canceled')),
  dest_lat double precision not null,
  dest_lon double precision not null,
  dest_name text,
  start_lat double precision,
  start_lon double precision,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  started_at timestamptz,
  ended_at timestamptz
);

create index if not exists idx_trip_plans_user on public.trip_plans(user_id, created_at desc);
create index if not exists idx_trip_plans_active on public.trip_plans(status, updated_at desc);
create unique index if not exists uniq_trip_active_per_user
  on public.trip_plans(user_id) where status in ('planned', 'riding');

alter table public.trip_plans enable row level security;

drop policy if exists "trip_plans_select_own" on public.trip_plans;
drop policy if exists "trip_plans_insert_own" on public.trip_plans;
drop policy if exists "trip_plans_update_own" on public.trip_plans;
drop policy if exists "trip_plans_delete_own" on public.trip_plans;
create policy "trip_plans_select_own" on public.trip_plans
  for select using (user_id = auth.uid());
create policy "trip_plans_insert_own" on public.trip_plans
  for insert with check (user_id = auth.uid());
create policy "trip_plans_update_own" on public.trip_plans
  for update using (user_id = auth.uid());
create policy "trip_plans_delete_own" on public.trip_plans
  for delete using (user_id = auth.uid());

drop trigger if exists trg_trip_plans_updated on public.trip_plans;
create trigger trg_trip_plans_updated
before update on public.trip_plans
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------
-- 3) 创建行程计划 POST /api/trip/plan
--    先把该用户其它未结束的行程置为 canceled(一人同时只算一个行程)
-- ---------------------------------------------------------------
create or replace function public.trip_plan_create(
  p_dest_lat double precision,
  p_dest_lon double precision,
  p_dest_name text default null,
  p_start_lat double precision default null,
  p_start_lon double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.trip_plans;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED: 未登录';
  end if;
  if p_dest_lat is null or p_dest_lon is null
     or abs(p_dest_lat) > 90 or abs(p_dest_lon) > 180 then
    raise exception 'BAD_COORD: 经纬度非法';
  end if;

  update public.trip_plans
     set status = 'canceled', ended_at = coalesce(ended_at, now())
   where user_id = v_uid and status in ('planned', 'riding');

  insert into public.trip_plans
    (user_id, status, dest_lat, dest_lon, dest_name, start_lat, start_lon)
  values
    (v_uid, 'planned', p_dest_lat, p_dest_lon, p_dest_name, p_start_lat, p_start_lon)
  returning * into v_row;

  return jsonb_build_object(
    'trip_id', v_row.id,
    'status', v_row.status,
    'dest_lat', v_row.dest_lat,
    'dest_lon', v_row.dest_lon,
    'dest_name', v_row.dest_name,
    'created_at', v_row.created_at
  );
end;
$$;

grant execute on function public.trip_plan_create(double precision, double precision, text, double precision, double precision)
  to authenticated;

-- ---------------------------------------------------------------
-- 4) 更新行程状态 PUT /api/trip/status
--    finished / canceled 时顺手清掉位置心跳,立即退出附近统计
-- ---------------------------------------------------------------
create or replace function public.trip_status_update(
  p_trip_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.trip_plans;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED: 未登录';
  end if;
  if p_status is null or p_status not in ('planned', 'riding', 'finished', 'canceled') then
    raise exception 'TRIP_STATUS_INVALID: %', coalesce(p_status, 'null');
  end if;

  update public.trip_plans
     set status = p_status,
         started_at = case
           when p_status = 'riding' and started_at is null then now()
           else started_at
         end,
         ended_at = case
           when p_status in ('finished', 'canceled') then now()
           else ended_at
         end
   where id = p_trip_id and user_id = v_uid
  returning * into v_row;

  if v_row.id is null then
    raise exception 'TRIP_NOT_FOUND: %', p_trip_id;
  end if;

  if p_status in ('finished', 'canceled') then
    delete from public.ride_presence where user_id = v_uid;
  end if;

  return jsonb_build_object(
    'trip_id', v_row.id,
    'status', v_row.status,
    'started_at', v_row.started_at,
    'ended_at', v_row.ended_at
  );
end;
$$;

grant execute on function public.trip_status_update(uuid, text) to authenticated;

-- ---------------------------------------------------------------
-- 5) 目的地计划前往骑手总人数 GET /api/rider/count
--    口径:状态 planned/riding + 2 小时内活跃 + 目的地落在半径内,去重人数
-- ---------------------------------------------------------------
create or replace function public.rider_count_to_dest(
  p_dest_lat double precision,
  p_dest_lon double precision,
  p_radius_m integer default 3000
)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  with candidates as (
    select distinct t.user_id
    from public.trip_plans t
    where t.status in ('planned', 'riding')
      and t.updated_at > now() - interval '120 minutes'
      and (auth.uid() is null or t.user_id <> auth.uid())
      and public.haversine_m(p_dest_lat, p_dest_lon, t.dest_lat, t.dest_lon)
            <= greatest(coalesce(p_radius_m, 3000), 100)
  )
  select jsonb_build_object(
    'count', (select count(*) from candidates),
    'radius_m', greatest(coalesce(p_radius_m, 3000), 100),
    'active_window_min', 120,
    'disclaimer', public.disclaimer_text()
  );
$$;

grant execute on function public.rider_count_to_dest(double precision, double precision, integer)
  to anon, authenticated;

-- ---------------------------------------------------------------
-- 6) 沿途附近匿名骑手统计 GET /api/rider/nearby
--    数据源 ride_presence(骑行中位置心跳),先补 bearing / speed / trip_id
-- ---------------------------------------------------------------
alter table public.ride_presence add column if not exists bearing double precision;
alter table public.ride_presence add column if not exists speed_kmh numeric(5,1);
alter table public.ride_presence add column if not exists trip_id uuid references public.trip_plans(id) on delete set null;

create or replace function public.riders_nearby(
  p_lat double precision,
  p_lon double precision,
  p_bearing double precision default null,
  p_radius_m integer default 2000
)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  with cfg as (
    select
      p_lat as lat,
      p_lon as lon,
      case when p_bearing is null then null
        else (((p_bearing::numeric % 360) + 360) % 360)::double precision end as brg,
      greatest(coalesce(p_radius_m, 2000), 200) as radius_m
  ),
  cand as (
    select
      r.user_id,
      r.bearing as other_brg,
      public.haversine_m(cfg.lat, cfg.lon, r.lat, r.lng) as dist_m,
      -- 对方相对我的方位角(0=正北,顺时针)
      degrees(atan2(
        sin(radians(r.lng - cfg.lon)) * cos(radians(r.lat)),
        cos(radians(cfg.lat)) * sin(radians(r.lat))
          - sin(radians(cfg.lat)) * cos(radians(r.lat)) * cos(radians(r.lng - cfg.lon))
      )) as azimuth_deg
    from public.ride_presence r, cfg
    where r.updated_at > now() - interval '120 seconds'
      and (auth.uid() is null or r.user_id <> auth.uid())
      and public.haversine_m(cfg.lat, cfg.lon, r.lat, r.lng) <= cfg.radius_m
  ),
  classified as (
    select
      c.*,
      cfg.brg as my_brg,
      case
        when c.other_brg is null or cfg.brg is null then null
        else public.bearing_delta(c.other_brg, cfg.brg)
      end as brg_delta,
      case
        when cfg.brg is null then null
        else public.bearing_delta(c.azimuth_deg, cfg.brg) > 90
      end as is_behind
    from cand c, cfg
  )
  select jsonb_build_object(
    'total', (select count(*) from classified),
    'behind_same_direction',
      (select count(*) from classified
        where brg_delta is not null and brg_delta <= 60 and is_behind is true),
    'oncoming',
      (select count(*) from classified
        where brg_delta is not null and brg_delta >= 120),
    'unknown_direction',
      (select count(*) from classified where brg_delta is null),
    'bearing',
      (select brg from cfg),
    'radius_m',
      (select radius_m from cfg),
    'fresh_seconds', 120,
    'disclaimer', public.disclaimer_text()
  );
$$;

grant execute on function public.riders_nearby(double precision, double precision, double precision, integer)
  to anon, authenticated;

-- ---------------------------------------------------------------
-- 7) 轨迹:点位航向 + 用户删除自己的轨迹
-- ---------------------------------------------------------------
alter table public.ride_points add column if not exists bearing double precision;

drop policy if exists "rides_delete_own" on public.ride_records;
create policy "rides_delete_own" on public.ride_records
  for delete using (user_id = auth.uid());

drop policy if exists "points_delete_own" on public.ride_points;
create policy "points_delete_own" on public.ride_points
  for delete using (
    exists (
      select 1 from public.ride_records r
      where r.id = ride_points.ride_id and r.user_id = auth.uid()
    )
  );

-- 校验(执行后可跑一遍):
-- select public.disclaimer_text();
-- select public.rider_count_to_dest(39.9087, 116.3975, 3000);
-- select public.riders_nearby(39.9087, 116.3975, 78.4, 2000);


-- ================= 0020: 城市摩托车限行规则 =================
-- 对应《V1 内测・最终定稿 接口清单》第 3 节 GET /api/moto/rules
-- 设计口径:
--   · 只存"交管公告的文字摘要 + 来源链接",不做任何算法判定(不判定某辆车能不能走);
--   · 规则原文必须人工核对后录入,列表里 verified=false 的条目 App 会额外提示"待核对";
--   · 本迁移只把城市清单铺好,rule_text 留空,由运营按城市逐条补齐(附填写模板在文件末尾)。
-- 可重复执行。

-- ---------------------------------------------------------------
-- 1) 规则表
-- ---------------------------------------------------------------
create table if not exists public.moto_rules (
  city_code text primary key,              -- 行政区划代码,如 110100
  city_name text not null,                 -- 北京市
  province text,                           -- 北京
  rule_text text,                          -- 交管公告摘要(纯文本,可含换行)
  source_url text,                         -- 来源链接(交管官网/政府公告)
  effective_from date,                     -- 该摘要对应政策的生效日期
  verified boolean not null default false, -- 是否已人工核对
  verified_by text,                        -- 核对人(内测阶段记个名字即可)
  updated_at timestamptz not null default now()
);

alter table public.moto_rules enable row level security;

drop policy if exists "moto_rules_select_all" on public.moto_rules;
drop policy if exists "moto_rules_admin_write" on public.moto_rules;
drop policy if exists "moto_rules_admin_update" on public.moto_rules;
drop policy if exists "moto_rules_admin_delete" on public.moto_rules;

-- 所有人可读(规则是公开信息)
create policy "moto_rules_select_all" on public.moto_rules
  for select using (true);

-- 只有管理员可维护(复用已有的 public.is_admin())
create policy "moto_rules_admin_write" on public.moto_rules
  for insert with check (public.is_admin());
create policy "moto_rules_admin_update" on public.moto_rules
  for update using (public.is_admin());
create policy "moto_rules_admin_delete" on public.moto_rules
  for delete using (public.is_admin());

drop trigger if exists trg_moto_rules_updated on public.moto_rules;
create trigger trg_moto_rules_updated
before update on public.moto_rules
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------
-- 2) 查询接口 GET /api/moto/rules → rpc/moto_rule
--    入参可以是行政区划代码(110100)也可以是城市名(北京市/北京)
-- ---------------------------------------------------------------
create or replace function public.moto_rule(p_city_code text)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  with hit as (
    select r.*
    from public.moto_rules r
    where p_city_code is not null
      and length(trim(p_city_code)) > 0
      and (
        r.city_code = trim(p_city_code)
        or r.city_name = trim(p_city_code)
        or r.city_name = trim(p_city_code) || '市'
        or replace(r.city_name, '市', '') = replace(trim(p_city_code), '市', '')
      )
    limit 1
  )
  select case
    when exists (select 1 from hit) then (
      select jsonb_build_object(
        'found', true,
        'city_code', h.city_code,
        'city_name', h.city_name,
        'province', h.province,
        'rule_text', h.rule_text,
        'source_url', h.source_url,
        'effective_from', h.effective_from,
        'verified', h.verified,
        'updated_at', h.updated_at,
        'disclaimer', public.disclaimer_text()
      )
      from hit h
    )
    else jsonb_build_object(
      'found', false,
      'city_code', p_city_code,
      'city_name', null,
      'rule_text', null,
      'verified', false,
      'disclaimer', public.disclaimer_text()
    )
  end;
$$;

grant execute on function public.moto_rule(text) to anon, authenticated;

-- ---------------------------------------------------------------
-- 3) 城市清单(rule_text 留空 = 待录入)
--    录入后 App 端会自动显示;verified 由运营核对官方公告后置 true
-- ---------------------------------------------------------------
insert into public.moto_rules (city_code, city_name, province, verified) values
  ('110100', '北京市', '北京', false),
  ('120100', '天津市', '天津', false),
  ('310100', '上海市', '上海', false),
  ('440100', '广州市', '广东', false),
  ('440300', '深圳市', '广东', false),
  ('330100', '杭州市', '浙江', false),
  ('320100', '南京市', '江苏', false),
  ('510100', '成都市', '四川', false),
  ('500100', '重庆市', '重庆', false),
  ('420100', '武汉市', '湖北', false),
  ('610100', '西安市', '陕西', false),
  ('350200', '厦门市', '福建', false)
on conflict (city_code) do nothing;

-- ---------------------------------------------------------------
-- 4) 录入模板(复制到 SQL Editor 改内容执行;或走管理后台)
-- ---------------------------------------------------------------
-- update public.moto_rules set
--   rule_text = '1) ……;' || chr(10) || '2) ……;',
--   source_url = 'https://……',
--   effective_from = '2025-01-01',
--   verified = true,
--   verified_by = '内测运营'
-- where city_code = '110100';

-- 校验:
-- select public.moto_rule('110100');
-- select public.moto_rule('北京市');
-- select public.moto_rule('330100');
