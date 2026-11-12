-- ================= 0015: 匿名轻社交(同路骑友徽章数) =================
-- WELL WAY: 匿名轻社交 - 只展示车型 + 徽章信息,不暴露昵称/主页/聊天
-- 安全聚合函数:仅返回「当前在骑行中(ride_presence 有活跃上报)」骑友的徽章数量,
-- 不返回任何个人资料;个人资料、主页、聊天入口均已随 0014 移除。
-- 在 Supabase Dashboard → SQL Editor 中粘贴执行(可重复执行)。

create or replace function public.rider_badge_counts()
returns table (user_id uuid, badge_count bigint)
language sql
security definer
set search_path = public
stable
as $$
  select ub.user_id, count(*)::bigint as badge_count
  from public.user_badges ub
  where exists (
    select 1 from public.ride_presence rp
    where rp.user_id = ub.user_id
  )
  group by ub.user_id;
$$;

revoke all on function public.rider_badge_counts() from public;
grant execute on function public.rider_badge_counts() to authenticated;
