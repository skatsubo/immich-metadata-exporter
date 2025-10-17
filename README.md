# Export asset metadata from Immich to XMP sidecars

[Description](#description) | [How to use](#how-to-use) | [How it works](#how-it-works) | [Caveats](#caveats) | [Todo](#todo) | [Sidecar example](#sidecar-example)

## Description

This is a proof of concept for exporting (writing) Immich asset metadata to companion XMP sidecars.

Why do that? 
- To restore accidentally deleted sidecars as discussed on Discord: [Bulk (re)write of xmp sidecar files](https://discord.com/channels/979116623879368755/1425744361718677587) (also [AnswerOverflow link](https://www.answeroverflow.com/m/1425744361718677587) to the web version).
- This is a learning opportunity to better understand Immich data structures.

So I wrote this bash/SQL as a response to the Discord post, out of curiosity and to illustrate Immich asset/metadata internals.

## How to use

1. Clone the repo or download two files: [export.sh](https://raw.githubusercontent.com/skatsubo/immich-metadata-exporter/refs/heads/main/export.sh), [sidecars.sh](https://raw.githubusercontent.com/skatsubo/immich-metadata-exporter/refs/heads/main/sidecars.sh), [metadata.sql](https://raw.githubusercontent.com/skatsubo/immich-metadata-exporter/refs/heads/main/metadata.sql).

2. Run the script in `preview` mode and check the generated sidecars in `./sidecars-preview`:

```sh
bash export.sh --preview
```

3. Run the script to actually write sidecars to original location:

```sh
bash export.sh
```

### Examples

Run in preview mode, with debug output, targeting both known and unknown sidecars, using environment variables:
```sh
TARGET=all PREVIEW=1 DEBUG=1 ./export.sh
```

Preview export with filtering: only process assets uploaded since 2025-10-10 and having "2025" in their file name. Using "heredoc" syntax for a complex SQL filter to avoid shell quoting headaches.
```sh
asset_filter=$(cat <<'EOF'
"createdAt" >= '2025-10-10' AND "originalFileName" ILIKE '%2025%'
EOF
)

bash export.sh --target all --filter "$asset_filter" --preview
```

### Getting help

Check the usage instructions by providing `--help / -h`.

```
./export.sh --help

Immich metadata to sidecar exporter

Writes asset metadata to companion XMP sidecars.

Usage:
  ./export.sh                # Write metadata to known sidecars (those having sidecarPath defined in the database)
  ./export.sh [--args...]    # Export with extra args: asset filter, target (see optinal arguments below), preview mode, debug
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
  --debug                            Debug. Print more verbose output. In preview mode it prints diff for modified files.

Examples:
  ./export.sh --preview
  ./export.sh --preview --debug
  ./export.sh --target all --filter "\"createdAt\" >= '2025-10-10'"
```

## How it works

The script exports asset metadata to sidecars using:
- SQL - to get the asset metadata directly from the database
- exiftool - to write (create or update) sidecar files on disk

First, it extracts metadata from the database (by invoking psql in the database container) and saves it as a JSON file in exiftool format.
Next, it invokes exiftool (in the Immich server container) to actually write sidecar files using data from the JSON file.

The script does not modify Immich database in any way. E.g. upon creating a sidecar on disk it will not update `sidecarPath` value for the asset in the database. (Trigger the metadata refresh or sidecar discovery jobs to let Immich discover new sidecars.)

## Caveats

> [!WARNING]
> This is a quick PoC and work-in-progress. It is not resilient to weird file names or other irregularities in data. Try it in the preview mode or against a throwaway Immich instance first.  
> For a supported implementation consider using Immich API.

- When writing a sidecar, all supported non-empty metadata fields will be written, regardless of whether they were modified in Immich or not. (Immich writes only modified fields).
- The tool writes timestamps (DateTimeOriginal, DateCreated) using the local+offset form (UTC offset), as per MWG guidance and as Immich does when time zone / offset is known. This works, but the offset calculation is not thoroughly tested and might produce incorrect results in edge cases.
- Exiftool still rewrites the sidecar file even if its content is not going to be modified. Therefore its file system timestamp gets changed.
- Sidecar modifications may produce large diff (can be seen in debug output) even for small changes due to possible differences in XMP XML layout of original vs generated sidecars. Example: an original sidecar written in "XMP Compact" by Digikam using exiv2 _vs_ a sidecar generated by exiftool in non-compact form by default.
- File names containing line breaks are not supported.

## Todo

- [ ] Avoid rewriting sidecars if content is not going to be modified
- [ ] Face/people export
- [ ] Preview stats: number of files to be created or modified
- [ ] Cleanup on exit (remove tmp dir in the container)
- [ ] Self contained export.sh script

## Sidecar example

### Exiftool

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
