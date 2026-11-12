-- 0017: 后台「用户反馈」只读查看
-- 管理员可读取全部用户反馈(意见反馈 / 品牌添加请求),普通用户仍只能看自己的
-- 与 0011 admin_logs 的 RLS 模式一致: 复用 public.is_admin()
create index if not exists feedback_created_at_idx on public.feedback (created_at desc);

drop policy if exists "feedback_admin_select" on public.feedback;
create policy "feedback_admin_select" on public.feedback
  for select to authenticated
  using (public.is_admin());
