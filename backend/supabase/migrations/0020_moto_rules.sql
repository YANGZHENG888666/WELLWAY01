-- ================= 0020: 城市摩托车限行规则 =================
-- 对应《V1 内测・最终定稿 接口清单》第 3 节 GET /api/moto/rules
-- 设计口径:
--   · 只存"交管公告的文字摘要 + 来源链接",不做任何算法判定(不判定某辆车能不能走);
--   · 规则原文必须人工核对后录入,列表里 verified=false 的条目 App 会额外提示"待核对";
--   · 本迁移只把城市清单铺好,rule_text 留空,由运营按城市逐条补齐(附填写模板在文件末尾)。
-- 可重复执行。

-- ---------------------------------------------------------------
-- 1) 规则表
-- ---------------------------------------------------------------
create table if not exists public.moto_rules (
  city_code text primary key,              -- 行政区划代码,如 110100
  city_name text not null,                 -- 北京市
  province text,                           -- 北京
  rule_text text,                          -- 交管公告摘要(纯文本,可含换行)
  source_url text,                         -- 来源链接(交管官网/政府公告)
  effective_from date,                     -- 该摘要对应政策的生效日期
  verified boolean not null default false, -- 是否已人工核对
  verified_by text,                        -- 核对人(内测阶段记个名字即可)
  updated_at timestamptz not null default now()
);

alter table public.moto_rules enable row level security;

drop policy if exists "moto_rules_select_all" on public.moto_rules;
drop policy if exists "moto_rules_admin_write" on public.moto_rules;
drop policy if exists "moto_rules_admin_update" on public.moto_rules;
drop policy if exists "moto_rules_admin_delete" on public.moto_rules;

-- 所有人可读(规则是公开信息)
create policy "moto_rules_select_all" on public.moto_rules
  for select using (true);

-- 只有管理员可维护(复用已有的 public.is_admin())
create policy "moto_rules_admin_write" on public.moto_rules
  for insert with check (public.is_admin());
create policy "moto_rules_admin_update" on public.moto_rules
  for update using (public.is_admin());
create policy "moto_rules_admin_delete" on public.moto_rules
  for delete using (public.is_admin());

drop trigger if exists trg_moto_rules_updated on public.moto_rules;
create trigger trg_moto_rules_updated
before update on public.moto_rules
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------
-- 2) 查询接口 GET /api/moto/rules → rpc/moto_rule
--    入参可以是行政区划代码(110100)也可以是城市名(北京市/北京)
-- ---------------------------------------------------------------
create or replace function public.moto_rule(p_city_code text)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  with hit as (
    select r.*
    from public.moto_rules r
    where p_city_code is not null
      and length(trim(p_city_code)) > 0
      and (
        r.city_code = trim(p_city_code)
        or r.city_name = trim(p_city_code)
        or r.city_name = trim(p_city_code) || '市'
        or replace(r.city_name, '市', '') = replace(trim(p_city_code), '市', '')
      )
    limit 1
  )
  select case
    when exists (select 1 from hit) then (
      select jsonb_build_object(
        'found', true,
        'city_code', h.city_code,
        'city_name', h.city_name,
        'province', h.province,
        'rule_text', h.rule_text,
        'source_url', h.source_url,
        'effective_from', h.effective_from,
        'verified', h.verified,
        'updated_at', h.updated_at,
        'disclaimer', public.disclaimer_text()
      )
      from hit h
    )
    else jsonb_build_object(
      'found', false,
      'city_code', p_city_code,
      'city_name', null,
      'rule_text', null,
      'verified', false,
      'disclaimer', public.disclaimer_text()
    )
  end;
$$;

grant execute on function public.moto_rule(text) to anon, authenticated;

-- ---------------------------------------------------------------
-- 3) 城市清单(rule_text 留空 = 待录入)
--    录入后 App 端会自动显示;verified 由运营核对官方公告后置 true
-- ---------------------------------------------------------------
insert into public.moto_rules (city_code, city_name, province, verified) values
  ('110100', '北京市', '北京', false),
  ('120100', '天津市', '天津', false),
  ('310100', '上海市', '上海', false),
  ('440100', '广州市', '广东', false),
  ('440300', '深圳市', '广东', false),
  ('330100', '杭州市', '浙江', false),
  ('320100', '南京市', '江苏', false),
  ('510100', '成都市', '四川', false),
  ('500100', '重庆市', '重庆', false),
  ('420100', '武汉市', '湖北', false),
  ('610100', '西安市', '陕西', false),
  ('350200', '厦门市', '福建', false)
on conflict (city_code) do nothing;

-- ---------------------------------------------------------------
-- 4) 录入模板(复制到 SQL Editor 改内容执行;或走管理后台)
-- ---------------------------------------------------------------
-- update public.moto_rules set
--   rule_text = '1) ……;' || chr(10) || '2) ……;',
--   source_url = 'https://……',
--   effective_from = '2025-01-01',
--   verified = true,
--   verified_by = '内测运营'
-- where city_code = '110100';

-- 校验:
-- select public.moto_rule('110100');
-- select public.moto_rule('北京市');
-- select public.moto_rule('330100');
