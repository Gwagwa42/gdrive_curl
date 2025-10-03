#!/usr/bin/env bash
set -euo pipefail

# Test Framework for gdrive_curl.sh
# Provides helper functions and test utilities

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GDRIVE_SCRIPT="$PROJECT_ROOT/gdrive_curl.sh"
TEST_DATA_DIR="$SCRIPT_DIR/data"
TEST_LOG_DIR="$SCRIPT_DIR/logs"
TEST_LOG_FILE="$TEST_LOG_DIR/test_$(date +%Y%m%d_%H%M%S).log"

# Test configuration
export TEST_MODE=1
export TEST_FOLDER_NAME="gdrive_curl_test_$(date +%s)"
export TEST_FILE_PREFIX="test_file_"
export TEST_CLEANUP=${TEST_CLEANUP:-1}  # Set to 0 to keep test files for debugging

# Scope configuration for tests
export TEST_SCOPE_MODE="${TEST_SCOPE_MODE:-app}"  # Default to app mode for tests

# Initialize test environment
init_test_env() {
    mkdir -p "$TEST_LOG_DIR"
    touch "$TEST_LOG_FILE"

    echo "=== Test Environment ===" | tee -a "$TEST_LOG_FILE"
    echo "Script: $GDRIVE_SCRIPT" | tee -a "$TEST_LOG_FILE"
    echo "Test folder: $TEST_FOLDER_NAME" | tee -a "$TEST_LOG_FILE"
    echo "Log file: $TEST_LOG_FILE" | tee -a "$TEST_LOG_FILE"
    echo "========================" | tee -a "$TEST_LOG_FILE"
    echo "" | tee -a "$TEST_LOG_FILE"

    # Check if script exists
    if [[ ! -f "$GDRIVE_SCRIPT" ]]; then
        echo -e "${RED}ERROR: gdrive_curl.sh not found at $GDRIVE_SCRIPT${NC}"
        exit 1
    fi

    # Check if authenticated (with correct scope)
    if [[ "$TEST_SCOPE_MODE" == "full" ]]; then
        auth_check="$GDRIVE_SCRIPT --full-access list"
        init_cmd="$GDRIVE_SCRIPT --full-access init"
    else
        auth_check="$GDRIVE_SCRIPT --app-only list"
        init_cmd="$GDRIVE_SCRIPT --app-only init"
    fi

    if ! $auth_check >/dev/null 2>&1; then
        echo -e "${YELLOW}WARNING: Not authenticated for $TEST_SCOPE_MODE mode. Run '$init_cmd' first${NC}"
        echo "Some tests will be skipped"
    fi
}

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"

    if [[ "$expected" == "$actual" ]]; then
        pass "$message"
        return 0
    else
        fail "$message: expected '$expected' but got '$actual'"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"

    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$message"
        return 0
    else
        fail "$message: '$haystack' does not contain '$needle'"
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local message="${2:-}"

    if [[ -n "$value" ]]; then
        pass "$message"
        return 0
    else
        fail "$message: value is empty"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-}"

    if [[ -f "$file" ]]; then
        pass "$message"
        return 0
    else
        fail "$message: file '$file' does not exist"
        return 1
    fi
}

assert_command_success() {
    local command="$1"
    local message="${2:-}"

    if eval "$command" >> "$TEST_LOG_FILE" 2>&1; then
        pass "$message"
        return 0
    else
        fail "$message: command failed: $command"
        return 1
    fi
}

assert_command_fails() {
    local command="$1"
    local message="${2:-}"

    if ! eval "$command" >> "$TEST_LOG_FILE" 2>&1; then
        pass "$message"
        return 0
    else
        fail "$message: command should have failed: $command"
        return 1
    fi
}

# Test execution functions
run_test() {
    local test_name="$1"
    local test_function="$2"

    ((TESTS_RUN++))
    echo -e "${BLUE}Running: $test_name${NC}"
    echo "=== Test: $test_name ===" >> "$TEST_LOG_FILE"

    # Run test in subshell to isolate failures
    if (
        set -e
        $test_function
    ); then
        echo ""
    else
        echo ""
    fi
}

skip_test() {
    local test_name="$1"
    local reason="${2:-}"

    ((TESTS_SKIPPED++))
    echo -e "${YELLOW}⊘ SKIP: $test_name${NC}"
    [[ -n "$reason" ]] && echo "  Reason: $reason"
    echo "SKIPPED: $test_name - $reason" >> "$TEST_LOG_FILE"
}

pass() {
    local message="$1"
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓ PASS${NC}: $message"
    echo "  PASS: $message" >> "$TEST_LOG_FILE"
}

fail() {
    local message="$1"
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗ FAIL${NC}: $message"
    echo "  FAIL: $message" >> "$TEST_LOG_FILE"
}

# Helper functions for gdrive operations
gdrive() {
    # Add scope flag based on TEST_SCOPE_MODE
    if [[ "$TEST_SCOPE_MODE" == "full" ]]; then
        "$GDRIVE_SCRIPT" --full-access "$@" 2>> "$TEST_LOG_FILE"
    else
        "$GDRIVE_SCRIPT" --app-only "$@" 2>> "$TEST_LOG_FILE"
    fi
}

gdrive_silent() {
    # Add scope flag based on TEST_SCOPE_MODE
    if [[ "$TEST_SCOPE_MODE" == "full" ]]; then
        "$GDRIVE_SCRIPT" --full-access "$@" >> "$TEST_LOG_FILE" 2>&1
    else
        "$GDRIVE_SCRIPT" --app-only "$@" >> "$TEST_LOG_FILE" 2>&1
    fi
}

# Get the token file path based on scope mode
get_token_file() {
    if [[ "$TEST_SCOPE_MODE" == "full" ]]; then
        echo "$HOME/.config/gdrive-curl/tokens-full.json"
    else
        echo "$HOME/.config/gdrive-curl/tokens-app.json"
    fi
}

get_test_folder_id() {
    # Get or create test folder
    local folder_id
    folder_id=$(gdrive find-folder "$TEST_FOLDER_NAME" 2>/dev/null | head -1 | cut -f1)

    if [[ -z "$folder_id" ]]; then
        # Create test folder
        folder_id=$(gdrive create-folder "$TEST_FOLDER_NAME" | jq -r '.id' 2>/dev/null)
    fi

    echo "$folder_id"
}

create_test_file() {
    local filename="${1:-test_file_$(date +%s).txt}"
    local content="${2:-This is a test file created at $(date)}"
    local filepath="$TEST_DATA_DIR/$filename"

    mkdir -p "$TEST_DATA_DIR"
    echo "$content" > "$filepath"
    echo "$filepath"
}

upload_test_file() {
    local filename="${1:-test_file_$(date +%s).txt}"
    local content="${2:-Test content}"
    local parent_id="${3:-}"

    local filepath=$(create_test_file "$filename" "$content")
    local file_id

    if [[ -n "$parent_id" ]]; then
        file_id=$(gdrive upload "$filepath" "$filename" "$parent_id" | jq -r '.id' 2>/dev/null)
    else
        file_id=$(gdrive upload "$filepath" "$filename" | jq -r '.id' 2>/dev/null)
    fi

    echo "$file_id"
}

cleanup_test_file() {
    local file_id="$1"
    if [[ -n "$file_id" ]]; then
        gdrive_silent delete "$file_id" || true
    fi
}

cleanup_test_folder() {
    local folder_id="${1:-}"

    if [[ -z "$folder_id" ]]; then
        folder_id=$(gdrive find-folder "$TEST_FOLDER_NAME" 2>/dev/null | head -1 | cut -f1)
    fi

    if [[ -n "$folder_id" ]]; then
        # Delete all files in test folder first
        gdrive list "$folder_id" 2>/dev/null | while read -r file_id _; do
            [[ -n "$file_id" ]] && gdrive_silent delete "$file_id"
        done

        # Delete the folder
        gdrive_silent delete "$folder_id"
    fi
}

# Test suite functions
run_test_suite() {
    local suite_name="$1"
    shift
    local test_functions=("$@")

    echo ""
    echo -e "${BLUE}═══ Test Suite: $suite_name ═══${NC}"
    echo "=== Test Suite: $suite_name ===" >> "$TEST_LOG_FILE"

    for test_func in "${test_functions[@]}"; do
        if declare -f "$test_func" > /dev/null; then
            # Extract test description from function comment
            local test_desc=$(declare -f "$test_func" | grep -m1 "# Test:" | sed 's/.*# Test: //')
            [[ -z "$test_desc" ]] && test_desc="$test_func"

            run_test "$test_desc" "$test_func"
        else
            echo -e "${RED}Warning: Test function $test_func not found${NC}"
        fi
    done
}

# Final report
print_test_summary() {
    echo ""
    echo "═══════════════════════════════"
    echo "         TEST SUMMARY"
    echo "═══════════════════════════════"
    echo -e "Tests run:     $TESTS_RUN"
    echo -e "Tests passed:  ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed:  ${RED}$TESTS_FAILED${NC}"
    echo -e "Tests skipped: ${YELLOW}$TESTS_SKIPPED${NC}"
    echo "═══════════════════════════════"

    echo "" >> "$TEST_LOG_FILE"
    echo "=== TEST SUMMARY ===" >> "$TEST_LOG_FILE"
    echo "Tests run: $TESTS_RUN" >> "$TEST_LOG_FILE"
    echo "Tests passed: $TESTS_PASSED" >> "$TEST_LOG_FILE"
    echo "Tests failed: $TESTS_FAILED" >> "$TEST_LOG_FILE"
    echo "Tests skipped: $TESTS_SKIPPED" >> "$TEST_LOG_FILE"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "\n${RED}TESTS FAILED${NC}"
        echo "Check log file: $TEST_LOG_FILE"
        return 1
    else
        echo -e "\n${GREEN}ALL TESTS PASSED${NC}"
        return 0
    fi
}

# Cleanup on exit
cleanup_on_exit() {
    if [[ "$TEST_CLEANUP" == "1" ]]; then
        echo "Cleaning up test files..."
        cleanup_test_folder
        rm -rf "$TEST_DATA_DIR"
    else
        echo "Test cleanup disabled. Files kept for debugging."
    fi
}

# Set trap for cleanup
trap cleanup_on_exit EXIT