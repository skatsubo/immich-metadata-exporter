#!/usr/bin/env bash

set -e -u -o pipefail

#
# args
#

# the "where" condition (filter) to specify which assets' metadata to export
# it will be put verbatim into the "where" clause when selecting assets for metadata export: WHERE ... AND $asset_filter
# example: selecting assets uploaded since 2025-10-10
#   asset."createdAt" >= '2025-10-10'
# you should edit the line between EOFs
asset_filter=$(cat <<'EOF'
1=1
EOF
)

# target sidecars for the export
target="${TARGET:-known}"

# preview / dry run
preview="${PREVIEW:-}"

# debug
debug="${DEBUG:-}"

#
# vars
#
immich_container=immich_server
postgres_container=immich_postgres
postgres_user=postgres
postgres_db=immich

metadata_file=metadata.json
query_metadata_file=metadata.sql
sidecars_script=sidecars.sh
sidecars_preview_dir=sidecars-preview
# path inside the immich container
ime_dir=/tmp/immich-metadata-exporter

#
# functions
#
log() {
    echo "[${FUNCNAME[1]}]" "$@"
}

psql_cmd() {
  docker exec -i "$postgres_container" psql --tuples-only -U "$postgres_user" -d "$postgres_db" "$@"
}

immich_cmd() {
  docker exec -ti "$immich_container" "$@"
}

export_metadata_to_json() {
  log "Export metadata to json in exiftool format: $metadata_file"
  psql_cmd -Aq -v target="$target" -v asset_filter="$asset_filter" <"$query_metadata_file" > "$metadata_file"
}

handle_sidecars() {
  log "Write (create/update) sidecars"

  immich_cmd mkdir -p "$ime_dir"

  docker cp "$metadata_file" "$immich_container:$ime_dir/$metadata_file" >/dev/null

  docker cp "$sidecars_script" "$immich_container:$ime_dir/$sidecars_script" >/dev/null
  immich_cmd sh -c "cd $ime_dir && preview=$preview debug=$debug bash $sidecars_script"

  if [[ -n $preview ]]; then
    rm -rf "$sidecars_preview_dir"
    if docker cp "$immich_container:$ime_dir/preview" "$sidecars_preview_dir" >/dev/null ; then
      log "Dry run done. Generated sidecars are written to: $sidecars_preview_dir.
Generated files:
$(find $sidecars_preview_dir -type f | head -3)
..."
    fi
  fi
}

#
# command line functions
#
cli_print_help() {
    echo
    echo "Immich metadata to sidecar exporter"
    echo
    echo "Writes asset metadata to companion XMP sidecars."
    echo "For more info see https://github.com/skatsubo/immich-metadata-exporter"
    echo
    echo "Usage:"
    echo "  $0                # By default, export metadata for known assets: those that have sidecar path defined in the database"
    echo "  $0 [--args...]    # Export with extra args: asset filter, target (see optinal arguments below)"
    echo "  $0 --help         # Show this help"
    echo
    echo "Optional arguments:"
    echo "  --target { known | unknown | all } Target assets/sidecars to process."
    echo "                                       known:   process assets with existing sidecars (having non-empty 'asset.sidecarPath' in the database)"
    echo "                                       unknown: process assets without sidecars (having empty 'asset.sidecarPath' in the database)"
    echo "                                       all:     process all assets"
    echo "                                     Default: known"
    echo "  --filter <condition>               SQL \"where\" condition to limit which assets' metadata to export."
    echo "                                     It is passed verbatim to the where clause when selecting assets for export: WHERE ... AND <condition>"
    echo "                                     Default: 1=1 (no filtering)"
    echo "  --preview                          Preview (dry run). Generate metadata.json and sidecars but do not write anything to the original location."
    echo "  --debug                            Debug. Print more verbose output."
    echo
    echo "Examples:"
    echo "  $0 --preview"
    echo "  $0 --target all --filter "'"asset.\"createdAt\" >= '"'2025-10-10'"'"'
    echo
}

cli_parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --target)   target="$2"; shift 2 ;;
            --filter)   asset_filter="$2"; shift 2 ;;
            --preview)  preview="true"; shift 1 ;;
            --debug)    debug="true"; shift 1 ;;
            --help|-h)  cli_print_help; exit 0 ;;
            *)          cli_print_help; exit 0 ;;
        esac
    done
    validate_args
}

validate_args() {
  if [[ ! $target =~ ^(known|unknown|all)$ ]]; then 
    log "ERROR Allowed target values: known, unknown, all"
    cli_print_help
    exit 1
  fi 
}

#
# main
#
cli_parse_args "$@"
export_metadata_to_json
handle_sidecars
