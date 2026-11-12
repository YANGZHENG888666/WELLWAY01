-- 管理操作日志:内容表任何增删改自动记录(操作人/时间/旧值/新值)
-- 在 Supabase Dashboard → SQL Editor 中执行本文件。

-- 1. 日志表
create table if not exists public.admin_logs (
  id bigint generated always as identity primary key,
  table_name text not null,
  action text not null check (action in ('INSERT','UPDATE','DELETE')),
  row_id text,
  old_data jsonb,
  new_data jsonb,
  actor_id uuid references auth.users(id) on delete set null,
  actor_email text,
  created_at timestamptz not null default now()
);

create index if not exists admin_logs_created_at_idx on public.admin_logs (created_at desc);
create index if not exists admin_logs_table_idx on public.admin_logs (table_name, created_at desc);

alter table public.admin_logs enable row level security;

-- 2. 只有管理员可读
drop policy if exists "admin_logs_admin_select" on public.admin_logs;
create policy "admin_logs_admin_select" on public.admin_logs
for select to authenticated
using (public.is_admin());

-- 3. 触发函数:INSERT/UPDATE/DELETE 落日志(security definer 由 postgres 执行,绕过 RLS)
create or replace function public.log_content_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.admin_logs (table_name, action, row_id, old_data, new_data, actor_id, actor_email)
  values (
    tg_table_name,
    tg_op,
    coalesce((new.id)::text, (old.id)::text),
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end,
    auth.uid(),
    nullif(auth.jwt() ->> 'email', '')
  );
  return coalesce(new, old);
end
$$;

-- 4. 挂到管理内容表(可重复执行)
do $$
declare t text;
begin
  foreach t in array array['brands','models','routes','checkpoints','badges'] loop
    execute format('drop trigger if exists trg_admin_log on public.%I', t);
    execute format('create trigger trg_admin_log after insert or update or delete on public.%I for each row execute function public.log_content_change()', t);
  end loop;
end
$$;

-- 5. 权限(沿用默认授权;触发函数已由 postgres 执行,无需额外授权)
grant all on table public.admin_logs to authenticated;
