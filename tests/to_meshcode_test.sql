BEGIN;
-- Total tests: 14 (Tokyo) + 14 (Kyoto) = 28 tests.
SELECT plan(28);

-- Tokyo Tests
WITH tokyo_tests AS (
  SELECT *
  FROM (
    VALUES
      ('Lv1',    5339),
      ('X40',    53392),
      ('X20',    5339235),
      ('X16',    5339467),
      ('Lv2',    533935),
      ('X8',     5339476),
      ('X5',     5339354),
      ('X4',     533947637),
      ('X2_5',   533935446),
      ('X2',     533935885),
      ('Lv3',    53393599),
      ('Lv4',    533935992),
      ('Lv5',    5339359921),
      ('Lv6',    53393599212)
  ) AS t(level, expected)
)
SELECT is(
  jismesh.to_meshcode(
    ST_SetSRID(ST_MakePoint(139.745433, 35.658581), 4326),
    level::jismesh.mesh_level
  ),
  expected,
  'Tokyo: to_meshcode for ' || level
)
FROM tokyo_tests;

-- Kyoto Tests
WITH kyoto_tests AS (
  SELECT *
  FROM (
    VALUES
      ('Lv1',    5235),
      ('X40',    52352),
      ('X20',    5235245),
      ('X16',    5235467),
      ('Lv2',    523536),
      ('X8',     5235476),
      ('X5',     5235363),
      ('X4',     523547647),
      ('X2_5',   523536336),
      ('X2',     523536805),
      ('Lv3',    52353680),
      ('Lv4',    523536804),
      ('Lv5',    5235368041),
      ('Lv6',    52353680412)
  ) AS t(level, expected)
)
SELECT is(
  jismesh.to_meshcode(
    ST_SetSRID(ST_MakePoint(135.759363, 34.987574), 4326),
    level::jismesh.mesh_level
  ),
  expected,
  'Kyoto: to_meshcode for ' || level
)
FROM kyoto_tests;

SELECT * FROM finish();
ROLLBACK;
