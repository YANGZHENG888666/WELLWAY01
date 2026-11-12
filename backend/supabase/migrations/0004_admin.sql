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
