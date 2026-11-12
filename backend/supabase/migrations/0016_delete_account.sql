-- WELL WAY 注销账号(2026-08-25)
-- 合规依据: 个保法第47条(删除权) / App Store 审核指南 5.1.1(v)(账号删除入口)
-- 用法: Supabase Dashboard → SQL Editor 整体粘贴执行, 可重复执行。
-- 说明: 用户数据表(profiles / vehicles / ride_records / ride_points /
--       user_badges / route_favorites / ride_checkins / ride_presence)
--       均以 auth.users 为外键 on delete cascade, 删除 auth.users 记录即级联清除;
--       feedback / admin_logs 为 on delete set null(匿名化保留, 不含个人信息)。
--       车辆照片存放于 Storage 桶 vehicle-photos/<uid>/ 下, 由 App 端在调用
--       本函数前通过 Storage API 删除(直接 SQL 删除 storage.objects 会被
--       Supabase Storage 拦截, 报 42501, 因此这里不再触碰 storage 表)。

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'forbidden: 未登录';
  end if;

  -- 删除 auth.users 记录(其余用户数据表级联清除)
  delete from auth.users where id = v_uid;
end;
$$;

grant execute on function public.delete_my_account() to anon, authenticated;

-- 校验: 列出该函数, 确认已创建
-- select proname from pg_proc where proname = 'delete_my_account';
