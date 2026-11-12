-- 今日(北京时间)各路线的真实骑行人数统计
-- 供 App 卡片/详情页「今天有 X 位骑友骑行」使用
-- 说明:ride_records 行级权限是"只能看自己的记录",
-- 所以这里用 security definer 函数只返回聚合计数,不暴露任何个人数据。

create or replace function public.count_route_riders_today()
returns table (route_id bigint, rider_count bigint)
language sql
security definer
set search_path = public
as $$
  select r.route_id, count(distinct r.user_id)::bigint as rider_count
  from public.ride_records r
  where r.route_id is not null
    and r.started_at >= date_trunc('day', now() at time zone 'Asia/Shanghai') at time zone 'Asia/Shanghai'
  group by r.route_id
$$;

-- 允许匿名与登录用户调用(只拿得到聚合计数)
grant execute on function public.count_route_riders_today() to anon, authenticated;

-- 备注(可执行验证):
-- select * from public.count_route_riders_today();
