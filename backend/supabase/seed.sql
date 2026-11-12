-- ⚠️ 车型库已改由 backend/scripts/catalog/ 流程生成（281 品牌 / 1943 款，见该目录 README）。
-- 本文件里的 7 品牌 / 25 款只是最初的起步样例，保留作为离线初始化用，不要再手工往这里补车型：
--   车型目录源文件 → backend/scripts/catalog/data/catalog.json
--   入库脚本     → node backend/scripts/catalog/load-catalog.mjs --apply
-- Prices are indicative MSRP in CNY and MUST be verified before release.
-- Safe to run multiple times (upsert by brand name / model name).

insert into public.brands (name, name_en, is_hot, sort) values
  ('春风动力', 'CFMOTO', true, 1),
  ('阿普利亚', 'Aprilia', true, 2),
  ('川崎', 'Kawasaki', true, 3),
  ('本田', 'Honda', true, 4),
  ('贝纳利', 'Benelli', false, 5),
  ('雅马哈', 'Yamaha', true, 6),
  ('铃木', 'Suzuki', false, 7)
on conflict (name) do update set
  name_en = excluded.name_en,
  is_hot = excluded.is_hot,
  sort = excluded.sort;

insert into public.models
  (brand_id, name, series, model_type, displacement_cc, price_min, price_max, rating, is_new, sort)
select
  b.id, m.name, m.series, m.model_type, m.displacement_cc,
  m.price_min, m.price_max, m.rating, m.is_new, m.sort
from (values
  -- 春风动力
  ('春风动力', '春风 450SR', 'SR系列', '跑车', 450, 23980, 28580, 8.9, true, 1),
  ('春风动力', '春风 500SR', 'SR系列', '跑车', 500, 28980, 28980, 9.3, true, 2),
  ('春风动力', '春风 450NK', 'NK系列', '街车', 450, 23880, 23880, 8.9, false, 3),
  ('春风动力', '春风 450MT', 'MT系列', 'ADV', 450, 30580, 32580, 9.0, true, 4),
  ('春风动力', '春风 250SR', 'SR系列', '跑车', 250, 19980, 21580, 8.7, false, 5),
  ('春风动力', '春风 800NK', 'NK系列', '街车', 799, 44980, 49980, 9.1, false, 6),
  -- 阿普利亚
  ('阿普利亚', '阿普利亚 RS 457', 'RS系列', '跑车', 457, 41800, 41800, 9.0, true, 1),
  ('阿普利亚', '阿普利亚 Tuono 457', 'Tuono系列', '街车', 457, 40800, 40800, 8.9, true, 2),
  -- 川崎
  ('川崎', '川崎 Ninja 400', 'Ninja系列', '跑车', 399, 49800, 49800, 8.8, false, 1),
  ('川崎', '川崎 Z400', 'Z系列', '街车', 399, 47800, 47800, 8.7, false, 2),
  ('川崎', '川崎 Ninja 650', 'Ninja系列', '跑车', 649, 70800, 70800, 8.6, false, 3),
  ('川崎', '川崎 Z900', 'Z系列', '街车', 948, 89800, 89800, 9.0, false, 4),
  ('川崎', '川崎 Versys 650', 'Versys系列', 'ADV', 649, 69800, 69800, 8.5, false, 5),
  -- 本田
  ('本田', '本田 CB400F', 'CB系列', '街车', 399, 39000, 39000, 8.6, false, 1),
  ('本田', '本田 CM300', 'CM系列', '复古', 286, 34500, 34500, 8.5, false, 2),
  ('本田', '本田 CB400X', 'CB系列', 'ADV', 399, 41500, 41500, 8.5, false, 3),
  ('本田', '本田 CBR400R', 'CBR系列', '跑车', 399, 42000, 42000, 8.5, false, 4),
  ('本田', '本田 PCX160', 'PCX系列', '踏板', 157, 22990, 22990, 8.4, false, 5),
  -- 贝纳利
  ('贝纳利', '贝纳利 502C', 'C系列', '复古', 500, 39800, 39800, 8.4, false, 1),
  ('贝纳利', '贝纳利 TRK502', 'TRK系列', 'ADV', 500, 39800, 45800, 8.6, false, 2),
  ('贝纳利', '贝纳利 幼狮 250', 'Leoncino系列', '复古', 250, 19900, 19900, 8.3, false, 3),
  -- 雅马哈
  ('雅马哈', '雅马哈 YZF-R3', 'YZF系列', '跑车', 321, 43800, 43800, 8.6, false, 1),
  ('雅马哈', '雅马哈 MT-03', 'MT系列', '街车', 321, 39800, 39800, 8.5, false, 2),
  ('雅马哈', '雅马哈 NMAX155', 'NMAX系列', '踏板', 155, 27800, 27800, 8.3, false, 3),
  -- 铃木
  ('铃木', '铃木 GSX250R', 'GSX系列', '跑车', 248, 26680, 26680, 8.4, false, 1)
) as m(brand_name, name, series, model_type, displacement_cc, price_min, price_max, rating, is_new, sort)
join public.brands b on b.name = m.brand_name
on conflict (brand_id, name) do update set
  series = excluded.series,
  model_type = excluded.model_type,
  displacement_cc = excluded.displacement_cc,
  price_min = excluded.price_min,
  price_max = excluded.price_max,
  rating = excluded.rating,
  is_new = excluded.is_new,
  sort = excluded.sort;

-- ---------------------------------------------------------------
-- Demo routes / checkpoints / badges (coordinates are illustrative)
-- ---------------------------------------------------------------
insert into public.routes
  (name, start_name, end_name, distance_m, elevation_m, difficulty, duration_min, geo_json)
values
  ('城市穿梭线', '滨江路', '中央公园', 20000, 120, '简单', 45, null),
  ('山路打卡线', '山脚驿站', '山顶观景台', 58000, 980, '困难', 150, null)
on conflict (name) do update set
  start_name = excluded.start_name,
  end_name = excluded.end_name,
  distance_m = excluded.distance_m,
  elevation_m = excluded.elevation_m,
  difficulty = excluded.difficulty,
  duration_min = excluded.duration_min,
  geo_json = excluded.geo_json;

insert into public.checkpoints (route_id, name, seq, lat, lng, radius_m)
select r.id, c.name, c.seq, c.lat, c.lng, c.radius_m
from (values
  ('城市穿梭线', '滨江路起点', 1, 31.2304, 121.4737, 50),
  ('城市穿梭线', '中央公园', 2, 31.2252, 121.4392, 80),
  ('山路打卡线', '山脚驿站', 1, 30.2741, 120.1551, 60),
  ('山路打卡线', '半山观景台', 2, 30.2905, 120.1608, 60),
  ('山路打卡线', '山顶观景台', 3, 30.3052, 120.1682, 80)
) as c(route_name, name, seq, lat, lng, radius_m)
join public.routes r on r.name = c.route_name
on conflict (route_id, seq) do update set
  name = excluded.name,
  lat = excluded.lat,
  lng = excluded.lng,
  radius_m = excluded.radius_m;

insert into public.badges (route_id, name, image_url, condition_desc, seq)
select r.id, b.name, b.image_url, b.condition_desc, b.seq
from (values
  (null, '新手首骑', null, '完成第一次骑行记录', 1),
  (null, '打卡达人', null, '累计完成 10 次路线打卡', 2),
  ('山路打卡线', '山路挑战者', null, '完成「山路打卡线」全程', 3)
) as b(route_name, name, image_url, condition_desc, seq)
left join public.routes r on r.name = b.route_name
on conflict (name) do update set
  route_id = excluded.route_id,
  image_url = excluded.image_url,
  condition_desc = excluded.condition_desc,
  seq = excluded.seq;

-- ---------------------------------------------------------------
-- Figma 演示路线(北京)/ 路线徽章 / 活动(幂等)
-- ---------------------------------------------------------------
insert into public.routes
  (name, start_name, end_name, distance_m, elevation_m, difficulty, duration_min, geo_json)
values
  ('四惠桥通勤线', '四惠桥', '国贸', 12600, 120, '简单', 45, null),
  ('香山压弯线', '香山脚下', '鬼笑石', 18200, 640, '困难', 130, null),
  ('长安街夜骑线', '西单', '建国门', 9800, 40, '简单', 35, null)
on conflict (name) do update set
  start_name = excluded.start_name,
  end_name = excluded.end_name,
  distance_m = excluded.distance_m,
  elevation_m = excluded.elevation_m,
  difficulty = excluded.difficulty,
  duration_min = excluded.duration_min;

insert into public.checkpoints (route_id, name, seq, lat, lng, radius_m)
select r.id, c.name, c.seq, c.lat, c.lng, c.radius_m
from (values
  ('四惠桥通勤线', '四惠桥', 1, 39.9087, 116.4975, 80),
  ('四惠桥通勤线', '东四环桥洞', 2, 39.9110, 116.4920, 80),
  ('四惠桥通勤线', '国贸', 3, 39.9086, 116.4598, 80),
  ('香山压弯线', '香山脚下', 1, 39.9906, 116.1900, 100),
  ('香山压弯线', '鬼笑石', 2, 39.9720, 116.1850, 100),
  ('长安街夜骑线', '西单路口', 1, 39.9075, 116.3740, 80),
  ('长安街夜骑线', '建国门桥', 2, 39.9078, 116.4350, 80)
) as c(route_name, name, seq, lat, lng, radius_m)
join public.routes r on r.name = c.route_name
on conflict (route_id, seq) do update set
  name = excluded.name,
  lat = excluded.lat,
  lng = excluded.lng,
  radius_m = excluded.radius_m;

insert into public.badges (route_id, name, image_url, condition_desc, seq)
select r.id, b.name, b.image_url, b.condition_desc, b.seq
from (values
  ('四惠桥通勤线', '通勤骑士', null, '完成「四惠桥通勤线」全程', 4),
  ('香山压弯线', '跑山骑士', null, '完成「香山压弯线」全程', 5),
  ('长安街夜骑线', '夜骑骑士', null, '完成「长安街夜骑线」全程', 6)
) as b(route_name, name, image_url, condition_desc, seq)
left join public.routes r on r.name = b.route_name
on conflict (name) do update set
  route_id = excluded.route_id,
  image_url = excluded.image_url,
  condition_desc = excluded.condition_desc,
  seq = excluded.seq;

insert into public.activities (name, route_id, starts_at, ends_at, reward_desc, slots, status)
select a.name, r.id, a.starts_at::timestamptz, a.ends_at::timestamptz, a.reward_desc, a.slots, a.status
from (values
  ('周末骑行挑战', '四惠桥通勤线', '2026-08-15 07:00:00+08', '2026-08-15 12:00:00+08',
   '完成挑战可获得限定徽章;完赛前 20 名额外获得骑行装备', 12, 'upcoming'),
  ('夜骑长安街', '长安街夜骑线', '2026-08-22 20:00:00+08', '2026-08-22 23:00:00+08',
   '完赛可获得夜骑限定徽章与骑行装备', 28, 'upcoming')
) as a(name, route_name, starts_at, ends_at, reward_desc, slots, status)
join public.routes r on r.name = a.route_name
on conflict (name) do update set
  route_id = excluded.route_id,
  starts_at = excluded.starts_at,
  ends_at = excluded.ends_at,
  reward_desc = excluded.reward_desc,
  slots = excluded.slots,
  status = excluded.status;
