#!/usr/bin/env bash

set -e
set -u
set -o pipefail

ime_dir=/tmp/immich-metadata-exporter
metadata_file=metadata.json
preview_dir=''

if [[ -n $debug ]]; then
  rsync_debug="-v"
  xargs_debug="-t"
fi

log() {
    echo "[${FUNCNAME[1]}]" "$@"
}

install_tools() {
  packages="libimage-exiftool-perl jq colordiff rsync"
  if ! dpkg -s $packages &>/dev/null; then
    log "Install tools: $packages"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -yqq --no-install-recommends $packages || echo "apt install error: exit $?"
  fi
}

scan_sidecars() {
  log "Discover existing and absent sidecars"
  sidecars=sidecars
  sidecars_existing=sidecars_existing
  sidecars_absent=sidecars_absent
  jq --raw-output0 '.[].SourceFile' "$metadata_file" | sort -zu > "$sidecars"
  # find returns non-zero exit code if any listed file is missing
  find -files0-from "$sidecars" -print0 2>/dev/null | sort -z > "$sidecars_existing" || true
  comm -z -23 "$sidecars" "$sidecars_existing" > "$sidecars_absent"
}

# TODO: revisit
generate_preview_configs() {
  log
  preview_metadata_file="preview_$metadata_file"
  preview_sidecars="preview_$sidecars"
  preview_sidecars_absent="preview_$sidecars_absent"

  # prepend preview_dir if defined (when dry run)
  if [[ -n $preview_dir ]]; then
    jq --arg preview_dir "$preview_dir" 'map(.SourceFile = $preview_dir + .SourceFile)' "$metadata_file" > "$preview_metadata_file"
    sed -z "s|.*|${preview_dir}\0|" "$sidecars" > "$preview_sidecars"
    sed -z "s|.*|${preview_dir}\0|" "$sidecars_absent" > "$preview_sidecars_absent"
  fi
}

# create empty "placeholder" sidecars to make sure that all files exist
# this is required for exiftool batch execution
# otherwise exiftool will skip non-existent files instead of writing them
touch_missing_sidecars() {
  log
  if [[ -z $preview_dir ]]; then
    list_file="$sidecars_absent"
  else
    list_file="$preview_sidecars_absent"
  fi
  # create directories
  sed -z 's#/[^/]*$##' "$list_file" | xargs -0 $xargs_debug mkdir -p
  # touch files
  xargs -0 $xargs_debug touch <"$list_file"
}

copy_existing_sidecars() {
  log
  rsync -a $rsync_debug --files-from="$sidecars_existing" --from0 / "$preview_dir"/
}

write_sidecars() {
  log
  # TODO: different handling of preview ?
  # TODO: fix "Error opening file" for missing files
  # TODO: fix "already exists"
  # exiftool -TagsFromFile src.jpg -all:all dst.mie
  #     Copy all meta information in its original form from a JPEG image to a MIE file. The MIE file will be created if it doesn't exist. This technique can be used to store the metadata of an image so it can be inserted back into the image (with the inverse command) later in a workflow.
  # exiftool -o dst.mie -all:all src.jpg
  #     This command performs exactly the same task as the command above, except that the -o option will not write to an output file that already exists.
  # -o OUTFILE or FMT (-out)
  #     Set the output file or directory name when writing information. Without this option, when any "real" tags are written the original file is renamed to FILE_original and output is written to FILE. When writing only FileName and/or Directory "pseudo" tags, -o causes the file to be copied instead of moved, but directories specified for either of these tags take precedence over that specified by the -o option.
  #     OUTFILE may be - to write to stdout. The output file name may also be specified using a FMT string in which %d, %f and %e represent the directory, file name and extension of FILE. Also, %c may be used to add a copy number. See the -w option for FMT string examples.
  #     The output file is taken to be a directory name if it already exists as a directory or if the name ends with '/'. Output directories are created if necessary. Existing files will not be overwritten. Combining the -overwrite_original option with -o causes the original source file to be erased after the output file is successfully written.
  #     A special feature of this option allows the creation of certain types of files from scratch, or with the metadata from another type of file. The following file types may be created using this technique:
  #     XMP, EXIF, EXV, MIE, ICC/ICM, VRD, DR4
  #     The output file type is determined by the extension of OUTFILE (specified as -.EXT when writing to stdout). The output file is then created from a combination of information in FILE (as if the -tagsFromFile option was used), and tag values assigned on the command line. If no FILE is specified, the output file may be created from scratch using only tags assigned on the command line.
  # if [[ -z $preview ]]; then
  if [[ -z $preview_dir ]]; then
    <"$sidecars" tr '\0' '\n' | exiftool -json="$metadata_file" -overwrite_original -@ -
  else
    <"$preview_sidecars" tr '\0' '\n' | exiftool -json="$preview_metadata_file" -overwrite_original -@ -
  fi
}

print_diff() {
  log
  echo "===================="
  echo "exiftool plan / diff"
  echo " [+] = create"
  echo " [*] = modify"
  echo " [ ] = no op"
  echo "===================="
  # not super efficient but will do the job of diff'ing old vs new sidecars
  while IFS= read -r -d '' new; do
    old="${new#"$preview_dir"}"
    if [ ! -f "$old" ]; then
      echo "[+] $old"
      continue
    fi
    if cmp -s "$old" "$new"; then
      echo "[ ] $old"
    else
      echo "[*] $old"
      colordiff -U 2 "$old" "$new" | grep -vE '(\+\+\+|---) /'
      echo
    fi
  done < <(find "$preview_dir" -type f -print0)
}

#
# main
#

# TODO
# trap 'rm -rf "$ime_dir"' EXIT HUP INT PIPE QUIT TERM

install_tools
scan_sidecars

# actual execution or dry run (write to the original location vs write to a temp dir)
if [[ -z $preview ]]; then
  touch_missing_sidecars
  write_sidecars
else
  preview_dir="$ime_dir/files"
  # cleanup after previous invocation
  rm -rf "$preview_dir"
 
  generate_preview_configs
  touch_missing_sidecars
  copy_existing_sidecars
  write_sidecars
  print_diff
fi

# TODO
# cleanup by default (if $skip_cleanup is not set)
# if [[ -z $skip_cleanup ]]; then
#   rm -rf /tmp/ime
# fi
