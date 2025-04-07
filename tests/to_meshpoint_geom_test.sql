BEGIN;
SELECT plan(15);

-- Define the test cases using a CTE.
WITH test_data(meshcode, lat_multiplier, lon_multiplier, expected_lat, expected_lon) AS (
  VALUES
    (5339,       0.0, 0.0, 35.0 + 1.0/3.0, 139.0),
    (53391,      0.0, 0.0, 35.0 + 1.0/3.0, 139.0),
    (5339115,    0.0, 0.0, 35.0 + 1.0/3.0, 139.0),
    (5339007,    0.0, 0.0, 35.0 + 1.0/3.0, 139.0),
    (533900,     0.0, 0.0, 35.0 + 1.0/3.0, 139.0),
    (5339006,    0.0, 0.0, 35.0 + 1.0/3.0, 139.0),
    (5339001,    0.0, 0.0, 35.0 + 1.0/3.0, 139.0),
    (533900617,  0.0, 0.0, 35.0 + 1.0/3.0, 139.0),
    (533900116,  0.0, 0.0, 35.0 + 1.0/3.0, 139.0),
    (533900005,  0.0, 0.0, 35.0 + 1.0/3.0, 139.0),
    (53390000,   0.0, 0.0, 35.0 + 1.0/3.0, 139.0),
    (533900001,  0.0, 0.0, 35.0 + 1.0/3.0, 139.0),
    (5339000011, 0.0, 0.0, 35.0 + 1.0/3.0, 139.0),
    (53390000111,0.0, 0.0, 35.0 + 1.0/3.0, 139.0),
    (53393599212,0.5, 0.5, 35.6588542,    139.74609375)
)
-- For each test case, compare the generated geometry with the expected point.
SELECT ok(
  ST_DWithin(
    jismesh.to_meshpoint_geom(meshcode, lat_multiplier, lon_multiplier),
    ST_SetSRID(ST_MakePoint(expected_lon, expected_lat), 4326),
    1e-6
  ),
  format('to_meshpoint_geom(%s, %s, %s) returns expected geometry', meshcode, lat_multiplier, lon_multiplier)
)
FROM test_data;

SELECT * FROM finish();
ROLLBACK;
