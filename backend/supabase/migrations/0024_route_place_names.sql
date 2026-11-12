-- 修正路线的泛化起终点名称，避免出发页把城市名当成目的地。
-- 路线 9「洱海环湖骑行」实际为大理古城 → 双廊。

update public.routes
set start_name = '大理古城',
    end_name = '双廊'
where id = 9;
