BEGIN;
SELECT plan(32);

WITH tests AS (
  SELECT *
  FROM (
    VALUES
      (0,           NULL,  'to_meshlevel(0) IS NULL'),
      (5,           NULL,  'to_meshlevel(5) IS NULL'),
      (533947639,   NULL,  'to_meshlevel(533947639) IS NULL'),
      (NULL,        NULL,  'to_meshlevel(NULL) IS NULL'),
      (5339,        'Lv1', 'to_meshlevel(5339) = Lv1'),
      (53392,       'X40', 'to_meshlevel(53392) = X40'),
      (5339245,     'X20', 'to_meshlevel(5339245) = X20'),
      (5339467,     'X16', 'to_meshlevel(5339467) = X16'),
      (533936,      'Lv2', 'to_meshlevel(533936) = Lv2'),
      (5339476,     'X8',  'to_meshlevel(5339476) = X8'),
      (5339363,     'X5',  'to_meshlevel(5339363) = X5'),
      (533947647,   'X4',  'to_meshlevel(533947647) = X4'),
      (533936336,   'X2_5','to_meshlevel(533936336) = X2_5'),
      (533936805,   'X2', 'to_meshlevel(533936805) = X2'),
      (53393680,    'Lv3', 'to_meshlevel(53393680) = Lv3'),
      (533936804,   'Lv4', 'to_meshlevel(533936804) = Lv4'),
      (5339368041,  'Lv5', 'to_meshlevel(5339368041) = Lv5'),
      (53393680412, 'Lv6', 'to_meshlevel(53393680412) = Lv6'),
      (5235,        'Lv1', 'to_meshlevel(5235) = Lv1'),
      (52352,       'X40', 'to_meshlevel(52352) = X40'),
      (5235245,     'X20', 'to_meshlevel(5235245) = X20'),
      (5235467,     'X16', 'to_meshlevel(5235467) = X16'),
      (523536,      'Lv2', 'to_meshlevel(523536) = Lv2'),
      (5235476,     'X8',  'to_meshlevel(5235476) = X8'),
      (5235363,     'X5',  'to_meshlevel(5235363) = X5'),
      (523547647,   'X4',  'to_meshlevel(523547647) = X4'),
      (523536336,   'X2_5','to_meshlevel(523536336) = X2_5'),
      (523536805,   'X2', 'to_meshlevel(523536805) = X2'),
      (52353680,    'Lv3', 'to_meshlevel(52353680) = Lv3'),
      (523536804,   'Lv4', 'to_meshlevel(523536804) = Lv4'),
      (5235368041,  'Lv5', 'to_meshlevel(5235368041) = Lv5'),
      (52353680412, 'Lv6', 'to_meshlevel(52353680412) = Lv6')
  ) AS t(meshcode, expected, description)
)
SELECT
  CASE
    WHEN expected IS NULL THEN
      ok(to_meshlevel(meshcode) IS NULL, description)
    ELSE
      is(to_meshlevel(meshcode), expected::mesh_level, description)
  END
FROM tests;

SELECT * FROM finish();
ROLLBACK;
