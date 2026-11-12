-- 匿名骑手在场统计隐私收口
-- 1) App 只通过聚合函数获取人数，不再读取其他用户的 id / 坐标 / 昵称 / 车辆
-- 2) ride_presence 仅允许本人读取自己的心跳行
-- 3) 清理历史写入的昵称与车辆名，后续客户端也不再上报

create or replace function public.riders_on_route(p_route_id bigint)
returns jsonb
language sql
security definer
stable
set search_path = public
as $$
  select jsonb_build_object(
    'count',
    (
      select count(distinct r.user_id)
      from public.ride_presence r
      where r.route_id = p_route_id
        and r.updated_at > now() - interval '120 seconds'
        and (auth.uid() is null or r.user_id <> auth.uid())
    ),
    'fresh_seconds', 120
  );
$$;

grant execute on function public.riders_on_route(bigint) to anon, authenticated;

drop policy if exists "ride_presence_select" on public.ride_presence;
drop policy if exists "ride_presence_select_own" on public.ride_presence;
create policy "ride_presence_select_own" on public.ride_presence
  for select using (user_id = auth.uid());

update public.ride_presence
set nickname = null,
    vehicle_name = null;

comment on table public.ride_presence is
  '骑行中匿名位置心跳：客户端只能读取本人记录；其他骑手仅可通过 riders_on_route / riders_nearby 获取聚合人数。';

-- 验证：
-- select public.riders_on_route(1);
-- select * from public.ride_presence limit 1; -- 普通用户应只能看到自己的行
