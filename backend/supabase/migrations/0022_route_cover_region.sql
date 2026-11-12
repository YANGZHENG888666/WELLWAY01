-- 路线列表卡片:封面缩略图 + 所在省市(均由后台维护)
alter table public.routes
  add column if not exists cover_image_url text,
  add column if not exists province text,
  add column if not exists city text;

comment on column public.routes.cover_image_url is '列表卡片封面图(Storage route-images),为空时由 map_url 或内置线稿兜底';
comment on column public.routes.province is '所在省份,如「北京」「四川」';
comment on column public.routes.city is '所在城市,如「北京」「成都市」';
