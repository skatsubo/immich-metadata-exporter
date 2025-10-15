WITH assets AS (
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
asset_tags AS (
  SELECT 
    a.id AS asset_id,
    json_agg(t.value order by t.value) filter (where t.value is not null) AS tag_list
  FROM assets a
  LEFT JOIN tag_asset ta ON a.id = ta."assetsId"
  LEFT JOIN tag t ON ta."tagsId" = t.id
  GROUP BY a.id
),
metadata AS (
  SELECT
    COALESCE(a."sidecarPath", a."originalPath" || '.xmp') AS "SourceFile",
    NULLIF(ae.description, '') AS "Description",
    NULLIF(ae.description, '') AS "ImageDescription",
    TO_CHAR(ae."dateTimeOriginal" AT TIME ZONE 'UTC', 'YYYY:MM:DD HH24:MI:SS.MS') || '+00:00' AS "DateTimeOriginal",
    ae.latitude AS "GPSLatitude",
    ae.longitude AS "GPSLongitude",
    ae.rating AS "Rating",
    at.tag_list AS "TagsList"
  FROM assets a
  LEFT JOIN asset_exif ae ON a.id = ae."assetId"
  LEFT JOIN asset_tags at ON a.id = at.asset_id
)
SELECT json_agg(
  json_strip_nulls(row_to_json(metadata))
)
FROM metadata
WHERE num_nonnulls("Description", "ImageDescription", "TagsList", "DateTimeOriginal", "GPSLatitude", "GPSLongitude", "Rating") > 0
