-- WELL WAY: 活动报名计数 RPC + 骑行记录名称列
-- 在 Supabase Dashboard → SQL Editor 中执行本文件。

-- 1. 活动已报名人数(security definer 绕过 RLS,给 anon 提供真实计数)
create or replace function public.activity_registration_count(p_activity_id bigint)
returns int
language sql
security definer
set search_path = public
as $$
  select count(*)::int
  from public.activity_registrations
  where activity_id = p_activity_id;
$$;

grant execute on function public.activity_registration_count(bigint) to anon, authenticated;

-- 2. 骑行记录自定义名称(重命名记录,跨设备同步)
alter table public.ride_records add column if not exists name text;

-- 3. 活动报名数默认返回视图(可选,用于列表直接展示剩余名额)
create or replace view public.activities_with_count as
select
  a.*,
  case
    when a.ends_at is not null and a.ends_at < now() then 'ended'
    when a.starts_at is not null and a.starts_at <= now() then 'ongoing'
    else 'upcoming'
  end as current_status,
  (select count(*) from public.activity_registrations r where r.activity_id = a.id) as registered_count
from public.activities a;
