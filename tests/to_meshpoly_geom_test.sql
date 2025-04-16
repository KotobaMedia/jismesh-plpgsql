BEGIN;
SELECT plan(2);

-- Tokyo Lv1 meshcode 5339
SELECT is(
  ST_AsText(jismesh.to_meshpoly_geom(5339)),
  'POLYGON((139 35.33333333333333,140 35.33333333333333,140 35.99999999999999,139 35.99999999999999,139 35.33333333333333))',
  'to_meshpoly_geom(5339) returns expected polygon for Tokyo Lv1'
);

-- Kyoto Lv1 meshcode 5235
SELECT is(
  ST_AsText(jismesh.to_meshpoly_geom(5235)),
  'POLYGON((135 34.666666666666664,136 34.666666666666664,136 35.33333333333333,135 35.33333333333333,135 34.666666666666664))',
  'to_meshpoly_geom(5235) returns expected polygon for Kyoto Lv1'
);

SELECT * FROM finish();
ROLLBACK;
