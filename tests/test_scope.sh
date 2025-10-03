#!/usr/bin/env bash
set -euo pipefail

# Load test framework
source "$(dirname "$0")/test_helpers.sh"

# Scope Configuration Tests

test_scope_command_output() {
    # Test: Scope command returns expected output
    local output=$(gdrive scope 2>&1)

    assert_contains "$output" "Current scope configuration" "Scope command shows configuration"
    assert_contains "$output" "Mode:" "Shows mode field"
    assert_contains "$output" "Description:" "Shows description field"
    assert_contains "$output" "Scope URL:" "Shows scope URL field"
    assert_contains "$output" "Token file:" "Shows token file field"
    assert_contains "$output" "Status:" "Shows authentication status"
}

test_app_only_flag() {
    # Test: --app-only flag works correctly
    local output=$("$GDRIVE_SCRIPT" --app-only scope 2>&1)

    assert_contains "$output" "Mode: app" "App-only flag sets correct mode"
    assert_contains "$output" "App-created files only" "Shows app-only description"
    assert_contains "$output" "tokens-app.json" "Uses app token file"
    assert_contains "$output" "drive.file" "Uses drive.file scope"
}

test_full_access_flag() {
    # Test: --full-access flag works correctly
    local output=$("$GDRIVE_SCRIPT" --full-access scope 2>&1)

    assert_contains "$output" "Mode: full" "Full access flag sets correct mode"
    assert_contains "$output" "Full Google Drive access" "Shows full access description"
    assert_contains "$output" "tokens-full.json" "Uses full token file"
    assert_contains "$output" "www.googleapis.com/auth/drive" "Uses full drive scope"
}

test_scope_mode_env_var() {
    # Test: SCOPE_MODE environment variable works

    # Test with app mode
    local output=$(SCOPE_MODE=app "$GDRIVE_SCRIPT" scope 2>&1)
    assert_contains "$output" "Mode: app" "SCOPE_MODE=app sets correct mode"

    # Test with full mode
    output=$(SCOPE_MODE=full "$GDRIVE_SCRIPT" scope 2>&1)
    assert_contains "$output" "Mode: full" "SCOPE_MODE=full sets correct mode"
}

test_flag_overrides_env() {
    # Test: Command line flag overrides environment variable

    # Set env to app, but use --full-access flag
    local output=$(SCOPE_MODE=app "$GDRIVE_SCRIPT" --full-access scope 2>&1)
    assert_contains "$output" "Mode: full" "Flag overrides env variable"

    # Set env to full, but use --app-only flag
    output=$(SCOPE_MODE=full "$GDRIVE_SCRIPT" --app-only scope 2>&1)
    assert_contains "$output" "Mode: app" "Flag overrides env variable"
}

test_token_file_separation() {
    # Test: Different scopes use different token files
    local app_token_file="$HOME/.config/gdrive-curl/tokens-app.json"
    local full_token_file="$HOME/.config/gdrive-curl/tokens-full.json"

    # Check app mode uses correct file
    local app_output=$("$GDRIVE_SCRIPT" --app-only scope 2>&1)
    assert_contains "$app_output" "tokens-app.json" "App mode uses tokens-app.json"

    # Check full mode uses correct file
    local full_output=$("$GDRIVE_SCRIPT" --full-access scope 2>&1)
    assert_contains "$full_output" "tokens-full.json" "Full mode uses tokens-full.json"
}

test_default_scope_mode() {
    # Test: Default scope mode is app-only
    local output=$("$GDRIVE_SCRIPT" scope 2>&1)
    assert_contains "$output" "Mode: app" "Default mode is app-only"
    assert_contains "$output" "App-created files only" "Default is restrictive mode"
}

test_scope_with_other_commands() {
    # Test: Scope flags work with other commands

    # Test with list command
    if "$GDRIVE_SCRIPT" --app-only list >/dev/null 2>&1 || [[ $? -eq 1 ]]; then
        pass "--app-only flag works with list command"
    else
        fail "--app-only flag failed with list command"
    fi

    if "$GDRIVE_SCRIPT" --full-access list >/dev/null 2>&1 || [[ $? -eq 1 ]]; then
        pass "--full-access flag works with list command"
    else
        fail "--full-access flag failed with list command"
    fi
}

test_help_shows_scope_flags() {
    # Test: Help output includes scope flag documentation
    local help_output=$("$GDRIVE_SCRIPT" --help 2>&1)

    assert_contains "$help_output" "--full-access" "Help shows --full-access flag"
    assert_contains "$help_output" "--app-only" "Help shows --app-only flag"
    assert_contains "$help_output" "SCOPE FLAGS" "Help has scope flags section"
}

test_authentication_status() {
    # Test: Scope command shows authentication status
    local output=$(gdrive scope 2>&1)

    # Check that status line exists
    assert_contains "$output" "Status:" "Shows status field"

    # Status should be one of these
    if echo "$output" | grep -qE "Authenticated|Token expired|Not authenticated"; then
        pass "Shows valid authentication status"
    else
        fail "Invalid authentication status"
    fi
}

# Main test execution
main() {
    init_test_env

    echo -e "${BLUE}Testing scope mode: $TEST_SCOPE_MODE${NC}"

    run_test_suite "OAuth Scope Tests" \
        test_scope_command_output \
        test_app_only_flag \
        test_full_access_flag \
        test_scope_mode_env_var \
        test_flag_overrides_env \
        test_token_file_separation \
        test_default_scope_mode \
        test_scope_with_other_commands \
        test_help_shows_scope_flags \
        test_authentication_status

    print_test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi