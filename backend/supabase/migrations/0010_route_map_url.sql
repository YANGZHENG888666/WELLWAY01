-- 路线图: routes 增加 map_url,存储上传到 route-images 桶的路线图(上传时已转高分辨率 PNG)
alter table public.routes
  add column if not exists map_url text;

-- route-images 桶(若 0004 未执行过则补建)
insert into storage.buckets (id, name, public) values
  ('route-images', 'route-images', true)
on conflict (id) do nothing;

create policy if not exists "route_images_read_public" on storage.objects
for select to anon, authenticated
using (bucket_id = 'route-images');

create policy if not exists "route_images_admin_write" on storage.objects
for all to authenticated
using (bucket_id = 'route-images' and public.is_admin())
with check (bucket_id = 'route-images' and public.is_admin());
