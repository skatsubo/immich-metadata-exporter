WITH a AS (
  SELECT
    id,
    "originalPath",
    "sidecarPath"
  FROM asset
  WHERE
    (
      (:'target' = 'known' AND "sidecarPath" IS NOT NULL)
      OR
      (:'target' = 'unknown' AND "sidecarPath" IS NULL)
      OR 
      :'target' = 'all'
    )
    AND "deletedAt" IS NULL
    AND "originalPath" NOT IN ('', '*')
    AND :asset_filter
  ORDER BY "originalPath"
),
a_tag AS (
  SELECT 
    a.id AS asset_id,
    json_agg(t.value order by t.value) filter (where t.value is not null) AS tag_list
  FROM a
  LEFT JOIN tag_asset ta ON a.id = ta."assetsId"
  LEFT JOIN tag t ON ta."tagsId" = t.id
  GROUP BY a.id
),
a_exif AS (
  SELECT "assetId",
    -- convert Luxon timeZone to UTC offset
    -- calculation is done by definition as a difference between wall clocks in two time zones, see https://www.postgresql.org/message-id/875zlhnn5d.fsf%40news-spur.riddles.org.uk
    -- intermediate steps
    --   convert Luxon fixed-offset tz `UTC+offset` to PG posix tz `-offset` with opposite sign
    --   keep named time zones as is
    --   strip seconds (last 3 chars)
    left((
        "dateTimeOriginal" at time zone replace(replace("timeZone", 'UTC+', '-'), 'UTC-', '+') - "dateTimeOriginal" at time zone 'UTC'
      )::text, -3) AS utc_offset
  FROM asset_exif
),
metadata AS (
  SELECT
    COALESCE(a."sidecarPath", a."originalPath" || '.xmp') AS "SourceFile",
    NULLIF(ae.description, '') AS "Description",
    NULLIF(ae.description, '') AS "ImageDescription",
    TO_CHAR(("dateTimeOriginal" + coalesce(utc_offset, '0')::interval) at time zone 'UTC', 'YYYY:MM:DD HH24:MI:SS.MS')
    ||
    CASE
      WHEN utc_offset::interval > '0'::interval
      THEN '+' || utc_offset
      ELSE
        CASE
          WHEN utc_offset::interval < '0'::interval
          THEN utc_offset
          ELSE ''
        END
    END
    AS "DateTimeOriginal",
    a_exif.utc_offset AS "XMP:OffsetTimeOriginal", -- experimental, visible in metadata json, does not appear in a sidecar
    ae.latitude AS "GPSLatitude",
    ae.longitude AS "GPSLongitude",
    ae.rating AS "Rating",
    at.tag_list AS "TagsList"
  FROM a
  LEFT JOIN asset_exif ae ON a.id = ae."assetId"
  LEFT JOIN a_exif ON a.id = a_exif."assetId"
  LEFT JOIN a_tag at ON a.id = at.asset_id
)
SELECT json_agg(
  json_strip_nulls(row_to_json(metadata))
)
FROM metadata
WHERE num_nonnulls("Description", "ImageDescription", "TagsList", "DateTimeOriginal", "GPSLatitude", "GPSLongitude", "Rating") > 0
