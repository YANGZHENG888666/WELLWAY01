-- WELL WAY: 骑行统计安全加固(可重复执行)
-- 修复:定位跳变导致 recalculate_ride_stats 数值溢出(numeric(5,1) overflow)
-- 1) 过滤相邻轨迹点 >1000m 的跳变段 2) 平均/最大速度封顶 300 km/h
-- 在 Supabase Dashboard → SQL Editor 中粘贴执行。

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
  ),
  clean as (
    -- 过滤定位跳变段(>1000m)与异常速度,防止脏定位撑爆里程/平均速度
    select
      case when seg_m <= 1000 then seg_m else 0 end as seg_m,
      least(coalesce(speed_kmh, 0), 300) as speed_kmh
    from seg
  )
  select
    coalesce(round(sum(seg_m))::int, 0),
    coalesce(max(speed_kmh), 0)
  into v_distance_m, v_max_kmh
  from clean;

  select
    coalesce(extract(epoch from (max(recorded_at) - min(recorded_at)))::int, 0)
  into v_duration_s
  from public.ride_points
  where ride_id = p_ride_id;

  v_avg_kmh := case
    when v_duration_s > 0
      then least(round((v_distance_m::numeric / 1000.0) / (v_duration_s::numeric / 3600.0), 1), 300)
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

grant execute on function public.recalculate_ride_stats(uuid) to anon, authenticated;
