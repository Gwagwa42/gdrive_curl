#!/usr/bin/env bash
set -euo pipefail

# Load test framework
source "$(dirname "$0")/test_helpers.sh"

# mkdir-tree tests against the real Drive API.
# Everything is created under one throwaway folder that is deleted at the end.
# See test_mkdir_tree_offline.sh for the exhaustive, credential-free suite.

WRAPPER_SCRIPT="$PROJECT_ROOT/gdrive_mkdir.sh"
TEST_ROOT_ID=""

setup() {
    local output
    output=$(gdrive create-folder "mkdir_tree_test_$(date +%s)")
    TEST_ROOT_ID=$(echo "$output" | jq -r '.id' 2>/dev/null || echo "")
    [[ -n "$TEST_ROOT_ID" ]] || { echo -e "${RED}Could not create test root folder${NC}"; exit 1; }
}

teardown() {
    if [[ -n "$TEST_ROOT_ID" ]]; then
        gdrive_silent delete "$TEST_ROOT_ID" || true
    fi
}

test_creates_nested_tree() {
    # Test: Creates nested folders and reports their IDs
    local output child_id grandchild_id listing
    output=$(gdrive mkdir-tree --parent-id="$TEST_ROOT_ID" -v "Client A/Invoices/2026" "Client A/Contracts")

    assert_contains "$output" "Created: Client A [ID: " "Top level folder created"
    assert_contains "$output" "Created: Client A/Invoices/2026 [ID: " "Deep folder created"
    assert_contains "$output" "Done! 4 folder(s) created, 0 already existed" "Summary reports four creations"

    child_id=$(echo "$output" | sed -n 's/^Created: Client A \[ID: \(.*\)\]$/\1/p')
    if assert_not_empty "$child_id" "Top level folder ID extracted"; then
        listing=$(gdrive list "$child_id" 2>/dev/null)
        assert_contains "$listing" "Invoices" "Invoices is inside Client A"
        assert_contains "$listing" "Contracts" "Contracts is inside Client A"
    fi

    grandchild_id=$(echo "$output" | sed -n 's/^Created: Client A\/Invoices \[ID: \(.*\)\]$/\1/p')
    if assert_not_empty "$grandchild_id" "Invoices folder ID extracted"; then
        listing=$(gdrive list "$grandchild_id" 2>/dev/null)
        assert_contains "$listing" "2026" "2026 is inside Invoices"
    fi
}

test_rerun_reuses_existing() {
    # Test: Re-running reuses existing folders and only creates new ones
    local output listing
    output=$(gdrive mkdir-tree --parent-id="$TEST_ROOT_ID" -v "Client A/Invoices/2026" "Client A/Invoices/2027")

    assert_contains "$output" "Exists: Client A [ID: " "Existing top level folder reused"
    assert_contains "$output" "Exists: Client A/Invoices/2026 [ID: " "Existing deep folder reused"
    assert_contains "$output" "Created: Client A/Invoices/2027 [ID: " "New sibling created"
    assert_contains "$output" "Done! 1 folder(s) created, 3 already existed" "Summary reflects reuse"

    listing=$(gdrive list "$TEST_ROOT_ID" 2>/dev/null)
    assert_equals "1" "$(echo "$listing" | grep -c "Client A")" "No duplicate top level folder"
}

test_wrapper_with_paths_file() {
    # Test: gdrive_mkdir.sh reads a paths file and honours the historical contract
    local paths_file output
    paths_file=$(create_test_file "paths.txt" $'Client B\nClient B/1 - dossier permanent\nClient B/1 - dossier permanent/Pieces')
    output=$("$WRAPPER_SCRIPT" --app-only -f "$paths_file" --parent-id="$TEST_ROOT_ID" -v 2>>"$TEST_LOG_FILE")

    assert_contains "$output" "Done!" "Wrapper prints Done!"
    assert_contains "$output" "1 - dossier permanent [ID: " "Wrapper reports folder IDs"

    output=$(gdrive mkdir-tree --parent-id="$TEST_ROOT_ID" --json "Client B/1 - dossier permanent/Pieces")
    assert_equals "false false false" "$(echo "$output" | jq -r '[.[].created] | join(" ")')" "JSON rerun shows nothing created"
}

# Main test execution
main() {
    init_test_env

    # Check authentication first
    if ! gdrive_silent list; then
        echo -e "${YELLOW}Skipping mkdir-tree tests - not authenticated${NC}"
        exit 0
    fi

    setup

    run_test_suite "mkdir-tree Tests" \
        test_creates_nested_tree \
        test_rerun_reuses_existing \
        test_wrapper_with_paths_file

    teardown

    print_test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
