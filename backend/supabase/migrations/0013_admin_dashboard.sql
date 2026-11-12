-- WELL WAY 后台升级 2026-08-23
-- 内容: ① 数据监测统计函数 ② 管理员管理 RPC ③ 日志防篡改加固
-- 用法: Supabase Dashboard → SQL Editor 整体粘贴执行, 可重复执行。

-- ============================================================
-- 1. 数据监测: 综合统计(仅管理员可调用, security definer)
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
    'activities_total', (select count(*) from public.activities),
    'regs_total',       (select count(*) from public.activity_registrations),
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
-- 2. 管理员管理 RPC(仅管理员可调用)
-- ============================================================
create or replace function public.admin_list()
returns table (id uuid, email text, nickname text, is_admin boolean, created_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'forbidden';
  end if;
  return query
    select p.id, u.email::text, p.nickname::text, p.is_admin, p.created_at
    from public.profiles p
    join auth.users u on u.id = p.id
    order by p.created_at asc;
end;
$$;

create or replace function public.admin_grant(p_email text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
begin
  if not public.is_admin() then
    raise exception 'forbidden';
  end if;
  select id into v_uid
  from auth.users
  where lower(email) = lower(p_email)
  limit 1;
  if v_uid is null then
    raise exception '该邮箱尚未注册, 无法授予管理员';
  end if;
  insert into public.profiles (id, nickname, is_admin)
  values (v_uid, coalesce(nullif(split_part(p_email, '@', 1), ''), '管理员'), true)
  on conflict (id) do update set is_admin = true;
  return true;
end;
$$;

create or replace function public.admin_revoke(p_email text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_admins int;
begin
  if not public.is_admin() then
    raise exception 'forbidden';
  end if;
  select id into v_uid
  from auth.users
  where lower(email) = lower(p_email)
  limit 1;
  if v_uid is null then
    raise exception '该邮箱尚未注册';
  end if;
  if lower(p_email) = '421975135@qq.com' then
    raise exception '主管理员不可被移除';
  end if;
  select count(*) into v_admins from public.profiles where is_admin;
  if v_admins <= 1 then
    raise exception '至少需要保留一名管理员';
  end if;
  update public.profiles set is_admin = false where id = v_uid;
  return true;
end;
$$;

grant execute on function public.admin_list(), public.admin_grant(text), public.admin_revoke(text) to authenticated;

-- ============================================================
-- 3. 日志防篡改: 日志只能由触发器(security definer)写入, 任何人不可改/删
-- ============================================================
revoke insert, update, delete, truncate on table public.admin_logs from anon, authenticated;

-- 刷新 PostgREST schema 缓存
notify pgrst, 'reload schema';
