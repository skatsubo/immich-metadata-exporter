# Export asset metadata from Immich to XMP sidecars

- [Description](#description) | [How to use](#how-to-use) | [Caveats](#caveats) | [Todo](#todo) | [Sidecar example](#sidecar-example)

## Description

This is a proof of concept for exporting (writing) asset metadata to companion XMP sidecars.

Why do that? 
- Discussed on Discord (link to web version on AnswerOverflow): [Bulk (re)write of xmp sidecar files](https://www.answeroverflow.com/m/1425744361718677587).
- Also, it's a learning opportunity to better understand Immich data structures. So I wrote this SQL + shell pair as a response to the Discord post, out of curiosity and to illustrate Immich's asset metadata internals.

The script exports asset metadata to sidecars using:
- SQL - to get asset metadata from the database directly
- exiftool - to write (create or update) sidecar files on disk

(It does not modify Immich database in any way. E.g. upon creating a sidecar on disk it will not update `asset.sidecarPath` in the database.)

## How to use

1. Clone the repo or download two files: [export.sh](https://raw.githubusercontent.com/skatsubo/immich-metadata-exporter/refs/heads/main/export.sh) and [metadata.sql](https://raw.githubusercontent.com/skatsubo/immich-metadata-exporter/refs/heads/main/metadata.sql).

2. Run the script:

```sh
bash export.sh
```

3. It will extract metadata from the database and create a JSON for exiftool. Next, it will invoke exiftool to actually write/update sidecar files using data from the JSON file.

### Examples

Dry run export with filtering: only process assets uploaded since 2025-10-10 and having "img" in their file name.  
To avoid shell quoting headaches when passing a complex filter use "heredoc" syntax. Place the filter between the EOF's below:
```sh
asset_filter=$(cat <<'EOF'
"createdAt" >= '2025-10-10' AND "originalFileName" ILIKE '%img%'
EOF
)

bash export.sh --target all --filter "$asset_filter" --dry-run
```

### Getting help

Check the usage instructions by providing `--help / -h`.

```
./export.sh --help

Immich metadata to sidecar exporter

Writes asset metadata to companion XMP sidecars.
For more info see https://github.com/skatsubo/immich-metadata-exporter

Usage:
  export.sh                # By default, export metadata for known assets: those that have sidecar path defined in the database
  export.sh [--args...]    # Export with extra args: asset filter, target (see optinal arguments below)
  export.sh --help         # Show this help

Optional arguments:
  --target { known | all } Target assets/sidecars to process.
                             known: process assets with existing sidecars (having non-empty 'asset.sidecarPath' in the database)
                             all:   process all assets
                           Default: known
  --filter <condition>     SQL "where" condition to limit which assets' metadata to export.
                           It is passed verbatim to the where clause when selecting assets for export: WHERE ... AND <condition>
                           Default: 1=1 (no filtering)
  --dry-run                Dry run. Generate metadata.json but do not invoke exiftool to write sidecars.

Examples:
  export.sh --target all --filter "asset.\"createdAt\" >= '2025-10-10'" --dry-run
```

## Caveats

> [!WARNING]
> This is a quick PoC and work-in-progress. It is not secure against SQL injections, shell injections and other irregularities in data. Try it on a throwaway Immich instance first.  
> For a supported implementation consider using Immich API.

## Todo

Todo / maybe:
- [ ] Write DateTimeOriginal with timezone instead of UTC (so TZ will be visible in XMP)
- [ ] Diff/plan of changes (before applying or when dry run)
- [ ] Face/people export

## Sidecar example

### Exiftool

Command:
```sh
exiftool -n -G -json portrait.jpg.xmp
```

JSON output:
```json
[{
  "SourceFile": "portrait.jpg.xmp",
  "FileName": "portrait.jpg.xmp",
  "Directory": ".",
  ...
  "Description": "Pierre and Marie Curie in their lab",
  "ImageDescription": "Pierre and Marie Curie in their lab",
  "TagsList": ["People/Marie Curie","People/Pierre Curie","Physics"],
  "DateTimeOriginal": "1900:01:01 01:01:00.000+01:00",
  "DateCreated": "1900:01:01 01:01:00.000+01:00",
  "GPSLatitude": 48.85341,
  "GPSLongitude": 2.3488,
  "Rating": 4,
}]
```

### XMP sidecar

`portrait.jpg.xmp` as written by Immich:
```xml
<?xpacket begin='﻿' id='W5M0MpCehiHzreSzNTczkc9d'?>
<x:xmpmeta xmlns:x='adobe:ns:meta/' x:xmptk='Image::ExifTool 13.00'>
<rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'>

 <rdf:Description rdf:about=''
  xmlns:dc='http://purl.org/dc/elements/1.1/'>
  <dc:description>
   <rdf:Alt>
    <rdf:li xml:lang='x-default'>Pierre and Marie Curie in their lab</rdf:li>
   </rdf:Alt>
  </dc:description>
 </rdf:Description>

 <rdf:Description rdf:about=''
  xmlns:digiKam='http://www.digikam.org/ns/1.0/'>
  <digiKam:TagsList>
   <rdf:Seq>
    <rdf:li>People/Marie Curie</rdf:li>
    <rdf:li>People/Pierre Curie</rdf:li>
    <rdf:li>Physics</rdf:li>
   </rdf:Seq>
  </digiKam:TagsList>
 </rdf:Description>

 <rdf:Description rdf:about=''
  xmlns:exif='http://ns.adobe.com/exif/1.0/'>
  <exif:DateTimeOriginal>1900-01-01T01:01:00.000+01:00</exif:DateTimeOriginal>
  <exif:GPSLatitude>48,51.2046N</exif:GPSLatitude>
  <exif:GPSLongitude>2,20.928E</exif:GPSLongitude>
 </rdf:Description>

 <rdf:Description rdf:about=''
  xmlns:photoshop='http://ns.adobe.com/photoshop/1.0/'>
  <photoshop:DateCreated>1900-01-01T01:01:00.000+01:00</photoshop:DateCreated>
 </rdf:Description>

 <rdf:Description rdf:about=''
  xmlns:tiff='http://ns.adobe.com/tiff/1.0/'>
  <tiff:ImageDescription>
   <rdf:Alt>
    <rdf:li xml:lang='x-default'>Pierre and Marie Curie in their lab</rdf:li>
   </rdf:Alt>
  </tiff:ImageDescription>
 </rdf:Description>

 <rdf:Description rdf:about=''
  xmlns:xmp='http://ns.adobe.com/xap/1.0/'>
  <xmp:Rating>4</xmp:Rating>
 </rdf:Description>
</rdf:RDF>
</x:xmpmeta>
<?xpacket end='w'?>
```
