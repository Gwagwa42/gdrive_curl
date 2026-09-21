#!/usr/bin/env bash
set -euo pipefail

# mkdir-tree tests that run WITHOUT network or credentials.
# A fake 'curl' (tests/stubs/curl) emulates the Drive API with on-disk state,
# so idempotence, caching, retries and output formats can be checked anywhere.

# No Drive cleanup needed: nothing real is created
export TEST_CLEANUP=0
source "$(dirname "$0")/test_helpers.sh"

STUBS_DIR="$SCRIPT_DIR/stubs"
WRAPPER_SCRIPT="$PROJECT_ROOT/gdrive_mkdir.sh"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

export STUB_STATE_DIR="$SANDBOX/state"
export HOME="$SANDBOX/home"
export TOKENS_FILE="$SANDBOX/tokens.json"
export CLIENT_ID="stub-client-id"
export CLIENT_SECRET="stub-client-secret"
export PATH="$STUBS_DIR:$PATH"
export GDRIVE_RETRY_DELAY=0

# A never-expiring token so ensure_access_token never tries to refresh
jq -n --argjson now "$(date +%s)" \
    '{access_token: "stub-token", refresh_token: "stub-refresh", expires_in: 999999, obtained_at: $now}' \
    > "$TOKENS_FILE"

reset_state() {
    rm -rf "$STUB_STATE_DIR"
    mkdir -p "$STUB_STATE_DIR" "$HOME"
}

folder_count() {
    wc -l < "$STUB_STATE_DIR/folders.tsv" | tr -d ' '
}

count_requests() {
    # $1: prefix such as "GET" or "POST"
    grep -c "^$1 " "$STUB_STATE_DIR/requests.log" || true
}

mk() {
    # Run mkdir-tree (callers redirect stderr as needed)
    "$GDRIVE_SCRIPT" --app-only mkdir-tree "$@"
}

# Paths shaped like the Granger driver folder structure (parents listed first)
write_driver_paths() {
    local file="$1" base="1010042 DUPONT Jean - 1850112345678"
    {
        echo "$base"
        for sub in "1 - dossier permanent" "2 - frais" "3 - medecine du travail"; do
            echo "$base/1010042$sub"
        done
        echo "$base/10100421 - dossier permanent/10100421 - pieces administratives"
        echo "$base/10100421 - dossier permanent/10100422 - contrat de travail et avenants"
    } > "$file"
}

test_creates_full_tree() {
    # Test: Creates every folder of a paths file under the parent (verbose format)
    reset_state
    local paths="$SANDBOX/driver.txt" output
    write_driver_paths "$paths"

    output=$(mk -f "$paths" --parent-id=rootfolder -v)

    assert_equals "6" "$(folder_count)" "Six folders created"
    assert_contains "$output" "Created: 1010042 DUPONT Jean - 1850112345678 [ID: stub1]" "Root folder reported with ID"
    assert_contains "$output" "Done! 6 folder(s) created, 0 already existed" "Done! summary printed"
    assert_equals "rootfolder" "$(awk -F'\t' '$1=="stub1"{print $2}' "$STUB_STATE_DIR/folders.tsv")" "Root folder is under --parent-id"
    assert_equals "stub1" "$(awk -F'\t' '$1=="stub2"{print $2}' "$STUB_STATE_DIR/folders.tsv")" "Sub folder is under root folder"

    # Contract relied upon by the intranet caller: first '1 - dossier permanent' line carries the folder ID
    local permanent_id
    permanent_id=$(echo "$output" | sed -n 's/.*1 - dossier permanent[^[]*\[ID: \([A-Za-z0-9_-]*\)\].*/\1/p' | head -n1)
    assert_equals "stub2" "$permanent_id" "Dossier permanent ID is extractable"
}

test_rerun_is_idempotent() {
    # Test: Running twice reuses every folder and creates nothing
    reset_state
    local paths="$SANDBOX/driver.txt" output
    write_driver_paths "$paths"
    mk -f "$paths" --parent-id=rootfolder -v >/dev/null

    output=$(mk -f "$paths" --parent-id=rootfolder -v)

    assert_equals "6" "$(folder_count)" "No duplicate folders"
    assert_contains "$output" "Exists: 1010042 DUPONT Jean - 1850112345678 [ID: stub1]" "Existing folder reported with its ID"
    assert_contains "$output" "Done! 0 folder(s) created, 6 already existed" "Summary counts existing folders"
    if [[ "$output" == *"Created:"* ]]; then
        fail "Rerun should not create anything"
    else
        pass "Rerun created nothing"
    fi
}

test_rerun_creates_only_missing() {
    # Test: Missing folders are created, existing ones kept
    reset_state
    local paths="$SANDBOX/driver.txt" output
    write_driver_paths "$paths"
    mk -f "$paths" --parent-id=rootfolder -v >/dev/null
    # Simulate two folders deleted in Drive
    sed -i '/2 - frais/d; /contrat de travail/d' "$STUB_STATE_DIR/folders.tsv"

    output=$(mk -f "$paths" --parent-id=rootfolder -v)

    assert_equals "6" "$(folder_count)" "Tree complete again"
    assert_contains "$output" "Done! 2 folder(s) created, 4 already existed" "Only the two missing folders were created"
    assert_contains "$output" "Created: 1010042 DUPONT Jean - 1850112345678/10100422 - frais" "Missing sub folder created"
}

test_implicit_parents() {
    # Test: A single deep path creates intermediate folders (mkdir -p)
    reset_state
    local output
    output=$(mk --parent-id=p "a/b/c")

    assert_equals "3" "$(folder_count)" "Three levels created"
    assert_equals $'stub1\ta\nstub2\ta/b\nstub3\ta/b/c' "$output" "Default output is id<TAB>path per segment"
}

test_prefix_cache() {
    # Test: Shared prefixes are resolved once per run
    reset_state
    mk --parent-id=p "a/b" "a/c" "a/b/d" >/dev/null

    assert_equals "4" "$(folder_count)" "a, a/b, a/c, a/b/d created"
    assert_equals "4" "$(count_requests GET)" "One lookup per distinct folder"
    assert_equals "4" "$(count_requests POST)" "One creation per distinct folder"
}

test_json_output() {
    # Test: --json prints a machine-readable array, verbose goes to stderr
    reset_state
    local stdout stderr
    stdout=$(mk --parent-id=p --json -v "x/y" 2>"$SANDBOX/stderr")
    stderr=$(cat "$SANDBOX/stderr")

    assert_equals "2" "$(echo "$stdout" | jq 'length')" "Two entries"
    assert_equals "x/y" "$(echo "$stdout" | jq -r '.[1].path')" "Path recorded"
    assert_equals "stub1" "$(echo "$stdout" | jq -r '.[1].parent_id')" "Parent ID recorded"
    assert_equals "true" "$(echo "$stdout" | jq -r '.[0].created')" "created flag set"
    assert_contains "$stderr" "Done!" "Verbose summary on stderr"

    stdout=$(mk --parent-id=p --json "x/y" 2>/dev/null)
    assert_equals "false" "$(echo "$stdout" | jq -r '.[0].created')" "created=false on rerun"
}

test_dry_run() {
    # Test: --dry-run resolves but never creates
    reset_state
    mk --parent-id=p "a" >/dev/null
    : > "$STUB_STATE_DIR/requests.log"
    local output
    output=$(mk --parent-id=p --dry-run -v "a/b/c")

    assert_equals "1" "$(folder_count)" "Nothing created"
    assert_equals "0" "$(count_requests POST)" "No POST issued"
    assert_contains "$output" "Exists: a [ID: stub1]" "Existing folder resolved"
    assert_contains "$output" "Would create: a/b/c" "Missing folder announced"
    assert_contains "$output" "Dry run complete: 2 folder(s) would be created, 1 already exist" "Dry-run summary"
    if [[ "$output" == *"Done!"* ]]; then
        fail "Dry run must not print Done!"
    else
        pass "Dry run does not print Done!"
    fi

    # Same child name under two parents that do not exist yet must not be confused
    output=$(mk --parent-id=p --dry-run --json "n1/x" "n2/x" 2>/dev/null)
    assert_equals "4" "$(echo "$output" | jq 'length')" "Both hypothetical children counted"
    assert_equals "null" "$(echo "$output" | jq '.[1].id')" "Hypothetical folder has null id"
    assert_equals "null" "$(echo "$output" | jq '.[1].parent_id')" "Hypothetical parent has null id"
    assert_equals "p" "$(echo "$output" | jq -r '.[0].parent_id')" "Real parent id kept"
    output=$(mk --parent-id=p --dry-run "n1/x" 2>/dev/null)
    assert_equals $'-\tn1\n-\tn1/x' "$output" "Default output uses '-' for hypothetical ids"
    assert_equals "1" "$(folder_count)" "Still nothing created"
}

test_retry_on_transient_error() {
    # Test: 429 and 503 are retried, then the run succeeds
    reset_state
    printf '429\n503\n' > "$STUB_STATE_DIR/fail_queue"
    local output
    output=$(mk --parent-id=p -v "a" 2>"$SANDBOX/stderr")

    assert_contains "$output" "Done! 1 folder(s) created" "Run succeeded after retries"
    assert_equals "2" "$(grep -c 'retrying' "$SANDBOX/stderr")" "Two retries logged"
}

test_gives_up_after_max_retries() {
    # Test: Persistent 5xx fails the run with exit 1
    reset_state
    printf '503\n503\n503\n' > "$STUB_STATE_DIR/fail_queue"
    local output rc=0
    output=$(GDRIVE_RETRIES=2 mk --parent-id=p -v "a" 2>"$SANDBOX/stderr") || rc=$?

    assert_equals "1" "$rc" "Exit code 1"
    assert_contains "$(cat "$SANDBOX/stderr")" "Giving up after 3 attempts" "Gives up after retries"
    assert_equals "0" "$(folder_count)" "Nothing created"
}

test_stops_at_first_api_error() {
    # Test: A non-retryable error stops immediately, earlier folders are kept
    reset_state
    # request 1: lookup a, 2: create a, 3: lookup a/b -> 403
    printf '\n\n403\n' > "$STUB_STATE_DIR/fail_queue"
    local output rc=0
    output=$(mk --parent-id=p -v "a/b" "c" 2>"$SANDBOX/stderr") || rc=$?

    assert_equals "1" "$rc" "Exit code 1"
    assert_equals "1" "$(folder_count)" "Only the first folder was created"
    assert_contains "$output" "Created: a [ID: stub1]" "Progress before the error is reported"
    assert_contains "$(cat "$SANDBOX/stderr")" "Injected failure 403" "API error message forwarded"
    if [[ "$output" == *"Done!"* ]]; then
        fail "Done! must not be printed on failure"
    else
        pass "No Done! on failure"
    fi
}

test_special_characters() {
    # Test: Quotes and backslashes in names survive query escaping and JSON encoding
    reset_state
    local name="O'Brien \\ \"Co\"" output
    mk --parent-id=p "$name/sub" >/dev/null
    output=$(mk --parent-id=p -v "$name/sub")

    assert_equals "$name" "$(awk -F'\t' '$1=="stub1"{print $3}' "$STUB_STATE_DIR/folders.tsv")" "Name stored verbatim"
    assert_contains "$output" "Exists: $name [ID: stub1]" "Existing folder with quotes found again"
    assert_equals "2" "$(folder_count)" "No duplicates"
}

test_paths_file_parsing() {
    # Test: Comments, blank lines, CRLF and surrounding slashes/spaces are handled
    reset_state
    printf '# comment\r\n\r\n  /a/b/  \r\n\r\na//c\n' > "$SANDBOX/paths.txt"
    local output
    output=$(mk -f "$SANDBOX/paths.txt" --parent-id=p)

    assert_equals "3" "$(folder_count)" "a, a/b, a/c created"
    assert_equals $'stub1\ta\nstub2\ta/b\nstub3\ta/c' "$output" "Normalized paths"
}

test_stdin_and_positional_paths() {
    # Test: -f - reads stdin, positional paths are added
    reset_state
    local output
    output=$(printf 'a\n' | mk -f - --parent-id=p "b")

    assert_equals $'stub1\ta\nstub2\tb' "$output" "Both sources processed"
}

test_argument_errors() {
    # Test: Missing paths or unreadable file exit 1 with a message
    reset_state
    local rc=0 err
    err=$(mk --parent-id=p 2>&1) || rc=$?
    assert_equals "1" "$rc" "No paths -> exit 1"
    assert_contains "$err" "No paths given" "No paths message"

    rc=0
    err=$(mk -f "$SANDBOX/missing.txt" 2>&1) || rc=$?
    assert_equals "1" "$rc" "Missing file -> exit 1"
    assert_contains "$err" "Cannot read paths file" "Missing file message"

    rc=0
    err=$(mk --bogus "a" 2>&1) || rc=$?
    assert_equals "1" "$rc" "Unknown option -> exit 1"
    assert_contains "$err" "Unknown option for mkdir-tree: --bogus" "Unknown option message"
}

test_wrapper_contract() {
    # Test: gdrive_mkdir.sh keeps the historical '-f FILE --parent-id=ID -v' contract
    reset_state
    local paths="$SANDBOX/driver.txt" output
    write_driver_paths "$paths"

    output=$("$WRAPPER_SCRIPT" -f "$paths" --parent-id=rootfolder -v 2>&1)

    assert_equals "6" "$(folder_count)" "Wrapper created the tree"
    assert_contains "$output" "Done!" "Wrapper prints Done!"
    assert_contains "$output" "1 - dossier permanent [ID: stub2]" "Wrapper output carries IDs"

    output=$("$WRAPPER_SCRIPT" --full-access --help 2>&1)
    assert_contains "$output" "Usage: " "Wrapper --help works"
}

# Main test execution
main() {
    mkdir -p "$TEST_LOG_DIR"
    touch "$TEST_LOG_FILE"

    run_test_suite "mkdir-tree Offline Tests" \
        test_creates_full_tree \
        test_rerun_is_idempotent \
        test_rerun_creates_only_missing \
        test_implicit_parents \
        test_prefix_cache \
        test_json_output \
        test_dry_run \
        test_retry_on_transient_error \
        test_gives_up_after_max_retries \
        test_stops_at_first_api_error \
        test_special_characters \
        test_paths_file_parsing \
        test_stdin_and_positional_paths \
        test_argument_errors \
        test_wrapper_contract

    print_test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
