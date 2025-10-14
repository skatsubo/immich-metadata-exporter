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
    coalesce(
      json_agg(t.value order by t.value) filter (where t.value is not null),
      '[]'::json
    ) AS tag_list
  FROM assets a
  LEFT JOIN tag_asset ta ON a.id = ta."assetsId"
  LEFT JOIN tag t ON ta."tagsId" = t.id
  GROUP BY a.id
)
SELECT json_agg(
  json_build_object(
    'SourceFile', coalesce(a."sidecarPath", a."originalPath" || '.xmp'),
    'Description', ae.description,
    'ImageDescription', ae.description,
    'TagsList', at.tag_list,
    'DateTimeOriginal', 
      to_char(ae."dateTimeOriginal" AT TIME ZONE 'UTC', 'YYYY:MM:DD HH24:MI:SS.MS') || '+00:00',
    'GPSLatitude', ae.latitude,
    'GPSLongitude', ae.longitude
  )
) AS exiftool_json
FROM assets a
LEFT JOIN asset_exif ae ON a.id = ae."assetId"
LEFT JOIN asset_tags at ON a.id = at.asset_id;
