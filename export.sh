#!/usr/bin/env bash

set -e
set -u
set -o pipefail

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

# export (write to) known sidecars or all sidecars
target=known

#
# vars
#
immich_container=immich_server
postgres_container=immich_postgres
postgres_user=postgres
postgres_db=immich

metadata_json_file="metadata.json"

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
  docker exec -i "$immich_container" "$@"
}

install_tools() {
  packages="libimage-exiftool-perl jq"
  if ! immich_cmd dpkg -s $packages &>/dev/null; then
    log "Install tools: $packages"
    # immich_cmd bash <<< 'apt-get update -qq && apt-get install -yqq --no-install-recommends $packages &>/dev/null || echo "apt install error: exit $?"'
    immich_cmd bash <<< "apt-get update -qq ; apt-get install -yqq --no-install-recommends $packages || echo apt install error: exit $?"
  fi
}

export_json() {
  log "Export metadata to json: $metadata_json_file"

  query_metadata_json_file=metadata.sql
#   query_metadata_json=$(cat <<'EOF'
#     select '{"assetIds": [' || string_agg('"' || id::text || '"', ', ') || ']}' 
#     from (select * from asset_id limit (:uuid_count)) t
# EOF
#   )
  psql_cmd -Aq -v target="$target" -v asset_filter="$asset_filter" <"$query_metadata_json_file" > "$metadata_json_file"
}

print_sidecars() {
  log "Print existing sidecars"
  immich_cmd sh -c 'jq -r ".[].SourceFile" | exiftool -json -@ -' <"$metadata_json_file"
}

write_sidecar() {
  log "Write (create/update) sidecars"
  immich_cmd sh -c 'tee /tmp/metadata.json | jq -r ".[].SourceFile" | exiftool -json=/tmp/metadata.json -@ -' <"$metadata_json_file"
  # longer version of the above
  # docker cp "$metadata_json_file" "$immich_container:/tmp/$metadata_json_file"
  # immich_cmd sh -c "jq -r '.[].SourceFile' /tmp/$metadata_json_file | exiftool -json=/tmp/$metadata_json_file -overwrite_original -@ -"
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
    echo "  --target { known | all } Target assets/sidecars to process."
    echo "                             known: process assets with existing sidecars (having non-empty 'asset.sidecarPath' in the database)"
    echo "                             all:   process all assets"
    echo "                           Default: known"
    echo "  --filter <condition>     SQL \"where\" condition to limit which assets' metadata to export."
    echo "                           It is passed verbatim to the where clause when selecting assets for export: WHERE ... AND <condition>"
    echo "                           Default: 1=1 (no filtering)"
    # echo "  --output-dir             Output directory for writing sidecars. Same directory structure will be created; original paths will be 'rebased' into this directory."
    echo "  --dry-run                Dry run. Generate metadata.json but do not invoke exiftool to write sidecars."
    echo
    echo "Examples:"
    echo "  $0 --target all --filter "'"asset.\"createdAt\" >= '"'2025-10-10'"'" --dry-run'
    echo
}

cli_parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --target)     if [[ $2 == "known" ]] || [[ $2 == "all" ]]; then 
                            target="$2"; shift 2
                          else 
                            log "ERROR Allowed target values: all, known." ; cli_print_help; exit 1
                          fi 
                          ;;
            --filter)     asset_filter="$2"; shift 2 ;;
            # --output-dir) output_dir="$2"; shift 2 ;;
            --dry-run)    dry_run="true"; shift 1 ;;
            --help|-h)    cli_print_help; exit 0 ;;
            *)            cli_print_help; exit 0 ;;
        esac
    done
}

#
# main
#
cli_parse_args "$@"
install_tools
export_json
# sidecars before
if [[ -n "${DEBUG:-}" ]] ; then print_sidecars ; fi

if [[ -z "${dry_run:-}" ]]; then
  write_sidecar
else
  log "Dry run: done."
  exit 0
fi

# sidecars after
if [[ -n "${DEBUG:-}" ]] ; then print_sidecars ; fi
