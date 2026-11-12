-- 0021_drop_vehicle_plate.sql
-- 车牌功能下线:产品/合规口径为「不采集车牌」(见 legal/privacy.html、docs/API-V1.md)。
-- 本迁移删除 vehicles.plate,使口径与事实一致。可重复执行。
--
-- 执行前备份(2026-09-17 执行时全库仅 1 行有值,已存 backend/supabase/backups/plate-backup-2026-09-17.txt):
--   select id, user_id, nickname, plate from public.vehicles where plate is not null and plate <> '';

alter table public.vehicles drop column if exists plate;

comment on table public.vehicles is '用户车库车辆。不含车牌(plate 已于 0021 下线,合规口径:不采集车牌)';
