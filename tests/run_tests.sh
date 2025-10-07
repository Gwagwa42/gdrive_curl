#!/usr/bin/env bash
set -euo pipefail

# Master Test Runner for gdrive_curl.sh
# Runs all test suites and provides comprehensive reporting

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GDRIVE_SCRIPT="$PROJECT_ROOT/gdrive_curl.sh"
LOG_DIR="$SCRIPT_DIR/logs"
SUMMARY_LOG="$LOG_DIR/test_summary_$(date +%Y%m%d_%H%M%S).log"

# Test suite files
TEST_SUITES=(
    "test_auth.sh"
    "test_scope.sh"
    "test_file_ops.sh"
    "test_folder_ops.sh"
    "test_permissions.sh"
    "test_star_trash.sh"
    "test_search_export.sh"
    "test_revisions.sh"
)

# Counters
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
SKIPPED_SUITES=0

# Options
VERBOSE=${VERBOSE:-0}
QUICK=${QUICK:-0}
SUITE_FILTER="${1:-}"
CLEANUP=${TEST_CLEANUP:-1}

# Scope mode configuration
SCOPE_MODE="${SCOPE_MODE:-app}"
export TEST_SCOPE_MODE="$SCOPE_MODE"

# Help message
show_help() {
    cat << EOF
${BOLD}gdrive_curl.sh Test Suite Runner${NC}

${BOLD}USAGE:${NC}
    $0 [options] [test_suite]

${BOLD}OPTIONS:${NC}
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -q, --quick         Run quick tests only (skip slow tests)
    -n, --no-cleanup    Don't cleanup test files after tests
    -l, --list          List available test suites

${BOLD}TEST SUITES:${NC}
    auth                Authentication tests
    scope               OAuth scope configuration tests
    file                File operations tests
    folder              Folder operations tests
    permissions         Permission management tests
    star-trash          Star and trash management tests
    search-export       Search and export tests
    revisions           Version history tests
    all                 Run all test suites (default)

${BOLD}ENVIRONMENT VARIABLES:${NC}
    SCOPE_MODE=app|full Run tests with specific scope (default: app)
    TEST_CLEANUP=0      Keep test files for debugging
    VERBOSE=1           Enable verbose output
    QUICK=1             Skip slow tests

${BOLD}EXAMPLES:${NC}
    $0                  # Run all tests (app mode)
    $0 auth             # Run only authentication tests
    $0 -v file          # Run file tests with verbose output
    $0 -n permissions   # Run permission tests without cleanup
    SCOPE_MODE=full $0  # Run all tests with full Drive access
    SCOPE_MODE=app $0 scope  # Run scope tests in app mode

EOF
}

# Capitalize first letter (portable for older bash)
capitalize() {
    local str="$1"
    echo "$(echo "${str:0:1}" | tr '[:lower:]' '[:upper:]')${str:1}"
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=1
                export VERBOSE
                shift
                ;;
            -q|--quick)
                QUICK=1
                export QUICK
                shift
                ;;
            -n|--no-cleanup)
                CLEANUP=0
                export TEST_CLEANUP=0
                shift
                ;;
            -l|--list)
                echo "${BOLD}Available test suites:${NC}"
                for suite in "${TEST_SUITES[@]}"; do
                    name=${suite%.sh}
                    name=${name#test_}
                    echo "  - $name"
                done
                exit 0
                ;;
            *)
                SUITE_FILTER="$1"
                shift
                ;;
        esac
    done
}

# Print banner
print_banner() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                          ║${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}gdrive_curl.sh Test Suite${NC}                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Testing ${BOLD}29 commands${NC} across ${BOLD}8 test suites${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Scope Mode: ${BOLD}$TEST_SCOPE_MODE${NC} $([ "$TEST_SCOPE_MODE" = "full" ] && echo "(Full Drive Access)" || echo "(App-Only Access)")  ${CYAN}║${NC}"
    echo -e "${CYAN}║                                                          ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo
}

# Check prerequisites
check_prerequisites() {
    echo -e "${BLUE}Checking prerequisites...${NC}"

    # Check if gdrive_curl.sh exists
    if [[ ! -f "$GDRIVE_SCRIPT" ]]; then
        echo -e "${RED}✗ gdrive_curl.sh not found at $GDRIVE_SCRIPT${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ gdrive_curl.sh found${NC}"
    fi

    # Check for required commands
    for cmd in curl jq bash; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}✗ Required command '$cmd' not found${NC}"
            exit 1
        else
            echo -e "${GREEN}✓ $cmd available${NC}"
        fi
    done

    # Check authentication with correct scope
    if [[ "$TEST_SCOPE_MODE" == "full" ]]; then
        auth_check_cmd="$GDRIVE_SCRIPT --full-access list"
        init_cmd="$GDRIVE_SCRIPT --full-access init"
    else
        auth_check_cmd="$GDRIVE_SCRIPT --app-only list"
        init_cmd="$GDRIVE_SCRIPT --app-only init"
    fi

    if $auth_check_cmd >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Authentication valid ($TEST_SCOPE_MODE mode)${NC}"
    else
        echo -e "${YELLOW}⚠ Not authenticated for $TEST_SCOPE_MODE mode - some tests will be skipped${NC}"
        echo -e "${YELLOW}  Run: $init_cmd${NC}"
    fi

    # Create log directory
    mkdir -p "$LOG_DIR"
    echo -e "${GREEN}✓ Log directory ready${NC}"

    echo
}

# Filter test suites based on user input
filter_suites() {
    local filter="$1"
    local filtered_suites=()

    if [[ -z "$filter" ]] || [[ "$filter" == "all" ]]; then
        filtered_suites=("${TEST_SUITES[@]}")
    else
        for suite in "${TEST_SUITES[@]}"; do
            suite_name=${suite%.sh}
            suite_name=${suite_name#test_}
            suite_name=${suite_name//_/-}

            if [[ "$suite_name" == *"$filter"* ]]; then
                filtered_suites+=("$suite")
            fi
        done
    fi

    if [[ ${#filtered_suites[@]} -eq 0 ]]; then
        echo -e "${RED}No test suites match filter: $filter${NC}"
        echo "Use -l to list available suites"
        exit 1
    fi

    echo "${filtered_suites[@]}"
}

# Run a single test suite
run_test_suite() {
    local suite_file="$1"
    local suite_name=${suite_file%.sh}
    suite_name=${suite_name#test_}
    suite_name=${suite_name//_/ }

    ((TOTAL_SUITES++))

    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}Running: ${BOLD}$(capitalize "$suite_name") Tests${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"

    local suite_path="$SCRIPT_DIR/$suite_file"
    local suite_log="$LOG_DIR/${suite_file%.sh}_$(date +%Y%m%d_%H%M%S).log"

    if [[ ! -f "$suite_path" ]]; then
        echo -e "${RED}✗ Test suite not found: $suite_path${NC}"
        ((FAILED_SUITES++))
        return 1
    fi

    # Make sure test is executable
    chmod +x "$suite_path"

    # Run the test suite
    if [[ $VERBOSE -eq 1 ]]; then
        if bash "$suite_path" 2>&1 | tee "$suite_log"; then
            echo -e "${GREEN}✓ $(capitalize "$suite_name") tests passed${NC}"
            ((PASSED_SUITES++))
        else
            echo -e "${RED}✗ $(capitalize "$suite_name") tests failed${NC}"
            ((FAILED_SUITES++))
        fi
    else
        if bash "$suite_path" > "$suite_log" 2>&1; then
            echo -e "${GREEN}✓ $(capitalize "$suite_name") tests passed${NC}"
            ((PASSED_SUITES++))

            # Show summary from log
            if grep -q "TEST SUMMARY" "$suite_log"; then
                sed -n '/TEST SUMMARY/,/═══════/p' "$suite_log" | sed '1d;$d'
            fi
        else
            echo -e "${RED}✗ $(capitalize "$suite_name") tests failed${NC}"
            ((FAILED_SUITES++))

            # Show failures from log
            echo -e "${YELLOW}Failed tests:${NC}"
            grep "FAIL:" "$suite_log" | head -5
            echo -e "${YELLOW}See full log: $suite_log${NC}"
        fi
    fi

    echo
}

# Generate summary report
generate_summary() {
    {
        echo "======================================"
        echo "Test Execution Summary"
        echo "======================================"
        echo "Date: $(date)"
        echo "Script: $GDRIVE_SCRIPT"
        echo ""
        echo "Test Suites Run: $TOTAL_SUITES"
        echo "Passed: $PASSED_SUITES"
        echo "Failed: $FAILED_SUITES"
        echo "Skipped: $SKIPPED_SUITES"
        echo ""

        if [[ $FAILED_SUITES -gt 0 ]]; then
            echo "Failed Suites:"
            for log in "$LOG_DIR"/*.log; do
                if grep -q "TESTS FAILED" "$log" 2>/dev/null; then
                    basename "$log"
                fi
            done
        fi

        echo ""
        echo "Logs directory: $LOG_DIR"
    } | tee "$SUMMARY_LOG"
}

# Print final results
print_results() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    TEST RESULTS                         ║${NC}"
    echo -e "${CYAN}╟──────────────────────────────────────────────────────────╢${NC}"

    printf "${CYAN}║${NC} %-25s %30s ${CYAN}║${NC}\n" "Test Suites Run:" "$TOTAL_SUITES"
    printf "${CYAN}║${NC} %-25s ${GREEN}%30s${NC} ${CYAN}║${NC}\n" "Passed:" "$PASSED_SUITES"
    printf "${CYAN}║${NC} %-25s ${RED}%30s${NC} ${CYAN}║${NC}\n" "Failed:" "$FAILED_SUITES"

    if [[ $SKIPPED_SUITES -gt 0 ]]; then
        printf "${CYAN}║${NC} %-25s ${YELLOW}%30s${NC} ${CYAN}║${NC}\n" "Skipped:" "$SKIPPED_SUITES"
    fi

    echo -e "${CYAN}╟──────────────────────────────────────────────────────────╢${NC}"

    if [[ $FAILED_SUITES -eq 0 ]]; then
        echo -e "${CYAN}║${NC}           ${GREEN}${BOLD}✓ ALL TESTS PASSED!${NC}                          ${CYAN}║${NC}"
    else
        echo -e "${CYAN}║${NC}           ${RED}${BOLD}✗ SOME TESTS FAILED${NC}                          ${CYAN}║${NC}"
    fi

    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "Full test logs available in: ${BLUE}$LOG_DIR${NC}"
    echo -e "Summary log: ${BLUE}$SUMMARY_LOG${NC}"
}

# Cleanup function
cleanup() {
    if [[ $CLEANUP -eq 1 ]]; then
        echo -e "\n${YELLOW}Cleaning up test files...${NC}"

        # Clean up any remaining test files in Drive
        if "$GDRIVE_SCRIPT" list 2>/dev/null | grep -q "gdrive_curl_test"; then
            "$GDRIVE_SCRIPT" list 2>/dev/null | grep "gdrive_curl_test" | awk '{print $1}' | \
                while read -r id; do
                    "$GDRIVE_SCRIPT" delete "$id" 2>/dev/null || true
                done
        fi

        # Clean up local test data
        rm -rf "$SCRIPT_DIR/data"/* 2>/dev/null || true

        echo -e "${GREEN}✓ Cleanup complete${NC}"
    else
        echo -e "${YELLOW}Cleanup disabled - test files retained${NC}"
    fi
}

# Main execution
main() {
    parse_args "$@"

    # Set up trap for cleanup
    trap cleanup EXIT

    print_banner
    check_prerequisites

    # Get filtered test suites
    suites_to_run=($(filter_suites "$SUITE_FILTER"))

    echo -e "${BLUE}Running ${#suites_to_run[@]} test suite(s)${NC}\n"

    # Run each test suite
    for suite in "${suites_to_run[@]}"; do
        run_test_suite "$suite"
    done

    generate_summary
    print_results

    # Exit with failure if any tests failed
    if [[ $FAILED_SUITES -gt 0 ]]; then
        exit 1
    fi

    exit 0
}

# Run main function
main "$@"