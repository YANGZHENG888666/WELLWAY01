-- WELL WAY: 同路骑士实时位置上报 + 反馈落库
-- 在 Supabase Dashboard → SQL Editor 中执行本文件(可与 0006 一起执行)。

-- ---------------------------------------------------------------
-- 1. 骑行中位置上报(同路骑士列表展示昵称/车辆/距离)
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

-- 所有人可读(仅昵称/车辆/所在路线位置,数据临时、15 分钟自动过期)
-- 可重复执行:先删后建
drop policy if exists "ride_presence_select" on public.ride_presence;
drop policy if exists "ride_presence_insert_own" on public.ride_presence;
drop policy if exists "ride_presence_update_own" on public.ride_presence;
drop policy if exists "ride_presence_delete_own" on public.ride_presence;
create policy "ride_presence_select" on public.ride_presence
  for select using (true);
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
