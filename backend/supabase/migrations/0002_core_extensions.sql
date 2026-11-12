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
  ('route-images', 'route-images', true)
on conflict (id) do nothing;

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
