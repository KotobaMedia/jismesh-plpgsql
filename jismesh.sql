-- Drop type and function if they exist (for easy re-running)
DROP FUNCTION IF EXISTS to_meshlevel(bigint);
DROP TYPE IF EXISTS mesh_level;

-- Define the mesh_level enum type
CREATE TYPE mesh_level AS ENUM (
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

-- Create the PL/pgSQL function to determine mesh level for a single code
CREATE OR REPLACE FUNCTION to_meshlevel(code bigint)
RETURNS mesh_level AS $$
DECLARE
    level mesh_level;
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


CREATE OR REPLACE FUNCTION to_meshpoint_geom(
    _meshcode BIGINT,
    _lat_multiplier DOUBLE PRECISION DEFAULT 0.0,
    _lon_multiplier DOUBLE PRECISION DEFAULT 0.0
)
RETURNS geometry(Point, 4326) AS $$
DECLARE
    -- Constants based on Rust code structure
    UNIT_LAT_LV1 DOUBLE PRECISION := 2.0 / 3.0;
    UNIT_LON_LV1 DOUBLE PRECISION := 1.0;
    UNIT_LAT_LV2 DOUBLE PRECISION := UNIT_LAT_LV1 / 8.0;
    UNIT_LON_LV2 DOUBLE PRECISION := UNIT_LON_LV1 / 8.0;
    UNIT_LAT_LV3 DOUBLE PRECISION := UNIT_LAT_LV2 / 10.0;
    UNIT_LON_LV3 DOUBLE PRECISION := UNIT_LON_LV2 / 10.0;
    UNIT_LAT_LV4 DOUBLE PRECISION := UNIT_LAT_LV3 / 2.0;
    UNIT_LON_LV4 DOUBLE PRECISION := UNIT_LON_LV3 / 2.0;
    UNIT_LAT_LV5 DOUBLE PRECISION := UNIT_LAT_LV4 / 2.0;
    UNIT_LON_LV5 DOUBLE PRECISION := UNIT_LON_LV4 / 2.0;
    UNIT_LAT_LV6 DOUBLE PRECISION := UNIT_LAT_LV5 / 2.0;
    UNIT_LON_LV6 DOUBLE PRECISION := UNIT_LON_LV5 / 2.0;
    UNIT_LAT_40000 DOUBLE PRECISION := UNIT_LAT_LV1 / 2.0;
    UNIT_LON_40000 DOUBLE PRECISION := UNIT_LON_LV1 / 2.0;
    UNIT_LAT_20000 DOUBLE PRECISION := UNIT_LAT_40000 / 2.0;
    UNIT_LON_20000 DOUBLE PRECISION := UNIT_LON_40000 / 2.0;
    UNIT_LAT_16000 DOUBLE PRECISION := UNIT_LAT_LV1 / 5.0;
    UNIT_LON_16000 DOUBLE PRECISION := UNIT_LON_LV1 / 5.0;
    UNIT_LAT_8000 DOUBLE PRECISION := UNIT_LAT_LV1 / 10.0;
    UNIT_LON_8000 DOUBLE PRECISION := UNIT_LON_LV1 / 10.0;
    UNIT_LAT_4000 DOUBLE PRECISION := UNIT_LAT_8000 / 2.0;
    UNIT_LON_4000 DOUBLE PRECISION := UNIT_LON_8000 / 2.0;
    UNIT_LAT_5000 DOUBLE PRECISION := UNIT_LAT_LV2 / 2.0;
    UNIT_LON_5000 DOUBLE PRECISION := UNIT_LON_LV2 / 2.0;
    UNIT_LAT_2500 DOUBLE PRECISION := UNIT_LAT_5000 / 2.0;
    UNIT_LON_2500 DOUBLE PRECISION := UNIT_LON_5000 / 2.0;
    UNIT_LAT_2000 DOUBLE PRECISION := UNIT_LAT_LV2 / 5.0;
    UNIT_LON_2000 DOUBLE PRECISION := UNIT_LON_LV2 / 5.0;

    -- Variables
    lat DOUBLE PRECISION;
    lon DOUBLE PRECISION;
    level mesh_level; -- Changed type from TEXT
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
    level := to_meshlevel(_meshcode);

    -- Return NULL if the mesh level could not be determined (invalid meshcode)
    IF level IS NULL THEN
        RETURN NULL;
    END IF;

    -- Extract digits (only extract necessary digits based on level/length if needed for optimization,
    -- but extracting all up to 11 is simpler for now)
    -- Ensure length check is implicitly handled by to_meshlevel returning NULL
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
    lat := ab * UNIT_LAT_LV1;
    lon := cd * UNIT_LON_LV1 + 100.0;

    -- Level-specific adjustments and unit determination
    -- Uses the level determined by the to_meshlevel function
    CASE level
        WHEN 'Lv1' THEN
            unit_lat := UNIT_LAT_LV1;
            unit_lon := UNIT_LON_LV1;
        WHEN 'X40' THEN
            -- Check standard: Rust uses e/3 == 1, e%2 == 0. Assuming e=1,2,3,4
            -- e=3,4 -> lat += UNIT_LAT_40000
            -- e=2,4 -> lon += UNIT_LON_40000
            IF e >= 3 THEN lat := lat + UNIT_LAT_40000; END IF;
            IF e % 2 = 0 THEN lon := lon + UNIT_LON_40000; END IF;
            unit_lat := UNIT_LAT_40000;
            unit_lon := UNIT_LON_40000;
        WHEN 'X20' THEN
            -- Base X40 adjustment
            IF e >= 3 THEN lat := lat + UNIT_LAT_40000; END IF;
            IF e % 2 = 0 THEN lon := lon + UNIT_LON_40000; END IF;
            -- X20 adjustment (f=1,2,3,4)
            -- f=3,4 -> lat += UNIT_LAT_20000
            -- f=2,4 -> lon += UNIT_LON_20000
            IF f >= 3 THEN lat := lat + UNIT_LAT_20000; END IF;
            IF f % 2 = 0 THEN lon := lon + UNIT_LON_20000; END IF;
            unit_lat := UNIT_LAT_20000;
            unit_lon := UNIT_LON_20000;
        WHEN 'X16' THEN
             -- Rust uses e/2, f/2. Assuming e,f = 0-4? Check standard.
             -- Assuming integer division intended.
             lat := lat + floor(e / 2.0)::FLOAT * UNIT_LAT_16000;
             lon := lon + floor(f / 2.0)::FLOAT * UNIT_LON_16000;
             unit_lat := UNIT_LAT_16000;
             unit_lon := UNIT_LON_16000;
        WHEN 'X8' THEN
             -- Rust uses e, f directly. Assuming e,f = 0-9? Check standard.
             lat := lat + e * UNIT_LAT_8000;
             lon := lon + f * UNIT_LON_8000;
             unit_lat := UNIT_LAT_8000;
             unit_lon := UNIT_LON_8000;
        WHEN 'X4' THEN
             -- Base X8 adjustment
             lat := lat + e * UNIT_LAT_8000;
             lon := lon + f * UNIT_LON_8000;
             -- X4 adjustment (h=1,2,3,4)
             -- h=3,4 -> lat += UNIT_LAT_4000
             -- h=2,4 -> lon += UNIT_LON_4000
             IF h >= 3 THEN lat := lat + UNIT_LAT_4000; END IF;
             IF h % 2 = 0 THEN lon := lon + UNIT_LON_4000; END IF;
             unit_lat := UNIT_LAT_4000;
             unit_lon := UNIT_LON_4000;
        WHEN 'Lv2' THEN
            lat := lat + e * UNIT_LAT_LV2;
            lon := lon + f * UNIT_LON_LV2;
            unit_lat := UNIT_LAT_LV2;
            unit_lon := UNIT_LON_LV2;
        WHEN 'X5' THEN
            -- Base Lv2 adjustment
            lat := lat + e * UNIT_LAT_LV2;
            lon := lon + f * UNIT_LON_LV2;
            -- X5 adjustment (g=1,2,3,4)
            -- g=3,4 -> lat += UNIT_LAT_5000
            -- g=2,4 -> lon += UNIT_LON_5000
            IF g >= 3 THEN lat := lat + UNIT_LAT_5000; END IF;
            IF g % 2 = 0 THEN lon := lon + UNIT_LON_5000; END IF;
            unit_lat := UNIT_LAT_5000;
            unit_lon := UNIT_LON_5000;
        WHEN 'X2_5' THEN
            -- Base Lv2 adjustment
            lat := lat + e * UNIT_LAT_LV2;
            lon := lon + f * UNIT_LON_LV2;
            -- Base X5 adjustment
            IF g >= 3 THEN lat := lat + UNIT_LAT_5000; END IF;
            IF g % 2 = 0 THEN lon := lon + UNIT_LON_5000; END IF;
            -- X2.5 adjustment (h=1,2,3,4)
            -- h=3,4 -> lat += UNIT_LAT_2500
            -- h=2,4 -> lon += UNIT_LON_2500
            IF h >= 3 THEN lat := lat + UNIT_LAT_2500; END IF;
            IF h % 2 = 0 THEN lon := lon + UNIT_LON_2500; END IF;
            unit_lat := UNIT_LAT_2500;
            unit_lon := UNIT_LON_2500;
        WHEN 'X2' THEN
            -- Base Lv2 adjustment
            lat := lat + e * UNIT_LAT_LV2;
            lon := lon + f * UNIT_LON_LV2;
            -- X2 adjustment (g, h = 0-4?) Check standard. Rust uses g/2, h/2.
            lat := lat + floor(g / 2.0)::FLOAT * UNIT_LAT_2000;
            lon := lon + floor(h / 2.0)::FLOAT * UNIT_LON_2000;
            unit_lat := UNIT_LAT_2000;
            unit_lon := UNIT_LON_2000;
        WHEN 'Lv3' THEN
            lat := lat + e * UNIT_LAT_LV2; -- Base Lv2
            lon := lon + f * UNIT_LON_LV2;
            lat := lat + g * UNIT_LAT_LV3; -- Lv3 part
            lon := lon + h * UNIT_LON_LV3;
            unit_lat := UNIT_LAT_LV3;
            unit_lon := UNIT_LON_LV3;
        WHEN 'Lv4' THEN
            lat := lat + e * UNIT_LAT_LV2; lat := lat + g * UNIT_LAT_LV3; -- Base Lv3
            lon := lon + f * UNIT_LON_LV2; lon := lon + h * UNIT_LON_LV3;
            -- Lv4 adjustment (i=1,2,3,4)
            -- i=3,4 -> lat += UNIT_LAT_LV4
            -- i=2,4 -> lon += UNIT_LON_LV4
            IF i >= 3 THEN lat := lat + UNIT_LAT_LV4; END IF;
            IF i % 2 = 0 THEN lon := lon + UNIT_LON_LV4; END IF;
            unit_lat := UNIT_LAT_LV4;
            unit_lon := UNIT_LON_LV4;
        WHEN 'Lv5' THEN
            lat := lat + e * UNIT_LAT_LV2; lat := lat + g * UNIT_LAT_LV3; -- Base Lv3
            lon := lon + f * UNIT_LON_LV2; lon := lon + h * UNIT_LON_LV3;
            IF i >= 3 THEN lat := lat + UNIT_LAT_LV4; END IF; -- Base Lv4 part
            IF i % 2 = 0 THEN lon := lon + UNIT_LON_LV4; END IF;
            -- Lv5 adjustment (j=1,2,3,4)
            -- j=3,4 -> lat += UNIT_LAT_LV5
            -- j=2,4 -> lon += UNIT_LON_LV5
            IF j >= 3 THEN lat := lat + UNIT_LAT_LV5; END IF;
            IF j % 2 = 0 THEN lon := lon + UNIT_LON_LV5; END IF;
            unit_lat := UNIT_LAT_LV5;
            unit_lon := UNIT_LON_LV5;
        WHEN 'Lv6' THEN
            lat := lat + e * UNIT_LAT_LV2; lat := lat + g * UNIT_LAT_LV3; -- Base Lv3
            lon := lon + f * UNIT_LON_LV2; lon := lon + h * UNIT_LON_LV3;
            IF i >= 3 THEN lat := lat + UNIT_LAT_LV4; END IF; -- Base Lv4 part
            IF i % 2 = 0 THEN lon := lon + UNIT_LON_LV4; END IF;
            IF j >= 3 THEN lat := lat + UNIT_LAT_LV5; END IF; -- Base Lv5 part
            IF j % 2 = 0 THEN lon := lon + UNIT_LON_LV5; END IF;
            -- Lv6 adjustment (k=1,2,3,4)
            -- k=3,4 -> lat += UNIT_LAT_LV6
            -- k=2,4 -> lon += UNIT_LON_LV6
            IF k >= 3 THEN lat := lat + UNIT_LAT_LV6; END IF;
            IF k % 2 = 0 THEN lon := lon + UNIT_LON_LV6; END IF;
            unit_lat := UNIT_LAT_LV6;
            unit_lon := UNIT_LON_LV6;
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
CREATE OR REPLACE FUNCTION to_meshpoly_geom(
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
    sw_point := to_meshpoint_geom(_meshcode, 0.0, 0.0); -- Bottom-left corner
    ne_point := to_meshpoint_geom(_meshcode, 1.0, 1.0); -- Top-right corner

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

DROP FUNCTION IF EXISTS to_meshcode(geometry(Point, 4326), mesh_level);
DROP FUNCTION IF EXISTS to_meshcodes(box2d, mesh_level);

DROP FUNCTION IF EXISTS fmod;
CREATE FUNCTION fmod (
   dividend double precision,
   divisor double precision
) RETURNS double precision
    LANGUAGE sql IMMUTABLE AS
'SELECT dividend - floor(dividend / divisor) * divisor';

-- Function to calculate meshcode from a PostGIS Point and mesh level
CREATE OR REPLACE FUNCTION to_meshcode(geom geometry(Point, 4326), level mesh_level)
RETURNS bigint AS $$
DECLARE
    lat double precision;
    lon double precision;
    -- Unit constants (derived from JIS X 0410)
    UNIT_LAT_LV1 double precision := 2.0 / 3.0;
    UNIT_LON_LV1 double precision := 1.0;
    UNIT_LAT_LV2 double precision := UNIT_LAT_LV1 / 8.0; -- 1.0 / 12.0
    UNIT_LON_LV2 double precision := UNIT_LON_LV1 / 8.0; -- 1.0 / 8.0
    UNIT_LAT_LV3 double precision := UNIT_LAT_LV2 / 10.0; -- 1.0 / 120.0
    UNIT_LON_LV3 double precision := UNIT_LON_LV2 / 10.0; -- 1.0 / 80.0
    UNIT_LAT_LV4 double precision := UNIT_LAT_LV3 / 2.0; -- 1.0 / 240.0
    UNIT_LON_LV4 double precision := UNIT_LON_LV3 / 2.0; -- 1.0 / 160.0
    UNIT_LAT_LV5 double precision := UNIT_LAT_LV4 / 2.0; -- 1.0 / 480.0
    UNIT_LON_LV5 double precision := UNIT_LON_LV4 / 2.0; -- 1.0 / 320.0
    UNIT_LAT_LV6 double precision := UNIT_LAT_LV5 / 2.0; -- 1.0 / 960.0
    UNIT_LON_LV6 double precision := UNIT_LON_LV5 / 2.0; -- 1.0 / 640.0
    UNIT_LAT_40000 double precision := UNIT_LAT_LV1 / 2.0; -- 1.0 / 3.0
    UNIT_LON_40000 double precision := UNIT_LON_LV1 / 2.0; -- 1.0 / 2.0
    UNIT_LAT_20000 double precision := UNIT_LAT_40000 / 2.0; -- 1.0 / 6.0
    UNIT_LON_20000 double precision := UNIT_LON_40000 / 2.0; -- 1.0 / 4.0
    UNIT_LAT_16000 double precision := UNIT_LAT_LV1 / 5.0; -- 2.0 / 15.0 (5 divisions in Lv1)
    UNIT_LON_16000 double precision := UNIT_LON_LV1 / 5.0; -- 1.0 / 5.0 (5 divisions in Lv1)
    UNIT_LAT_8000 double precision := UNIT_LAT_LV1 / 10.0; -- 2.0 / 30.0
    UNIT_LON_8000 double precision := UNIT_LON_LV1 / 10.0; -- 1.0 / 10.0
    UNIT_LAT_5000 double precision := UNIT_LAT_LV2 / 2.0; -- 1.0 / 24.0
    UNIT_LON_5000 double precision := UNIT_LON_LV2 / 2.0; -- 1.0 / 16.0
    UNIT_LAT_4000 double precision := UNIT_LAT_8000 / 2.0; -- 1.0 / 30.0
    UNIT_LON_4000 double precision := UNIT_LON_8000 / 2.0; -- 1.0 / 20.0
    UNIT_LAT_2500 double precision := UNIT_LAT_5000 / 2.0; -- 1.0 / 48.0
    UNIT_LON_2500 double precision := UNIT_LON_5000 / 2.0; -- 1.0 / 32.0
    UNIT_LAT_2000 double precision := UNIT_LAT_LV2 / 5.0; -- 1.0 / 60.0 (5 divisions in Lv2)
    UNIT_LON_2000 double precision := UNIT_LON_LV2 / 5.0; -- 1.0 / 40.0 (5 divisions in Lv2)
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
            ab := floor(rem_lat_lv0 / UNIT_LAT_LV1);
            cd := floor(rem_lon_lv0 / UNIT_LON_LV1);
            RETURN ab * 100 + cd;

        WHEN 'X40' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / UNIT_LAT_LV1);
            cd := floor(rem_lon_lv0 / UNIT_LON_LV1);
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := fmod(lat, UNIT_LAT_LV1);
            rem_lon_lv1 := fmod(lon, UNIT_LON_LV1);
            e := floor(rem_lat_lv1 / UNIT_LAT_40000) * 2 + floor(rem_lon_lv1 / UNIT_LON_40000) + 1;
            RETURN base_lv1 * 10 + e;

        WHEN 'X20' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / UNIT_LAT_LV1);
            cd := floor(rem_lon_lv0 / UNIT_LON_LV1);
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := fmod(lat, UNIT_LAT_LV1);
            rem_lon_lv1 := fmod(lon, UNIT_LON_LV1);
            e := floor(rem_lat_lv1 / UNIT_LAT_40000) * 2 + floor(rem_lon_lv1 / UNIT_LON_40000) + 1;
            base_40000 := base_lv1 * 10 + e;
            rem_lat_40000 := fmod(rem_lat_lv1, UNIT_LAT_40000);
            rem_lon_40000 := fmod(rem_lon_lv1, UNIT_LON_40000);
            f := floor(rem_lat_40000 / UNIT_LAT_20000) * 2 + floor(rem_lon_40000 / UNIT_LON_20000) + 1;
            g := 5;
            RETURN base_40000 * 100 + f * 10 + g;

        WHEN 'X16' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / UNIT_LAT_LV1);
            cd := floor(rem_lon_lv0 / UNIT_LON_LV1);
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := fmod(lat, UNIT_LAT_LV1);
            rem_lon_lv1 := fmod(lon, UNIT_LON_LV1);
            e := floor(rem_lat_lv1 / UNIT_LAT_16000) * 2; -- Index 0..4 -> 0,2,4,6,8
            f := floor(rem_lon_lv1 / UNIT_LON_16000) * 2; -- Index 0..4 -> 0,2,4,6,8
            g := 7;
            RETURN base_lv1 * 1000 + e * 100 + f * 10 + g;

        WHEN 'Lv2' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / UNIT_LAT_LV1);
            cd := floor(rem_lon_lv0 / UNIT_LON_LV1);
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := fmod(lat, UNIT_LAT_LV1);
            rem_lon_lv1 := fmod(lon, UNIT_LON_LV1);
            e := floor(rem_lat_lv1 / UNIT_LAT_LV2);
            f := floor(rem_lon_lv1 / UNIT_LON_LV2);
            RETURN base_lv1 * 100 + e * 10 + f;

        WHEN 'X8' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / UNIT_LAT_LV1);
            cd := floor(rem_lon_lv0 / UNIT_LON_LV1);
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := fmod(lat, UNIT_LAT_LV1);
            rem_lon_lv1 := fmod(lon, UNIT_LON_LV1);
            e := floor(rem_lat_lv1 / UNIT_LAT_8000); -- Index 0..4
            f := floor(rem_lon_lv1 / UNIT_LON_8000); -- Index 0..4
            g := 6;
            RETURN base_lv1 * 1000 + e * 100 + f * 10 + g;

        WHEN 'X5' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / UNIT_LAT_LV1);
            cd := floor(rem_lon_lv0 / UNIT_LON_LV1);
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := fmod(lat, UNIT_LAT_LV1);
            rem_lon_lv1 := fmod(lon, UNIT_LON_LV1);
            e := floor(rem_lat_lv1 / UNIT_LAT_LV2);
            f := floor(rem_lon_lv1 / UNIT_LON_LV2);
            base_lv2 := base_lv1 * 100 + e * 10 + f;
            rem_lat_lv2 := fmod(rem_lat_lv1, UNIT_LAT_LV2);
            rem_lon_lv2 := fmod(rem_lon_lv1, UNIT_LON_LV2);
            g := floor(rem_lat_lv2 / UNIT_LAT_5000) * 2 + floor(rem_lon_lv2 / UNIT_LON_5000) + 1;
            RETURN base_lv2 * 10 + g;

        WHEN 'X4' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / UNIT_LAT_LV1);
            cd := floor(rem_lon_lv0 / UNIT_LON_LV1);
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := fmod(lat, UNIT_LAT_LV1);
            rem_lon_lv1 := fmod(lon, UNIT_LON_LV1);
            e := floor(rem_lat_lv1 / UNIT_LAT_8000);
            f := floor(rem_lon_lv1 / UNIT_LON_8000);
            g := 6;
            base_8000 := base_lv1 * 1000 + e * 100 + f * 10 + g;
            rem_lat_8000 := fmod(rem_lat_lv1, UNIT_LAT_8000);
            rem_lon_8000 := fmod(rem_lon_lv1, UNIT_LON_8000);
            h := floor(rem_lat_8000 / UNIT_LAT_4000) * 2 + floor(rem_lon_8000 / UNIT_LON_4000) + 1;
            i := 7;
            RETURN base_8000 * 100 + h * 10 + i;

        WHEN 'X2_5' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / UNIT_LAT_LV1);
            cd := floor(rem_lon_lv0 / UNIT_LON_LV1);
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := fmod(lat, UNIT_LAT_LV1);
            rem_lon_lv1 := fmod(lon, UNIT_LON_LV1);
            e := floor(rem_lat_lv1 / UNIT_LAT_LV2);
            f := floor(rem_lon_lv1 / UNIT_LON_LV2);
            base_lv2 := base_lv1 * 100 + e * 10 + f;
            rem_lat_lv2 := fmod(rem_lat_lv1, UNIT_LAT_LV2);
            rem_lon_lv2 := fmod(rem_lon_lv1, UNIT_LON_LV2);
            g := floor(rem_lat_lv2 / UNIT_LAT_5000) * 2 + floor(rem_lon_lv2 / UNIT_LON_5000) + 1;
            base_5000 := base_lv2 * 10 + g;
            rem_lat_5000 := fmod(rem_lat_lv2, UNIT_LAT_5000);
            rem_lon_5000 := fmod(rem_lon_lv2, UNIT_LON_5000);
            h := floor(rem_lat_5000 / UNIT_LAT_2500) * 2 + floor(rem_lon_5000 / UNIT_LON_2500) + 1;
            i := 6;
            RETURN base_5000 * 100 + h * 10 + i;

        WHEN 'X2' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / UNIT_LAT_LV1);
            cd := floor(rem_lon_lv0 / UNIT_LON_LV1);
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := fmod(lat, UNIT_LAT_LV1);
            rem_lon_lv1 := fmod(lon, UNIT_LON_LV1);
            e := floor(rem_lat_lv1 / UNIT_LAT_LV2);
            f := floor(rem_lon_lv1 / UNIT_LON_LV2);
            base_lv2 := base_lv1 * 100 + e * 10 + f;
            rem_lat_lv2 := fmod(rem_lat_lv1, UNIT_LAT_LV2);
            rem_lon_lv2 := fmod(rem_lon_lv1, UNIT_LON_LV2);
            g := floor(rem_lat_lv2 / UNIT_LAT_2000) * 2; -- Index 0..4 -> 0,2,4,6,8
            h := floor(rem_lon_lv2 / UNIT_LON_2000) * 2; -- Index 0..4 -> 0,2,4,6,8
            i := 5;
            RETURN base_lv2 * 1000 + g * 100 + h * 10 + i;

        WHEN 'Lv3' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / UNIT_LAT_LV1);
            cd := floor(rem_lon_lv0 / UNIT_LON_LV1);
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := fmod(lat, UNIT_LAT_LV1);
            rem_lon_lv1 := fmod(lon, UNIT_LON_LV1);
            e := floor(rem_lat_lv1 / UNIT_LAT_LV2);
            f := floor(rem_lon_lv1 / UNIT_LON_LV2);
            base_lv2 := base_lv1 * 100 + e * 10 + f;
            rem_lat_lv2 := fmod(rem_lat_lv1, UNIT_LAT_LV2);
            rem_lon_lv2 := fmod(rem_lon_lv1, UNIT_LON_LV2);
            g := floor(rem_lat_lv2 / UNIT_LAT_LV3);
            h := floor(rem_lon_lv2 / UNIT_LON_LV3);
            RETURN base_lv2 * 100 + g * 10 + h;

        WHEN 'Lv4' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / UNIT_LAT_LV1);
            cd := floor(rem_lon_lv0 / UNIT_LON_LV1);
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := fmod(lat, UNIT_LAT_LV1);
            rem_lon_lv1 := fmod(lon, UNIT_LON_LV1);
            e := floor(rem_lat_lv1 / UNIT_LAT_LV2);
            f := floor(rem_lon_lv1 / UNIT_LON_LV2);
            base_lv2 := base_lv1 * 100 + e * 10 + f;
            rem_lat_lv2 := fmod(rem_lat_lv1, UNIT_LAT_LV2);
            rem_lon_lv2 := fmod(rem_lon_lv1, UNIT_LON_LV2);
            g := floor(rem_lat_lv2 / UNIT_LAT_LV3);
            h := floor(rem_lon_lv2 / UNIT_LON_LV3);
            base_lv3 := base_lv2 * 100 + g * 10 + h;
            rem_lat_lv3 := fmod(rem_lat_lv2, UNIT_LAT_LV3);
            rem_lon_lv3 := fmod(rem_lon_lv2, UNIT_LON_LV3);
            i := floor(rem_lat_lv3 / UNIT_LAT_LV4) * 2 + floor(rem_lon_lv3 / UNIT_LON_LV4) + 1;
            RETURN base_lv3 * 10 + i;

        WHEN 'Lv5' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / UNIT_LAT_LV1);
            cd := floor(rem_lon_lv0 / UNIT_LON_LV1);
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := fmod(lat, UNIT_LAT_LV1);
            rem_lon_lv1 := fmod(lon, UNIT_LON_LV1);
            e := floor(rem_lat_lv1 / UNIT_LAT_LV2);
            f := floor(rem_lon_lv1 / UNIT_LON_LV2);
            base_lv2 := base_lv1 * 100 + e * 10 + f;
            rem_lat_lv2 := fmod(rem_lat_lv1, UNIT_LAT_LV2);
            rem_lon_lv2 := fmod(rem_lon_lv1, UNIT_LON_LV2);
            g := floor(rem_lat_lv2 / UNIT_LAT_LV3);
            h := floor(rem_lon_lv2 / UNIT_LON_LV3);
            base_lv3 := base_lv2 * 100 + g * 10 + h;
            rem_lat_lv3 := fmod(rem_lat_lv2, UNIT_LAT_LV3);
            rem_lon_lv3 := fmod(rem_lon_lv2, UNIT_LON_LV3);
            i := floor(rem_lat_lv3 / UNIT_LAT_LV4) * 2 + floor(rem_lon_lv3 / UNIT_LON_LV4) + 1;
            base_lv4 := base_lv3 * 10 + i;
            rem_lat_lv4 := fmod(rem_lat_lv3, UNIT_LAT_LV4);
            rem_lon_lv4 := fmod(rem_lon_lv3, UNIT_LON_LV4);
            j := floor(rem_lat_lv4 / UNIT_LAT_LV5) * 2 + floor(rem_lon_lv4 / UNIT_LON_LV5) + 1;
            RETURN base_lv4 * 10 + j;

        WHEN 'Lv6' THEN
            rem_lat_lv0 := lat;
            rem_lon_lv0 := lon - 100.0;
            ab := floor(rem_lat_lv0 / UNIT_LAT_LV1);
            cd := floor(rem_lon_lv0 / UNIT_LON_LV1);
            base_lv1 := ab * 100 + cd;
            rem_lat_lv1 := fmod(lat, UNIT_LAT_LV1);
            rem_lon_lv1 := fmod(lon, UNIT_LON_LV1);
            e := floor(rem_lat_lv1 / UNIT_LAT_LV2);
            f := floor(rem_lon_lv1 / UNIT_LON_LV2);
            base_lv2 := base_lv1 * 100 + e * 10 + f;
            rem_lat_lv2 := fmod(rem_lat_lv1, UNIT_LAT_LV2);
            rem_lon_lv2 := fmod(rem_lon_lv1, UNIT_LON_LV2);
            g := floor(rem_lat_lv2 / UNIT_LAT_LV3);
            h := floor(rem_lon_lv2 / UNIT_LON_LV3);
            base_lv3 := base_lv2 * 100 + g * 10 + h;
            rem_lat_lv3 := fmod(rem_lat_lv2, UNIT_LAT_LV3);
            rem_lon_lv3 := fmod(rem_lon_lv2, UNIT_LON_LV3);
            i := floor(rem_lat_lv3 / UNIT_LAT_LV4) * 2 + floor(rem_lon_lv3 / UNIT_LON_LV4) + 1;
            base_lv4 := base_lv3 * 10 + i;
            rem_lat_lv4 := fmod(rem_lat_lv3, UNIT_LAT_LV4);
            rem_lon_lv4 := fmod(rem_lon_lv3, UNIT_LON_LV4);
            j := floor(rem_lat_lv4 / UNIT_LAT_LV5) * 2 + floor(rem_lon_lv4 / UNIT_LON_LV5) + 1;
            base_lv5 := base_lv4 * 10 + j;
            rem_lat_lv5 := fmod(rem_lat_lv4, UNIT_LAT_LV5);
            rem_lon_lv5 := fmod(rem_lon_lv4, UNIT_LON_LV5);
            k := floor(rem_lat_lv5 / UNIT_LAT_LV6) * 2 + floor(rem_lon_lv5 / UNIT_LON_LV6) + 1;
            RETURN base_lv5 * 10 + k;

        ELSE
            -- Should not happen if mesh_level enum is used correctly
            RETURN NULL;
    END CASE;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT; -- Function result depends only on inputs

-- Function to calculate all meshcodes that intersect a given box2d at specified mesh level
CREATE OR REPLACE FUNCTION to_meshcodes(bbox box2d, level mesh_level)
RETURNS TABLE(meshcode bigint) AS $$
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
BEGIN
    -- Extract box coordinates
    min_lon := ST_XMin(bbox);
    min_lat := ST_YMin(bbox);
    max_lon := ST_XMax(bbox);
    max_lat := ST_YMax(bbox);

    -- Validate input coordinates
    IF min_lon < 100.0 OR max_lon >= 180.0 OR min_lat < 0.0 OR max_lat >= 66.66 THEN
        RAISE EXCEPTION 'Box coordinates out of valid range (lon: 100.0-180.0, lat: 0.0-66.66)';
    END IF;

    -- Determine the unit size for the specified mesh level
    CASE level
        WHEN 'Lv1' THEN
            unit_lat := 2.0/3.0;
            unit_lon := 1.0;
        WHEN 'X40' THEN
            unit_lat := 1.0/3.0;
            unit_lon := 0.5;
        WHEN 'X20' THEN
            unit_lat := 1.0/6.0;
            unit_lon := 0.25;
        WHEN 'X16' THEN
            unit_lat := 2.0/15.0;
            unit_lon := 0.2;
        WHEN 'Lv2' THEN
            unit_lat := 1.0/12.0;
            unit_lon := 1.0/8.0;
        WHEN 'X8' THEN
            unit_lat := 2.0/15.0;
            unit_lon := 0.2;
        WHEN 'X5' THEN
            unit_lat := 1.0/24.0;
            unit_lon := 1.0/16.0;
        WHEN 'X4' THEN
            unit_lat := 1.0/30.0;
            unit_lon := 0.1;
        WHEN 'X2_5' THEN
            unit_lat := 1.0/48.0;
            unit_lon := 1.0/32.0;
        WHEN 'X2' THEN
            unit_lat := 1.0/60.0;
            unit_lon := 1.0/40.0;
        WHEN 'Lv3' THEN
            unit_lat := 1.0/120.0;
            unit_lon := 1.0/80.0;
        WHEN 'Lv4' THEN
            unit_lat := 1.0/240.0;
            unit_lon := 1.0/160.0;
        WHEN 'Lv5' THEN
            unit_lat := 1.0/480.0;
            unit_lon := 1.0/320.0;
        WHEN 'Lv6' THEN
            unit_lat := 1.0/960.0;
            unit_lon := 1.0/640.0;
        ELSE
            RAISE EXCEPTION 'Invalid mesh level: %', level;
    END CASE;

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
            meshcode := to_meshcode(ST_SetSRID(ST_MakePoint(x + unit_lon/2, y + unit_lat/2), 4326), level);

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

-- Example Usage (requires PostGIS):
-- SELECT to_meshcode(ST_SetSRID(ST_MakePoint(139.745433, 35.658581), 4326), 'Lv1'::mesh_level); --> 5339
-- SELECT to_meshcode(ST_SetSRID(ST_MakePoint(139.745433, 35.658581), 4326), 'Lv6'::mesh_level); --> 53393599212
-- SELECT to_meshcode(ST_SetSRID(ST_MakePoint(135.759363, 34.987574), 4326), 'Lv3'::mesh_level); --> 52353680
-- SELECT to_meshcode(ST_SetSRID(ST_MakePoint(99.0, 35.0), 4326), 'Lv1'::mesh_level); --> NULL (invalid longitude)
-- SELECT to_meshcode(NULL, 'Lv1'::mesh_level); --> NULL

-- Example for to_meshcodes:
-- Get all Lv1 meshcodes for Tokyo area:
-- SELECT meshcode FROM to_meshcodes(ST_MakeEnvelope(139.5, 35.5, 140.0, 36.0, 4326)::box2d, 'Lv1'::mesh_level);
-- Get all Lv3 meshcodes for a small area:
-- SELECT meshcode FROM to_meshcodes(ST_MakeEnvelope(139.7, 35.6, 139.8, 35.7, 4326)::box2d, 'Lv3'::mesh_level);
