-- 事故现场记录（只做留存，不提供自动报警 / 救援调度）
--
-- 产品口径：
--   1. 用户必须先自行拨打 110 / 120 / 122；
--   2. 本表只保存用户主动提交的时间、路线、坐标与经过，供本人、
--      家人、保险或维修方核对，也供客服在后台只读查看；
--   3. 不自动通知任何第三方，不承诺平台派人救援。
--
-- 权限：
--   - 仅登录用户（含匿名登录）可插入自己的记录；
--   - 用户只能读取自己的记录；
--   - 管理员可只读全部记录；
--   - 不提供 update / delete 策略，事故记录不可被用户篡改或删除；
--     注销账号时随 auth.users 级联删除。
--
-- 可重复执行。

create table if not exists public.incident_reports (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  route_name text,
  latitude double precision,
  longitude double precision,
  incident_type text not null,
  note text not null default '',
  occurred_at timestamptz not null default now(),
  app_version text,
  created_at timestamptz not null default now(),
  constraint incident_reports_type_check
    check (incident_type in ('fall', 'collision', 'breakdown', 'other')),
  constraint incident_reports_note_check
    check (char_length(note) <= 500),
  constraint incident_reports_coordinate_check
    check (
      (latitude is null and longitude is null)
      or (
        latitude is not null
        and longitude is not null
        and latitude between -90 and 90
        and longitude between -180 and 180
      )
    )
);

alter table public.incident_reports
  drop constraint if exists incident_reports_coordinate_check;
alter table public.incident_reports
  add constraint incident_reports_coordinate_check
  check (
    (latitude is null and longitude is null)
    or (
      latitude is not null
      and longitude is not null
      and latitude between -90 and 90
      and longitude between -180 and 180
    )
  );

comment on table public.incident_reports is
  '用户主动提交的事故现场记录；仅留存，不触发报警、通知或救援调度。';

create index if not exists incident_reports_created_at_idx
  on public.incident_reports (created_at desc);
create index if not exists incident_reports_user_id_idx
  on public.incident_reports (user_id);

alter table public.incident_reports enable row level security;

drop policy if exists "incident_reports_insert_own" on public.incident_reports;
drop policy if exists "incident_reports_select_own" on public.incident_reports;
drop policy if exists "incident_reports_select_admin" on public.incident_reports;

create policy "incident_reports_insert_own" on public.incident_reports
  for insert to authenticated
  with check (user_id = auth.uid());

create policy "incident_reports_select_own" on public.incident_reports
  for select to authenticated
  using (user_id = auth.uid());

create policy "incident_reports_select_admin" on public.incident_reports
  for select to authenticated
  using (public.is_admin());

revoke all on public.incident_reports from anon;
grant select, insert on public.incident_reports to authenticated;
grant usage, select on sequence public.incident_reports_id_seq to authenticated;
