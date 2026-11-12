-- WELL WAY 一键修复(2026-08-23):补齐云端缺失对象并刷新 schema 缓存
-- 用法:在 Supabase Dashboard → SQL Editor 中整体粘贴本文件执行即可,可重复执行。

-- 1. routes 增加 map_url(路线图)
alter table public.routes
  add column if not exists map_url text;

-- 2. route-images 桶 + 公开读 + 管理员写
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

-- 3. route_favorites(路线收藏)
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

-- 4. admin_logs(管理操作日志,后台"操作日志"页依赖)
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

drop policy if exists "admin_logs_admin_select" on public.admin_logs;
create policy "admin_logs_admin_select" on public.admin_logs
for select to authenticated
using (public.is_admin());

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

do $$
declare t text;
begin
  foreach t in array array['brands','models','routes','checkpoints','badges'] loop
    execute format('drop trigger if exists trg_admin_log on public.%I', t);
    execute format('create trigger trg_admin_log after insert or update or delete on public.%I for each row execute function public.log_content_change()', t);
  end loop;
end
$$;

grant all on table public.admin_logs to authenticated;

-- 5. 刷新 PostgREST schema 缓存(否则后台仍报"找不到表/列")
notify pgrst, 'reload schema';
