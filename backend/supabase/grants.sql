-- WELL WAY: 给 anon / authenticated / service_role 开放 public 下所有表/序列/函数的权限
-- (新 Supabase 项目不会自动给 SQL Editor 创建的表授权,需要显式执行)

grant usage on schema public to anon, authenticated, service_role;

grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;
grant all on all functions in schema public to anon, authenticated, service_role;

-- 以后新建的表也自动带权限
alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on functions to anon, authenticated, service_role;
