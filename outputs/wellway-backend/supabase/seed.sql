-- WELL WAY starter vehicle library.
-- Data comes from public spec sheets / official announcements.
-- Prices are indicative MSRP in CNY and MUST be verified before release.

insert into public.brands (name, name_en, is_hot, sort) values
  ('春风动力', 'CFMOTO', true, 1),
  ('阿普利亚', 'Aprilia', true, 2),
  ('川崎', 'Kawasaki', true, 3),
  ('本田', 'Honda', true, 4),
  ('贝纳利', 'Benelli', false, 5);

insert into public.models
  (brand_id, name, series, model_type, displacement_cc, price_min, price_max, rating, is_new, sort)
values
  (1, '春风 450SR', 'SR系列', '跑车', 450, 23980, 28580, 8.9, true, 1),
  (1, '春风 500SR', 'SR系列', '跑车', 500, 28980, 28980, 9.3, true, 2),
  (1, '春风 450NK', 'NK系列', '街车', 450, 23880, 23880, 8.9, false, 3),
  (1, '春风 450MT', 'MT系列', 'ADV', 450, 30580, 32580, 9.0, true, 4),
  (2, '阿普利亚 RS 457', 'RS系列', '跑车', 457, 41800, 41800, 9.0, true, 1),
  (2, '阿普利亚 Tuono 457', 'Tuono系列', '街车', 457, 40800, 40800, 8.9, true, 2),
  (3, '川崎 Ninja 400', 'Ninja系列', '跑车', 399, 49800, 49800, 8.8, false, 1),
  (3, '川崎 Z400', 'Z系列', '街车', 399, 47800, 47800, 8.7, false, 2),
  (4, '本田 CB400F', 'CB系列', '街车', 399, 39000, 39000, 8.6, false, 1),
  (4, '本田 CM300', 'CM系列', '复古', 286, 34500, 34500, 8.5, false, 2),
  (5, '贝纳利 502C', 'C系列', '复古', 500, 39800, 39800, 8.4, false, 1),
  (5, '贝纳利 TRK502', 'TRK系列', 'ADV', 500, 39800, 45800, 8.6, false, 2);
