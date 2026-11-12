-- WELL WAY 去除社交属性(2026-08-24)
-- 目标: 满足国内应用市场上架要求, 移除「活动(报名)」与「同路聊天」两类社交功能。
-- 用法: Supabase Dashboard → SQL Editor 整体粘贴执行, 可重复执行。

-- ============================================================
-- 1. 活动: 先删依赖它的视图/函数, 再删表(表上的策略随表删除)
-- ============================================================
drop view if exists public.activities_with_count;
drop view if exists public.activities_current;
drop function if exists public.activity_registration_count(bigint);

drop table if exists public.activity_registrations;
drop table if exists public.activities;

-- ============================================================
-- 2. 同路聊天
-- ============================================================
drop table if exists public.route_chat_messages;

-- ============================================================
-- 3. 数据监测统计不再包含活动(其余字段保持不变)
-- ============================================================
create or replace function public.admin_dashboard_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not public.is_admin() then
    raise exception 'forbidden: 仅管理员可查看数据监测';
  end if;

  select jsonb_build_object(
    'users_total',      (select count(*) from auth.users),
    'users_today',      (select count(*) from auth.users
                          where created_at >= date_trunc('day', now() at time zone 'Asia/Shanghai')
                                               at time zone 'Asia/Shanghai'),
    'rides_today',      (select count(*) from public.ride_records
                          where started_at >= date_trunc('day', now() at time zone 'Asia/Shanghai')
                                              at time zone 'Asia/Shanghai'),
    'riders_today',     (select count(distinct user_id) from public.ride_records
                          where started_at >= date_trunc('day', now() at time zone 'Asia/Shanghai')
                                              at time zone 'Asia/Shanghai'),
    'routes_total',     (select count(*) from public.routes),
    'routes_active',    (select count(*) from public.routes where is_active),
    'brands_total',     (select count(*) from public.brands),
    'models_total',     (select count(*) from public.models),
    'checkpoints_total',(select count(*) from public.checkpoints),
    'badges_total',     (select count(*) from public.badges),
    'favorites_total',  (select count(*) from public.route_favorites),
    'rides_7d', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'day', to_char(d, 'MM-DD'), 'cnt', c
      ) order by d), '[]'::jsonb)
      from (
        select d, count(r.id)::int as c
        from generate_series(0, 6) as n(days_ago),
             lateral (select ((now() at time zone 'Asia/Shanghai')::date - n.days_ago)::date as d) day,
             lateral (select (day.d::timestamp at time zone 'Asia/Shanghai') as d_start) bounds
        left join public.ride_records r
          on r.started_at >= bounds.d_start
         and r.started_at <  bounds.d_start + interval '1 day'
        group by day.d
      ) x
    ),
    'routes_today', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'route_id', route_id, 'rider_count', rider_count
      ) order by rider_count desc), '[]'::jsonb)
      from public.count_route_riders_today()
    )
  ) into v;
  return v;
end;
$$;

grant execute on function public.admin_dashboard_stats() to authenticated;

-- ============================================================
-- 4. 操作日志触发器只挂到现存内容表(activities 已删除)
-- ============================================================
do $$
declare t text;
begin
  foreach t in array array['brands','models','routes','checkpoints','badges'] loop
    execute format('drop trigger if exists trg_admin_log on public.%I', t);
    execute format('create trigger trg_admin_log after insert or update or delete on public.%I for each row execute function public.log_content_change()', t);
  end loop;
end
$$;
