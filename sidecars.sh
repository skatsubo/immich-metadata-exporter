#!/usr/bin/env bash

set -e -u -o pipefail

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
    log "Install tools inside the Immich container: $packages"
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
  # find returns non-zero exit code if any of "files-from" is missing
  find -files0-from "$sidecars" -print0 2>/dev/null | sort -z > "$sidecars_existing" || true
  comm -z -23 "$sidecars" "$sidecars_existing" > "$sidecars_absent"
}

generate_preview_configs() {
  log
  preview_metadata_file="preview_$metadata_file"
  preview_sidecars="preview_$sidecars"
  preview_sidecars_absent="preview_$sidecars_absent"
  # prepend preview_dir if defined
  if [[ -n $preview_dir ]]; then
    jq --arg preview_dir "$preview_dir" 'map(.SourceFile = $preview_dir + .SourceFile)' "$metadata_file" > "$preview_metadata_file"
    sed -z "s|.*|${preview_dir}\0|" "$sidecars" > "$preview_sidecars"
    sed -z "s|.*|${preview_dir}\0|" "$sidecars_absent" > "$preview_sidecars_absent"
  fi
}

# create empty "placeholder" sidecars to make sure that all files exist
# this is required for exiftool batch execution
# otherwise exiftool will skip non-existent files instead of writing them
touch_absent_sidecars() {
  if [[ ! -s $sidecars_absent ]]; then
    return
  fi
  log
  if [[ -z $preview_dir ]]; then
    absent="$sidecars_absent"
  else
    absent="$preview_sidecars_absent"
  fi
  # create directories
  sed -z 's#/[^/]*$##' "$absent" | uniq | xargs -0 $xargs_debug mkdir -p
  # touch absentfiles
  xargs -0 $xargs_debug touch <"$absent"
}

copy_existing_sidecars() {
  log
  rsync -a $rsync_debug --files-from="$sidecars_existing" --from0 / "$preview_dir"/
}

write_sidecars() {
  if [[ -z $preview_dir ]]; then
    metadata="$metadata_file"
    files="$sidecars"
  else
    metadata="$preview_metadata_file"
    files="$preview_sidecars"
  fi
  log "Targeting $(jq 'length' "$metadata") sidecar files"
  # use MWG module to match Immich/exiftool-vendored behavior (writing DateCreated when DateTimeOriginal is provided)
  <"$files" tr '\0' '\n' | exiftool -json="$metadata" -overwrite_original -use MWG -@ - 2>&1 | sed 's/image files updated/files updated/'
}

# diff implemented only in preview mode
print_diff() {
  log
  echo "===================="
  echo "exiftool plan / diff"
  echo " [+] = create"
  echo " [*] = modify"
  if [[ -n $debug ]]; then
  echo " [ ] = no op"
  fi
  echo "===================="
  # not super efficient but will do the job of diff'ing old vs new sidecars
  while IFS= read -r -d '' new; do
    old="${new#"$preview_dir"}"

    # plan: create if not exists
    if [[ ! -f "$old" ]]; then
      echo "[+] $old"
      continue
    fi

    # if exists then compare by content
    if cmp -s "$old" "$new"; then
      # plan: skip (no op) if identical
      if [[ -n $debug ]]; then
        echo "[ ] $old"
      fi
    else
      # plan: modify (update) if different
      echo "[*] $old"
      if [[ -n $debug ]]; then
        # diff and grep may return exit code 1 upon successful execution
        # ignore exit status for the sake of simplicity
        colordiff -U 2 "$old" "$new" | grep -vE '^\S*(\+\+\+|---) ' || :
        echo
      fi
    fi
  done < <(find "$preview_dir" -type f -print0)
}

#
# main
#

install_tools
scan_sidecars

if [[ -z $preview ]]; then
  # actual execution (write to the original location)
  touch_absent_sidecars
  write_sidecars
else
  # preview / dry run (write to a temp dir)
  preview_dir="$ime_dir/preview"
  rm -rf "$preview_dir" 
  generate_preview_configs
  touch_absent_sidecars
  copy_existing_sidecars
  write_sidecars
  print_diff
fi
