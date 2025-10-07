#!/usr/bin/env bash
set -euo pipefail

# --- CONFIG ---
# OAuth credentials must be set via environment variables
CLIENT_ID="${CLIENT_ID:-}"
CLIENT_SECRET="${CLIENT_SECRET:-}"

# Scope mode configuration: 'app' for drive.file (default) or 'full' for full drive access
# Can be set via SCOPE_MODE env var or command line flags
SCOPE_MODE="${SCOPE_MODE:-app}"

# Function to configure scope based on mode
configure_scope() {
    if [[ "$SCOPE_MODE" == "full" ]]; then
        SCOPE="${SCOPE:-https://www.googleapis.com/auth/drive}"
        TOKENS_FILE="${TOKENS_FILE:-$HOME/.config/gdrive-curl/tokens-full.json}"
        SCOPE_DESC="Full Google Drive access"
    else
        SCOPE="${SCOPE:-https://www.googleapis.com/auth/drive.file}"
        TOKENS_FILE="${TOKENS_FILE:-$HOME/.config/gdrive-curl/tokens-app.json}"
        SCOPE_DESC="App-created files only"
    fi
    mkdir -p "$(dirname "$TOKENS_FILE")"
}

# Validate credentials are set (except for usage/help display)
validate_credentials() {
    if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
        echo "ERROR: OAuth credentials not configured." >&2
        echo "" >&2
        echo "Please set your Google OAuth credentials:" >&2
        echo "  export CLIENT_ID='your-client-id.apps.googleusercontent.com'" >&2
        echo "  export CLIENT_SECRET='your-client-secret'" >&2
        echo "" >&2
        echo "To create OAuth credentials:" >&2
        echo "  1. Go to https://console.cloud.google.com/" >&2
        echo "  2. Create/select a project and enable Google Drive API" >&2
        echo "  3. Create OAuth 2.0 credentials (TV & Limited Input devices type)" >&2
        echo "  4. Configure OAuth consent screen with Drive API scope" >&2
        echo "" >&2
        echo "For detailed instructions, see README.md" >&2
        exit 1
    fi
}

API_DEV_CODE="https://oauth2.googleapis.com/device/code"
API_TOKEN="https://oauth2.googleapis.com/token"
API_FILES="https://www.googleapis.com/drive/v3/files"
API_UPLOAD="https://www.googleapis.com/upload/drive/v3/files"

require() {
    command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }
}

json_get() {
    # $1: json; $2: jq path
    echo "$1" | jq -r "$2 // empty"
}

save_tokens() {
    mkdir -p "$(dirname "$TOKENS_FILE")"
    echo "$1" | jq '.' > "$TOKENS_FILE"
}

have_tokens() {
    [[ -f "$TOKENS_FILE" ]] && jq -e '.refresh_token and .access_token' "$TOKENS_FILE" >/dev/null 2>&1
}

access_token_fresh() {
    # returns 0 if token is fresh, 1 otherwise
    local now exp
    now=$(date +%s)
    exp=$(jq -r '.obtained_at + .expires_in - 60' "$TOKENS_FILE" 2>/dev/null || echo 0) # 60s skew
    [[ "$now" -lt "$exp" ]]
}

obtain_device_code() {
    local resp encoded_scope
    encoded_scope=$(printf %s "$SCOPE" | jq -s -R -r @uri)

    # Debug output if DEBUG environment variable is set
    if [[ -n "${DEBUG:-}" ]]; then
        echo "DEBUG: Requesting device code from: $API_DEV_CODE" >&2
        echo "DEBUG: CLIENT_ID: $CLIENT_ID" >&2
        echo "DEBUG: SCOPE (encoded): $encoded_scope" >&2
    fi

    resp=$(curl -sS -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=$CLIENT_ID&scope=$encoded_scope" \
        "$API_DEV_CODE")

    # Debug output if DEBUG environment variable is set
    if [[ -n "${DEBUG:-}" ]]; then
        echo "DEBUG: Response from Google:" >&2
        echo "$resp" | jq '.' >&2
    fi

    echo "$resp"
}

poll_for_tokens() {
    local device_code interval started resp err
    device_code="$1"
    interval="$2"
    started=$(date +%s)

    while :; do
        resp=$(curl -sS -X POST \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&device_code=$device_code&grant_type=urn:ietf:params:oauth:grant-type:device_code" \
            "$API_TOKEN")

        err=$(json_get "$resp" '.error')
        if [[ -n "$err" ]]; then
            case "$err" in
                authorization_pending|slow_down)
                    sleep "$interval"
                    continue
                    ;;
                access_denied)
                    echo "Authorization denied." >&2; exit 1;;
                expired_token)
                    echo "Device code expired; run 'init' again." >&2; exit 1;;
                *)
                    echo "OAuth error: $err" >&2; echo "$resp" >&2; exit 1;;
            esac
        fi

        # success
        local now
        now=$(date +%s)
        echo "$resp" | jq --argjson now "$now" '. + {obtained_at: $now}'
        return 0
    done
}

refresh_tokens() {
    local resp now
    resp=$(curl -sS -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&refresh_token=$(jq -r .refresh_token "$TOKENS_FILE")&grant_type=refresh_token" \
        "$API_TOKEN")
    if [[ -n "$(json_get "$resp" '.error')" ]]; then
        echo "Failed to refresh token:" >&2
        echo "$resp" >&2
        exit 1
    fi
    now=$(date +%s)
    new=$(jq --argjson now "$now" \
        --arg rt "$(jq -r .refresh_token "$TOKENS_FILE")" \
        -n \
        --argjson resp "$resp" \
        '$resp + {refresh_token:$rt, obtained_at:$now}')
    save_tokens "$new"
}

ensure_access_token() {
    if ! have_tokens; then
        echo "No tokens. Run: $0 init" >&2
        exit 1
    fi
    if ! access_token_fresh; then
        refresh_tokens
    fi
    jq -r .access_token "$TOKENS_FILE"
}

check_api_error() {
    local resp="$1"
    local operation="${2:-API call}"

    # Check if response contains an error field
    if echo "$resp" | jq -e '.error' >/dev/null 2>&1; then
        local error_msg=$(echo "$resp" | jq -r '.error.message // .error // "Unknown error"')
        local error_code=$(echo "$resp" | jq -r '.error.code // ""')

        echo "Error during $operation:" >&2
        echo "  $error_msg" >&2

        # Provide helpful guidance based on error type
        if [[ "$error_msg" == *"unauthorized"* ]] || [[ "$error_msg" == *"Unauthorized"* ]]; then
            echo "  Try re-authenticating: $0 init" >&2
        elif [[ "$error_msg" == *"insufficient"* ]] || [[ "$error_code" == "403" ]]; then
            echo "  Check permissions for this scope mode: $0 scope" >&2
        fi

        return 1
    fi
    return 0
}

mime_of() {
    file --mime-type -b "$1"
}

filesize_of() {
    # Cross-platform file size detection
    local file="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        stat -f%z "$file"
    else
        stat -c%s "$file"
    fi
}

upload_multipart() {
    local file="$1"; shift
    local name="${1:-$(basename "$file")}"; shift || true
    local parent_id="${1:-}"; shift || true

    local access token mime
    token=$(ensure_access_token)
    mime=$(mime_of "$file")

    local metadata='{"name":"'"$name"'"}'
    if [[ -n "$parent_id" ]]; then
        metadata='{"name":"'"$name"'","parents":["'"$parent_id"'"]}'
    fi

    curl -sS -X POST -L \
        -H "Authorization: Bearer $token" \
        -F "metadata=$metadata;type=application/json; charset=UTF-8" \
        -F "file=@${file};type=${mime}" \
        "$API_UPLOAD?uploadType=multipart&supportsAllDrives=true"
}

upload_resumable() {
    local file="$1"; shift
    local name="${1:-$(basename "$file")}"; shift || true
    local parent_id="${1:-}"; shift || true

    local token mime size init_body session_url
    token=$(ensure_access_token)
    mime=$(mime_of "$file")
    size=$(filesize_of "$file")

    init_body='{"name":"'"$name"'"}'
    if [[ -n "$parent_id" ]]; then
        init_body='{"name":"'"$name"'","parents":["'"$parent_id"'"]}'
    fi

    # 1) Initiate session
    session_url=$(curl -sS -D - -o /dev/null -X POST \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json; charset=UTF-8" \
        -H "X-Upload-Content-Type: $mime" \
        -H "X-Upload-Content-Length: $size" \
        -d "$init_body" \
        "$API_UPLOAD?uploadType=resumable&supportsAllDrives=true" \
        | awk '/^Location:/ {print $2}' | tr -d '\r')

    if [[ -z "$session_url" ]]; then
        echo "Failed to start resumable session" >&2; exit 1
    fi

    # 2) Upload bytes; for simplicity do single PUT (works for most shells)
    curl -sS -X PUT \
        -H "Content-Type: $mime" \
        -H "Content-Length: $size" \
        --data-binary @"$file" \
        "$session_url"
}

list_folder_id_by_name() {
    # Utility: find folder ids by name (returns clean ID list)
    local q name token resp
    name="$1"
    token=$(ensure_access_token)
    q="mimeType='application/vnd.google-apps.folder' and name='$(printf %s "$name" | sed "s/'/\\\'/g")' and trashed=false"
    resp=$(curl -sS -G "$API_FILES" \
        -H "Authorization: Bearer $token" \
        --data-urlencode "q=$q" \
        --data-urlencode "fields=files(id,name)")

    # Check for API errors before parsing
    if ! check_api_error "$resp" "finding folder"; then
        return 1
    fi

    # Parse and display results in a clean format
    echo "$resp" | jq -r '.files[] | "\(.id)\t\(.name)"'
}

download_file() {
    local file_id="$1"
    local output_path="${2:-}"
    local token resp filename
    token=$(ensure_access_token)

    # If no output path specified, get the original filename from Drive
    if [[ -z "$output_path" ]]; then
        resp=$(curl -sS -G "$API_FILES/$file_id" \
            -H "Authorization: Bearer $token" \
            --data-urlencode "fields=name")
        filename=$(echo "$resp" | jq -r '.name // "download"')
        output_path="$filename"
    fi

    # Download the file
    curl -sS -L \
        -H "Authorization: Bearer $token" \
        -o "$output_path" \
        "$API_FILES/$file_id?alt=media&supportsAllDrives=true"

    echo "Downloaded to: $output_path"
}

list_files() {
    local parent_id="${1:-}"
    local page_size="${2:-100}"
    local token q resp next_token
    token=$(ensure_access_token)

    # Build query based on parent folder
    if [[ -n "$parent_id" ]]; then
        q="'$parent_id' in parents and trashed=false"
    else
        q="trashed=false"
    fi

    # Handle pagination - loop until all files retrieved
    next_token=""
    while :; do
        if [[ -n "$next_token" ]]; then
            resp=$(curl -sS -G "$API_FILES" \
                -H "Authorization: Bearer $token" \
                --data-urlencode "q=$q" \
                --data-urlencode "pageSize=$page_size" \
                --data-urlencode "pageToken=$next_token" \
                --data-urlencode "fields=files(id,name,mimeType,size,modifiedTime),nextPageToken" \
                --data-urlencode "orderBy=name")
        else
            resp=$(curl -sS -G "$API_FILES" \
                -H "Authorization: Bearer $token" \
                --data-urlencode "q=$q" \
                --data-urlencode "pageSize=$page_size" \
                --data-urlencode "fields=files(id,name,mimeType,size,modifiedTime),nextPageToken" \
                --data-urlencode "orderBy=name")
        fi

        # Check for API errors before parsing
        if ! check_api_error "$resp" "listing files"; then
            return 1
        fi

        # Display results in clean format
        echo "$resp" | jq -r '.files[] | "\(.id)\t\(.name)\t\(.mimeType)\t\(.size // "N/A")\t\(.modifiedTime)"'

        # Check for next page
        next_token=$(echo "$resp" | jq -r '.nextPageToken // empty')
        [[ -z "$next_token" ]] && break
    done
}

delete_file() {
    local file_id="$1"
    local token
    token=$(ensure_access_token)

    curl -sS -X DELETE \
        -H "Authorization: Bearer $token" \
        "$API_FILES/$file_id?supportsAllDrives=true"

    echo "File $file_id permanently deleted"
}

trash_file() {
    local file_id="$1"
    local token
    token=$(ensure_access_token)

    curl -sS -X PATCH \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d '{"trashed": true}' \
        "$API_FILES/$file_id?supportsAllDrives=true"

    echo "File $file_id moved to trash"
}

get_file_info() {
    local file_id="$1"
    local token resp
    token=$(ensure_access_token)

    resp=$(curl -sS -G "$API_FILES/$file_id" \
        -H "Authorization: Bearer $token" \
        --data-urlencode "fields=id,name,mimeType,size,createdTime,modifiedTime,owners,parents,webViewLink,trashed" \
        --data-urlencode "supportsAllDrives=true")

    echo "$resp" | jq '.'
}

create_folder() {
    local name="$1"
    local parent_id="${2:-}"
    local token metadata
    token=$(ensure_access_token)

    metadata='{"name":"'"$name"'","mimeType":"application/vnd.google-apps.folder"}'
    if [[ -n "$parent_id" ]]; then
        metadata='{"name":"'"$name"'","mimeType":"application/vnd.google-apps.folder","parents":["'"$parent_id"'"]}'
    fi

    curl -sS -X POST \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$metadata" \
        "$API_FILES?supportsAllDrives=true"
}

rename_file() {
    local file_id="$1"
    local new_name="$2"
    local token
    token=$(ensure_access_token)

    curl -sS -X PATCH \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d '{"name":"'"$new_name"'"}' \
        "$API_FILES/$file_id?supportsAllDrives=true"
}

move_file() {
    local file_id="$1"
    local new_parent_id="$2"
    local token resp old_parents
    token=$(ensure_access_token)

    # Get current parents
    resp=$(curl -sS -G "$API_FILES/$file_id" \
        -H "Authorization: Bearer $token" \
        --data-urlencode "fields=parents")
    old_parents=$(echo "$resp" | jq -r '.parents | join(",")')

    # Move file by removing old parents and adding new parent
    curl -sS -X PATCH \
        -H "Authorization: Bearer $token" \
        "$API_FILES/$file_id?addParents=$new_parent_id&removeParents=$old_parents&supportsAllDrives=true"
}

copy_file() {
    local file_id="$1"
    local new_name="${2:-}"
    local parent_id="${3:-}"
    local token metadata
    token=$(ensure_access_token)

    metadata='{}'
    if [[ -n "$new_name" ]]; then
        metadata='{"name":"'"$new_name"'"}'
    fi
    if [[ -n "$parent_id" ]]; then
        metadata=$(echo "$metadata" | jq --arg pid "$parent_id" '. + {parents: [$pid]}')
    fi

    curl -sS -X POST \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$metadata" \
        "$API_FILES/$file_id/copy?supportsAllDrives=true"
}

update_file() {
    local file_id="$1"
    local local_file="$2"
    local token mime size
    token=$(ensure_access_token)
    mime=$(mime_of "$local_file")
    size=$(filesize_of "$local_file")

    # Use simple upload for updates
    curl -sS -X PATCH \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: $mime" \
        -H "Content-Length: $size" \
        --data-binary @"$local_file" \
        "$API_UPLOAD/$file_id?uploadType=media&supportsAllDrives=true"
}

restore_file() {
    local file_id="$1"
    local token
    token=$(ensure_access_token)

    curl -sS -X PATCH \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d '{"trashed": false}' \
        "$API_FILES/$file_id?supportsAllDrives=true"

    echo "File $file_id restored from trash"
}

share_file() {
    local file_id="$1"
    local role="${2:-reader}"  # reader, writer, commenter
    local token resp
    token=$(ensure_access_token)

    # Validate role
    case "$role" in
        reader|writer|commenter) ;;
        *) echo "Invalid role: $role (use reader, writer, or commenter)" >&2; exit 1;;
    esac

    # Create permission for anyone with the link
    resp=$(curl -sS -X POST \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d '{"role":"'"$role"'","type":"anyone"}' \
        "$API_FILES/$file_id/permissions?supportsAllDrives=true")

    # Check for errors
    if echo "$resp" | jq -e '.error' >/dev/null 2>&1; then
        echo "Error creating share link:" >&2
        echo "$resp" | jq '.error.message' >&2
        exit 1
    fi

    # Get and display the shareable link
    link=$(curl -sS -G "$API_FILES/$file_id" \
        -H "Authorization: Bearer $token" \
        --data-urlencode "fields=webViewLink" | jq -r '.webViewLink')

    echo "Share link created with $role permission:"
    echo "$link"
}

export_file() {
    local file_id="$1"
    local format="$2"
    local output="${3:-}"
    local token export_mime
    token=$(ensure_access_token)

    # Map format to MIME type for Google Workspace exports
    case "$format" in
        # Google Docs exports
        pdf) export_mime="application/pdf";;
        docx) export_mime="application/vnd.openxmlformats-officedocument.wordprocessingml.document";;
        txt) export_mime="text/plain";;
        html) export_mime="text/html";;
        rtf) export_mime="application/rtf";;
        odt) export_mime="application/vnd.oasis.opendocument.text";;

        # Google Sheets exports
        xlsx) export_mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";;
        csv) export_mime="text/csv";;
        ods) export_mime="application/vnd.oasis.opendocument.spreadsheet";;
        tsv) export_mime="text/tab-separated-values";;

        # Google Slides exports
        pptx) export_mime="application/vnd.openxmlformats-officedocument.presentationml.presentation";;
        odp) export_mime="application/vnd.oasis.opendocument.presentation";;

        *) echo "Unsupported format: $format" >&2
           echo "Supported: pdf, docx, txt, html, rtf, odt, xlsx, csv, ods, tsv, pptx, odp" >&2
           exit 1;;
    esac

    # If no output path specified, use file_id.format
    if [[ -z "$output" ]]; then
        output="${file_id}.${format}"
    fi

    # Export the file
    curl -sS -L \
        -H "Authorization: Bearer $token" \
        -o "$output" \
        "$API_FILES/$file_id/export?mimeType=$(printf %s "$export_mime" | jq -s -R -r @uri)"

    echo "Exported to: $output"
}

search_files() {
    local query="$1"
    local page_size="${2:-100}"
    local token resp
    token=$(ensure_access_token)

    # Perform search query
    resp=$(curl -sS -G "$API_FILES" \
        -H "Authorization: Bearer $token" \
        --data-urlencode "q=$query" \
        --data-urlencode "pageSize=$page_size" \
        --data-urlencode "fields=files(id,name,mimeType,size,modifiedTime),nextPageToken" \
        --data-urlencode "orderBy=modifiedTime desc")

    # Check for API errors before parsing
    if ! check_api_error "$resp" "searching files"; then
        return 1
    fi

    # Display results in tab-separated format
    echo "$resp" | jq -r '.files[] | "\(.id)\t\(.name)\t\(.mimeType)\t\(.size // "N/A")\t\(.modifiedTime)"'
}

get_quota() {
    local token resp used total percent used_hr total_hr
    token=$(ensure_access_token)

    # Get storage quota information
    resp=$(curl -sS -G "https://www.googleapis.com/drive/v3/about" \
        -H "Authorization: Bearer $token" \
        --data-urlencode "fields=storageQuota,user")

    # Parse storage quota (bytes)
    used=$(echo "$resp" | jq -r '.storageQuota.usage // 0')
    total=$(echo "$resp" | jq -r '.storageQuota.limit // 0')

    # Convert to human-readable format
    used_hr=$(numfmt --to=iec-i --suffix=B "$used" 2>/dev/null || echo "$used bytes")
    total_hr=$(numfmt --to=iec-i --suffix=B "$total" 2>/dev/null || echo "$total bytes")

    # Calculate percentage
    if [[ "$total" -gt 0 ]]; then
        percent=$(awk -v u="$used" -v t="$total" 'BEGIN {printf "%.1f", (u/t)*100}')
    else
        percent="N/A"
    fi

    echo "Storage: $used_hr used of $total_hr ($percent%)"
}

list_permissions() {
    local file_id="$1"
    local token resp
    token=$(ensure_access_token)

    # Get permissions for the file
    resp=$(curl -sS -G "$API_FILES/$file_id/permissions" \
        -H "Authorization: Bearer $token" \
        --data-urlencode "fields=permissions(id,type,role,emailAddress,displayName)")

    # Display permissions in tab-separated format
    echo "$resp" | jq -r '.permissions[] | "\(.id)\t\(.type)\t\(.role)\t\(.emailAddress // .displayName // "anyone")"'
}

list_trash() {
    local page_size="${1:-100}"
    local token resp next_token
    token=$(ensure_access_token)

    # Handle pagination for trash listing
    next_token=""
    while :; do
        if [[ -n "$next_token" ]]; then
            resp=$(curl -sS -G "$API_FILES" \
                -H "Authorization: Bearer $token" \
                --data-urlencode "q=trashed=true" \
                --data-urlencode "pageSize=$page_size" \
                --data-urlencode "pageToken=$next_token" \
                --data-urlencode "fields=files(id,name,mimeType,trashedTime),nextPageToken")
        else
            resp=$(curl -sS -G "$API_FILES" \
                -H "Authorization: Bearer $token" \
                --data-urlencode "q=trashed=true" \
                --data-urlencode "pageSize=$page_size" \
                --data-urlencode "fields=files(id,name,mimeType,trashedTime),nextPageToken")
        fi

        # Check for API errors before parsing
        if ! check_api_error "$resp" "listing trash"; then
            return 1
        fi

        # Display trashed files in tab-separated format
        echo "$resp" | jq -r '.files[] | "\(.id)\t\(.name)\t\(.mimeType)\t\(.trashedTime)"'

        # Check for next page
        next_token=$(echo "$resp" | jq -r '.nextPageToken // empty')
        [[ -z "$next_token" ]] && break
    done
}

star_file() {
    local file_id="$1"
    local token
    token=$(ensure_access_token)

    curl -sS -X PATCH \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d '{"starred": true}' \
        "$API_FILES/$file_id?supportsAllDrives=true"

    echo "File $file_id starred"
}

unstar_file() {
    local file_id="$1"
    local token
    token=$(ensure_access_token)

    curl -sS -X PATCH \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d '{"starred": false}' \
        "$API_FILES/$file_id?supportsAllDrives=true"

    echo "File $file_id unstarred"
}

delete_permission() {
    local file_id="$1"
    local permission_id="$2"
    local token
    token=$(ensure_access_token)

    curl -sS -X DELETE \
        -H "Authorization: Bearer $token" \
        "$API_FILES/$file_id/permissions/$permission_id"

    echo "Permission $permission_id deleted"
}

update_permission() {
    local file_id="$1"
    local permission_id="$2"
    local new_role="$3"
    local token
    token=$(ensure_access_token)

    # Validate role
    case "$new_role" in
        reader|writer|commenter) ;;
        *) echo "Invalid role: $new_role (use reader, writer, or commenter)" >&2; exit 1;;
    esac

    curl -sS -X PATCH \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d '{"role": "'"$new_role"'"}' \
        "$API_FILES/$file_id/permissions/$permission_id"

    echo "Permission $permission_id updated to $new_role"
}

list_revisions() {
    local file_id="$1"
    local token resp
    token=$(ensure_access_token)

    # Get revision history
    resp=$(curl -sS -G "$API_FILES/$file_id/revisions" \
        -H "Authorization: Bearer $token" \
        --data-urlencode "fields=revisions(id,modifiedTime,lastModifyingUser)")

    # Display revisions in tab-separated format
    echo "$resp" | jq -r '.revisions[] | "\(.id)\t\(.modifiedTime)\t\(.lastModifyingUser.displayName // .lastModifyingUser.emailAddress // "unknown")"'
}

get_revision() {
    local file_id="$1"
    local revision_id="$2"
    local output="${3:-}"
    local token filename
    token=$(ensure_access_token)

    # If no output path specified, get original filename and append revision ID
    if [[ -z "$output" ]]; then
        filename=$(curl -sS -G "$API_FILES/$file_id" \
            -H "Authorization: Bearer $token" \
            --data-urlencode "fields=name" | jq -r '.name')

        # Handle files with extension
        if [[ "$filename" == *.* ]]; then
            output="${filename%.*}_rev${revision_id}.${filename##*.}"
        else
            output="${filename}_rev${revision_id}"
        fi
    fi

    # Download the revision
    curl -sS -L \
        -H "Authorization: Bearer $token" \
        -o "$output" \
        "$API_FILES/$file_id/revisions/$revision_id?alt=media"

    echo "Downloaded revision to: $output"
}

get_starred() {
    local page_size="${1:-100}"
    local token resp next_token
    token=$(ensure_access_token)

    # Handle pagination for starred files
    next_token=""
    while :; do
        if [[ -n "$next_token" ]]; then
            resp=$(curl -sS -G "$API_FILES" \
                -H "Authorization: Bearer $token" \
                --data-urlencode "q=starred=true and trashed=false" \
                --data-urlencode "pageSize=$page_size" \
                --data-urlencode "pageToken=$next_token" \
                --data-urlencode "fields=files(id,name,mimeType,modifiedTime),nextPageToken")
        else
            resp=$(curl -sS -G "$API_FILES" \
                -H "Authorization: Bearer $token" \
                --data-urlencode "q=starred=true and trashed=false" \
                --data-urlencode "pageSize=$page_size" \
                --data-urlencode "fields=files(id,name,mimeType,modifiedTime),nextPageToken")
        fi

        # Check for API errors before parsing
        if ! check_api_error "$resp" "listing starred files"; then
            return 1
        fi

        # Display starred files in tab-separated format
        echo "$resp" | jq -r '.files[] | "\(.id)\t\(.name)\t\(.mimeType)\t\(.modifiedTime)"'

        # Check for next page
        next_token=$(echo "$resp" | jq -r '.nextPageToken // empty')
        [[ -z "$next_token" ]] && break
    done
}

show_scope_info() {
    echo "Current scope configuration:"
    echo "  Mode: $SCOPE_MODE"
    echo "  Description: $SCOPE_DESC"
    echo "  Scope URL: $SCOPE"
    echo "  Token file: $TOKENS_FILE"
    echo ""

    if have_tokens && access_token_fresh; then
        echo "Status: Authenticated ✓"
    elif have_tokens; then
        echo "Status: Token expired (run any command to auto-refresh)"
    else
        echo "Status: Not authenticated (run 'init' to authenticate)"
    fi

    echo ""
    echo "Usage:"
    if [[ "$SCOPE_MODE" == "app" ]]; then
        echo "  Current mode (app-only) can only access files created by this app."
        echo "  To access all Drive files, use: $0 --full-access <command>"
    else
        echo "  Current mode (full access) can access all files in your Drive."
        echo "  For restricted access, use: $0 --app-only <command>"
    fi
}

init_flow() {
    echo "Starting OAuth 2.0 device flow..."
    echo "Scope: $SCOPE_DESC ($SCOPE_MODE mode)"
    echo ""
    local dev resp user_code ver_url interval device_code
    dev=$(obtain_device_code)

    # Check for error in the response
    if [[ -n "$(json_get "$dev" '.error')" ]]; then
        local error_code error_desc
        error_code=$(json_get "$dev" '.error')
        error_desc=$(json_get "$dev" '.error_description')

        echo "Failed to obtain device code from Google:" >&2
        echo "Error: $error_code" >&2
        echo "Description: $error_desc" >&2
        echo >&2

        case "$error_code" in
            invalid_scope)
                echo "The OAuth client doesn't support the requested scope for device flow." >&2
                echo "Solutions:" >&2
                echo "  1. Use your own OAuth client ID that supports the Drive scope" >&2
                echo "  2. Configure the OAuth consent screen to include Drive API scopes" >&2
                echo "  3. Verify the client type supports device flow (TV & Limited Input)" >&2
                ;;
            invalid_client)
                echo "The CLIENT_ID is invalid or not found." >&2
                echo "Solutions:" >&2
                echo "  1. Check that CLIENT_ID is correct" >&2
                echo "  2. Ensure the OAuth client hasn't been deleted" >&2
                echo "  3. Create a new OAuth client in Google Cloud Console" >&2
                ;;
            *)
                echo "Possible causes:" >&2
                echo "  1. Invalid CLIENT_ID or CLIENT_SECRET" >&2
                echo "  2. Google Drive API not enabled in Google Cloud Console" >&2
                echo "  3. OAuth consent screen not configured" >&2
                ;;
        esac

        echo >&2
        echo "To use your own OAuth credentials, set:" >&2
        echo "  export CLIENT_ID='your-client-id.apps.googleusercontent.com'" >&2
        echo "  export CLIENT_SECRET='your-client-secret'" >&2
        exit 1
    fi

    user_code=$(json_get "$dev" '.user_code')
    ver_url=$(json_get "$dev" '.verification_url')
    interval=$(json_get "$dev" '.interval')
    device_code=$(json_get "$dev" '.device_code')

    # Validate required fields
    if [[ -z "$user_code" || -z "$ver_url" || -z "$device_code" ]]; then
        echo "Error: Invalid response from Google OAuth endpoint" >&2
        echo "Response received:" >&2
        echo "$dev" | jq '.' >&2
        echo >&2
        echo "Expected fields: user_code, verification_url, device_code" >&2
        exit 1
    fi

    echo
    echo "1) Visit: $ver_url"
    echo "2) Enter code: $user_code"
    echo "Waiting for approval..."
    echo

    resp=$(poll_for_tokens "$device_code" "${interval:-5}")
    save_tokens "$resp"

    # Make sure we keep the refresh_token if present; some accounts return it on first consent only.
    if [[ -z "$(json_get "$resp" '.refresh_token')" ]]; then
        echo "NOTE: No refresh_token returned. If this is a re-consent, revoke the app in https://myaccount.google.com/permissions and run init again." >&2
    fi

    echo "✅ Auth complete. Tokens saved to $TOKENS_FILE"
}

usage() {
    cat <<EOF
Usage: $0 [--full-access|--app-only] <command> [arguments]

SCOPE FLAGS (optional, must be first):
  --full-access                     Use full Drive access (all files)
  --app-only                        Use restricted access (app-created files only)

AUTHENTICATION & INFO:
  init                              Start OAuth device flow and save tokens
  scope                             Show current scope configuration and status

FILE UPLOAD:
  upload <file> [name] [parent_id]  Upload file (multipart, <= 5MB recommended)
  upload-big <file> [name] [parent_id]  Upload large file (resumable)
  update <file_id> <local_file>     Update existing file content

FILE DOWNLOAD:
  download <file_id> [output_path]  Download file by ID (auto-detects name if no path)

FILE MANAGEMENT:
  list [parent_id] [page_size]      List files (default: all files, page_size=100)
  info <file_id>                    Get detailed file metadata
  rename <file_id> <new_name>       Rename file or folder
  move <file_id> <new_parent_id>    Move file to different folder
  copy <file_id> [new_name] [parent_id]  Copy file
  trash <file_id>                   Move file to trash (soft delete)
  restore <file_id>                 Restore file from trash
  delete <file_id>                  Permanently delete file

FOLDER OPERATIONS:
  create-folder <name> [parent_id]  Create new folder
  find-folder "<name>"              Find folder IDs by name

SHARING & COLLABORATION:
  share <file_id> [role]            Create shareable link (role: reader/writer/commenter, default: reader)

SEARCH & DISCOVERY:
  search "<query>" [page_size]      Advanced search with Drive API query syntax

EXPORT:
  export <file_id> <format> [output]  Export Google Workspace files
                                      Formats: pdf, docx, txt, html, xlsx, csv, pptx

QUOTA & STORAGE:
  quota                               Show storage quota usage

PERMISSION MANAGEMENT:
  list-permissions <file_id>         List all permissions on a file
  delete-permission <file_id> <perm_id>  Revoke specific permission
  update-permission <file_id> <perm_id> <role>  Update permission role (reader/writer/commenter)

TRASH MANAGEMENT:
  list-trash [page_size]             List files in trash

STAR MANAGEMENT:
  star <file_id>                     Mark file as starred
  unstar <file_id>                   Remove star from file
  get-starred [page_size]            List all starred files

VERSION HISTORY:
  list-revisions <file_id>           List file revision history
  get-revision <file_id> <rev_id> [output]  Download specific file revision

ENVIRONMENT VARIABLES:
  CLIENT_ID          OAuth client ID (has default)
  CLIENT_SECRET      OAuth client secret (has default)
  SCOPE              OAuth scope (default: drive = full access)
  TOKENS_FILE        Token storage path (default: ~/.config/gdrive-curl/tokens.json)

EXAMPLES:
  $0 init                           # First-time setup
  $0 list                           # List all files
  $0 upload photo.jpg               # Upload file
  $0 download abc123 photo.jpg      # Download file
  $0 create-folder "My Folder"      # Create folder
  $0 find-folder "My Folder"        # Get folder ID
  $0 upload doc.pdf "" folder_id    # Upload to specific folder
  $0 share abc123 reader            # Create shareable view link
  $0 search "name contains 'tax' and mimeType='application/pdf'"  # Find PDFs with "tax" in name
  $0 export doc_id pdf report.pdf   # Export Google Doc to PDF
  $0 quota                          # Check storage usage
  $0 list-permissions abc123         # See who has access
  $0 star abc123                    # Star important file
  $0 get-starred                    # List starred files
  $0 list-trash                     # View trash contents
  $0 list-revisions abc123          # See file history

SCOPE EXAMPLES:
  $0 scope                          # Check current scope mode
  $0 --full-access list             # List all Drive files (full access)
  $0 --app-only upload file.txt     # Upload with app-only access
  SCOPE_MODE=full $0 init           # Initialize with full access via env var
EOF
}

main() {
    require curl
    require jq
    require file

    # Parse scope flags if present (must be first argument)
    if [[ "${1:-}" == "--full-access" ]]; then
        SCOPE_MODE="full"
        shift
    elif [[ "${1:-}" == "--app-only" ]]; then
        SCOPE_MODE="app"
        shift
    fi

    # Configure scope based on mode
    configure_scope

    local cmd="${1:-}"; shift || true

    # Check if command requires authentication (all except help, scope, and empty)
    case "$cmd" in
        -h|--help|help|scope|"")
            # Don't validate credentials for help, scope info, or empty command
            ;;
        *)
            # Validate credentials for all commands that interact with Google Drive
            validate_credentials
            ;;
    esac

    # Handle empty command
    [[ -z "$cmd" ]] && { usage; exit 1; }

    case "$cmd" in
        # Authentication & Info
        init) init_flow ;;
        scope) show_scope_info ;;

        # File Upload
        upload) [[ $# -ge 1 ]] || { usage; exit 1; }; upload_multipart "$@" ;;
        upload-big) [[ $# -ge 1 ]] || { usage; exit 1; }; upload_resumable "$@" ;;
        update) [[ $# -ge 2 ]] || { usage; exit 1; }; update_file "$@" ;;

        # File Download
        download) [[ $# -ge 1 ]] || { usage; exit 1; }; download_file "$@" ;;

        # File Management
        list) list_files "$@" ;;
        info) [[ $# -ge 1 ]] || { usage; exit 1; }; get_file_info "$1" ;;
        rename) [[ $# -ge 2 ]] || { usage; exit 1; }; rename_file "$1" "$2" ;;
        move) [[ $# -ge 2 ]] || { usage; exit 1; }; move_file "$1" "$2" ;;
        copy) [[ $# -ge 1 ]] || { usage; exit 1; }; copy_file "$@" ;;
        trash) [[ $# -ge 1 ]] || { usage; exit 1; }; trash_file "$1" ;;
        restore) [[ $# -ge 1 ]] || { usage; exit 1; }; restore_file "$1" ;;
        delete) [[ $# -ge 1 ]] || { usage; exit 1; }; delete_file "$1" ;;

        # Folder Operations
        create-folder) [[ $# -ge 1 ]] || { usage; exit 1; }; create_folder "$@" ;;
        find-folder) [[ $# -ge 1 ]] || { usage; exit 1; }; list_folder_id_by_name "$1" ;;

        # Sharing & Collaboration
        share) [[ $# -ge 1 ]] || { usage; exit 1; }; share_file "$@" ;;

        # Search & Discovery
        search) [[ $# -ge 1 ]] || { usage; exit 1; }; search_files "$@" ;;

        # Export
        export) [[ $# -ge 2 ]] || { usage; exit 1; }; export_file "$@" ;;

        # Quota & Storage
        quota) get_quota ;;

        # Permission Management
        list-permissions) [[ $# -ge 1 ]] || { usage; exit 1; }; list_permissions "$1" ;;
        delete-permission) [[ $# -ge 2 ]] || { usage; exit 1; }; delete_permission "$1" "$2" ;;
        update-permission) [[ $# -ge 3 ]] || { usage; exit 1; }; update_permission "$1" "$2" "$3" ;;

        # Trash Management
        list-trash) list_trash "$@" ;;

        # Star Management
        star) [[ $# -ge 1 ]] || { usage; exit 1; }; star_file "$1" ;;
        unstar) [[ $# -ge 1 ]] || { usage; exit 1; }; unstar_file "$1" ;;
        get-starred) get_starred "$@" ;;

        # Version History
        list-revisions) [[ $# -ge 1 ]] || { usage; exit 1; }; list_revisions "$1" ;;
        get-revision) [[ $# -ge 2 ]] || { usage; exit 1; }; get_revision "$@" ;;

        # Help/Unknown
        -h|--help|help) usage ;;
        *) echo "Unknown command: $cmd" >&2; echo; usage; exit 1 ;;
    esac
}

main "$@"

