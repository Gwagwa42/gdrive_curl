#!/usr/bin/env bash
set -euo pipefail

# gdrive_mkdir.sh - create a Google Drive folder hierarchy from a list of paths.
#
# Thin wrapper around 'gdrive_curl.sh mkdir-tree' that keeps the historical
# command-line contract used by callers such as the Granger intranet:
#
#   gdrive_mkdir.sh -f <paths_file> --parent-id=<folder_id> -v
#
# With -v, each folder is reported as 'Created|Exists: <path> [ID: <id>]' and a
# final 'Done!' line is printed; the exit code is 0 only if every path was
# created or already existed. Run with --help for the full option list.
#
# gdrive_curl.sh is looked up in this order:
#   1. $GDRIVE_CURL (explicit path)
#   2. gdrive_curl.sh next to this script
#   3. gdrive-curl on PATH (as installed by 'make install')
#
# Scope selection follows gdrive_curl.sh: SCOPE_MODE=app|full, or a leading
# --app-only / --full-access flag.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

resolve_gdrive_curl() {
    if [[ -n "${GDRIVE_CURL:-}" ]]; then
        echo "$GDRIVE_CURL"
    elif [[ -x "$SCRIPT_DIR/gdrive_curl.sh" ]]; then
        echo "$SCRIPT_DIR/gdrive_curl.sh"
    elif command -v gdrive-curl >/dev/null 2>&1; then
        command -v gdrive-curl
    else
        echo "gdrive_curl.sh not found (set GDRIVE_CURL or install it next to $0)" >&2
        exit 1
    fi
}

main() {
    local gdrive_curl scope_flag=""
    gdrive_curl=$(resolve_gdrive_curl)

    case "${1:-}" in
        --full-access|--app-only) scope_flag="$1"; shift ;;
    esac

    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        sed -n '4,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        echo
        exec "$gdrive_curl" mkdir-tree --help
    fi

    # shellcheck disable=SC2086
    exec "$gdrive_curl" $scope_flag mkdir-tree "$@"
}

main "$@"
