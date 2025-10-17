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
    -- convert Immich / exiftool-vendored / JS timeZone to UTC offset
    -- calculation is somewhat similar to https://www.postgresql.org/message-id/875zlhnn5d.fsf%40news-spur.riddles.org.uk
    -- additionally
    --   if timeZone has form `UTC+offset`, strip `UTC` and concat with timestamp to avoid interpreting it as a posix timezone (that has inverted meaning of a sign)
    --   otherwise, if timeZone is a named time zone, keep it as is
    --   strip seconds
    left(
      ("dateTimeOriginal"::timestamptz - (("dateTimeOriginal" at time zone 'UTC')||REPLACE(' '||"timeZone", ' UTC', ''))::timestamptz)::text
      , -3
    ) AS tz_offset -- utc_offset
  FROM asset_exif
),
metadata AS (
  SELECT
    COALESCE(a."sidecarPath", a."originalPath" || '.xmp') AS "SourceFile",
    NULLIF(ae.description, '') AS "Description",
    NULLIF(ae.description, '') AS "ImageDescription",
    TO_CHAR(("dateTimeOriginal" + coalesce(tz_offset, '0')::interval) at time zone 'UTC', 'YYYY:MM:DD HH24:MI:SS.MS')
    ||
    CASE
      WHEN tz_offset::interval > '0'::interval
      THEN '+' || tz_offset
      ELSE
        CASE
          WHEN tz_offset::interval < '0'::interval
          THEN tz_offset
          ELSE ''
        END
    END
    AS "DateTimeOriginal",
    a_exif.tz_offset AS "XMP:OffsetTimeOriginal", -- experimental, visible in metadata json, does not appear in a sidecar
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
