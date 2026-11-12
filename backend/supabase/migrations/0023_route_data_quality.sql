-- Route catalogue corrections:
-- 1) route metadata must match checkpoint coordinates
-- 2) drop duplicate demo routes from the public list
-- 3) fix the 20 m placeholder distance on 南雁路

update public.routes
set province = '上海', city = '上海'
where name = '城市穿梭线';

update public.routes
set province = '浙江', city = '杭州'
where name = '山路打卡线';

update public.routes
set distance_m = 25147,
    elevation_m = 523,
    duration_min = 23
where name = '南雁路';

update public.routes
set is_active = false
where name in ('香山跑山线', '长安街夜骑');
