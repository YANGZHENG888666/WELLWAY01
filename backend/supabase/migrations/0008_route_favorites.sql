-- WELL WAY: 路线收藏
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
