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
  plate text,
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
