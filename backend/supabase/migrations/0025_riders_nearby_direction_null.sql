-- 附近骑手方向统计：无航向时返回 null，而不是 0
-- 问题：riders_nearby 在 p_bearing 为 null 时 brg_delta 全为 null，
-- 但 behind_same_direction / oncoming 仍然 count(*) 成 0。
-- 客户端 hasDirection 判断的是「这两项是否为 nil」，于是永远判定方向可用，
-- 页面会出现「3 位骑手 · 对向 0 · 后方同向 0」，把「无法判断方向」伪装成「都是 0」。
-- 修复：无航向时两项返回 null，客户端改回「开始骑行并移动一段距离后更新」。
-- 可重复执行。

create or replace function public.riders_nearby(
  p_lat double precision,
  p_lon double precision,
  p_bearing double precision default null,
  p_radius_m integer default 2000
)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  with cfg as (
    select
      p_lat as lat,
      p_lon as lon,
      case when p_bearing is null then null
        else (((p_bearing::numeric % 360) + 360) % 360)::double precision end as brg,
      greatest(coalesce(p_radius_m, 2000), 200) as radius_m
  ),
  cand as (
    select
      r.user_id,
      r.bearing as other_brg,
      public.haversine_m(cfg.lat, cfg.lon, r.lat, r.lng) as dist_m,
      -- 对方相对我的方位角(0=正北,顺时针)
      degrees(atan2(
        sin(radians(r.lng - cfg.lon)) * cos(radians(r.lat)),
        cos(radians(cfg.lat)) * sin(radians(r.lat))
          - sin(radians(cfg.lat)) * cos(radians(r.lat)) * cos(radians(r.lng - cfg.lon))
      )) as azimuth_deg
    from public.ride_presence r, cfg
    where r.updated_at > now() - interval '120 seconds'
      and (auth.uid() is null or r.user_id <> auth.uid())
      and public.haversine_m(cfg.lat, cfg.lon, r.lat, r.lng) <= cfg.radius_m
  ),
  classified as (
    select
      c.*,
      cfg.brg as my_brg,
      case
        when c.other_brg is null or cfg.brg is null then null
        else public.bearing_delta(c.other_brg, cfg.brg)
      end as brg_delta,
      case
        when cfg.brg is null then null
        else public.bearing_delta(c.azimuth_deg, cfg.brg) > 90
      end as is_behind
    from cand c, cfg
  )
  select jsonb_build_object(
    'total', (select count(*) from classified),
    -- 没有航向时这两项必须是 null,不能是 0:
    -- 0 表示「看了,确实没有对向/同向的人」,null 表示「根本没法判断方向」,
    -- 客户端据此决定是画方向分布,还是写「移动一段距离后更新」。
    -- 用 cfg.brg 判断「有没有航向」，不能用 classified.my_brg：
    -- 附近一个骑手都没有时 classified 是空集，max(my_brg) 也是 null，
    -- 会把「有航向、只是没人」错报成「无法判断方向」。
    'behind_same_direction',
      (select case when (select brg from cfg) is null then null
        else count(*) filter (where brg_delta is not null and brg_delta <= 60 and is_behind is true) end
        from classified),
    'oncoming',
      (select case when (select brg from cfg) is null then null
        else count(*) filter (where brg_delta is not null and brg_delta >= 120) end
        from classified),
    'unknown_direction',
      (select count(*) from classified where brg_delta is null),
    'bearing',
      (select brg from cfg),
    'radius_m',
      (select radius_m from cfg),
    'fresh_seconds', 120,
    'disclaimer', public.disclaimer_text()
  );
$$;

grant execute on function public.riders_nearby(double precision, double precision, double precision, integer)
  to anon, authenticated;

