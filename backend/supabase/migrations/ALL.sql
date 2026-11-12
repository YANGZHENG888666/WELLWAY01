-- WELL WAY: 一键执行全部待执行迁移(0006 + 0007,可重复执行)
-- 在 Supabase Dashboard → SQL Editor 中整体粘贴本文件执行即可。
-- ================= 0006: 活动计数 + 骑行记录名称 =================
-- WELL WAY: 骑行记录自定义名称(活动相关已随 0014 移除)
-- 在 Supabase Dashboard → SQL Editor 中执行本文件。

-- 骑行记录自定义名称(重命名记录,跨设备同步)
alter table public.ride_records add column if not exists name text;

-- ================= 0007: 同路骑士 + 反馈 =================
-- WELL WAY: 同路骑士实时位置上报 + 反馈落库
-- 在 Supabase Dashboard → SQL Editor 中执行本文件(可与 0006 一起执行)。

-- ---------------------------------------------------------------
-- 1. 骑行中匿名位置心跳(仅供聚合人数统计)
--    行数据临时性:每次写入时自动清理 15 分钟未更新的旧行。
-- ---------------------------------------------------------------
create table if not exists public.ride_presence (
  user_id uuid primary key references auth.users(id) on delete cascade,
  route_id bigint not null references public.routes(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  vehicle_name text,
  nickname text,
  updated_at timestamptz not null default now()
);

alter table public.ride_presence enable row level security;

-- 仅本人可读；其他骑手只能通过聚合函数拿到人数
-- 可重复执行:先删后建
drop policy if exists "ride_presence_select" on public.ride_presence;
drop policy if exists "ride_presence_insert_own" on public.ride_presence;
drop policy if exists "ride_presence_update_own" on public.ride_presence;
drop policy if exists "ride_presence_delete_own" on public.ride_presence;
drop policy if exists "ride_presence_select_own" on public.ride_presence;
create policy "ride_presence_select_own" on public.ride_presence
  for select using (user_id = auth.uid());
create policy "ride_presence_insert_own" on public.ride_presence
  for insert with check (user_id = auth.uid());
create policy "ride_presence_update_own" on public.ride_presence
  for update using (user_id = auth.uid());
create policy "ride_presence_delete_own" on public.ride_presence
  for delete using (user_id = auth.uid());

-- 过期清理(15 分钟未上报即视为已离开)
create or replace function public.cleanup_ride_presence()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.ride_presence
  where updated_at < now() - interval '15 minutes';
  return coalesce(new, old);
end; $$;

drop trigger if exists trg_ride_presence_cleanup on public.ride_presence;
create trigger trg_ride_presence_cleanup
after insert or update on public.ride_presence
for each row execute function public.cleanup_ride_presence();

-- ---------------------------------------------------------------
-- 2. 意见反馈(App 内提交,管理后台可查看)
-- ---------------------------------------------------------------
create table if not exists public.feedback (
  id bigserial primary key,
  user_id uuid references auth.users(id) on delete set null,
  content text not null,
  contact text,
  app_version text,
  created_at timestamptz not null default now()
);

alter table public.feedback enable row level security;

drop policy if exists "feedback_insert" on public.feedback;
drop policy if exists "feedback_select_own" on public.feedback;
create policy "feedback_insert" on public.feedback
  for insert with check (true);
create policy "feedback_select_own" on public.feedback
  for select using (user_id = auth.uid());

-- 0008: 路线收藏
create table if not exists public.route_favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  route_id bigint not null references public.routes(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, route_id)
);

alter table public.route_favorites enable row level security;

drop policy if exists "route_favorites_select_own" on public.route_favorites;
create policy "route_favorites_select_own" on public.route_favorites
  for select using (auth.uid() = user_id);

drop policy if exists "route_favorites_insert_own" on public.route_favorites;
create policy "route_favorites_insert_own" on public.route_favorites
  for insert with check (auth.uid() = user_id);

drop policy if exists "route_favorites_delete_own" on public.route_favorites;
create policy "route_favorites_delete_own" on public.route_favorites
  for delete using (auth.uid() = user_id);

-- ================= 0009: 骑行统计安全加固 =================
-- WELL WAY: 骑行统计安全加固(可重复执行)
-- 修复:定位跳变导致 recalculate_ride_stats 数值溢出(numeric(5,1) overflow)
-- 1) 过滤相邻轨迹点 >1000m 的跳变段 2) 平均/最大速度封顶 300 km/h
-- 在 Supabase Dashboard → SQL Editor 中粘贴执行。

create or replace function public.recalculate_ride_stats(p_ride_id uuid)
returns void
language plpgsql
as $$
declare
  v_distance_m int;
  v_duration_s int;
  v_avg_kmh numeric(5,1);
  v_max_kmh numeric(5,1);
begin
  with pts as (
    select
      lat,
      lng,
      speed_kmh,
      recorded_at,
      lag(lat) over (order by recorded_at) as prev_lat,
      lag(lng) over (order by recorded_at) as prev_lng
    from public.ride_points
    where ride_id = p_ride_id
  ),
  seg as (
    select
      case
        when prev_lat is not null then
          6371000 * 2 * asin(sqrt(
            power(sin(radians(lat - prev_lat) / 2), 2) +
            cos(radians(prev_lat)) * cos(radians(lat)) *
            power(sin(radians(lng - prev_lng) / 2), 2)
          ))
        else 0
      end as seg_m,
      speed_kmh
    from pts
  ),
  clean as (
    -- 过滤定位跳变段(>1000m)与异常速度,防止脏定位撑爆里程/平均速度
    select
      case when seg_m <= 1000 then seg_m else 0 end as seg_m,
      least(coalesce(speed_kmh, 0), 300) as speed_kmh
    from seg
  )
  select
    coalesce(round(sum(seg_m))::int, 0),
    coalesce(max(speed_kmh), 0)
  into v_distance_m, v_max_kmh
  from clean;

  select
    coalesce(extract(epoch from (max(recorded_at) - min(recorded_at)))::int, 0)
  into v_duration_s
  from public.ride_points
  where ride_id = p_ride_id;

  v_avg_kmh := case
    when v_duration_s > 0
      then least(round((v_distance_m::numeric / 1000.0) / (v_duration_s::numeric / 3600.0), 1), 300)
      else 0
  end;

  update public.ride_records
  set
    distance_m = v_distance_m,
    duration_s = v_duration_s,
    avg_speed_kmh = v_avg_kmh,
    max_speed_kmh = case when v_max_kmh > 0 then v_max_kmh else max_speed_kmh end
  where id = p_ride_id;
end;
$$;

grant execute on function public.recalculate_ride_stats(uuid) to anon, authenticated;

-- ================= 0010: 路线图 map_url =================
-- 路线图: routes 增加 map_url,存储上传到 route-images 桶的路线图(上传时已转高分辨率 PNG)
alter table public.routes
  add column if not exists map_url text;

-- route-images 桶(若 0004 未执行过则补建)
insert into storage.buckets (id, name, public) values
  ('route-images', 'route-images', true)
on conflict (id) do nothing;

drop policy if exists "route_images_read_public" on storage.objects;
create policy "route_images_read_public" on storage.objects
for select to anon, authenticated
using (bucket_id = 'route-images');

drop policy if exists "route_images_admin_write" on storage.objects;
create policy "route_images_admin_write" on storage.objects
for all to authenticated
using (bucket_id = 'route-images' and public.is_admin())
with check (bucket_id = 'route-images' and public.is_admin());

-- ================= 0011: 管理操作日志 =================
-- 在 Supabase Dashboard → SQL Editor 中执行本文件。

-- 1. 日志表
create table if not exists public.admin_logs (
  id bigint generated always as identity primary key,
  table_name text not null,
  action text not null check (action in ('INSERT','UPDATE','DELETE')),
  row_id text,
  old_data jsonb,
  new_data jsonb,
  actor_id uuid references auth.users(id) on delete set null,
  actor_email text,
  created_at timestamptz not null default now()
);

create index if not exists admin_logs_created_at_idx on public.admin_logs (created_at desc);
create index if not exists admin_logs_table_idx on public.admin_logs (table_name, created_at desc);

alter table public.admin_logs enable row level security;

-- 2. 只有管理员可读
drop policy if exists "admin_logs_admin_select" on public.admin_logs;
create policy "admin_logs_admin_select" on public.admin_logs
for select to authenticated
using (public.is_admin());

-- 3. 触发函数:INSERT/UPDATE/DELETE 落日志(security definer 由 postgres 执行,绕过 RLS)
create or replace function public.log_content_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.admin_logs (table_name, action, row_id, old_data, new_data, actor_id, actor_email)
  values (
    tg_table_name,
    tg_op,
    coalesce((new.id)::text, (old.id)::text),
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end,
    auth.uid(),
    nullif(auth.jwt() ->> 'email', '')
  );
  return coalesce(new, old);
end
$$;

-- 4. 挂到管理内容表(可重复执行)
do $$
declare t text;
begin
  foreach t in array array['brands','models','routes','checkpoints','badges'] loop
    execute format('drop trigger if exists trg_admin_log on public.%I', t);
    execute format('create trigger trg_admin_log after insert or update or delete on public.%I for each row execute function public.log_content_change()', t);
  end loop;
end
$$;

-- 5. 权限(沿用默认授权;触发函数已由 postgres 执行,无需额外授权)
grant all on table public.admin_logs to authenticated;

-- ================= 0015: 匿名轻社交(同路骑友徽章数) =================
-- WELL WAY: 匿名轻社交 - 只展示车型 + 徽章信息,不暴露昵称/主页/聊天
-- 安全聚合函数:仅返回「当前在骑行中(ride_presence 有活跃上报)」骑友的徽章数量,
-- 不返回任何个人资料;个人资料、主页、聊天入口均已随 0014 移除。
-- 在 Supabase Dashboard → SQL Editor 中粘贴执行(可重复执行)。

create or replace function public.rider_badge_counts()
returns table (user_id uuid, badge_count bigint)
language sql
security definer
set search_path = public
stable
as $$
  select ub.user_id, count(*)::bigint as badge_count
  from public.user_badges ub
  where exists (
    select 1 from public.ride_presence rp
    where rp.user_id = ub.user_id
  )
  group by ub.user_id;
$$;

revoke all on function public.rider_badge_counts() from public;
grant execute on function public.rider_badge_counts() to authenticated;
