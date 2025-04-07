CREATE SCHEMA IF NOT EXISTS jismesh;

-- Drop type and function if they exist (for easy re-running)
DROP FUNCTION IF EXISTS jismesh.jismesh.to_meshlevel(bigint);
DROP TYPE IF EXISTS jismesh.mesh_level;

-- Define the jismesh.mesh_level enum type
CREATE TYPE jismesh.mesh_level AS ENUM (
    'Lv1',
    'X40',
    'Lv2',
    'X5',
    'X20',
    'X8',
    'X16',
    'Lv3',
    'Lv4',
    'X2',
    'X2_5',
    'X4',
    'Lv5',
    'Lv6'
);

-- Create a table to store Japan's Lv1 mesh codes
DROP TABLE IF EXISTS jismesh.japan_lv1_meshes;
CREATE TABLE jismesh.japan_lv1_meshes (
    meshcode bigint PRIMARY KEY
);
INSERT INTO jismesh.japan_lv1_meshes (meshcode) VALUES
    (6848), (6847), (6842), (6841), (6840), (6748), (6747), (6742), (6741), (6740), (6647), (6646), (6645), (6644), (6643), (6642),
    (6641), (6546), (6545), (6544), (6543), (6542), (6541), (6540), (6445), (6444), (6443), (6442), (6441), (6440), (6439), (6343),
    (6342), (6341), (6340), (6339), (6243), (6241), (6240), (6239), (6141), (6140), (6139), (6041), (6040), (6039), (5942), (5941),
    (5940), (5939), (5841), (5840), (5839), (5741), (5740), (5739), (5738), (5641), (5640), (5639), (5638), (5637), (5636), (5541),
    (5540), (5539), (5538), (5537), (5536), (5531), (5440), (5439), (5438), (5437), (5436), (5435), (5433), (5432), (5340), (5339),
    (5338), (5337), (5336), (5335), (5334), (5333), (5332), (5240), (5239), (5238), (5237), (5236), (5235), (5234), (5233), (5232),
    (5231), (5229), (5139), (5138), (5137), (5136), (5135), (5134), (5133), (5132), (5131), (5130), (5129), (5039), (5038), (5036),
    (5035), (5034), (5033), (5032), (5031), (5030), (5029), (4939), (4934), (4933), (4932), (4931), (4930), (4929), (4928), (4839),
    (4831), (4830), (4829), (4828), (4740), (4739), (4731), (4730), (4729), (4728), (4631), (4630), (4629), (4540), (4531), (4530),
    (4529), (4440), (4429), (4329), (4328), (4230), (4229), (4142), (4129), (4128), (4042), (4040), (4028), (4027), (3942), (3928),
    (3927), (3926), (3841), (3831), (3824), (3823), (3741), (3725), (3724), (3653), (3641), (3631), (3624), (3623), (3622), (3036);
CREATE INDEX jismesh.idx_japan_lv1_meshes_meshcode ON jismesh.japan_lv1_meshes(meshcode);

-- Create the PL/pgSQL function to determine mesh level for a single code
CREATE OR REPLACE FUNCTION jismesh.to_meshlevel(code bigint)
RETURNS jismesh.mesh_level AS $$
DECLARE
    level jismesh.mesh_level;
    num_digits integer;
    g integer;
    i integer;
    j integer;
    k integer;
BEGIN
    -- Check if the input code is NULL or non-positive, return NULL if so
    IF code IS NULL OR code <= 0 THEN
        RETURN NULL;
    END IF;

    -- Calculate number of digits for the meshcode
    -- Using log10 requires casting to numeric or double precision
    -- Handle potential log(0) or negative which shouldn't happen due to above check, but safer
    BEGIN
        num_digits := floor(log(code::numeric))::integer + 1;
    EXCEPTION
        WHEN invalid_argument_for_logarithm THEN
            RETURN NULL; -- Should not happen with code > 0 check
        WHEN others THEN
            RETURN NULL; -- Catch any other math errors
    END;


    -- Determine mesh level based on the number of digits
    CASE num_digits
        WHEN 4 THEN
            level := 'Lv1';
        WHEN 5 THEN
            level := 'X40';
        WHEN 6 THEN
            level := 'Lv2';
        WHEN 7 THEN
            -- Extract the 7th digit (g)
            g := floor(code / power(10, num_digits - 7))::bigint % 10;
            CASE g
                WHEN 1, 2, 3, 4 THEN level := 'X5';
                WHEN 5 THEN level := 'X20';
                WHEN 6 THEN level := 'X8';
                WHEN 7 THEN level := 'X16';
                ELSE RETURN NULL; -- Invalid g
            END CASE;
        WHEN 8 THEN
            level := 'Lv3';
        WHEN 9 THEN
            -- Extract the 9th digit (i)
            i := floor(code / power(10, num_digits - 9))::bigint % 10;
            CASE i
                WHEN 1, 2, 3, 4 THEN level := 'Lv4';
                WHEN 5 THEN level := 'X2';
                WHEN 6 THEN level := 'X2_5';
                WHEN 7 THEN level := 'X4';
                ELSE RETURN NULL; -- Invalid i
            END CASE;
        WHEN 10 THEN
            -- Extract the 10th digit (j)
            j := floor(code / power(10, num_digits - 10))::bigint % 10;
            CASE j
                WHEN 1, 2, 3, 4 THEN level := 'Lv5';
                ELSE RETURN NULL; -- Invalid j
            END CASE;
        WHEN 11 THEN
            -- Extract the 11th digit (k)
            k := floor(code / power(10, num_digits - 11))::bigint % 10;
            CASE k
                WHEN 1, 2, 3, 4 THEN level := 'Lv6';
                ELSE RETURN NULL; -- Invalid k
            END CASE;
        ELSE
            RETURN NULL; -- Unknown number of digits
    END CASE;

    RETURN level;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;


CREATE OR REPLACE FUNCTION jismesh.to_meshpoint_geom(
    _meshcode BIGINT,
    _lat_multiplier DOUBLE PRECISION DEFAULT 0.0,
    _lon_multiplier DOUBLE PRECISION DEFAULT 0.0
)
RETURNS geometry(Point, 4326) AS $$
DECLARE
    -- Variables
    lat DOUBLE PRECISION;
    lon DOUBLE PRECISION;
    level jismesh.mesh_level; -- Changed type from TEXT
    mc_str TEXT := _meshcode::TEXT;
    len INT := length(mc_str);
    ab INT;
    cd INT;
    e INT := 0; -- Initialize to avoid NULL issues if not set
    f INT := 0;
    g INT := 0;
    h INT := 0;
    i INT := 0;
    j INT := 0;
    k INT := 0;
    unit_lat DOUBLE PRECISION;
    unit_lon DOUBLE PRECISION;

BEGIN
    -- Determine Mesh Level using the dedicated function
    level := jismesh.to_meshlevel(_meshcode);

    -- Return NULL if the mesh level could not be determined (invalid meshcode)
    IF level IS NULL THEN
        RETURN NULL;
    END IF;

    -- Extract digits (only extract necessary digits based on level/length if needed for optimization,
    -- but extracting all up to 11 is simpler for now)
    -- Ensure length check is implicitly handled by jismesh.to_meshlevel returning NULL
    ab := substring(mc_str, 1, 2)::INTEGER;
    cd := substring(mc_str, 3, 2)::INTEGER;
    IF len >= 5 THEN e := substring(mc_str, 5, 1)::INTEGER; END IF;
    IF len >= 6 THEN f := substring(mc_str, 6, 1)::INTEGER; END IF;
    IF len >= 7 THEN g := substring(mc_str, 7, 1)::INTEGER; END IF;
    IF len >= 8 THEN h := substring(mc_str, 8, 1)::INTEGER; END IF;
    IF len >= 9 THEN i := substring(mc_str, 9, 1)::INTEGER; END IF;
    IF len >= 10 THEN j := substring(mc_str, 10, 1)::INTEGER; END IF;
    IF len >= 11 THEN k := substring(mc_str, 11, 1)::INTEGER; END IF;

    -- Base adjustment (Common to all levels)
    lat := ab * jismesh.get_unit_lat('Lv1');
    lon := cd * jismesh.get_unit_lon('Lv1') + 100.0;

    -- Level-specific adjustments and unit determination
    -- Uses the level determined by the jismesh.to_meshlevel function
    CASE level
        WHEN 'Lv1' THEN
            unit_lat := jismesh.get_unit_lat('Lv1');
            unit_lon := jismesh.get_unit_lon('Lv1');
        WHEN 'X40' THEN
            -- Check standard: Rust uses e/3 == 1, e%2 == 0. Assuming e=1,2,3,4
            -- e=3,4 -> lat += UNIT_LAT_40000
            -- e=2,4 -> lon += UNIT_LON_40000
            IF e >= 3 THEN lat := lat + jismesh.get_unit_lat('X40'); END IF;
            IF e % 2 = 0 THEN lon := lon + jismesh.get_unit_lon('X40'); END IF;
            unit_lat := jismesh.get_unit_lat('X40');
            unit_lon := jismesh.get_unit_lon('X40');
        WHEN 'X20' THEN
            -- Base X40 adjustment
            IF e >= 3 THEN lat := lat + jismesh.get_unit_lat('X40'); END IF;
            IF e % 2 = 0 THEN lon := lon + jismesh.get_unit_lon('X40'); END IF;
            -- X20 adjustment (f=1,2,3,4)
            -- f=3,4 -> lat += UNIT_LAT_20000
            -- f=2,4 -> lon += UNIT_LON_20000
            IF f >= 3 THEN lat := lat + jismesh.get_unit_lat('X20'); END IF;
            IF f % 2 = 0 THEN lon := lon + jismesh.get_unit_lon('X20'); END IF;
            unit_lat := jismesh.get_unit_lat('X20');
            unit_lon := jismesh.get_unit_lon('X20');
        WHEN 'X16' THEN
             -- Rust uses e/2, f/2. Assuming e,f = 0-4? Check standard.
             -- Assuming integer division intended.
             lat := lat + floor(e / 2.0)::FLOAT * jismesh.get_unit_lat('X16');
             lon := lon + floor(f / 2.0)::FLOAT * jismesh.get_unit_lon('X16');
             unit_lat := jismesh.get_unit_lat('X16');
             unit_lon := jismesh.get_unit_lon('X16');
        WHEN 'X8' THEN
             -- Rust uses e, f directly. Assuming e,f = 0-9? Check standard.
             lat := lat + e * jismesh.get_unit_lat('X8');
             lon := lon + f * jismesh.get_unit_lon('X8');
             unit_lat := jismesh.get_unit_lat('X8');
             unit_lon := jismesh.get_unit_lon('X8');
        WHEN 'X4' THEN
             -- Base X8 adjustment
             lat := lat + e * jismesh.get_unit_lat('X8');
             lon := lon + f * jismesh.get_unit_lon('X8');
             -- X4 adjustment (h=1,2,3,4)
             -- h=3,4 -> lat += UNIT_LAT_4000
             -- h=2,4 -> lon += UNIT_LON_4000
             IF h >= 3 THEN lat := lat + jismesh.get_unit_lat('X4'); END IF;
             IF h % 2 = 0 THEN lon := lon + jismesh.get_unit_lon('X4'); END IF;
             unit_lat := jismesh.get_unit_lat('X4');
             unit_lon := jismesh.get_unit_lon('X4');
        WHEN 'Lv2' THEN
            lat := lat + e * jismesh.get_unit_lat('Lv2');
            lon := lon + f * jismesh.get_unit_lon('Lv2');
            unit_lat := jismesh.get_unit_lat('Lv2');
            unit_lon := jismesh.get_unit_lon('Lv2');
        WHEN 'X5' THEN
            -- Base Lv2 adjustment
            lat := lat + e * jismesh.get_unit_lat('Lv2');
            lon := lon + f * jismesh.get_unit_lon('Lv2');
            -- X5 adjustment (g=1,2,3,4)
            -- g=3,4 -> lat += UNIT_LAT_5000
            -- g=2,4 -> lon += UNIT_LON_5000
            IF g >= 3 THEN lat := lat + jismesh.get_unit_lat('X5'); END IF;
            IF g % 2 = 0 THEN lon := lon + jismesh.get_unit_lon('X5'); END IF;
            unit_lat := jismesh.get_unit_lat('X5');
            unit_lon := jismesh.get_unit_lon('X5');
        WHEN 'X2_5' THEN
            -- Base Lv2 adjustment
            lat := lat + e * jismesh.get_unit_lat('Lv2');
            lon := lon + f * jismesh.get_unit_lon('Lv2');
            -- Base X5 adjustment
            IF g >= 3 THEN lat := lat + jismesh.get_unit_lat('X5'); END IF;
            IF g % 2 = 0 THEN lon := lon + jismesh.get_unit_lon('X5'); END IF;
            -- X2.5 adjustment (h=1,2,3,4)
            -- h=3,4 -> lat += UNIT_LAT_2500
            -- h=2,4 -> lon += UNIT_LON_2500
            IF h >= 3 THEN lat := lat + jismesh.get_unit_lat('X2_5'); END IF;
            IF h % 2 = 0 THEN lon := lon + jismesh.get_unit_lon('X2_5'); END IF;
            unit_lat := jismesh.get_unit_lat('X2_5');
            unit_lon := jismesh.get_unit_lon('X2_5');
        WHEN 'X2' THEN
            -- Base Lv2 adjustment
            lat := lat + e * jismesh.get_unit_lat('Lv2');
            lon := lon + f * jismesh.get_unit_lon('Lv2');
            -- X2 adjustment (g, h = 0-4?) Check standard. Rust uses g/2, h/2.
            lat := lat + floor(g / 2.0)::FLOAT * jismesh.get_unit_lat('X2');
            lon := lon + floor(h / 2.0)::FLOAT * jismesh.get_unit_lon('X2');
            unit_lat := jismesh.get_unit_lat('X2');
            unit_lon := jismesh.get_unit_lon('X2');
        WHEN 'Lv3' THEN
            lat := lat + e * jismesh.get_unit_lat('Lv2'); -- Base Lv2
            lon := lon + f * jismesh.get_unit_lon('Lv2');
            lat := lat + g * jismesh.get_unit_lat('Lv3'); -- Lv3 part
            lon := lon + h * jismesh.get_unit_lon('Lv3');
            unit_lat := jismesh.get_unit_lat('Lv3');
            unit_lon := jismesh.get_unit_lon('Lv3');
        WHEN 'Lv4' THEN
            lat := lat + e * jismesh.get_unit_lat('Lv2'); lat := lat + g * jismesh.get_unit_lat('Lv3'); -- Base Lv3
            lon := lon + f * jismesh.get_unit_lon('Lv2'); lon := lon + h * jismesh.get_unit_lon('Lv3');
            -- Lv4 adjustment (i=1,2,3,4)
            -- i=3,4 -> lat += UNIT_LAT_LV4
            -- i=2,4 -> lon += UNIT_LON_LV4
            IF i >= 3 THEN lat := lat + jismesh.get_unit_lat('Lv4'); END IF;
            IF i % 2 = 0 THEN lon := lon + jismesh.get_unit_lon('Lv4'); END IF;
            unit_lat := jismesh.get_unit_lat('Lv4');
            unit_lon := jismesh.get_unit_lon('Lv4');
        WHEN 'Lv5' THEN
            lat := lat + e * jismesh.get_unit_lat('Lv2'); lat := lat + g * jismesh.get_unit_lat('Lv3'); -- Base Lv3
            lon := lon + f * jismesh.get_unit_lon('Lv2'); lon := lon + h * jismesh.get_unit_lon('Lv3');
            IF i >= 3 THEN lat := lat + jismesh.get_unit_lat('Lv4'); END IF; -- Base Lv4 part
            IF i % 2 = 0 THEN lon := lon + jismesh.get_unit_lon('Lv4'); END IF;
            -- Lv5 adjustment (j=1,2,3,4)
            -- j=3,4 -> lat += UNIT_LAT_LV5
            -- j=2,4 -> lon += UNIT_LON_LV5
            IF j >= 3 THEN lat := lat + jismesh.get_unit_lat('Lv5'); END IF;
            IF j % 2 = 0 THEN lon := lon + jismesh.get_unit_lon('Lv5'); END IF;
            unit_lat := jismesh.get_unit_lat('Lv5');
            unit_lon := jismesh.get_unit_lon('Lv5');
        WHEN 'Lv6' THEN
            lat := lat + e * jismesh.get_unit_lat('Lv2'); lat := lat + g * jismesh.get_unit_lat('Lv3'); -- Base Lv3
            lon := lon + f * jismesh.get_unit_lon('Lv2'); lon := lon + h * jismesh.get_unit_lon('Lv3');
            IF i >= 3 THEN lat := lat + jismesh.get_unit_lat('Lv4'); END IF; -- Base Lv4 part
            IF i % 2 = 0 THEN lon := lon + jismesh.get_unit_lon('Lv4'); END IF;
            IF j >= 3 THEN lat := lat + jismesh.get_unit_lat('Lv5'); END IF; -- Base Lv5 part
            IF j % 2 = 0 THEN lon := lon + jismesh.get_unit_lon('Lv5'); END IF;
            -- Lv6 adjustment (k=1,2,3,4)
            -- k=3,4 -> lat += UNIT_LAT_LV6
            -- k=2,4 -> lon += UNIT_LON_LV6
            IF k >= 3 THEN lat := lat + jismesh.get_unit_lat('Lv6'); END IF;
            IF k % 2 = 0 THEN lon := lon + jismesh.get_unit_lon('Lv6'); END IF;
            unit_lat := jismesh.get_unit_lat('Lv6');
            unit_lon := jismesh.get_unit_lon('Lv6');
        -- No ELSE needed as level is guaranteed to be valid by the initial check
    END CASE;

    -- Apply multipliers using the determined unit size for the level
    lat := lat + unit_lat * _lat_multiplier;
    lon := lon + unit_lon * _lon_multiplier;

    -- Return geometry (Longitude first for ST_MakePoint)
    RETURN ST_SetSRID(ST_MakePoint(lon, lat), 4326);

END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT; -- Keep STRICT: returns NULL if _meshcode is NULL

-- Function to create a polygon geometry for a given meshcode
CREATE OR REPLACE FUNCTION jismesh.to_meshpoly_geom(
    _meshcode BIGINT
)
RETURNS geometry(Polygon, 4326) AS $$
DECLARE
    sw_point geometry(Point, 4326);
    ne_point geometry(Point, 4326);
    sw_lon DOUBLE PRECISION;
    sw_lat DOUBLE PRECISION;
    ne_lon DOUBLE PRECISION;
    ne_lat DOUBLE PRECISION;
    polygon geometry(Polygon, 4326);
BEGIN
    -- Calculate the southwest and northeast corners of the mesh cell
    sw_point := jismesh.to_meshpoint_geom(_meshcode, 0.0, 0.0); -- Bottom-left corner
    ne_point := jismesh.to_meshpoint_geom(_meshcode, 1.0, 1.0); -- Top-right corner

    -- Return NULL if any corner calculation failed
    IF sw_point IS NULL OR ne_point IS NULL THEN
        RETURN NULL;
    END IF;

    -- Extract coordinates from the points
    sw_lon := ST_X(sw_point);
    sw_lat := ST_Y(sw_point);
    ne_lon := ST_X(ne_point);
    ne_lat := ST_Y(ne_point);

    -- Create a polygon from the min/max coordinates
    -- Create the polygon with 5 points (closing the ring)
    polygon := ST_SetSRID(ST_MakePolygon(ST_MakeLine(ARRAY[
        ST_Point(sw_lon, sw_lat), -- SW
        ST_Point(ne_lon, sw_lat), -- SE
        ST_Point(ne_lon, ne_lat), -- NE
        ST_Point(sw_lon, ne_lat), -- NW
        ST_Point(sw_lon, sw_lat)  -- SW again to close the polygon
    ])), 4326);

    RETURN polygon;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT; -- STRICT: returns NULL if _meshcode is NULL

CREATE OR REPLACE FUNCTION jismesh.fmod (
   dividend double precision,
   divisor double precision
) RETURNS double precision
    LANGUAGE sql IMMUTABLE AS
'SELECT dividend - floor(dividend / divisor) * divisor';

-- Function to calculate meshcode from a PostGIS Point and mesh level
CREATE OR REPLACE FUNCTION jismesh.to_meshcode(geom geometry(Point, 4326), level jismesh.mesh_level)
RETURNS bigint AS $$
DECLARE
    lat double precision;
    lon double precision;
    -- Intermediate calculation variables
    rem_lat_lv0 double precision; rem_lon_lv0 double precision;
    rem_lat_lv1 double precision; rem_lon_lv1 double precision;
    rem_lat_lv2 double precision; rem_lon_lv2 double precision;
    rem_lat_lv3 double precision; rem_lon_lv3 double precision;
    rem_lat_lv4 double precision; rem_lon_lv4 double precision;
    rem_lat_lv5 double precision; rem_lon_lv5 double precision;
    rem_lat_40000 double precision; rem_lon_40000 double precision;
    rem_lat_8000 double precision; rem_lon_8000 double precision;
    rem_lat_5000 double precision; rem_lon_5000 double precision;
    ab bigint; cd bigint; e bigint; f bigint; g bigint; h bigint; i bigint; j bigint; k bigint;
    base_lv1 bigint; base_lv2 bigint; base_lv3 bigint; base_lv4 bigint; base_lv5 bigint;
    base_40000 bigint; base_8000 bigint; base_5000 bigint;
BEGIN
    -- Extract coordinates
    lat := ST_Y(geom);
    lon := ST_X(geom);

    -- Validate inputs
    IF geom IS NULL OR level IS NULL OR NOT (lat >= 0.0 AND lat < 66.66 AND lon >= 100.0 AND lon < 180.0) THEN
        RETURN NULL;
    END IF;

    -- Calculate mesh code based on level
    CASE level
        WHEN 'Lv1' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0; -- lon is >= 100
            ab := floor(rem_lat_lv0 / jismesh.get_unit_lat('Lv1'));
            cd := floor(rem_lon_lv0 / jismesh.get_unit_lon('Lv1'));
            RETURN ab * 100 + cd;

        WHEN 'X40' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / jismesh.get_unit_lat('Lv1'));
            cd := floor(rem_lon_lv0 / jismesh.get_unit_lon('Lv1'));
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := jismesh.fmod(lat, jismesh.get_unit_lat('Lv1'));
            rem_lon_lv1 := jismesh.fmod(lon, jismesh.get_unit_lon('Lv1'));
            e := floor(rem_lat_lv1 / jismesh.get_unit_lat('X40')) * 2 + floor(rem_lon_lv1 / jismesh.get_unit_lon('X40')) + 1;
            RETURN base_lv1 * 10 + e;

        WHEN 'X20' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / jismesh.get_unit_lat('Lv1'));
            cd := floor(rem_lon_lv0 / jismesh.get_unit_lon('Lv1'));
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := jismesh.fmod(lat, jismesh.get_unit_lat('Lv1'));
            rem_lon_lv1 := jismesh.fmod(lon, jismesh.get_unit_lon('Lv1'));
            e := floor(rem_lat_lv1 / jismesh.get_unit_lat('X40')) * 2 + floor(rem_lon_lv1 / jismesh.get_unit_lon('X40')) + 1;
            base_40000 := base_lv1 * 10 + e;
            rem_lat_40000 := jismesh.fmod(rem_lat_lv1, jismesh.get_unit_lat('X40'));
            rem_lon_40000 := jismesh.fmod(rem_lon_lv1, jismesh.get_unit_lon('X40'));
            f := floor(rem_lat_40000 / jismesh.get_unit_lat('X20')) * 2 + floor(rem_lon_40000 / jismesh.get_unit_lon('X20')) + 1;
            g := 5;
            RETURN base_40000 * 100 + f * 10 + g;

        WHEN 'X16' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / jismesh.get_unit_lat('Lv1'));
            cd := floor(rem_lon_lv0 / jismesh.get_unit_lon('Lv1'));
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := jismesh.fmod(lat, jismesh.get_unit_lat('Lv1'));
            rem_lon_lv1 := jismesh.fmod(lon, jismesh.get_unit_lon('Lv1'));
            e := floor(rem_lat_lv1 / jismesh.get_unit_lat('X16')) * 2; -- Index 0..4 -> 0,2,4,6,8
            f := floor(rem_lon_lv1 / jismesh.get_unit_lon('X16')) * 2; -- Index 0..4 -> 0,2,4,6,8
            g := 7;
            RETURN base_lv1 * 1000 + e * 100 + f * 10 + g;

        WHEN 'Lv2' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / jismesh.get_unit_lat('Lv1'));
            cd := floor(rem_lon_lv0 / jismesh.get_unit_lon('Lv1'));
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := jismesh.fmod(lat, jismesh.get_unit_lat('Lv1'));
            rem_lon_lv1 := jismesh.fmod(lon, jismesh.get_unit_lon('Lv1'));
            e := floor(rem_lat_lv1 / jismesh.get_unit_lat('Lv2'));
            f := floor(rem_lon_lv1 / jismesh.get_unit_lon('Lv2'));
            RETURN base_lv1 * 100 + e * 10 + f;

        WHEN 'X8' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / jismesh.get_unit_lat('Lv1'));
            cd := floor(rem_lon_lv0 / jismesh.get_unit_lon('Lv1'));
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := jismesh.fmod(lat, jismesh.get_unit_lat('Lv1'));
            rem_lon_lv1 := jismesh.fmod(lon, jismesh.get_unit_lon('Lv1'));
            e := floor(rem_lat_lv1 / jismesh.get_unit_lat('X8')); -- Index 0..4
            f := floor(rem_lon_lv1 / jismesh.get_unit_lon('X8')); -- Index 0..4
            g := 6;
            RETURN base_lv1 * 1000 + e * 100 + f * 10 + g;

        WHEN 'X5' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / jismesh.get_unit_lat('Lv1'));
            cd := floor(rem_lon_lv0 / jismesh.get_unit_lon('Lv1'));
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := jismesh.fmod(lat, jismesh.get_unit_lat('Lv1'));
            rem_lon_lv1 := jismesh.fmod(lon, jismesh.get_unit_lon('Lv1'));
            e := floor(rem_lat_lv1 / jismesh.get_unit_lat('Lv2'));
            f := floor(rem_lon_lv1 / jismesh.get_unit_lon('Lv2'));
            base_lv2 := base_lv1 * 100 + e * 10 + f;
            rem_lat_lv2 := jismesh.fmod(rem_lat_lv1, jismesh.get_unit_lat('Lv2'));
            rem_lon_lv2 := jismesh.fmod(rem_lon_lv1, jismesh.get_unit_lon('Lv2'));
            g := floor(rem_lat_lv2 / jismesh.get_unit_lat('X5')) * 2 + floor(rem_lon_lv2 / jismesh.get_unit_lon('X5')) + 1;
            RETURN base_lv2 * 10 + g;

        WHEN 'X4' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / jismesh.get_unit_lat('Lv1'));
            cd := floor(rem_lon_lv0 / jismesh.get_unit_lon('Lv1'));
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := jismesh.fmod(lat, jismesh.get_unit_lat('Lv1'));
            rem_lon_lv1 := jismesh.fmod(lon, jismesh.get_unit_lon('Lv1'));
            e := floor(rem_lat_lv1 / jismesh.get_unit_lat('X8'));
            f := floor(rem_lon_lv1 / jismesh.get_unit_lon('X8'));
            g := 6;
            base_8000 := base_lv1 * 1000 + e * 100 + f * 10 + g;
            rem_lat_8000 := jismesh.fmod(rem_lat_lv1, jismesh.get_unit_lat('X8'));
            rem_lon_8000 := jismesh.fmod(rem_lon_lv1, jismesh.get_unit_lon('X8'));
            h := floor(rem_lat_8000 / jismesh.get_unit_lat('X4')) * 2 + floor(rem_lon_8000 / jismesh.get_unit_lon('X4')) + 1;
            i := 7;
            RETURN base_8000 * 100 + h * 10 + i;

        WHEN 'X2_5' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / jismesh.get_unit_lat('Lv1'));
            cd := floor(rem_lon_lv0 / jismesh.get_unit_lon('Lv1'));
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := jismesh.fmod(lat, jismesh.get_unit_lat('Lv1'));
            rem_lon_lv1 := jismesh.fmod(lon, jismesh.get_unit_lon('Lv1'));
            e := floor(rem_lat_lv1 / jismesh.get_unit_lat('Lv2'));
            f := floor(rem_lon_lv1 / jismesh.get_unit_lon('Lv2'));
            base_lv2 := base_lv1 * 100 + e * 10 + f;
            rem_lat_lv2 := jismesh.fmod(rem_lat_lv1, jismesh.get_unit_lat('Lv2'));
            rem_lon_lv2 := jismesh.fmod(rem_lon_lv1, jismesh.get_unit_lon('Lv2'));
            g := floor(rem_lat_lv2 / jismesh.get_unit_lat('X5')) * 2 + floor(rem_lon_lv2 / jismesh.get_unit_lon('X5')) + 1;
            base_5000 := base_lv2 * 10 + g;
            rem_lat_5000 := jismesh.fmod(rem_lat_lv2, jismesh.get_unit_lat('X5'));
            rem_lon_5000 := jismesh.fmod(rem_lon_lv2, jismesh.get_unit_lon('X5'));
            h := floor(rem_lat_5000 / jismesh.get_unit_lat('X2_5')) * 2 + floor(rem_lon_5000 / jismesh.get_unit_lon('X2_5')) + 1;
            i := 6;
            RETURN base_5000 * 100 + h * 10 + i;

        WHEN 'X2' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / jismesh.get_unit_lat('Lv1'));
            cd := floor(rem_lon_lv0 / jismesh.get_unit_lon('Lv1'));
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := jismesh.fmod(lat, jismesh.get_unit_lat('Lv1'));
            rem_lon_lv1 := jismesh.fmod(lon, jismesh.get_unit_lon('Lv1'));
            e := floor(rem_lat_lv1 / jismesh.get_unit_lat('Lv2'));
            f := floor(rem_lon_lv1 / jismesh.get_unit_lon('Lv2'));
            base_lv2 := base_lv1 * 100 + e * 10 + f;
            rem_lat_lv2 := jismesh.fmod(rem_lat_lv1, jismesh.get_unit_lat('Lv2'));
            rem_lon_lv2 := jismesh.fmod(rem_lon_lv1, jismesh.get_unit_lon('Lv2'));
            g := floor(rem_lat_lv2 / jismesh.get_unit_lat('X2')) * 2; -- Index 0..4 -> 0,2,4,6,8
            h := floor(rem_lon_lv2 / jismesh.get_unit_lon('X2')) * 2; -- Index 0..4 -> 0,2,4,6,8
            i := 5;
            RETURN base_lv2 * 1000 + g * 100 + h * 10 + i;

        WHEN 'Lv3' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / jismesh.get_unit_lat('Lv1'));
            cd := floor(rem_lon_lv0 / jismesh.get_unit_lon('Lv1'));
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := jismesh.fmod(lat, jismesh.get_unit_lat('Lv1'));
            rem_lon_lv1 := jismesh.fmod(lon, jismesh.get_unit_lon('Lv1'));
            e := floor(rem_lat_lv1 / jismesh.get_unit_lat('Lv2'));
            f := floor(rem_lon_lv1 / jismesh.get_unit_lon('Lv2'));
            base_lv2 := base_lv1 * 100 + e * 10 + f;
            rem_lat_lv2 := jismesh.fmod(rem_lat_lv1, jismesh.get_unit_lat('Lv2'));
            rem_lon_lv2 := jismesh.fmod(rem_lon_lv1, jismesh.get_unit_lon('Lv2'));
            g := floor(rem_lat_lv2 / jismesh.get_unit_lat('Lv3'));
            h := floor(rem_lon_lv2 / jismesh.get_unit_lon('Lv3'));
            RETURN base_lv2 * 100 + g * 10 + h;

        WHEN 'Lv4' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / jismesh.get_unit_lat('Lv1'));
            cd := floor(rem_lon_lv0 / jismesh.get_unit_lon('Lv1'));
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := jismesh.fmod(lat, jismesh.get_unit_lat('Lv1'));
            rem_lon_lv1 := jismesh.fmod(lon, jismesh.get_unit_lon('Lv1'));
            e := floor(rem_lat_lv1 / jismesh.get_unit_lat('Lv2'));
            f := floor(rem_lon_lv1 / jismesh.get_unit_lon('Lv2'));
            base_lv2 := base_lv1 * 100 + e * 10 + f;
            rem_lat_lv2 := jismesh.fmod(rem_lat_lv1, jismesh.get_unit_lat('Lv2'));
            rem_lon_lv2 := jismesh.fmod(rem_lon_lv1, jismesh.get_unit_lon('Lv2'));
            g := floor(rem_lat_lv2 / jismesh.get_unit_lat('Lv3'));
            h := floor(rem_lon_lv2 / jismesh.get_unit_lon('Lv3'));
            base_lv3 := base_lv2 * 100 + g * 10 + h;
            rem_lat_lv3 := jismesh.fmod(rem_lat_lv2, jismesh.get_unit_lat('Lv3'));
            rem_lon_lv3 := jismesh.fmod(rem_lon_lv2, jismesh.get_unit_lon('Lv3'));
            i := floor(rem_lat_lv3 / jismesh.get_unit_lat('Lv4')) * 2 + floor(rem_lon_lv3 / jismesh.get_unit_lon('Lv4')) + 1;
            RETURN base_lv3 * 10 + i;

        WHEN 'Lv5' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / jismesh.get_unit_lat('Lv1'));
            cd := floor(rem_lon_lv0 / jismesh.get_unit_lon('Lv1'));
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := jismesh.fmod(lat, jismesh.get_unit_lat('Lv1'));
            rem_lon_lv1 := jismesh.fmod(lon, jismesh.get_unit_lon('Lv1'));
            e := floor(rem_lat_lv1 / jismesh.get_unit_lat('Lv2'));
            f := floor(rem_lon_lv1 / jismesh.get_unit_lon('Lv2'));
            base_lv2 := base_lv1 * 100 + e * 10 + f;
            rem_lat_lv2 := jismesh.fmod(rem_lat_lv1, jismesh.get_unit_lat('Lv2'));
            rem_lon_lv2 := jismesh.fmod(rem_lon_lv1, jismesh.get_unit_lon('Lv2'));
            g := floor(rem_lat_lv2 / jismesh.get_unit_lat('Lv3'));
            h := floor(rem_lon_lv2 / jismesh.get_unit_lon('Lv3'));
            base_lv3 := base_lv2 * 100 + g * 10 + h;
            rem_lat_lv3 := jismesh.fmod(rem_lat_lv2, jismesh.get_unit_lat('Lv3'));
            rem_lon_lv3 := jismesh.fmod(rem_lon_lv2, jismesh.get_unit_lon('Lv3'));
            i := floor(rem_lat_lv3 / jismesh.get_unit_lat('Lv4')) * 2 + floor(rem_lon_lv3 / jismesh.get_unit_lon('Lv4')) + 1;
            base_lv4 := base_lv3 * 10 + i;
            rem_lat_lv4 := jismesh.fmod(rem_lat_lv3, jismesh.get_unit_lat('Lv4'));
            rem_lon_lv4 := jismesh.fmod(rem_lon_lv3, jismesh.get_unit_lon('Lv4'));
            j := floor(rem_lat_lv4 / jismesh.get_unit_lat('Lv5')) * 2 + floor(rem_lon_lv4 / jismesh.get_unit_lon('Lv5')) + 1;
            RETURN base_lv4 * 10 + j;

        WHEN 'Lv6' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / jismesh.get_unit_lat('Lv1'));
            cd := floor(rem_lon_lv0 / jismesh.get_unit_lon('Lv1'));
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := jismesh.fmod(lat, jismesh.get_unit_lat('Lv1'));
            rem_lon_lv1 := jismesh.fmod(lon, jismesh.get_unit_lon('Lv1'));
            e := floor(rem_lat_lv1 / jismesh.get_unit_lat('Lv2'));
            f := floor(rem_lon_lv1 / jismesh.get_unit_lon('Lv2'));
            base_lv2 := base_lv1 * 100 + e * 10 + f;
            rem_lat_lv2 := jismesh.fmod(rem_lat_lv1, jismesh.get_unit_lat('Lv2'));
            rem_lon_lv2 := jismesh.fmod(rem_lon_lv1, jismesh.get_unit_lon('Lv2'));
            g := floor(rem_lat_lv2 / jismesh.get_unit_lat('Lv3'));
            h := floor(rem_lon_lv2 / jismesh.get_unit_lon('Lv3'));
            base_lv3 := base_lv2 * 100 + g * 10 + h;
            rem_lat_lv3 := jismesh.fmod(rem_lat_lv2, jismesh.get_unit_lat('Lv3'));
            rem_lon_lv3 := jismesh.fmod(rem_lon_lv2, jismesh.get_unit_lon('Lv3'));
            i := floor(rem_lat_lv3 / jismesh.get_unit_lat('Lv4')) * 2 + floor(rem_lon_lv3 / jismesh.get_unit_lon('Lv4')) + 1;
            base_lv4 := base_lv3 * 10 + i;
            rem_lat_lv4 := jismesh.fmod(rem_lat_lv3, jismesh.get_unit_lat('Lv4'));
            rem_lon_lv4 := jismesh.fmod(rem_lon_lv3, jismesh.get_unit_lon('Lv4'));
            j := floor(rem_lat_lv4 / jismesh.get_unit_lat('Lv5')) * 2 + floor(rem_lon_lv4 / jismesh.get_unit_lon('Lv5')) + 1;
            base_lv5 := base_lv4 * 10 + j;
            rem_lat_lv5 := jismesh.fmod(rem_lat_lv4, jismesh.get_unit_lat('Lv5'));
            rem_lon_lv5 := jismesh.fmod(rem_lon_lv4, jismesh.get_unit_lon('Lv5'));
            k := floor(rem_lat_lv5 / jismesh.get_unit_lat('Lv6')) * 2 + floor(rem_lon_lv5 / jismesh.get_unit_lon('Lv6')) + 1;
            RETURN base_lv5 * 10 + k;

        ELSE
            -- Should not happen if jismesh.mesh_level enum is used correctly
            RETURN NULL;
    END CASE;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT; -- Function result depends only on inputs

-- Function to calculate all meshcodes that intersect a given box2d at specified mesh level
CREATE OR REPLACE FUNCTION jismesh.to_meshcodes(bbox box2d, level jismesh.mesh_level)
RETURNS TABLE(meshcode bigint, geom geometry(Polygon, 4326)) AS $$
DECLARE
    min_lon double precision;
    min_lat double precision;
    max_lon double precision;
    max_lat double precision;
    x double precision;
    y double precision;
    -- Unit constants (derived from JIS X 0410)
    unit_lat double precision;
    unit_lon double precision;
    -- Initial grid cell
    start_lon double precision;
    start_lat double precision;
    -- Loop counters
    i integer;
    j integer;
    -- Lv1 meshcode
    base_lv1 bigint;
BEGIN
    -- Extract box coordinates
    min_lon := ST_XMin(bbox);
    min_lat := ST_YMin(bbox);
    max_lon := ST_XMax(bbox);
    max_lat := ST_YMax(bbox);

    -- Clamp coordinate values to valid range instead of raising an exception
    min_lon := GREATEST(min_lon, 100.0);
    min_lat := GREATEST(min_lat, 0.0);
    max_lon := LEAST(max_lon, 180.0);
    max_lat := LEAST(max_lat, 66.66);

    -- Determine the unit size for the specified mesh level
    unit_lat := jismesh.get_unit_lat(level);
    unit_lon := jismesh.get_unit_lon(level);

    -- Find the starting point (round down to nearest grid cell)
    -- Adding a small buffer to ensure we don't miss cells due to floating point precision
    start_lon := floor(min_lon / unit_lon) * unit_lon;
    start_lat := floor(min_lat / unit_lat) * unit_lat;

    -- Loop through all cells that intersect the bbox
    y := start_lat;
    WHILE y < max_lat LOOP
        x := start_lon;
        WHILE x < max_lon LOOP
            -- Create point at bottom-left corner of each cell and get its meshcode
            -- The returned meshcode will represent the entire cell
            meshcode := jismesh.to_meshcode(ST_SetSRID(ST_MakePoint(x + unit_lon/2, y + unit_lat/2), 4326), level);
            base_lv1 := left(meshcode::text, 4)::bigint; -- Get the base Lv1 meshcode
            -- Ignore any meshcodes that are not in japan_lv1_meshes
            IF NOT EXISTS (SELECT 1 FROM jismesh.japan_lv1_meshes j WHERE j.meshcode = base_lv1) THEN
                RAISE DEBUG 'Skipping meshcode %: not in japan_lv1_meshes', base_lv1;
                x := x + unit_lon;
                CONTINUE;
            END IF;

            geom := jismesh.to_meshpoly_geom(meshcode);

            -- Only return valid meshcodes (to_meshcode returns NULL for invalid inputs)
            IF meshcode IS NOT NULL THEN
                RETURN NEXT;
            END IF;

            x := x + unit_lon;
        END LOOP;
        y := y + unit_lat;
    END LOOP;

    RETURN;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

-- Drop the old table first if it exist
DROP TABLE IF EXISTS jismesh.mesh_level_units;

-- 1. Create the lookup table
CREATE TABLE jismesh.mesh_level_units (
    level jismesh.mesh_level PRIMARY KEY,
    unit_lat double precision NOT NULL,
    unit_lon double precision NOT NULL
);

-- 2. Populate the table with pre-calculated values
-- You can calculate these once (e.g., using psql or another script)
DO $$
DECLARE
    UNIT_LAT_LV1 CONSTANT double precision := 2.0 / 3.0;
    UNIT_LON_LV1 CONSTANT double precision := 1.0;
BEGIN
    INSERT INTO jismesh.mesh_level_units (level, unit_lat, unit_lon) VALUES
        ('Lv1',  UNIT_LAT_LV1 / 1.0,   UNIT_LON_LV1 / 1.0),
        ('X40',  UNIT_LAT_LV1 / 2.0,   UNIT_LON_LV1 / 2.0),
        ('X20',  UNIT_LAT_LV1 / 4.0,   UNIT_LON_LV1 / 4.0),
        ('X16',  UNIT_LAT_LV1 / 5.0,   UNIT_LON_LV1 / 5.0),
        ('Lv2',  UNIT_LAT_LV1 / 8.0,   UNIT_LON_LV1 / 8.0),
        ('X8',   UNIT_LAT_LV1 / 10.0,  UNIT_LON_LV1 / 10.0),
        ('X5',   UNIT_LAT_LV1 / 16.0,  UNIT_LON_LV1 / 16.0),
        ('X4',   UNIT_LAT_LV1 / 20.0,  UNIT_LON_LV1 / 20.0),
        ('X2_5', UNIT_LAT_LV1 / 32.0,  UNIT_LON_LV1 / 32.0),
        ('X2',   UNIT_LAT_LV1 / 40.0,  UNIT_LON_LV1 / 40.0),
        ('Lv3',  UNIT_LAT_LV1 / 80.0,  UNIT_LON_LV1 / 80.0),
        ('Lv4',  UNIT_LAT_LV1 / 160.0, UNIT_LON_LV1 / 160.0),
        ('Lv5',  UNIT_LAT_LV1 / 320.0, UNIT_LON_LV1 / 320.0),
        ('Lv6',  UNIT_LAT_LV1 / 640.0, UNIT_LON_LV1 / 640.0);
END $$;

-- 3. Create functions that query the lookup table

CREATE OR REPLACE FUNCTION jismesh.get_unit_lat(p_level jismesh.mesh_level)
RETURNS double precision AS $$
    SELECT m.unit_lat
    FROM jismesh.mesh_level_units m
    WHERE m.level = p_level
    LIMIT 1; -- Good practice, though PRIMARY KEY ensures max 1 row
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION jismesh.get_unit_lon(p_level jismesh.mesh_level)
RETURNS double precision AS $$
    SELECT m.unit_lon
    FROM jismesh.mesh_level_units m
    WHERE m.level = p_level
    LIMIT 1; -- Good practice
$$ LANGUAGE SQL IMMUTABLE STRICT;
