#!/usr/bin/env bash
set -euo pipefail

# Load test framework
source "$(dirname "$0")/test_helpers.sh"

# Authentication Tests

test_check_authentication() {
    # Test: Check if authenticated
    if gdrive_silent list; then
        pass "Authentication is valid"
    else
        fail "Not authenticated or token expired"
    fi
}

test_token_file_exists() {
    # Test: Token file exists
    local token_file=$(get_token_file)
    assert_file_exists "$token_file" "Token file exists ($TEST_SCOPE_MODE mode)"
}

test_token_file_valid_json() {
    # Test: Token file contains valid JSON
    local token_file=$(get_token_file)
    if [[ -f "$token_file" ]]; then
        if jq empty "$token_file" 2>/dev/null; then
            pass "Token file contains valid JSON ($TEST_SCOPE_MODE mode)"
        else
            fail "Token file does not contain valid JSON ($TEST_SCOPE_MODE mode)"
        fi
    else
        skip_test "Token file JSON validation" "Token file does not exist"
    fi
}

test_token_has_required_fields() {
    # Test: Token file has required fields
    local token_file=$(get_token_file)
    if [[ -f "$token_file" ]]; then
        local has_access_token=$(jq -r '.access_token // empty' "$token_file")
        local has_refresh_token=$(jq -r '.refresh_token // empty' "$token_file")

        if [[ -n "$has_access_token" ]]; then
            pass "Token file has access_token ($TEST_SCOPE_MODE mode)"
        else
            fail "Token file missing access_token ($TEST_SCOPE_MODE mode)"
        fi

        if [[ -n "$has_refresh_token" ]]; then
            pass "Token file has refresh_token ($TEST_SCOPE_MODE mode)"
        else
            fail "Token file missing refresh_token ($TEST_SCOPE_MODE mode)"
        fi
    else
        skip_test "Token field validation" "Token file does not exist"
    fi
}

test_list_command_works() {
    # Test: Basic list command works (proves auth is working)
    if output=$(gdrive list 2>&1); then
        pass "List command works with authentication"
    else
        fail "List command failed - authentication may be invalid"
    fi
}

test_quota_command_works() {
    # Test: Quota command works (requires valid auth)
    if output=$(gdrive quota 2>&1); then
        assert_contains "$output" "Storage:" "Quota command returns storage info"
    else
        fail "Quota command failed"
    fi
}

test_scope_command() {
    # Test: Scope command works and shows correct configuration
    if output=$(gdrive scope 2>&1); then
        assert_contains "$output" "Current scope configuration" "Scope command returns configuration"
        assert_contains "$output" "$TEST_SCOPE_MODE" "Scope shows correct mode"

        if [[ "$TEST_SCOPE_MODE" == "full" ]]; then
            assert_contains "$output" "Full Google Drive access" "Shows full access description"
            assert_contains "$output" "tokens-full.json" "Shows correct token file"
        else
            assert_contains "$output" "App-created files only" "Shows app-only description"
            assert_contains "$output" "tokens-app.json" "Shows correct token file"
        fi
    else
        fail "Scope command failed"
    fi
}

# Main test execution
main() {
    init_test_env

    run_test_suite "Authentication Tests" \
        test_check_authentication \
        test_token_file_exists \
        test_token_file_valid_json \
        test_token_has_required_fields \
        test_scope_command \
        test_list_command_works \
        test_quota_command_works

    print_test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi