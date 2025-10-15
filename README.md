# Export asset metadata from Immich to XMP sidecars

[Description](#description) | [How to use](#how-to-use) | [How it works](#how-it-works) | [Caveats](#caveats) | [Todo](#todo) | [Sidecar example](#sidecar-example)

## Description

This is a proof of concept for exporting (writing) Immich asset metadata to companion XMP sidecars.

Why do that? 
- To restore accidentally deleted sidecars as discussed on Discord: [Bulk (re)write of xmp sidecar files](https://discord.com/channels/979116623879368755/1425744361718677587) (also [link](https://www.answeroverflow.com/m/1425744361718677587) to the web version on AnswerOverflow).
- This is a learning opportunity to better understand Immich data structures.

So I wrote this bash/SQL as a response to the Discord post, out of curiosity and to illustrate Immich asset/metadata internals.

## How to use

1. Clone the repo or download two files: [export.sh](https://raw.githubusercontent.com/skatsubo/immich-metadata-exporter/refs/heads/main/export.sh) and [metadata.sql](https://raw.githubusercontent.com/skatsubo/immich-metadata-exporter/refs/heads/main/metadata.sql).

2. Run the script in `preview` mode and check the generated sidecars in `./sidecars-preview`.

```sh
bash export.sh --preview
```

3. Run the script to actually write sidecars to original location:

```sh
bash export.sh
```

### Examples

Preview export with filtering: only process assets uploaded since 2025-10-10 and having "img" in their file name.  
To avoid shell quoting headaches when passing a complex filter use "heredoc" syntax. Place the filter between the EOF's below:
```sh
asset_filter=$(cat <<'EOF'
"createdAt" >= '2025-10-10' AND "originalFileName" ILIKE '%img%'
EOF
)

bash export.sh --target all --filter "$asset_filter" --preview
```

Run with environment variables:
```sh
DEBUG=1 PREVIEW=1 TARGET=all ./export.sh
```


### Getting help

Check the usage instructions by providing `--help / -h`.

```
./export.sh --help

Immich metadata to sidecar exporter

Writes asset metadata to companion XMP sidecars.

Usage:
  ./export.sh                # By default, export metadata for known assets: those that have sidecar path defined in the database
  ./export.sh [--args...]    # Export with extra args: asset filter, target (see optinal arguments below)
  ./export.sh --help         # Show this help

Optional arguments:
  --target { known | unknown | all } Target assets/sidecars to process.
                                       known:   process assets with existing sidecars (having non-empty 'asset.sidecarPath' in the database)
                                       unknown: process assets without sidecars (having empty 'asset.sidecarPath' in the database)
                                       all:     process all assets
                                     Default: known
  --filter <condition>               SQL "where" condition to limit which assets' metadata to export.
                                     It is passed verbatim to the where clause when selecting assets for export: WHERE ... AND <condition>
                                     Default: 1=1 (no filtering)
  --preview                          Preview (dry run). Generate metadata.json and sidecars but do not write anything to the original location.
  --debug                            Debug. Print more verbose output.

Examples:
  ./export.sh --preview
  ./export.sh --target all --filter "asset.\"createdAt\" >= '2025-10-10'"
```

## How it works

The script exports asset metadata to sidecars using:
- SQL - to get asset metadata from the database directly
- exiftool - to write (create or update) sidecar files on disk

First, it extracts metadata from the database (by invoking psql in the database container) and saves it as a JSON file in exiftool format.
Next, it invokes exiftool (in the Immich server container) to actually write/update sidecar files using data from the JSON file.

The script does not modify Immich database in any way. E.g. upon creating a sidecar on disk it will not update `sidecarPath` value for the asset in the database.

## Caveats

> [!WARNING]
> This is a quick PoC and work-in-progress. It is not secure against SQL injections, shell injections and other irregularities in data or file names. Try it on a throwaway Immich instance first.  
> For a supported implementation consider using Immich API.

- When writing sidecars, all supported non-empty metadata fields will be written, regardless of whether they were modified or not. (Compare this to Immich: it writes only modified fields).
- When the generated sidecar and the original sidecar are almost identical (have the same metadata fields and values) and only differ by exiftool version in the XMP meta `x:xmptk='Image::ExifTool <version>'`, the original sidecar will be overwritten and its file timestamp will change.
- Timestamps (DateTimeOriginal, DateCreated) are currently written as UTC +00:00 without TZ offset. (Immich includes TZ offset when writing sidecars because TZ is provided by a user while editing timestamps. In the database, dateTimeOriginal is simply UTC).
- File names containing line breaks are not supported.

## Todo

Todo / maybe:
- [ ] Write `DateTimeOriginal` with timezone instead of UTC +00:00 to have explicit TZ value in XMP timestamps (same as Immich works currently). Perhaps leverage `timeZone` value in `asset_exif`.
- [ ] Face/people export
- [ ] Execution stats (number of files created and modified)

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
