-- WELL WAY 一键初始化(按顺序执行全部迁移 + 种子数据)

--------------------------------------------------------------
-- 0001_initial_schema.sql
--------------------------------------------------------------
-- WELL WAY backend: initial schema
-- Target: Supabase (Postgres). Run via `supabase db push` or SQL editor.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------
-- Profiles (anonymous account + optional email binding)
-- ---------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null default '骑友',
  avatar_url text,
  email_bound boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------
-- Vehicle library
-- ---------------------------------------------------------------
create table public.brands (
  id bigserial primary key,
  name text not null,
  name_en text,
  logo_url text,
  is_hot boolean not null default false,
  sort int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.models (
  id bigserial primary key,
  brand_id bigint not null references public.brands(id) on delete cascade,
  name text not null,
  series text,
  model_type text not null, -- 跑车 / 街车 / ADV / 复古 / 踏板
  displacement_cc int,
  price_min int,
  price_max int,
  rating numeric(3,1),
  image_url text,
  is_new boolean not null default false,
  is_active boolean not null default true,
  sort int not null default 0,
  created_at timestamptz not null default now()
);

create index idx_models_brand on public.models(brand_id);
create index idx_models_filter on public.models(model_type, displacement_cc, price_min, rating);

-- ---------------------------------------------------------------
-- User garage
-- ---------------------------------------------------------------
create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  brand_id bigint not null references public.brands(id),
  model_id bigint not null references public.models(id),
  nickname text,
  color text,
  photo_url text,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

create index idx_vehicles_user on public.vehicles(user_id);

-- ---------------------------------------------------------------
-- Routes / checkpoints
-- ---------------------------------------------------------------
create table public.routes (
  id bigserial primary key,
  name text not null,
  start_name text,
  end_name text,
  distance_m int not null default 0,
  elevation_m int not null default 0,
  difficulty text not null default '简单', -- 简单 / 中等 / 困难
  duration_min int,
  geo_json jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.checkpoints (
  id bigserial primary key,
  route_id bigint not null references public.routes(id) on delete cascade,
  name text not null,
  seq int not null default 0,
  lat double precision,
  lng double precision,
  radius_m int not null default 50
);

-- ---------------------------------------------------------------
-- Ride records + GPS points
-- ---------------------------------------------------------------
create table public.ride_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  route_id bigint references public.routes(id),
  vehicle_id uuid references public.vehicles(id),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  distance_m int not null default 0,
  duration_s int not null default 0,
  avg_speed_kmh numeric(5,1),
  max_speed_kmh numeric(5,1),
  elevation_gain_m int not null default 0,
  status text not null default 'completed', -- completed / abandoned
  created_at timestamptz not null default now()
);

create index idx_rides_user on public.ride_records(user_id, started_at desc);

create table public.ride_points (
  id bigserial primary key,
  ride_id uuid not null references public.ride_records(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  speed_kmh numeric(5,1),
  recorded_at timestamptz not null
);

create index idx_ride_points_ride on public.ride_points(ride_id);

-- ---------------------------------------------------------------
-- Badges
-- ---------------------------------------------------------------
create table public.badges (
  id bigserial primary key,
  route_id bigint references public.routes(id) on delete cascade,
  name text not null,
  image_url text,
  condition_desc text,
  seq int not null default 0
);

create table public.user_badges (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  badge_id bigint not null references public.badges(id) on delete cascade,
  ride_id uuid references public.ride_records(id) on delete set null,
  earned_at timestamptz not null default now(),
  unique(user_id, badge_id)
);

-- ---------------------------------------------------------------
-- Activities (P2, reserved)
-- ---------------------------------------------------------------
create table public.activities (
  id bigserial primary key,
  name text not null,
  route_id bigint references public.routes(id),
  starts_at timestamptz,
  ends_at timestamptz,
  reward_desc text,
  slots int,
  status text not null default 'upcoming', -- upcoming / ongoing / ended
  created_at timestamptz not null default now()
);

create table public.activity_registrations (
  id bigserial primary key,
  activity_id bigint not null references public.activities(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(activity_id, user_id)
);

-- ---------------------------------------------------------------
-- updated_at helper
-- ---------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end; $$;

create trigger trg_profiles_updated
before update on public.profiles
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------
-- Auto-create profile when a user (anonymous or email) signs up
-- ---------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, nickname)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'nickname', '骑友')
  )
  on conflict (id) do nothing;
  return new;
end; $$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.brands enable row level security;
alter table public.models enable row level security;
alter table public.vehicles enable row level security;
alter table public.routes enable row level security;
alter table public.checkpoints enable row level security;
alter table public.ride_records enable row level security;
alter table public.ride_points enable row level security;
alter table public.badges enable row level security;
alter table public.user_badges enable row level security;
alter table public.activities enable row level security;
alter table public.activity_registrations enable row level security;

create policy "profiles_select_own" on public.profiles
for select using (auth.uid() = id);

create policy "profiles_insert_own" on public.profiles
for insert with check (auth.uid() = id);

create policy "profiles_update_own" on public.profiles
for update using (auth.uid() = id);

create policy "brands_read_public" on public.brands
for select using (true);

create policy "models_read_public" on public.models
for select using (true);

create policy "vehicles_select_own" on public.vehicles
for select using (auth.uid() = user_id);

create policy "vehicles_insert_own" on public.vehicles
for insert with check (auth.uid() = user_id);

create policy "vehicles_update_own" on public.vehicles
for update using (auth.uid() = user_id);

create policy "vehicles_delete_own" on public.vehicles
for delete using (auth.uid() = user_id);

create policy "routes_read_public" on public.routes
for select using (true);

create policy "checkpoints_read_public" on public.checkpoints
for select using (true);

create policy "badges_read_public" on public.badges
for select using (true);

create policy "rides_select_own" on public.ride_records
for select using (auth.uid() = user_id);

create policy "rides_insert_own" on public.ride_records
for insert with check (auth.uid() = user_id);

create policy "rides_update_own" on public.ride_records
for update using (auth.uid() = user_id);

create policy "points_select_own" on public.ride_points
for select using (
  exists (
    select 1 from public.ride_records r
    where r.id = ride_id and r.user_id = auth.uid()
  )
);

create policy "points_insert_own" on public.ride_points
for insert with check (
  exists (
    select 1 from public.ride_records r
    where r.id = ride_id and r.user_id = auth.uid()
  )
);

create policy "user_badges_select_own" on public.user_badges
for select using (auth.uid() = user_id);

create policy "user_badges_insert_own" on public.user_badges
for insert with check (auth.uid() = user_id);

create policy "activities_read_public" on public.activities
for select using (true);

create policy "registrations_select_own" on public.activity_registrations
for select using (auth.uid() = user_id);

create policy "registrations_insert_own" on public.activity_registrations
for insert with check (auth.uid() = user_id);

--------------------------------------------------------------
-- 0002_core_extensions.sql
--------------------------------------------------------------
-- WELL WAY: core extensions
-- Chat between riders heading to the same destination (同路人聊天),
-- ride check-ins (打卡), storage buckets, realtime publication,
-- and a few missing indexes/constraints.

-- ---------------------------------------------------------------
-- 1. Route chat (同路人聊天)
-- ---------------------------------------------------------------
create table public.route_chat_messages (
  id bigserial primary key,
  route_id bigint not null references public.routes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 500),
  created_at timestamptz not null default now()
);

create index idx_chat_route_time on public.route_chat_messages(route_id, created_at);
create index idx_chat_user on public.route_chat_messages(user_id);

alter table public.route_chat_messages enable row level security;

create policy "chat_select_route" on public.route_chat_messages
for select using (
  exists (select 1 from public.routes r where r.id = route_id and r.is_active)
);

create policy "chat_insert_own" on public.route_chat_messages
for insert with check (auth.uid() = user_id);

-- ---------------------------------------------------------------
-- 2. Ride check-ins (打卡)
-- ---------------------------------------------------------------
create table public.ride_checkins (
  id bigserial primary key,
  ride_id uuid not null references public.ride_records(id) on delete cascade,
  checkpoint_id bigint not null references public.checkpoints(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  checked_at timestamptz not null default now(),
  unique(ride_id, checkpoint_id)
);

create index idx_checkins_ride on public.ride_checkins(ride_id);
create index idx_checkins_user on public.ride_checkins(user_id);

alter table public.ride_checkins enable row level security;

create policy "checkins_select_own" on public.ride_checkins
for select using (auth.uid() = user_id);

create policy "checkins_insert_own" on public.ride_checkins
for insert with check (
  auth.uid() = user_id
  and exists (
    select 1 from public.ride_records r
    where r.id = ride_id and r.user_id = auth.uid()
  )
);

-- ---------------------------------------------------------------
-- 3. Storage buckets
--    vehicle-photos: private, per-user folder <uid>/...
--    route-images:   public (admin uploads via service role)
-- ---------------------------------------------------------------
insert into storage.buckets (id, name, public) values
  ('vehicle-photos', 'vehicle-photos', false),
  ('route-images', 'route-images', true),
  ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists "avatars_select_own" on storage.objects;
create policy "avatars_select_own" on storage.objects
for select to authenticated using (
  bucket_id = 'avatars'
  and auth.uid()::text = (storage.foldername(name))[1]
);

drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own" on storage.objects
for insert to authenticated with check (
  bucket_id = 'avatars'
  and auth.uid()::text = (storage.foldername(name))[1]
);

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own" on storage.objects
for update to authenticated using (
  bucket_id = 'avatars'
  and auth.uid()::text = (storage.foldername(name))[1]
);

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own" on storage.objects
for delete to authenticated using (
  bucket_id = 'avatars'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "vehicle_photos_select_own" on storage.objects
for select using (
  bucket_id = 'vehicle-photos'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "vehicle_photos_insert_own" on storage.objects
for insert with check (
  bucket_id = 'vehicle-photos'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "vehicle_photos_update_own" on storage.objects
for update using (
  bucket_id = 'vehicle-photos'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "vehicle_photos_delete_own" on storage.objects
for delete using (
  bucket_id = 'vehicle-photos'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "route_images_public_read" on storage.objects
for select using (bucket_id = 'route-images');

-- ---------------------------------------------------------------
-- 4. Realtime: chat messages push to clients
-- ---------------------------------------------------------------
do $$
begin
  alter publication supabase_realtime add table public.route_chat_messages;
exception
  when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------
-- 5. Missing constraints / indexes
-- ---------------------------------------------------------------
alter table public.models
  add constraint models_displacement_positive
  check (displacement_cc is null or displacement_cc > 0);

alter table public.models
  add constraint models_price_range
  check (price_min is null or price_max is null or price_max >= price_min);

alter table public.routes
  add constraint routes_distance_positive
  check (distance_m >= 0);

alter table public.ride_records
  add constraint rides_status_valid
  check (status in ('completed', 'abandoned', 'riding'));

alter table public.activities
  add constraint activities_status_valid
  check (status in ('upcoming', 'ongoing', 'ended'));

create index idx_ride_points_ride_time on public.ride_points(ride_id, recorded_at);

-- one model name per brand must be unique (used by seed upserts)
create unique index brands_name_unique on public.brands(name);
create unique index models_brand_name_unique on public.models(brand_id, name);
create unique index routes_name_unique on public.routes(name);
create unique index checkpoints_route_seq_unique on public.checkpoints(route_id, seq);
create unique index badges_name_unique on public.badges(name);

-- vehicles: track last update
alter table public.vehicles
  add column if not exists updated_at timestamptz not null default now();

create trigger trg_vehicles_updated
before update on public.vehicles
for each row execute function public.set_updated_at();

--------------------------------------------------------------
-- 0003_functions.sql
--------------------------------------------------------------
-- WELL WAY: SQL functions used by the app

-- ---------------------------------------------------------------
-- recalculate_ride_stats: recompute distance / duration / speeds
-- from the GPS points of a ride. Call after inserting ride_points.
-- ---------------------------------------------------------------
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
  )
  select
    coalesce(round(sum(seg_m))::int, 0),
    coalesce(max(speed_kmh), 0)
  into v_distance_m, v_max_kmh
  from seg;

  select
    coalesce(extract(epoch from (max(recorded_at) - min(recorded_at)))::int, 0)
  into v_duration_s
  from public.ride_points
  where ride_id = p_ride_id;

  v_avg_kmh := case
    when v_duration_s > 0
      then round((v_distance_m::numeric / 1000.0) / (v_duration_s::numeric / 3600.0), 1)
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

-- ---------------------------------------------------------------
-- award_badge: grant a badge, idempotent.
-- Returns true when the badge was newly awarded.
-- ---------------------------------------------------------------
create or replace function public.award_badge(
  p_user_id uuid,
  p_badge_id bigint,
  p_ride_id uuid default null
)
returns boolean
language plpgsql
as $$
declare
  v_id bigint;
begin
  insert into public.user_badges (user_id, badge_id, ride_id)
  values (p_user_id, p_badge_id, p_ride_id)
  on conflict (user_id, badge_id) do nothing
  returning id into v_id;

  return v_id is not null;
end;
$$;

-- ---------------------------------------------------------------
-- activities_current: computed activity status, so the app does
-- not depend on a scheduled job to flip statuses.
-- ---------------------------------------------------------------
create or replace view public.activities_current as
select
  a.*,
  case
    when a.ends_at is not null and a.ends_at < now() then 'ended'
    when a.starts_at is not null and a.starts_at <= now() then 'ongoing'
    else 'upcoming'
  end as current_status
from public.activities a;

--------------------------------------------------------------
-- 0004_admin.sql
--------------------------------------------------------------
-- WELL WAY: admin role + management permissions

-- 1. Admin flag on profiles
alter table public.profiles add column if not exists is_admin boolean not null default false;

-- 2. Helper: is the current user an admin?
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.is_admin
  );
$$;

-- 3. Admin write access on library / content tables
create policy "brands_admin_write" on public.brands
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "models_admin_write" on public.models
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "routes_admin_write" on public.routes
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "checkpoints_admin_write" on public.checkpoints
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "badges_admin_write" on public.badges
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "activities_admin_write" on public.activities
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "registrations_admin_write" on public.activity_registrations
for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- 4. Public catalog image bucket (brand logos / model images)
insert into storage.buckets (id, name, public) values
  ('catalog-images', 'catalog-images', true)
on conflict (id) do nothing;

create policy "catalog_images_admin_write" on storage.objects
for all to authenticated
using (bucket_id = 'catalog-images' and public.is_admin())
with check (bucket_id = 'catalog-images' and public.is_admin());

create policy "route_images_admin_write" on storage.objects
for all to authenticated
using (bucket_id = 'route-images' and public.is_admin())
with check (bucket_id = 'route-images' and public.is_admin());

--------------------------------------------------------------
-- seed.sql
--------------------------------------------------------------
-- WELL WAY starter vehicle library.
-- Data comes from public spec sheets / official announcements.
-- Prices are indicative MSRP in CNY and MUST be verified before release.
-- Safe to run multiple times (upsert by brand name / model name).

insert into public.brands (name, name_en, is_hot, sort) values
  ('春风动力', 'CFMOTO', true, 1),
  ('阿普利亚', 'Aprilia', true, 2),
  ('川崎', 'Kawasaki', true, 3),
  ('本田', 'Honda', true, 4),
  ('贝纳利', 'Benelli', false, 5),
  ('雅马哈', 'Yamaha', true, 6),
  ('铃木', 'Suzuki', false, 7)
on conflict (name) do update set
  name_en = excluded.name_en,
  is_hot = excluded.is_hot,
  sort = excluded.sort;

insert into public.models
  (brand_id, name, series, model_type, displacement_cc, price_min, price_max, rating, is_new, sort)
select
  b.id, m.name, m.series, m.model_type, m.displacement_cc,
  m.price_min, m.price_max, m.rating, m.is_new, m.sort
from (values
  -- 春风动力
  ('春风动力', '春风 450SR', 'SR系列', '跑车', 450, 23980, 28580, 8.9, true, 1),
  ('春风动力', '春风 500SR', 'SR系列', '跑车', 500, 28980, 28980, 9.3, true, 2),
  ('春风动力', '春风 450NK', 'NK系列', '街车', 450, 23880, 23880, 8.9, false, 3),
  ('春风动力', '春风 450MT', 'MT系列', 'ADV', 450, 30580, 32580, 9.0, true, 4),
  ('春风动力', '春风 250SR', 'SR系列', '跑车', 250, 19980, 21580, 8.7, false, 5),
  ('春风动力', '春风 800NK', 'NK系列', '街车', 799, 44980, 49980, 9.1, false, 6),
  -- 阿普利亚
  ('阿普利亚', '阿普利亚 RS 457', 'RS系列', '跑车', 457, 41800, 41800, 9.0, true, 1),
  ('阿普利亚', '阿普利亚 Tuono 457', 'Tuono系列', '街车', 457, 40800, 40800, 8.9, true, 2),
  -- 川崎
  ('川崎', '川崎 Ninja 400', 'Ninja系列', '跑车', 399, 49800, 49800, 8.8, false, 1),
  ('川崎', '川崎 Z400', 'Z系列', '街车', 399, 47800, 47800, 8.7, false, 2),
  ('川崎', '川崎 Ninja 650', 'Ninja系列', '跑车', 649, 70800, 70800, 8.6, false, 3),
  ('川崎', '川崎 Z900', 'Z系列', '街车', 948, 89800, 89800, 9.0, false, 4),
  ('川崎', '川崎 Versys 650', 'Versys系列', 'ADV', 649, 69800, 69800, 8.5, false, 5),
  -- 本田
  ('本田', '本田 CB400F', 'CB系列', '街车', 399, 39000, 39000, 8.6, false, 1),
  ('本田', '本田 CM300', 'CM系列', '复古', 286, 34500, 34500, 8.5, false, 2),
  ('本田', '本田 CB400X', 'CB系列', 'ADV', 399, 41500, 41500, 8.5, false, 3),
  ('本田', '本田 CBR400R', 'CBR系列', '跑车', 399, 42000, 42000, 8.5, false, 4),
  ('本田', '本田 PCX160', 'PCX系列', '踏板', 157, 22990, 22990, 8.4, false, 5),
  -- 贝纳利
  ('贝纳利', '贝纳利 502C', 'C系列', '复古', 500, 39800, 39800, 8.4, false, 1),
  ('贝纳利', '贝纳利 TRK502', 'TRK系列', 'ADV', 500, 39800, 45800, 8.6, false, 2),
  ('贝纳利', '贝纳利 幼狮 250', 'Leoncino系列', '复古', 250, 19900, 19900, 8.3, false, 3),
  -- 雅马哈
  ('雅马哈', '雅马哈 YZF-R3', 'YZF系列', '跑车', 321, 43800, 43800, 8.6, false, 1),
  ('雅马哈', '雅马哈 MT-03', 'MT系列', '街车', 321, 39800, 39800, 8.5, false, 2),
  ('雅马哈', '雅马哈 NMAX155', 'NMAX系列', '踏板', 155, 27800, 27800, 8.3, false, 3),
  -- 铃木
  ('铃木', '铃木 GSX250R', 'GSX系列', '跑车', 248, 26680, 26680, 8.4, false, 1)
) as m(brand_name, name, series, model_type, displacement_cc, price_min, price_max, rating, is_new, sort)
join public.brands b on b.name = m.brand_name
on conflict (brand_id, name) do update set
  series = excluded.series,
  model_type = excluded.model_type,
  displacement_cc = excluded.displacement_cc,
  price_min = excluded.price_min,
  price_max = excluded.price_max,
  rating = excluded.rating,
  is_new = excluded.is_new,
  sort = excluded.sort;

-- ---------------------------------------------------------------
-- Demo routes / checkpoints / badges (coordinates are illustrative)
-- ---------------------------------------------------------------
insert into public.routes
  (name, start_name, end_name, distance_m, elevation_m, difficulty, duration_min, geo_json)
values
  ('城市穿梭线', '滨江路', '中央公园', 20000, 120, '简单', 45, null),
  ('山路打卡线', '山脚驿站', '山顶观景台', 58000, 980, '困难', 150, null)
on conflict (name) do update set
  start_name = excluded.start_name,
  end_name = excluded.end_name,
  distance_m = excluded.distance_m,
  elevation_m = excluded.elevation_m,
  difficulty = excluded.difficulty,
  duration_min = excluded.duration_min,
  geo_json = excluded.geo_json;

insert into public.checkpoints (route_id, name, seq, lat, lng, radius_m)
select r.id, c.name, c.seq, c.lat, c.lng, c.radius_m
from (values
  ('城市穿梭线', '滨江路起点', 1, 31.2304, 121.4737, 50),
  ('城市穿梭线', '中央公园', 2, 31.2252, 121.4392, 80),
  ('山路打卡线', '山脚驿站', 1, 30.2741, 120.1551, 60),
  ('山路打卡线', '半山观景台', 2, 30.2905, 120.1608, 60),
  ('山路打卡线', '山顶观景台', 3, 30.3052, 120.1682, 80)
) as c(route_name, name, seq, lat, lng, radius_m)
join public.routes r on r.name = c.route_name
on conflict (route_id, seq) do update set
  name = excluded.name,
  lat = excluded.lat,
  lng = excluded.lng,
  radius_m = excluded.radius_m;

insert into public.badges (route_id, name, image_url, condition_desc, seq)
select r.id, b.name, b.image_url, b.condition_desc, b.seq
from (values
  (null, '新手首骑', null, '完成第一次骑行记录', 1),
  (null, '打卡达人', null, '累计完成 10 次路线打卡', 2),
  ('山路打卡线', '山路挑战者', null, '完成「山路打卡线」全程', 3)
) as b(route_name, name, image_url, condition_desc, seq)
left join public.routes r on r.name = b.route_name
on conflict (name) do update set
  route_id = excluded.route_id,
  image_url = excluded.image_url,
  condition_desc = excluded.condition_desc,
  seq = excluded.seq;



-- ===== 0006 activities + rename =====

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
-- WELL WAY starter vehicle library.
-- Data comes from public spec sheets / official announcements.
-- Prices are indicative MSRP in CNY and MUST be verified before release.
-- Safe to run multiple times (upsert by brand name / model name).

insert into public.brands (name, name_en, is_hot, sort) values
  ('春风动力', 'CFMOTO', true, 1),
  ('阿普利亚', 'Aprilia', true, 2),
  ('川崎', 'Kawasaki', true, 3),
  ('本田', 'Honda', true, 4),
  ('贝纳利', 'Benelli', false, 5),
  ('雅马哈', 'Yamaha', true, 6),
  ('铃木', 'Suzuki', false, 7)
on conflict (name) do update set
  name_en = excluded.name_en,
  is_hot = excluded.is_hot,
  sort = excluded.sort;

insert into public.models
  (brand_id, name, series, model_type, displacement_cc, price_min, price_max, rating, is_new, sort)
select
  b.id, m.name, m.series, m.model_type, m.displacement_cc,
  m.price_min, m.price_max, m.rating, m.is_new, m.sort
from (values
  -- 春风动力
  ('春风动力', '春风 450SR', 'SR系列', '跑车', 450, 23980, 28580, 8.9, true, 1),
  ('春风动力', '春风 500SR', 'SR系列', '跑车', 500, 28980, 28980, 9.3, true, 2),
  ('春风动力', '春风 450NK', 'NK系列', '街车', 450, 23880, 23880, 8.9, false, 3),
  ('春风动力', '春风 450MT', 'MT系列', 'ADV', 450, 30580, 32580, 9.0, true, 4),
  ('春风动力', '春风 250SR', 'SR系列', '跑车', 250, 19980, 21580, 8.7, false, 5),
  ('春风动力', '春风 800NK', 'NK系列', '街车', 799, 44980, 49980, 9.1, false, 6),
  -- 阿普利亚
  ('阿普利亚', '阿普利亚 RS 457', 'RS系列', '跑车', 457, 41800, 41800, 9.0, true, 1),
  ('阿普利亚', '阿普利亚 Tuono 457', 'Tuono系列', '街车', 457, 40800, 40800, 8.9, true, 2),
  -- 川崎
  ('川崎', '川崎 Ninja 400', 'Ninja系列', '跑车', 399, 49800, 49800, 8.8, false, 1),
  ('川崎', '川崎 Z400', 'Z系列', '街车', 399, 47800, 47800, 8.7, false, 2),
  ('川崎', '川崎 Ninja 650', 'Ninja系列', '跑车', 649, 70800, 70800, 8.6, false, 3),
  ('川崎', '川崎 Z900', 'Z系列', '街车', 948, 89800, 89800, 9.0, false, 4),
  ('川崎', '川崎 Versys 650', 'Versys系列', 'ADV', 649, 69800, 69800, 8.5, false, 5),
  -- 本田
  ('本田', '本田 CB400F', 'CB系列', '街车', 399, 39000, 39000, 8.6, false, 1),
  ('本田', '本田 CM300', 'CM系列', '复古', 286, 34500, 34500, 8.5, false, 2),
  ('本田', '本田 CB400X', 'CB系列', 'ADV', 399, 41500, 41500, 8.5, false, 3),
  ('本田', '本田 CBR400R', 'CBR系列', '跑车', 399, 42000, 42000, 8.5, false, 4),
  ('本田', '本田 PCX160', 'PCX系列', '踏板', 157, 22990, 22990, 8.4, false, 5),
  -- 贝纳利
  ('贝纳利', '贝纳利 502C', 'C系列', '复古', 500, 39800, 39800, 8.4, false, 1),
  ('贝纳利', '贝纳利 TRK502', 'TRK系列', 'ADV', 500, 39800, 45800, 8.6, false, 2),
  ('贝纳利', '贝纳利 幼狮 250', 'Leoncino系列', '复古', 250, 19900, 19900, 8.3, false, 3),
  -- 雅马哈
  ('雅马哈', '雅马哈 YZF-R3', 'YZF系列', '跑车', 321, 43800, 43800, 8.6, false, 1),
  ('雅马哈', '雅马哈 MT-03', 'MT系列', '街车', 321, 39800, 39800, 8.5, false, 2),
  ('雅马哈', '雅马哈 NMAX155', 'NMAX系列', '踏板', 155, 27800, 27800, 8.3, false, 3),
  -- 铃木
  ('铃木', '铃木 GSX250R', 'GSX系列', '跑车', 248, 26680, 26680, 8.4, false, 1)
) as m(brand_name, name, series, model_type, displacement_cc, price_min, price_max, rating, is_new, sort)
join public.brands b on b.name = m.brand_name
on conflict (brand_id, name) do update set
  series = excluded.series,
  model_type = excluded.model_type,
  displacement_cc = excluded.displacement_cc,
  price_min = excluded.price_min,
  price_max = excluded.price_max,
  rating = excluded.rating,
  is_new = excluded.is_new,
  sort = excluded.sort;

-- ---------------------------------------------------------------
-- Demo routes / checkpoints / badges (coordinates are illustrative)
-- ---------------------------------------------------------------
insert into public.routes
  (name, start_name, end_name, distance_m, elevation_m, difficulty, duration_min, geo_json)
values
  ('城市穿梭线', '滨江路', '中央公园', 20000, 120, '简单', 45, null),
  ('山路打卡线', '山脚驿站', '山顶观景台', 58000, 980, '困难', 150, null)
on conflict (name) do update set
  start_name = excluded.start_name,
  end_name = excluded.end_name,
  distance_m = excluded.distance_m,
  elevation_m = excluded.elevation_m,
  difficulty = excluded.difficulty,
  duration_min = excluded.duration_min,
  geo_json = excluded.geo_json;

insert into public.checkpoints (route_id, name, seq, lat, lng, radius_m)
select r.id, c.name, c.seq, c.lat, c.lng, c.radius_m
from (values
  ('城市穿梭线', '滨江路起点', 1, 31.2304, 121.4737, 50),
  ('城市穿梭线', '中央公园', 2, 31.2252, 121.4392, 80),
  ('山路打卡线', '山脚驿站', 1, 30.2741, 120.1551, 60),
  ('山路打卡线', '半山观景台', 2, 30.2905, 120.1608, 60),
  ('山路打卡线', '山顶观景台', 3, 30.3052, 120.1682, 80)
) as c(route_name, name, seq, lat, lng, radius_m)
join public.routes r on r.name = c.route_name
on conflict (route_id, seq) do update set
  name = excluded.name,
  lat = excluded.lat,
  lng = excluded.lng,
  radius_m = excluded.radius_m;

insert into public.badges (route_id, name, image_url, condition_desc, seq)
select r.id, b.name, b.image_url, b.condition_desc, b.seq
from (values
  (null, '新手首骑', null, '完成第一次骑行记录', 1),
  (null, '打卡达人', null, '累计完成 10 次路线打卡', 2),
  ('山路打卡线', '山路挑战者', null, '完成「山路打卡线」全程', 3)
) as b(route_name, name, image_url, condition_desc, seq)
left join public.routes r on r.name = b.route_name
on conflict (name) do update set
  route_id = excluded.route_id,
  image_url = excluded.image_url,
  condition_desc = excluded.condition_desc,
  seq = excluded.seq;

-- 

---------------------------------------------------------------
-- Figma 演示路线(北京)/ 路线徽章 / 活动(幂等)
-- ---------------------------------------------------------------
insert into public.routes
  (name, start_name, end_name, distance_m, elevation_m, difficulty, duration_min, geo_json)
values
  ('四惠桥通勤线', '四惠桥', '国贸', 12600, 120, '简单', 45, null),
  ('香山压弯线', '香山脚下', '鬼笑石', 18200, 640, '困难', 130, null),
  ('长安街夜骑线', '西单', '建国门', 9800, 40, '简单', 35, null)
on conflict (name) do update set
  start_name = excluded.start_name,
  end_name = excluded.end_name,
  distance_m = excluded.distance_m,
  elevation_m = excluded.elevation_m,
  difficulty = excluded.difficulty,
  duration_min = excluded.duration_min;

insert into public.checkpoints (route_id, name, seq, lat, lng, radius_m)
select r.id, c.name, c.seq, c.lat, c.lng, c.radius_m
from (values
  ('四惠桥通勤线', '四惠桥', 1, 39.9087, 116.4975, 80),
  ('四惠桥通勤线', '东四环桥洞', 2, 39.9110, 116.4920, 80),
  ('四惠桥通勤线', '国贸', 3, 39.9086, 116.4598, 80),
  ('香山压弯线', '香山脚下', 1, 39.9906, 116.1900, 100),
  ('香山压弯线', '鬼笑石', 2, 39.9720, 116.1850, 100),
  ('长安街夜骑线', '西单路口', 1, 39.9075, 116.3740, 80),
  ('长安街夜骑线', '建国门桥', 2, 39.9078, 116.4350, 80)
) as c(route_name, name, seq, lat, lng, radius_m)
join public.routes r on r.name = c.route_name
on conflict (route_id, seq) do update set
  name = excluded.name,
  lat = excluded.lat,
  lng = excluded.lng,
  radius_m = excluded.radius_m;

insert into public.badges (route_id, name, image_url, condition_desc, seq)
select r.id, b.name, b.image_url, b.condition_desc, b.seq
from (values
  ('四惠桥通勤线', '通勤骑士', null, '完成「四惠桥通勤线」全程', 4),
  ('香山压弯线', '跑山骑士', null, '完成「香山压弯线」全程', 5),
  ('长安街夜骑线', '夜骑骑士', null, '完成「长安街夜骑线」全程', 6)
) as b(route_name, name, image_url, condition_desc, seq)
left join public.routes r on r.name = b.route_name
on conflict (name) do update set
  route_id = excluded.route_id,
  image_url = excluded.image_url,
  condition_desc = excluded.condition_desc,
  seq = excluded.seq;

insert into public.activities (name, route_id, starts_at, ends_at, reward_desc, slots, status)
select a.name, r.id, a.starts_at::timestamptz, a.ends_at::timestamptz, a.reward_desc, a.slots, a.status
from (values
  ('周末骑行挑战', '四惠桥通勤线', '2026-08-15 07:00:00+08', '2026-08-15 12:00:00+08',
   '完成挑战可获得限定徽章;完赛前 20 名额外获得骑行装备', 12, 'upcoming'),
  ('夜骑长安街', '长安街夜骑线', '2026-08-22 20:00:00+08', '2026-08-22 23:00:00+08',
   '完赛可获得夜骑限定徽章与骑行装备', 28, 'upcoming')
) as a(name, route_name, starts_at, ends_at, reward_desc, slots, status)
join public.routes r on r.name = a.route_name
on conflict (name) do update set
  route_id = excluded.route_id,
  starts_at = excluded.starts_at,
  ends_at = excluded.ends_at,
  reward_desc = excluded.reward_desc,
  slots = excluded.slots,
  status = excluded.status;
